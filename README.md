# tds_repro

[![CI](https://github.com/jasoncpowell/tds_repro/actions/workflows/ci.yml/badge.svg)](https://github.com/jasoncpowell/tds_repro/actions/workflows/ci.yml)

A reproduction, test suite and proposed fix for an Ecto bug on SQL Server:
writing `nil` to a `date`, `time`, `datetime2`, `datetimeoffset` or `float`
column fails.

```
** (Tds.Error) Line 1 (Error 257): Implicit conversion from data type varbinary to date is not allowed.
```

Reported upstream as [tds#124](https://github.com/elixir-ecto/tds/issues/124)
(2021) and [tds#168](https://github.com/elixir-ecto/tds/issues/168) (2025),
both still open.

## Status

| | |
|---|---|
| **Bug** | Reproduces on ecto_sql 3.14.0, tds 2.3.8 and SQL Server 2022. |
| **Fix** | 13 lines in `Ecto.Adapters.Tds.dumpers/2` (commit `4d570f4`), applied to the copy of ecto_sql in [`vendor/ecto_sql`](vendor/ecto_sql). All 100 tests pass with it. |
| **Upstream PR** | Not submitted yet. Draft in [docs/pr-draft.md](docs/pr-draft.md). |

## Who is affected

Apps using Ecto with SQL Server that set one of these fields to nil through
`Repo.update/2`, `Repo.insert_all/3` or `Repo.update_all/3`:

- `:date`, `:time`, `:time_usec`, `:naive_datetime_usec`, `:utc_datetime_usec`
  and `:float` fields, with the columns Ecto's migrations create for them
- fields on hand-written columns of those SQL Server types, plus `real`,
  `text` and `ntext`

Plain `timestamps()` fields are not affected: they use the legacy `datetime`
type, which accepts the NULL. Details in [docs/root-cause.md](docs/root-cause.md).

To find exposed columns in a database, run
[`scripts/find_affected_columns.sql`](scripts/find_affected_columns.sql) in any
SQL Server client.

## Quick start

Needs Docker, Elixir and a Unix shell (macOS, Linux, or WSL on Windows).
Tested with Elixir 1.17.2 on OTP 27 and Elixir 1.20.4 on OTP 29. On Apple
Silicon, turn on Rosetta in Docker Desktop: the SQL Server image is amd64-only.

```sh
docker compose up -d --wait   # SQL Server on port 1433, waits until ready
mix setup                     # deps, database, migrations
bin/compare                   # the bug on released ecto_sql, then the fix
```

`bin/compare` runs the test suite against both versions of ecto_sql and checks
each result:

```
Released ecto_sql 3.14.0 (ECTO_SQL=upstream)
  ok    the bug reproduces: every :bug test fails (33 of 33 failed)
  ok    every other test passes (0 of 67 failed)

Vendored ecto_sql with the fix
  ok    every test passes (0 of 100 failed)
```

If port 1433 is taken, pick another and pass it to every command, for example
`MSSQL_PORT=14330 docker compose up -d --wait` and `MSSQL_PORT=14330 mix setup`.
If you started SQL Server earlier with `docker run --name mssql-repro`, remove
it first with `docker rm -f mssql-repro`.

Tear down with `docker compose down -v`.

## Released ecto_sql or the fix

By default the app compiles against [`vendor/ecto_sql`](vendor/ecto_sql), which
carries the fix. Set `ECTO_SQL=upstream` to compile against ecto_sql 3.14.0 from
Hex instead. Each gets its own build directory (`_build` and `_build_upstream`),
so switching is instant and never mixes the two. The first upstream build prints
compiler warnings from the tds dependency; they're not from this repo.

### Repro script

```sh
ECTO_SQL=upstream mix run -e "TdsRepro.run()"   # released
mix run -e "TdsRepro.run()"                     # with the fix
```

On released ecto_sql:

```
Using ecto_sql 3.14.0 as released (ECTO_SQL=upstream)

  works  INSERT leaving every date, time and float field nil
  BUG    UPDATE :date field on a date column to nil
         Line 1 (Error 257): Implicit conversion from data type varbinary to date is not allowed.
  BUG    UPDATE :time field on a time column to nil
         Line 1 (Error 257): Implicit conversion from data type varbinary to time is not allowed.
  BUG    UPDATE :time_usec field on a time(6) column to nil
         Line 1 (Error 257): Implicit conversion from data type varbinary to time is not allowed.
  works  UPDATE :naive_datetime field on a datetime column to nil
  BUG    UPDATE :naive_datetime_usec field on a datetime2 column to nil
         Line 1 (Error 257): Implicit conversion from data type varbinary to datetime2 is not allowed.
  BUG    UPDATE :utc_datetime_usec field on a datetimeoffset column to nil
         Line 1 (Error 257): Implicit conversion from data type varbinary to datetimeoffset is not allowed.
  BUG    UPDATE :float field on a float column to nil
         Line 1 (Error 206): Operand type clash: varbinary is incompatible with float
  BUG    insert_all with an explicit nil date
         Line 1 (Error 257): Implicit conversion from data type varbinary to date is not allowed.
  works  raw UPDATE with a typed %Tds.Parameter{} (what the fix sends)

7 of 10 writes hit the bug.
```

With the fix, every line reads `works` and it ends with `0 of 10 writes hit the bug.`

### Tests

```sh
mix test                                   # with the fix: all 100 pass
ECTO_SQL=upstream mix test --only bug      # released: all 33 fail
ECTO_SQL=upstream mix test --exclude bug   # released: the other 67 pass
```

Tests tagged `:bug` fail on released ecto_sql and pass with the fix. Everything
else passes on both.

| File | Covers |
|---|---|
| [`dumpers_test.exs`](test/tds_repro/dumpers_test.exs) | How the adapter dumps nil, without a database. The shape of the unit test the upstream PR needs. |
| [`nil_values_test.exs`](test/tds_repro/nil_values_test.exs) | Writing nil through `Repo.update`, `Repo.insert_all` and `Repo.update_all` for 25 combinations of Ecto field type and column type, plus checks that nothing else changed. |
| [`known_limitations_test.exs`](test/tds_repro/known_limitations_test.exs) | What the fix doesn't cover, asserted so a change in behaviour is noticed. |
| [`workarounds_test.exs`](test/tds_repro/workarounds_test.exs) | What works on released ecto_sql today. |

Tests use their own `tds_repro_test` database, created and migrated by
`mix test`.

### The fix itself

```sh
git show 4d570f4
```

## Scripts

| Command | Shows |
|---|---|
| `mix run scripts/conversion_matrix.exs` | Which column types accept a NULL declared as each type: why no single fallback works, and that the fix's typed NULLs are accepted. |
| `mix run scripts/find_affected_columns.exs` | The affected-columns query run against this repo's database. |

## Docs

- [Root cause](docs/root-cause.md): where the type gets lost, which types fail, and what the fix changes.
- [Upstream history](docs/upstream-history.md): what has been tried and said upstream, and how the fix responds.
- [Workarounds](docs/workarounds.md): writing nil on released ecto_sql today.
- [PR draft](docs/pr-draft.md): the proposed ecto_sql PR description and what's left before submitting.

## Vendored ecto_sql

`vendor/ecto_sql` is a copy of [ecto_sql](https://github.com/elixir-ecto/ecto_sql)
3.14.0 as published on Hex (Apache-2.0, see its `LICENSE.md`). It was committed
unmodified first (`1e4b48f`), and changes to it are kept in their own commits,
so this shows exactly what would go into an upstream PR:

```sh
git log -p -- vendor/ecto_sql
```

To move the fix into a fork of ecto_sql:

```sh
# in this repo
git format-patch -1 4d570f4 --relative=vendor/ecto_sql -o ..
# in the fork, on a new branch
git am -3 ../0001-*.patch
```

## CI

[`.github/workflows/ci.yml`](.github/workflows/ci.yml) runs `bin/compare upstream`
and `bin/compare fixed` as separate jobs against a SQL Server service
container, and checks formatting.
