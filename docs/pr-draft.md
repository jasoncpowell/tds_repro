# PR draft for elixir-ecto/ecto_sql

> **Internal draft, not yet submitted.** The text between the `pr-body`
> markers is the proposed PR description, written for the ecto_sql maintainers.
> Everything else is for us. To submit it, follow
> [creating-the-pr.md](creating-the-pr.md).

- **Repository:** [elixir-ecto/ecto_sql](https://github.com/elixir-ecto/ecto_sql), base branch `master`
- **Title:** Tds: send typed NULL for nil date, time and float params
- **Patches:** [`upstream/ecto_sql/`](../upstream/ecto_sql)

<!-- pr-body:start -->
Setting a `date`, `time`, `datetime2`, `datetimeoffset`, `float` or `real` column to nil through Ecto fails on SQL Server:

```
** (Tds.Error) Line 1 (Error 257): Implicit conversion from data type varbinary to date is not allowed. Use the CONVERT function to run this query.
```

`float` and `real` columns fail with error 206, "Operand type clash: varbinary is incompatible with float".

This fixes elixir-ecto/tds#124 and elixir-ecto/tds#168 in ecto_sql, which is where [the discussion on tds#124](https://github.com/elixir-ecto/tds/issues/124#issuecomment-2160155402) concluded the fix belongs.

### Reproduction

```elixir
defmodule Post do
  use Ecto.Schema

  schema "posts" do
    field :published_on, :date
  end
end

post = Repo.insert!(%Post{published_on: ~D[2024-01-01]})

post |> Ecto.Changeset.change(published_on: nil) |> Repo.update!()
# ** (Tds.Error) Line 1 (Error 257): Implicit conversion from data type varbinary to date is not allowed.
```

The same happens with `Repo.insert/2` when a changeset clears a field that was set, with `Repo.insert_all/3` rows containing nil, and with `Repo.update_all/3` setting nil.

### Cause

`Ecto.Adapters.Tds.Connection.prepare_param/1` picks a parameter type from the value (`%Date{}` becomes `:date`, and so on). A nil has nothing to pick from, so it reaches the driver untyped, and `Tds.Parameter.fix_data_type/1` declares it as `:binary`. SQL Server refuses to convert a varbinary NULL to `date`, `time`, `datetime2`, `datetimeoffset`, `float` or `real` columns.

As discussed in [tds#124](https://github.com/elixir-ecto/tds/issues/124#issuecomment-2159179856) and [tds#162](https://github.com/elixir-ecto/tds/pull/162#issuecomment-2157626223), the driver can't choose a better default: every type is refused by some column, and `:string` breaks `binary`, `varbinary` and `image` columns. The field's type has to come from Ecto.

### Change

`Ecto.Adapters.Tds.dumpers/2` now dumps a nil of the affected Ecto types as a pair of the nil and the TDS type a non-nil value of the field is sent as: `{nil, :datetime2}` for a `:naive_datetime` field, and so on. That is the same value-and-driver-type pair `Tds.Ecto.VarChar` dumps as `{value, :varchar}`, and `Ecto.Adapters.Tds.Connection.prepare_params/1` passes it on to a `%Tds.Parameter{}` the same way, through a clause that admits only those TDS types. So the Ecto type is used up in the dumpers, as for every other dumped value, and the connection's parameter code still handles only plain values and values already paired with a driver type. The driver keeps an explicit type and only falls back to `:binary` when there is none.

Unlike `Tds.Ecto.VarChar`, which is an `Ecto.Type` whose `dump/1` Ecto never calls for nil, this pair can carry nil. `Repo.update/2` and `Repo.delete/2` dump `changeset.filters` and hand them to `update/5` and `delete/4`, which render a nil filter as `IS NULL`. Both now match the pair too, so such a filter still compares with `IS NULL` rather than with a NULL parameter, which would never be true. They are the only place where the generated SQL depends on whether a dumped parameter is nil: `insert_each/2`'s `nil -> DEFAULT` clause cannot see one, because `Ecto.Adapters.SQL.insert/6` passes field names as the row and `unzip_inserts/2` emits a bare `nil` only for keys the row does not have.

The dumpers tag instead of building the struct because `lib/ecto/adapters/tds.ex` compiles without the optional tds dependency: unlike the connection, it has no `Code.ensure_loaded?(Tds)` guard, and a `%Tds.Parameter{}` literal there fails to compile for every ecto_sql user who doesn't have tds. So the struct is built in `Ecto.Adapters.Tds.Connection`, which only compiles when tds is loaded. The pair holds only atoms, and `mix test.as_a_dep` passes with it.

The dumpers clause matches the Ecto type against its own primitive, so only built-in types are tagged. A custom type with one of these primitives is unchanged: Ecto never calls its `dump/1` for nil, so the adapter can't tell how the type stores non-nil values (for example a `:date`-typed custom type that stores integers in an `int` column, which refuses a `date` NULL).

| Ecto type | Dumped nil |
|---|---|
| `:date` | `{nil, :date}` |
| `:time`, `:time_usec` | `{nil, :time}` |
| `:naive_datetime`, `:naive_datetime_usec` | `{nil, :datetime2}` |
| `:utc_datetime`, `:utc_datetime_usec` | `{nil, :datetimeoffset}` |
| `:float` | `{nil, :float}` (the driver declares a nil float as `decimal(1,0)`, which converts implicitly to `float` and `real`) |

For the date and time types these are the parameter types `prepare_param/1` gives non-nil `%Date{}`, `%Time{}`, `%NaiveDateTime{}` and `%DateTime{}` values; the driver only adds a value's precision to its declaration, as in `datetime2(6)`. Since a nil's type is now decided in the adapter and a value's in the connection, a new test checks that the two agree for each of the eight types. Non-nil values and all other types are untouched.

This relies on elixir-ecto/ecto#4214 (Ecto 3.11), which passes nil through adapter dumpers.

### Visible change

`Ecto.Adapters.SQL.to_sql/3` and the `:params` metadata of query telemetry events now contain the pair for these fields where they contained `nil`, such as `{nil, :datetimeoffset}` for a `:utc_datetime` field. `:cast_params` and the log lines of Repo calls still show `nil`; the log line of `Ecto.Adapters.SQL.explain/4`, which logs the dumped parameters, shows the pair. Noting it for the changelog.

The NULL is also narrower than the varbinary one it replaces, because it is typed from the declared Ecto field type. A built-in field declared over a column of another family, such as a `:date` field over a legacy `int` column, can no longer write nil, where the over-wide varbinary NULL was accepted. Such a field cannot write or read a non-nil value either, before or after this change, so no working schema is affected.

### Why the adapter's dumpers

tds#124 discussed passing the known types from changesets and queries down to the driver (the `wm-types` proof of concept in ecto and ecto_sql). Doing it in `dumpers/2` reaches the same goal without changing Ecto: every value Ecto dumps with a known type goes through the adapter's dumpers, which covers `Repo.insert/2`, `Repo.update/2`, `Repo.insert_all/3`, `Repo.update_all/3` and typed query parameters. As a side effect, `type(^value, :float)` with a nil value now works; today it becomes a cast of varbinary to float, which SQL Server rejects with error 529.

### Not covered

The rule is that the NULL is typed from the declared Ecto field type. That is right for the columns Ecto's migrations create for these types, and for any other date, time or float column. It is not applied in these cases:

- **Values without a type**: queries on a table name instead of a schema, `fragment/1` parameters and raw SQL still send an untyped nil. `type/2` or an explicit `%Tds.Parameter{}` remains the answer there.
- **Other types on columns that refuse a varbinary NULL**: `:string`, `:map` and `Tds.Ecto.VarChar` fields on legacy `text`/`ntext` columns, and a `:decimal` field on a `float` or `real` column, are still refused. Fixing strings would mean declaring nil strings as `nvarchar`, which breaks `:string` fields on `varbinary` columns, and the driver declares even an explicitly typed nil decimal as varbinary, so this PR leaves those types alone.
- **`in ^list` with a nil element**: Ecto dumps the list element by element and leaves a nil element bare, so it is still sent untyped, and SQL Server refuses to compare it with the column (error 402). Pre-existing. A `dumpers({:in, type}, {:in, type})` clause, like the Postgres adapter's, could type it without changing Ecto, but this PR leaves lists alone.
- **Custom Ecto types with these primitives** are left as today, for the reason above.

### Tests

- `test/ecto/type_test.exs`: dumping nil through the Tds adapter returns `{nil, tds_type}` for each of the eight types, while other types, non-nil values, arrays and a custom type with the `:date` primitive are unchanged.
- `test/ecto/adapters/tds_test.exs`: a nil of each of the eight types, dumped through the adapter, is prepared with the same parameter type as a non-nil value of the same field (`:float` for a float, which `prepare_params/1` leaves to the driver); a tagged nil is numbered like any other parameter, and an untagged nil is left to the driver as before; `update/5` and `delete/4` still compare a tagged nil filter with `IS NULL`.
- `integration_test/tds/nil_parameters_test.exs`: writes nil through `Repo.insert/2`, `Repo.update/2`, `Repo.insert_all/3` and `Repo.update_all/3` for each affected column type, plus a `type/2` cast of a nil float. It also covers the legacy `datetime` columns, which already accepted a varbinary NULL, and a custom type with the `:date` primitive on an integer column, to show both still work.

Without the fix, the four unit tests that check the typed NULL and the tagged nil filter fail, and 29 of the 40 integration tests fail; the 11 that pass cover the legacy `datetime` columns and the custom type, which work on both. With it, `mix test` passes (707 tests), `ECTO_ADAPTER=tds mix test` passes (418 tests, 101 excluded) against SQL Server 2022 (16.0.4275.2), and `mix test.as_a_dep` still compiles ecto_sql without tds.

A standalone reproduction covering 26 combinations of Ecto field type and column type is at https://github.com/jasoncpowell/tds_repro.
<!-- pr-body:end -->

## Verification log

Run on 2026-10-06 against ecto_sql master [`f049198`](https://github.com/elixir-ecto/ecto_sql/commit/f049198) with the patches applied, Elixir 1.20.4 on OTP 29, tds 2.3.8, and SQL Server 2022 (16.0.4275.2) running under Rosetta 2 emulation on Apple Silicon. ecto_sql's own CI uses Elixir 1.19.4 for unit tests and SQL Server 2019 and 2022 for Tds integration tests.

Without a database:

| Check | Result |
|---|---|
| `mix test`, with the fix | 707 passed |
| `mix format --check-formatted`, with the fix | passes |
| unit tests, without the fix | 4 of 139 failed; all four failures are new tests |
| `mix test.as_a_dep`, with the fix | passes |
| `mix test.as_a_dep`, with the first version's `tds.ex` | fails: "Tds.Parameter.__struct__/1 is undefined, cannot expand struct Tds.Parameter" |

Tds integration suite:

| Check | SQL Server 2022 (16.0.4275.2) |
|---|---|
| `ECTO_ADAPTER=tds mix test`, with the fix | 418 passed, 101 excluded |
| `nil_parameters_test.exs`, without the fix | 29 of 40 failed; the 11 that pass are the `datetime` column and custom type tests, which must pass on both |

The 2026-09-15 run of the first version of the fix, which built the `%Tds.Parameter{}` in the dumpers, also passed against SQL Server 2017 (14.0.3550.4) and 2019 (15.0.4490.9). The 2026-09-21 run of the version that tagged the nil with its Ecto type passed the same suites on master `86234e7` (704 unit tests). The parameters SQL Server receives are the same in both tagged versions.

`bin/verify-upstream` reproduces the with/without-fix checks for the new tests and runs `mix test.as_a_dep`, and CI runs it weekly against ecto_sql master and SQL Server 2019.

## Issue comments to post after the PR is open

On [tds#124](https://github.com/elixir-ecto/tds/issues/124), replacing `NNN`:

> I've opened elixir-ecto/ecto_sql#NNN, which fixes this in the Tds adapter: nil for date, time and float fields is now sent as a typed parameter (the dumpers tag the nil with the SQL Server type it is declared as, and the connection passes it to the driver as a typed parameter), so the driver never has to guess. It follows the direction discussed here: the type comes from Ecto, and the driver's `:binary` fallback is untouched. A reproduction with before/after tests is at https://github.com/jasoncpowell/tds_repro.

On [tds#168](https://github.com/elixir-ecto/tds/issues/168):

> This is the same bug as #124: the explicit nil reaches the driver without a type and is declared as varbinary. elixir-ecto/ecto_sql#NNN fixes it for schema fields, including `Repo.insert_all/3`.

## Open decisions

- ~~Whether to link the reproduction repository in the PR and comments.~~ Resolved 2026-09-21: `jasoncpowell/tds_repro` is public and returns 200 unauthenticated. Recheck before any later edit, and remove the links if that changes.
- Whether to mention the `text`/`ntext` limitation as a follow-up, or leave it unless a maintainer asks.
- ~~Whether the adapter should tag the nil with the TDS type (`{nil, :datetime2}`) instead of the Ecto type, as the first version of the fix did.~~ Resolved 2026-09-21 as "keep the Ecto type", then reversed on 2026-10-06 after team review: the adapter tags with the TDS type (`cbe5fdf`).
  - **Why.** The dumpers are where Ecto translates values "into adapter ones". Before the fix, the connection's parameter code only took plain values, `%Tds.Parameter{}` and `{value, :varchar}`, which is a value already paired with a driver type. The Ecto-type tag made it translate Ecto types for the first time.
  - **The 2026-09-21 reasons don't hold up.** `tds.ex` already calls tds at runtime (`Tds.Ecto.UUID`, `Tds.json_library/0`, `Tds.start_link/1`); only expanding a Tds struct there is ruled out. Ecto documents telemetry `:params` as "formatted for database drivers", and on Tds they already carry `Tds.Ecto.UUID`'s bytes, while `:cast_params` and Repo log lines still show `nil`. `prepare_param/1` types values by their struct, not by Ecto type, so there was no single decision to split. What is true is that a nil's type and a value's must agree, and they are now decided in different modules; the round-trip tests check that.
  - **Accepted costs.** `to_sql/3` and telemetry show `:datetimeoffset` for a `:utc_datetime` field. The five TDS types are listed both in the adapter's map and in the connection's guard; a mismatch fails loudly.
  - **Upstream.** The PR's "Change" section explains the pairing in one sentence. The decision itself isn't raised with the maintainers.
- Whether to also open a tds issue or PR so the driver declares a nil `:float` parameter as `float` instead of `decimal(1,0)` (`encode_float_type/1` and `encode_float_descriptor/1` in `lib/tds/types.ex`). It works today because SQL Server converts decimal to `float` and `real` implicitly, so this repo documents it and doesn't fix it.
