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

The same happens with `Repo.insert_all/3` rows containing nil and with `Repo.update_all/3` setting nil.

### Cause

`Ecto.Adapters.Tds.Connection.prepare_param/1` picks a parameter type from the value (`%Date{}` becomes `:date`, and so on). A nil has nothing to pick from, so it reaches the driver untyped, and `Tds.Parameter.fix_data_type/1` declares it as `:binary`. SQL Server refuses to convert a varbinary NULL to `date`, `time`, `datetime2`, `datetimeoffset`, `float` or `real` columns.

As discussed in [tds#124](https://github.com/elixir-ecto/tds/issues/124#issuecomment-2159179856) and [tds#162](https://github.com/elixir-ecto/tds/pull/162#issuecomment-2157626223), the driver can't choose a better default: every type is refused by some column, and `:string` breaks `binary`, `varbinary` and `image` columns. The field's type has to come from Ecto.

### Change

`Ecto.Adapters.Tds.dumpers/2` now tags a nil of the affected Ecto types with its type, as `{nil, :date}` and so on, the way `Tds.Ecto.VarChar` dumps `{value, :varchar}`. `Ecto.Adapters.Tds.Connection.prepare_params/1` turns the tag into a `%Tds.Parameter{}` through the same path as every other parameter, declared as the type `prepare_param/1` already uses for a non-nil date or time value of the same Ecto type, or as `float` for a nil float. The driver keeps an explicit type and only falls back to `:binary` when there is none.

The dumpers tag instead of building the struct because `lib/ecto/adapters/tds.ex` compiles without the optional tds dependency: unlike the connection, it has no `Code.ensure_loaded?(Tds)` guard, and a `%Tds.Parameter{}` literal there fails to compile for every ecto_sql user who doesn't have tds. So the struct is built in `Ecto.Adapters.Tds.Connection`, which only compiles when tds is loaded.

The dumpers clause matches the Ecto type against its own primitive, so only built-in types are tagged. A custom type with one of these primitives is unchanged: Ecto never calls its `dump/1` for nil, so the adapter can't tell how the type stores non-nil values (for example a `:date`-typed custom type that stores integers in an `int` column, which refuses a `date` NULL).

| Ecto type | NULL is declared as |
|---|---|
| `:date` | `date` |
| `:time`, `:time_usec` | `time` |
| `:naive_datetime`, `:naive_datetime_usec` | `datetime2` |
| `:utc_datetime`, `:utc_datetime_usec` | `datetimeoffset` |
| `:float` | `float` (the driver declares a nil float as `decimal(1,0)`, which converts implicitly to `float` and `real`) |

For the date and time types these are exactly the types `prepare_param/1` declares for non-nil `%Date{}`, `%Time{}`, `%NaiveDateTime{}` and `%DateTime{}` values. Non-nil values and all other types are untouched.

This relies on elixir-ecto/ecto#4214 (Ecto 3.11), which passes nil through adapter dumpers.

### Visible change

`Ecto.Adapters.SQL.to_sql/3` and the `:params` metadata of query telemetry events now contain `{nil, :date}` and the like for these fields, where they contained `nil`. Logged parameters are the cast values and still show `nil`. Nothing else changes for users; noting it for the changelog.

### Why the adapter's dumpers

tds#124 discussed passing the known types from changesets and queries down to the driver (the `wm-types` proof of concept in ecto and ecto_sql). Doing it in `dumpers/2` reaches the same goal without changing Ecto: every value Ecto dumps with a known type goes through the adapter's dumpers, which covers `Repo.update/2`, `Repo.insert_all/3`, `Repo.update_all/3` and typed query parameters. As a side effect, `type(^value, :float)` with a nil value now works; today it becomes a cast of varbinary to float, which SQL Server rejects with error 529.

### Not covered

The rule is that the NULL is typed from the declared Ecto field type. That is right for the columns Ecto's migrations create for these types, and for any other date, time or float column. It is not applied in these cases:

- **Values without a type**: queries on a table name instead of a schema, `fragment/1` parameters and raw SQL still send an untyped nil. `type/2` or an explicit `%Tds.Parameter{}` remains the answer there.
- **`:string` fields on legacy `text`/`ntext` columns** are also refused. Fixing them would mean declaring nil strings as `nvarchar`, which breaks `:string` fields on `varbinary` columns, so this PR leaves strings alone.
- **Custom Ecto types with these primitives** are left as today, for the reason above.

### Tests

- `test/ecto/type_test.exs`: dumping nil through the Tds adapter returns the tagged tuple for each of the eight types, while other types, non-nil values, arrays and a custom type with the `:date` primitive are unchanged.
- `test/ecto/adapters/tds_test.exs`: `prepare_params/1` turns each tag into the typed `%Tds.Parameter{}`, numbered like any other parameter, and leaves an untagged nil to the driver as before.
- `integration_test/tds/nil_parameters_test.exs`: writes nil through `Repo.update/2`, `Repo.insert_all/3` and `Repo.update_all/3` for each affected column type, plus a `type/2` cast of a nil float. It also covers the legacy `datetime` columns, which already accepted a varbinary NULL, and a custom type with the `:date` primitive on an integer column, to show both still work.

Without the fix, the three unit tests that check the typed NULL fail, and 22 of the 31 integration tests fail; the 9 that pass cover the legacy `datetime` columns and the custom type, which work on both. With it, `mix test` passes (700 tests), and `ECTO_ADAPTER=tds mix test` passes (409 tests, 101 excluded) against SQL Server 2022 (16.0.4275.2).

A standalone reproduction covering 26 combinations of Ecto field type and column type is at https://github.com/jasoncpowell/tds_repro.
<!-- pr-body:end -->

## Verification log

Run on 2026-09-18 against ecto_sql master [`2385763`](https://github.com/elixir-ecto/ecto_sql/commit/23857635127b8e94031847dd7522923e48b80150) with the patches applied, Elixir 1.20.4 on OTP 29, tds 2.3.8, and SQL Server 2022 (16.0.4275.2) running under Rosetta 2 emulation on Apple Silicon. ecto_sql's own CI uses Elixir 1.19.4 for unit tests and SQL Server 2019 and 2022 for Tds integration tests.

Without a database:

| Check | Result |
|---|---|
| `mix test`, with the fix | 700 passed |
| `mix test test/ecto/type_test.exs test/ecto/adapters/tds_test.exs`, without the fix | 3 of 138 failed; all three failures are new tests |

Tds integration suite:

| Check | SQL Server 2022 (16.0.4275.2) |
|---|---|
| `ECTO_ADAPTER=tds mix test`, with the fix | 409 passed, 101 excluded |
| `nil_parameters_test.exs`, without the fix | 22 of 31 failed; the 9 that pass are the `datetime` column and custom type tests, which must pass on both |

The 2026-09-15 run of the earlier version of the fix, which built the `%Tds.Parameter{}` in the dumpers, also passed against SQL Server 2017 (14.0.3550.4) and 2019 (15.0.4490.9).

`bin/verify-upstream` reproduces the with/without-fix checks for the new tests, and CI runs it weekly against ecto_sql master and SQL Server 2019.

## Issue comments to post after the PR is open

On [tds#124](https://github.com/elixir-ecto/tds/issues/124), replacing `NNN`:

> I've opened elixir-ecto/ecto_sql#NNN, which fixes this in the Tds adapter: nil for date, time and float fields is now sent as a typed parameter (the dumpers tag the nil with its Ecto type, and the connection declares the parameter type), so the driver never has to guess. It follows the direction discussed here: the type comes from Ecto, and the driver's `:binary` fallback is untouched. A reproduction with before/after tests is at https://github.com/jasoncpowell/tds_repro.

On [tds#168](https://github.com/elixir-ecto/tds/issues/168):

> This is the same bug as #124: the explicit nil reaches the driver without a type and is declared as varbinary. elixir-ecto/ecto_sql#NNN fixes it for schema fields, including `Repo.insert_all/3`.

## Open decisions

- Whether to link the reproduction repository in the PR and comments. It was publicly reachable on 2026-09-15; remove the links if that changes before submitting.
- Whether to mention the `text`/`ntext` limitation as a follow-up, or leave it unless a maintainer asks.
- Whether the adapter should tag the nil with the TDS type (`{nil, :datetime2}`) instead of the Ecto type, as the first version of the fix did. That would remove the mapping table from the connection and mirror the `{_, :varchar}` clause exactly, at the cost of TDS type names in the adapter and in `to_sql/3` output. The current split keeps the Ecto-to-TDS mapping next to `prepare_param/1` and `ecto_to_db/5`, where the other two copies live. Worth raising if a maintainer prefers the smaller change.
- Whether to also open a tds issue or PR so the driver declares a nil `:float` parameter as `float` instead of `decimal(1,0)` (`encode_float_type/1` and `encode_float_descriptor/1` in `lib/tds/types.ex`). It works today because SQL Server converts decimal to `float` and `real` implicitly, so this repo documents it and doesn't fix it.
