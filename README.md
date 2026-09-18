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
| **Bug** | Reproduces on the latest releases (ecto_sql 3.14.0, ecto 3.14.2, tds 2.3.8) and on ecto_sql master, against SQL Server 2017, 2019 and 2022. |
| **Fix** | Two small changes to ecto_sql's Tds adapter: `Ecto.Adapters.Tds.dumpers/2` tags a nil of the affected Ecto types with its type, and `Ecto.Adapters.Tds.Connection.prepare_params/1` turns the tag into a typed `%Tds.Parameter{}`. Applied to the copy of ecto_sql in [`vendor/ecto_sql`](vendor/ecto_sql) (`git log -p -- vendor/ecto_sql` shows it). All 121 tests in this repo pass with it. |
| **Upstream PR** | Ready, not submitted. The fix and its tests are in [`upstream/ecto_sql/`](upstream/ecto_sql) and pass on ecto_sql master: ecto_sql's full unit suite, and its full Tds integration suite against SQL Server 2022, with no regressions (the first version of the fix also passed on 2017 and 2019). See the [PR draft](docs/pr-draft.md) and [how to submit it](docs/creating-the-pr.md). |

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

## Setup

### Prerequisites

- **Docker**, with at least 2 GB of memory for containers, Microsoft's minimum
  for SQL Server.
- **On Apple Silicon**, turn on *Use Rosetta for x86_64/amd64 emulation on
  Apple Silicon* in Docker Desktop. SQL Server images are x86-64 only, and
  Microsoft doesn't test or support running them under emulation, but it works
  for this repo. CI runs natively on x86-64.
- **Elixir 1.17 or later**, with Hex and rebar (`mix local.hex --force && mix local.rebar --force`
  on a fresh install). Tested with Elixir 1.17.2 on OTP 27 and 1.20.4 on OTP 29.
- **A Unix shell:** macOS, Linux, or WSL on Windows.

Starting the container accepts the SQL Server end-user license agreement
(`ACCEPT_EULA=Y` in [`compose.yaml`](compose.yaml)) and runs the free Developer
edition. The image is pinned to SQL Server 2022 CU26 GDR (16.0.4275.2), the
build these results come from.

### Run it

```sh
docker compose up -d --wait   # SQL Server on port 1433, waits until it accepts queries
mix setup                     # deps for both ecto_sql versions, database, migrations
bin/compare                   # the bug on released ecto_sql, then the fix
```

`bin/compare` runs the test suite against both versions of ecto_sql and checks
each result:

```
Released ecto_sql 3.14.0 (ECTO_SQL=upstream)
  ok    the bug reproduces: every :bug test fails (42 of 42 failed)
  ok    every other test passes (0 of 79 failed)

Vendored ecto_sql with the fix
  ok    every test passes (0 of 121 failed)
```

If port 1433 is taken, pick another and pass it to every command, for example
`MSSQL_PORT=14330 docker compose up -d --wait`, `MSSQL_PORT=14330 mix setup`
and `MSSQL_PORT=14330 bin/compare`.

Tear down with `docker compose down -v`. The databases live inside the
container, so run `mix setup` again after it is recreated.

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
mix test                                   # with the fix: all 121 pass
ECTO_SQL=upstream mix test --only bug      # released: all 42 fail
ECTO_SQL=upstream mix test --exclude bug   # released: the other 79 pass
```

Tests tagged `:bug` fail on released ecto_sql and pass with the fix. Everything
else passes on both.

| File | Covers |
|---|---|
| [`dumpers_test.exs`](test/tds_repro/dumpers_test.exs) | How the adapter dumps nil and how the connection prepares the parameter, without a database. |
| [`nil_values_test.exs`](test/tds_repro/nil_values_test.exs) | Writing nil through `Repo.update`, `Repo.insert_all` and `Repo.update_all` for 24 of the 26 field type and column type combinations in [`TdsRepro.AllTypes`](lib/tds_repro/all_types.ex) (25 combinations of built-in types, plus the custom [`TdsRepro.IntDate`](lib/tds_repro/int_date.ex) type on an `int` column; the two `text`/`ntext` combinations are in `known_limitations_test.exs`), plus checks that nothing else changed. |
| [`known_limitations_test.exs`](test/tds_repro/known_limitations_test.exs) | What the fix doesn't cover, asserted so a change in behaviour is noticed, and why custom types are left alone. |
| [`workarounds_test.exs`](test/tds_repro/workarounds_test.exs) | What works on released ecto_sql today. |

Tests use their own `tds_repro_test` database, created and migrated by
`mix test`.

### The fix itself

```sh
git log -p -- vendor/ecto_sql
```

Two commits after the vendoring one: `4d570f4`, the first version, which built
a `%Tds.Parameter{}` in the adapter's dumpers, and the one that follows it,
which moves the struct into the connection so the adapter compiles without
tds, leaves custom types alone and documents how the driver sends a nil float.
[docs/root-cause.md](docs/root-cause.md#the-fix) explains both.

## Verifying the upstream patches

```sh
bin/verify-upstream
```

It clones ecto_sql master, applies [`upstream/ecto_sql/*.patch`](upstream/ecto_sql),
and runs the new upstream tests with the fix and without it:

```
Cloning https://github.com/elixir-ecto/ecto_sql.git
  at 2385763 2026-09-06 Fix NOT precedence for in and is_nil (#753)
  ok    patches apply (2 patches)

With the fix
  ok    unit tests pass (0 of 138 failed)
  ok    integration test passes (0 of 31 failed)

Without the fix (lib/ecto/adapters/tds.ex and tds/connection.ex from before the fix commit)
  ok    unit tests fail (3 of 138 failed)
  ok    integration test fails (22 of 31 failed)
```

The `at` line shows whichever ecto_sql master commit was cloned. The script
needs network access, and ecto_sql's integration tests drop and recreate a
database named `ecto_test` on your SQL Server. The full results are in the
[PR draft](docs/pr-draft.md#verification-log).

### Compiling without tds

tds is an optional dependency of ecto_sql, and `lib/ecto/adapters/tds.ex` is
compiled in every ecto_sql install, including apps that only use Postgres.
Unlike the connection module it has no `Code.ensure_loaded?(Tds)` guard, so a
reference to `Tds.Parameter` in it breaks those apps at compile time. The first
version of the fix did exactly that. ecto_sql's own test suite always has tds
available and can't catch it, so this repo checks it directly:

```sh
bin/compile-without-tds
```

It compiles the vendored adapter files with tds absent from the code path and
needs no SQL Server:

```
  ok    adapter compiles without tds (2 warnings about Tds functions, same as released ecto_sql)
  ok    guarded modules are skipped without tds (wrote Elixir.Ecto.Adapters.Tds.beam)
  ok    no new warnings (2 warnings, released ecto_sql has 2)
```

The two warnings are for `Tds.json_library/0` and `Tds.start_link/1`, which
`Ecto.Adapters.Tds` calls at runtime; released ecto_sql 3.14.0 has the same
two. The check fails on a compile error, on a guarded module being compiled, or
on a third warning.

## Scripts

| Command | Shows |
|---|---|
| `mix run scripts/conversion_matrix.exs` | Which column types accept a NULL declared as each type: why no single fallback works, and that the fix's typed NULLs are accepted. |
| `mix run scripts/find_affected_columns.exs` | The affected-columns query run against this repo's database. |

## Docs

- [Root cause](docs/root-cause.md): where the type gets lost, which types fail, and what the fix changes.
- [Upstream history](docs/upstream-history.md): what has been tried and said upstream, and how the fix responds.
- [Workarounds](docs/workarounds.md): writing nil on released ecto_sql today.
- [PR draft](docs/pr-draft.md): the proposed ecto_sql PR description and the verification results.
- [Creating the PR](docs/creating-the-pr.md): step-by-step submission instructions.
- [References](docs/references.md): every source the docs rely on.

## Using Claude with this repo

[`CLAUDE.md`](CLAUDE.md) gives Claude Code the repo's commands and rules. To
have Claude submit the fix, ask it to follow
[docs/creating-the-pr.md](docs/creating-the-pr.md). It will show you what it
is about to send and wait for your confirmation before each step others can
see: forking, pushing, opening the PR, and commenting on the tds issues.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `tcp connect: econnrefused` | SQL Server isn't running. Check `docker compose ps` and start it with `docker compose up -d --wait`. |
| `port is already allocated` from `docker compose up` | Something else is using port 1433, such as a container started earlier with `docker run --name mssql-repro`. Remove it (`docker rm -f mssql-repro`) or use another port with `MSSQL_PORT`. |
| The container never becomes healthy, or exits | Check `docker compose logs mssql`. The usual causes are less than 2 GB of memory for Docker, or Rosetta emulation turned off on Apple Silicon. |
| `the dependency is not available, run "mix deps.get"` with `ECTO_SQL=upstream` | Run `mix setup`, which fetches deps for both versions, or `ECTO_SQL=upstream mix deps.get`. |
| "Cannot open database" or login errors after `docker compose down`, or after `compose.yaml` changed the image | The container was recreated and its databases are gone. Run `mix setup`. |
| Compiler warnings from `tds` on the first build | They come from the dependency and are harmless. |
| Mix asks to install Hex or rebar | Answer yes, or run `mix local.hex --force && mix local.rebar --force` first. |

## Vendored ecto_sql

`vendor/ecto_sql` is a copy of [ecto_sql](https://github.com/elixir-ecto/ecto_sql)
3.14.0 as published on Hex (Apache-2.0, see its `LICENSE.md`). It was committed
unmodified first (`1e4b48f`), and changes to it are kept in their own commits,
so this shows exactly the change to the library:

```sh
git log -p -- vendor/ecto_sql
```

The same change, plus tests in ecto_sql's own test suite, is in
[`upstream/ecto_sql/`](upstream/ecto_sql) as patches against ecto_sql master.

## CI

[`.github/workflows/ci.yml`](.github/workflows/ci.yml) runs:

- `bin/compare upstream` and `bin/compare fixed` on Elixir 1.17 and 1.20,
  against the pinned SQL Server 2022 image, plus a formatting check.
- `bin/verify-upstream` against ecto_sql master and SQL Server 2019, on every
  push and weekly, to catch changes on master that break the patches.
- `bin/compile-without-tds` on Elixir 1.20, without SQL Server, as the job
  "Adapter compiles without tds".
