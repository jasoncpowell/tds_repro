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

`Ecto.Adapters.Tds.dumpers/2` now wraps nil for the affected Ecto types in a `%Tds.Parameter{}` with an explicit type. `prepare_param/1` already passes typed parameters through, and the driver only falls back to `:binary` when the type is missing.

| Ecto type | NULL is declared as |
|---|---|
| `:date` | `date` |
| `:time`, `:time_usec` | `time` |
| `:naive_datetime`, `:naive_datetime_usec` | `datetime2` |
| `:utc_datetime`, `:utc_datetime_usec` | `datetimeoffset` |
| `:float` | `float` |

These are the types `prepare_param/1` already uses for non-nil values of those fields, so no new conversions are introduced. Non-nil values and all other types are untouched.

This relies on elixir-ecto/ecto#4214 (Ecto 3.11), which passes nil through adapter dumpers.

### Why the adapter's dumpers

tds#124 discussed passing the known types from changesets and queries down to the driver (the `wm-types` proof of concept in ecto and ecto_sql). Doing it in `dumpers/2` reaches the same goal without changing Ecto: every value Ecto dumps with a known type goes through the adapter's dumpers, which covers `Repo.update/2`, `Repo.insert_all/3`, `Repo.update_all/3` and typed query parameters. As a side effect, `type(^value, :float)` with a nil value now works; today it becomes a cast of varbinary to float, which SQL Server rejects with error 529.

### Not covered

- **Values without a type**: queries on a table name instead of a schema, `fragment/1` parameters and raw SQL still send an untyped nil. `type/2` or an explicit `%Tds.Parameter{}` remains the answer there.
- **`:string` fields on legacy `text`/`ntext` columns** are also refused. Fixing them would mean declaring nil strings as `nvarchar`, which breaks `:string` fields on `varbinary` columns, so this PR leaves strings alone.

### Tests

- `test/ecto/type_test.exs`: dumping nil through the Tds adapter returns a typed `%Tds.Parameter{}` for each affected type, while other types and non-nil values are unchanged.
- `integration_test/tds/nil_parameters_test.exs`: writes nil through `Repo.update/2`, `Repo.insert_all/3` and `Repo.update_all/3` for each affected column type, plus a `type/2` cast of a nil float. It also covers the legacy `datetime` columns, which already accepted a varbinary NULL, to show they still work.

Without the fix, the new unit test fails and 22 of the 28 integration tests fail. With it, `mix test` passes (693 tests), and `ECTO_ADAPTER=tds mix test` passes (406 tests, 101 excluded) against SQL Server 2017, 2019 and 2022.

A standalone reproduction covering 25 combinations of Ecto field type and column type is at https://github.com/jasoncpowell/tds_repro.
<!-- pr-body:end -->

## Verification log

Run on 2026-09-15 against ecto_sql master [`2385763`](https://github.com/elixir-ecto/ecto_sql/commit/2385763) with the patches applied, Elixir 1.20.4 on OTP 29, tds 2.3.8, and SQL Server running under Rosetta 2 emulation on Apple Silicon. ecto_sql's own CI uses Elixir 1.19.4 for unit tests and SQL Server 2017 and 2019 for Tds integration tests.

Without a database:

| Check | Result |
|---|---|
| `mix test`, with the fix | 693 passed |
| `mix test test/ecto/type_test.exs`, without the fix | 2 of 3 passed; the failure is the new test |

Tds integration suite:

| Check | SQL Server 2017 (14.0.3550.4) | SQL Server 2019 (15.0.4490.9) | SQL Server 2022 (16.0.4275.2) |
|---|---|---|---|
| `ECTO_ADAPTER=tds mix test`, with the fix | 406 passed, 101 excluded | 406 passed, 101 excluded | 406 passed, 101 excluded |
| `ECTO_ADAPTER=tds mix test`, without the fix | not run | not run | 384 of 406 passed; all 22 failures are new tests |
| `nil_parameters_test.exs`, without the fix | 6 of 28 passed | 6 of 28 passed | 6 of 28 passed |

`bin/verify-upstream` reproduces the with/without-fix checks for the new tests, and CI runs it weekly against ecto_sql master and SQL Server 2019.

## Issue comments to post after the PR is open

On [tds#124](https://github.com/elixir-ecto/tds/issues/124), replacing `NNN`:

> I've opened elixir-ecto/ecto_sql#NNN, which fixes this in the Tds adapter: `Ecto.Adapters.Tds.dumpers/2` now sends nil for date, time and float fields as a typed parameter, so the driver never has to guess. It follows the direction discussed here: the type comes from Ecto, and the driver's `:binary` fallback is untouched. A reproduction with before/after tests is at https://github.com/jasoncpowell/tds_repro.

On [tds#168](https://github.com/elixir-ecto/tds/issues/168):

> This is the same bug as #124: the explicit nil reaches the driver without a type and is declared as varbinary. elixir-ecto/ecto_sql#NNN fixes it for schema fields, including `Repo.insert_all/3`.

## Open decisions

- Whether to link the reproduction repository in the PR and comments. It was publicly reachable on 2026-09-15; remove the links if that changes before submitting.
- Whether to mention the `text`/`ntext` limitation as a follow-up, or leave it unless a maintainer asks.
