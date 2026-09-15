# tds_repro

Minimal reproduction of the Ecto/Tds NULL-into-temporal-column bug
([tds#124](https://github.com/elixir-ecto/tds/issues/124),
[tds#168](https://github.com/elixir-ecto/tds/issues/168)).

Clearing a temporal field to `nil` fails on SQL Server with:

> Implicit conversion from data type varbinary to date is not allowed.

`nil` carries no type, so `ecto_sql`'s Tds adapter cannot infer one from the
value and the `tds` driver defaults it to `:binary` -> `varbinary(1)`.

## Run it

Start SQL Server (amd64 image; needs emulation on Apple Silicon):

    docker run -d --name mssql-repro --platform linux/amd64 \
      -p 1433:1433 \
      -e ACCEPT_EULA=Y -e MSSQL_SA_PASSWORD='some!Password' \
      mcr.microsoft.com/mssql/server:2022-latest

Wait for `SQL Server is now ready for client connections` in `docker logs
mssql-repro`, then:

    mix deps.get
    mix ecto.create
    mix ecto.migrate
    mix run -e "TdsRepro.run()"

Teardown: `docker rm -f mssql-repro`

## Result

Output with ecto_sql 3.14.0 as released. A later commit patches the vendored
copy (see [Vendored ecto_sql](#vendored-ecto_sql)), after which every case
passes. To see these failures again, run `git checkout 1e4b48f` (the unmodified
copy) before running the repro, and `git checkout main` to return.

    PASS  baseline: INSERT with values
    PASS  INSERT with nil temporal fields
    FAIL  UPDATE date -> nil
    FAIL  UPDATE time -> nil
    PASS  UPDATE naive_datetime  -> datetime -> nil
    FAIL  UPDATE naive_datetime_usec -> datetime2 -> nil
    FAIL  UPDATE utc_datetime_usec   -> datetimeoffset -> nil
    PASS  workaround: raw UPDATE with typed %Tds.Parameter{}
    FAIL  insert_all with explicit nil date

Which types break follows SQL Server's implicit-conversion matrix: `varbinary`
converts implicitly to the legacy `datetime`/`smalldatetime` types, but not to
the modern `date`, `time`, `datetime2`, `datetimeoffset`.

Note that Ecto's `:naive_datetime` maps to legacy `datetime`, which is why the
plain `:naive_datetime` case passes and the explicit `datetime2` column fails.

INSERTs escape the bug because Ecto omits `nil` fields from the column list
entirely; `insert_all` with an explicit `nil` key does not, and fails.

The passing workaround confirms the fix direction: supply an explicitly typed
`%Tds.Parameter{}` so the driver never has to guess.

## Vendored ecto_sql

`vendor/ecto_sql` is a copy of [ecto_sql](https://github.com/elixir-ecto/ecto_sql)
3.14.0 as published on Hex (Apache-2.0, see its `LICENSE.md`), used as a path
dependency so a fix can be developed and tested against this repro.

It was committed unmodified first, and changes to it are kept in their own
commits, so this shows exactly what would go into an upstream PR:

    git log -p -- vendor/ecto_sql
