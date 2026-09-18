# tds_repro

Reproduction, tests and proposed fix for an Ecto/ecto_sql bug on SQL Server:
writing `nil` to date, time, datetime2, datetimeoffset or float columns fails
because the Tds adapter sends an untyped NULL, which the tds driver declares as
varbinary. Background is in `docs/root-cause.md` and `docs/upstream-history.md`.

## Commands

- `docker compose up -d --wait` then `mix setup`: SQL Server and databases.
- `mix run -e "TdsRepro.run()"`: repro against the vendored ecto_sql with the
  fix. Prefix with `ECTO_SQL=upstream` for released ecto_sql 3.14.0 from Hex.
- `mix test`: all tests with the fix. `ECTO_SQL=upstream mix test --only bug`
  must fail entirely; `--exclude bug` must pass.
- `bin/compare`: both of the above checks, with a summary.
- `bin/verify-upstream`: applies `upstream/ecto_sql/*.patch` to ecto_sql master
  and runs the upstream tests with and without the fix.
- `bin/compile-without-tds`: compiles the vendored adapter with tds absent;
  must pass. Needs no SQL Server.
- `mix format --check-formatted`: must pass.
- `MSSQL_PORT` / `MSSQL_HOST` change the SQL Server connection for all of the
  above.

## Layout and rules

- `vendor/ecto_sql` is ecto_sql 3.14.0 from Hex. Only the fix commits touch
  it, each change in its own commit, so `git log -p -- vendor/ecto_sql` shows
  exactly the upstream change. The upstream patch is the squash of them.
- `upstream/ecto_sql/` holds the patch series for elixir-ecto/ecto_sql: the fix
  and its tests, generated with `git format-patch` from an ecto_sql checkout
  where they passed. The `lib/ecto/adapters/tds.ex` and
  `lib/ecto/adapters/tds/connection.ex` hunks must stay identical to the
  vendored fix. Regenerate the patches rather than editing them by hand, and
  rerun `bin/verify-upstream` afterwards.
- `lib/ecto/adapters/tds.ex` must compile without tds
  (`bin/compile-without-tds`); never expand a Tds struct there. Only the
  guarded connection and types modules may.
- `ECTO_SQL=upstream` builds into `_build_upstream` so the two ecto_sql
  versions never share compiled code.
- Tests tagged `:bug` fail on released ecto_sql and pass with the fix. Every
  other test must pass on both. Known limitations assert the SQL Server error.
- Docs cite their sources. Source links pin a tag or commit (ecto v3.14.2,
  ecto_sql v3.14.0, tds `f67d0a7cd0`), and every source is listed in
  `docs/references.md`.
- Commands and docs assume a Unix shell.

## Creating the upstream PR

Follow `docs/creating-the-pr.md`. Forking, pushing, opening the PR and
commenting on the tds issues are visible to others: show the user exactly what
will be sent and get their confirmation before each of those steps. Don't add
a CHANGELOG entry; the ecto_sql maintainers write it.
