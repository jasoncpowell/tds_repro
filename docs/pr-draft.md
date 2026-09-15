# PR draft for elixir-ecto/ecto_sql

> **Internal draft, not yet submitted.** Everything below the line is the
> proposed PR description, written for the ecto_sql maintainers. The checklist
> at the end is for us and gets removed before posting.

---

## Tds: send typed NULL for nil date, time and float parameters

Setting a `date`, `time`, `datetime2`, `datetimeoffset`, `float` or `real`
column to nil through Ecto fails on SQL Server:

```
** (Tds.Error) Line 1 (Error 257): Implicit conversion from data type varbinary to date is not allowed. Use the CONVERT function to run this query.
```

This addresses elixir-ecto/tds#124 and elixir-ecto/tds#168 from the ecto_sql
side, as suggested in the discussion on those issues.

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

The same happens with `Repo.insert_all/3` rows containing nil and with
`Repo.update_all/3` setting nil.

### Cause

`Ecto.Adapters.Tds.Connection.prepare_param/1` picks a parameter type from the
value (`%Date{}` becomes `:date`, and so on). A nil has nothing to pick from,
so it reaches the driver untyped and `Tds.Parameter.fix_data_type/1` declares
it as `:binary`. SQL Server refuses to convert a varbinary NULL to `date`,
`time`, `datetime2`, `datetimeoffset`, `float` or `real` columns.

As discussed in [tds#124](https://github.com/elixir-ecto/tds/issues/124#issuecomment-2159179856)
and [tds#162](https://github.com/elixir-ecto/tds/pull/162#issuecomment-2157626223),
the driver can't choose a better default: every type is refused by some
column, and `:string` breaks `binary`, `varbinary` and `image`. The field's
type has to come from Ecto.

### Change

`Ecto.Adapters.Tds.dumpers/2` now wraps nil for the affected Ecto types in a
`%Tds.Parameter{}` with an explicit type. `prepare_param/1` already passes
typed parameters through, and the driver only falls back to `:binary` when the
type is missing.

| Ecto type | NULL is declared as |
|---|---|
| `:date` | `date` |
| `:time`, `:time_usec` | `time` |
| `:naive_datetime`, `:naive_datetime_usec` | `datetime2` |
| `:utc_datetime`, `:utc_datetime_usec` | `datetimeoffset` |
| `:float` | `float` |

These are the types `prepare_param/1` already uses for non-nil values of
those fields, so no new conversions are introduced. Non-nil values and all
other types are untouched.

### Why the adapter's dumpers

tds#124 discussed passing the known types from changesets and queries down to
the driver (the `wm-types` proof of concept in ecto and ecto_sql). Doing it in
`dumpers/2` reaches the same goal without changing Ecto: every value Ecto
dumps with a known type goes through the adapter's dumpers, which covers
`Repo.update/2`, `Repo.insert_all/3`, `Repo.update_all/3` and typed query
parameters. As a side effect, `type(^value, :float)` with a nil value now
works; today it becomes a CAST of varbinary to float, which SQL Server
rejects with error 529.

### Not covered

- **Values without a type**: queries on a table name instead of a schema,
  `fragment/1` parameters and raw SQL still send an untyped nil. `type/2` or an
  explicit `%Tds.Parameter{}` remains the answer there.
- **`:string` fields on legacy `text`/`ntext` columns** are also refused.
  Fixing them would mean declaring nil strings as `nvarchar`, which breaks
  `:string` fields on `varbinary` columns, so this PR leaves strings alone.

### Testing

- Unit tests in `test/ecto/adapters/tds_test.exs` for each affected type, and
  that other types and non-nil values are unchanged.
- Integration tests in `integration_test/tds` updating, bulk inserting and
  `update_all`-ing nil for each affected type.
- Checked against SQL Server 2022 with a standalone reproduction covering 25
  combinations of Ecto field type and column type across `Repo.update/2`,
  `Repo.insert_all/3` and `Repo.update_all/3`:
  https://github.com/jasoncpowell/tds_repro

---

## Before submitting (internal)

- [ ] Fork ecto_sql, branch from `master`, and apply the fix commit with
      `git format-patch` / `git am` (see the README).
- [ ] Add the unit tests to `test/ecto/adapters/tds_test.exs`.
- [ ] Add the integration tests to `integration_test/tds` and run them with
      `ECTO_ADAPTER=tds mix test` against SQL Server.
- [ ] Run the full `mix test` in the fork.
- [ ] Add a `CHANGELOG.md` entry.
- [ ] Make sure the repro repository is public, or drop the link.
- [ ] After opening the PR, comment on tds#124 and tds#168 linking to it.
