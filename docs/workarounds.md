# Workarounds on released ecto_sql

Until a fix is released, these are the ways to write nil to an affected column.
Each one is checked by [`test/tds_repro/workarounds_test.exs`](../test/tds_repro/workarounds_test.exs)
against released ecto_sql 3.14.0.

To find which columns need them, run
[`scripts/find_affected_columns.sql`](../scripts/find_affected_columns.sql)
against the database, and see the field type table in
[root-cause.md](root-cause.md#why-only-some-column-types-fail).

## Summary

| Write | Date and time columns | `float` / `real` columns |
|---|---|---|
| `Repo.update/2` with a changeset | no direct workaround; use one of the options below | same |
| `Repo.update_all/3` | `type(^value, :date)` hint | raw SQL with a typed parameter |
| `Repo.insert_all/3` | leave the nil keys out | leave the nil keys out |
| Raw SQL | typed `%Tds.Parameter{}` | typed `%Tds.Parameter{}` |

## `update_all` with a `type/2` hint

Declaring the type in the query makes ecto_sql cast the parameter, and SQL
Server allows casting a varbinary NULL to `date`, `time`, `datetime2` and
`datetimeoffset`:

```elixir
value = nil

from(p in Post, where: p.id == ^post.id, update: [set: [published_on: type(^value, :date)]])
|> Repo.update_all([])
```

This also works on a table name without a schema.

It does **not** work for `float` or `real` columns: SQL Server doesn't allow
casting varbinary to float at all (error 529). With the fix it does.

`update_all` skips changesets, so validations don't run and `updated_at` isn't
set automatically. Set it in the same `set:` if you need it.

## Raw SQL with a typed parameter

An explicit type on `%Tds.Parameter{}` always wins, for any column type:

```elixir
Repo.query!("UPDATE posts SET score = @1 WHERE id = @2", [
  %Tds.Parameter{name: "@1", value: nil, type: :float},
  %Tds.Parameter{name: "@2", value: post.id, type: :integer}
])
```

Use `:date`, `:time`, `:datetime2`, `:datetimeoffset` or `:float` to match the
column.

## `insert_all` without the nil keys

A key that is left out isn't sent as a parameter, so the column gets its
default:

```elixir
rows = Enum.map(rows, &Map.reject(&1, fn {_key, value} -> is_nil(value) end))
Repo.insert_all(Post, rows)
```

Rows may leave out different keys. This inserts NULL only if the column's
default is NULL; a column with another default gets that instead.

## Changeset updates

There's no way to make `Repo.update/2` send a typed NULL on released ecto_sql:
the type is dropped inside the adapter, after the changeset is done. The
options are:

- **Split the write.** Apply the other changes with `Repo.update/2`, then clear
  the affected fields with `update_all` and a `type/2` hint (date and time
  columns) or raw SQL (float columns), ideally in one transaction.
- **Use the fix before it's released.** Point the app at a fork of ecto_sql
  that carries the fix, for example
  `{:ecto_sql, github: "your-org/ecto_sql", branch: "tds-nil-params"}`. This
  fixes every write path at once, but means tracking upstream releases on the
  fork until the fix lands, then switching back.

## Not recommended

Changing the column type to one that accepts a varbinary NULL (for example
`date` to `datetime`, or storing dates as strings, as one reporter on tds#124
did) avoids the error but changes storage and semantics for every row to work
around a driver issue.

## What doesn't work

These fail on released ecto_sql, and still fail with the fix. They're pinned
down in [`test/tds_repro/known_limitations_test.exs`](../test/tds_repro/known_limitations_test.exs):

- `fragment("?", ^value)` with a nil value, and raw SQL with a plain `nil`
  parameter: there is no type to use. Use a typed `%Tds.Parameter{}` instead.
- `insert_all` or `update_all` with nil on a table name instead of a schema,
  without a `type/2` hint.
- `:string` fields on legacy `text` or `ntext` columns. Raw SQL with
  `%Tds.Parameter{type: :string}` works for these.
