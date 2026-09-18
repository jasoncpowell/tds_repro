# References

Everything the docs in this repo rely on, grouped by source, with what each one
supports. Checked on 2026-09-15, except the rows added for the restructured fix
(the optional tds dependency, the `Code.ensure_loaded?(Tds)` guards,
`prepare_params/1`, the `{_, :varchar}` clause, `Tds.Ecto.VarChar`, the driver's
float encoding, `Ecto.Type.dump/3`, the `Ecto.Type` docs and Elixir's struct
docs), which were checked on 2026-09-18.

## Upstream reports and discussion

| Reference | Supports |
|---|---|
| [elixir-ecto/tds#124](https://github.com/elixir-ecto/tds/issues/124) (2021-07-06, open) | The original report: `Repo.update` of a nil `date` fails with errors 8180 and 257. |
| [tds#124: rschenk's analysis](https://github.com/elixir-ecto/tds/issues/124#issuecomment-1452901953) | Cause traced to `Tds.Parameter.fix_data_type/1`; `:string` breaks `varbinary`. |
| [tds#124: mjaric asks for a repro](https://github.com/elixir-ecto/tds/issues/124#issuecomment-1546648200) | Fix might belong in the Ecto adapter. |
| [rschenk/ecto_tds_null_dates](https://github.com/rschenk/ecto_tds_null_dates) | Earlier minimal reproduction (2023). |
| [tds#124: rschenk publishes the repro](https://github.com/elixir-ecto/tds/issues/124#issuecomment-1557647492) (2023-05-22) | Links to rschenk/ecto_tds_null_dates. |
| [tds#124: mlooney](https://github.com/elixir-ecto/tds/issues/124#issuecomment-1745349569) | Workaround of changing the column type to a string. |
| [tds#124: "any attempt to make nil be something else by default"](https://github.com/elixir-ecto/tds/issues/124#issuecomment-2158154829) | Maintainer: no default works; use `type/2`. |
| [tds#124: implicit conversion](https://github.com/elixir-ecto/tds/issues/124#issuecomment-2158171077) | Maintainer: don't rely on implicit conversion. |
| [tds#124: abueloshika](https://github.com/elixir-ecto/tds/issues/124#issuecomment-2158604830) | `type/2` doesn't help changesets. |
| [tds#124: changesets have types](https://github.com/elixir-ecto/tds/issues/124#issuecomment-2159096305) | Maintainer: the problem cases are values without types. |
| [tds#124: NULL storage per type](https://github.com/elixir-ecto/tds/issues/124#issuecomment-2159179856) | Maintainer: TDS encodes NULL differently per type. |
| [tds#124: Option 1 and Option 2](https://github.com/elixir-ecto/tds/issues/124#issuecomment-2160155402) | Issue belongs in ecto_sql; pass known types down. |
| [tds#124: only Option 1](https://github.com/elixir-ecto/tds/issues/124#issuecomment-2165036413), [follow-up](https://github.com/elixir-ecto/tds/issues/124#issuecomment-2166618540) | Maintainer agrees on passing types; asks about code paths; promises a PR. |
| [elixir-ecto/tds#162](https://github.com/elixir-ecto/tds/pull/162) (closed) and branch [`wm-nil-as-type-string`](https://github.com/elixir-ecto/tds/tree/wm-nil-as-type-string) | Rejected `:string` fallback. |
| [tds#162: rschenk](https://github.com/elixir-ecto/tds/pull/162#issuecomment-2155050557), [wojtekmach's test script](https://github.com/elixir-ecto/tds/pull/162#issuecomment-2157626223), [mjaric](https://github.com/elixir-ecto/tds/pull/162#issuecomment-2159217692), [closing comment](https://github.com/elixir-ecto/tds/pull/162#issuecomment-2160077979) | Which column types each fallback breaks; `:binary_id` priority. |
| [elixir-ecto/tds#168](https://github.com/elixir-ecto/tds/issues/168) (2025-04-03, open) | `insert_all` with an explicit nil fails against `datetime2`. |
| [Elixir Forum thread 40034](https://elixirforum.com/t/error-on-updating-a-time-field-to-null-using-ecto-with-tds-adapter/40034) (2021-05-27) | Same error for a `time` field. |
| `wm-types` proof of concept in [ecto](https://github.com/elixir-ecto/ecto/compare/24f914a...wm-types) and [ecto_sql](https://github.com/elixir-ecto/ecto_sql/compare/2385763...wm-types) (2024-06-10) | The maintainers' Option 1 sketch. |
| [elixir-ecto/tds#183](https://github.com/elixir-ecto/tds/pull/183) (draft) and branch [`next`](https://github.com/elixir-ecto/tds/tree/next) | Driver rewrite still falls back to `:binary` for untyped nils. |
| [elixir-ecto/tds#119](https://github.com/elixir-ecto/tds/issues/119), [elixir-ecto/ecto_sql#302](https://github.com/elixir-ecto/ecto_sql/issues/302) (2021) | Related: `Ecto.Adapters.SQL.query/4` doesn't set the correct type for parameters. |

## Code and changes

| Reference | Supports |
|---|---|
| tds [`97c736b`](https://github.com/elixir-ecto/tds/commit/97c736be2a) (2018-04-26) | Origin of the nil → `:binary` fallback. |
| tds [`parameter.ex#L79-L88`](https://github.com/elixir-ecto/tds/blob/f67d0a7cd0/lib/tds/parameter.ex#L79-L88) | Explicit types are kept; untyped nil becomes `:binary`. |
| tds [`parameter.ex#L119-L122`](https://github.com/elixir-ecto/tds/blob/f67d0a7cd0/lib/tds/parameter.ex#L119-L122) | Non-nil floats are typed `:float`. |
| tds [`types.ex#L978`](https://github.com/elixir-ecto/tds/blob/f67d0a7cd0/lib/tds/types.ex#L978) | Parameter declarations are built from the type. |
| tds [`types.ex#L923-L925`](https://github.com/elixir-ecto/tds/blob/f67d0a7cd0/lib/tds/types.ex#L923-L925), [`#L1150`](https://github.com/elixir-ecto/tds/blob/f67d0a7cd0/lib/tds/types.ex#L1150) | A `:float` parameter with a nil value is declared as `decimal(1,0)` (`encode_float_descriptor/1`); its value goes through the decimal encoder, which sends a nil as a varbinary NULL (`encode_float_type/1`). |
| tds [`protocol.ex#L198`](https://github.com/elixir-ecto/tds/blob/f67d0a7cd0/lib/tds/protocol.ex#L198), [`#L569`](https://github.com/elixir-ecto/tds/blob/f67d0a7cd0/lib/tds/protocol.ex#L569) | Statements are prepared with `sp_prepare` by default. |
| ecto_sql [`tds.ex#L155-L157`](https://github.com/elixir-ecto/ecto_sql/blob/v3.14.0/lib/ecto/adapters/tds.ex#L155-L157) (v3.14.0) | The dumpers the fix changes. |
| ecto_sql [`connection.ex#L102-L123`](https://github.com/elixir-ecto/ecto_sql/blob/v3.14.0/lib/ecto/adapters/tds/connection.ex#L102-L123), [`#L146`](https://github.com/elixir-ecto/ecto_sql/blob/v3.14.0/lib/ecto/adapters/tds/connection.ex#L146) | Parameter types come from values; typed parameters pass through; nil gets no type. |
| ecto_sql [`connection.ex#L79-L95`](https://github.com/elixir-ecto/ecto_sql/blob/v3.14.0/lib/ecto/adapters/tds/connection.ex#L79-L95) | `prepare_params/1` builds and numbers a `%Tds.Parameter{}` for every parameter; the fix's tagged nil takes this path. |
| ecto_sql [`connection.ex#L145`](https://github.com/elixir-ecto/ecto_sql/blob/v3.14.0/lib/ecto/adapters/tds/connection.ex#L145) | The existing `prepare_raw_param/1` clause for the `{_, :varchar}` tag; the fix's clause for `{nil, ecto_type}` sits just before it. |
| ecto_sql [`types.ex#L287-L289`](https://github.com/elixir-ecto/ecto_sql/blob/v3.14.0/lib/ecto/adapters/tds/types.ex#L287-L289) | `Tds.Ecto.VarChar.dump/1` returns `{value, :varchar}`, the tagging convention the fix reuses for nil. |
| ecto_sql [`connection.ex#L1`](https://github.com/elixir-ecto/ecto_sql/blob/v3.14.0/lib/ecto/adapters/tds/connection.ex#L1), [`types.ex#L1`](https://github.com/elixir-ecto/ecto_sql/blob/v3.14.0/lib/ecto/adapters/tds/types.ex#L1) | The connection and the `Tds.Ecto.*` types compile only when `Tds` is loaded; `lib/ecto/adapters/tds.ex` has no such guard. |
| ecto_sql [`mix.exs#L111`](https://github.com/elixir-ecto/ecto_sql/blob/v3.14.0/mix.exs#L111) (v3.14.0) | tds is an optional dependency, so the adapter must compile without it and can't build a `%Tds.Parameter{}`. |
| ecto_sql [`connection.ex#L1825-L1842`](https://github.com/elixir-ecto/ecto_sql/blob/v3.14.0/lib/ecto/adapters/tds/connection.ex#L1825-L1842) | Column types migrations create for date, time and float fields. |
| ecto [`type.ex#L1041-L1049`](https://github.com/elixir-ecto/ecto/blob/v3.14.2/lib/ecto/type.ex#L1041-L1049) (v3.14.2) | `adapter_dump/3` runs the adapter's dumpers, including for nil. |
| ecto [`type.ex#L542-L544`](https://github.com/elixir-ecto/ecto/blob/v3.14.2/lib/ecto/type.ex#L542-L544) | `Ecto.Type.dump/3` returns `{:ok, nil}` before calling a custom type's `dump/1`; why the fix leaves custom types alone. |
| ecto [`type.ex#L538-L540`](https://github.com/elixir-ecto/ecto/blob/v3.14.2/lib/ecto/type.ex#L538-L540) | A parameterized type's `dump/3` runs before that nil short-circuit, so `Ecto.ParameterizedType` handles its own nil. |
| ecto [`repo/schema.ex#L1365-L1366`](https://github.com/elixir-ecto/ecto/blob/v3.14.2/lib/ecto/repo/schema.ex#L1365-L1366), [`query/planner.ex#L2638`](https://github.com/elixir-ecto/ecto/blob/v3.14.2/lib/ecto/query/planner.ex#L2638) | Changes and query parameters are dumped through the adapter. |
| ecto [`changeset/relation.ex#L647-L649`](https://github.com/elixir-ecto/ecto/blob/v3.14.2/lib/ecto/changeset/relation.ex#L647-L649) | Inserts only include non-nil struct fields. |
| [elixir-ecto/ecto#4214](https://github.com/elixir-ecto/ecto/pull/4214) (Ecto 3.11.0) | Adapters receive nil in dumpers and loaders; required for the fix. |
| [elixir-ecto/ecto_sql#528](https://github.com/elixir-ecto/ecto_sql/pull/528), [`22be184`](https://github.com/elixir-ecto/ecto_sql/commit/22be18491f) | Tds loaders adjusted for ecto#4214. |
| [elixir-ecto/ecto_sql#579](https://github.com/elixir-ecto/ecto_sql/pull/579) (ecto_sql 3.12.0) | `%Tds.Parameter{}` accepted in `Repo.query/3`. |
| [elixir-ecto/ecto_sql#184](https://github.com/elixir-ecto/ecto_sql/pull/184) (2020-03-10) | Tds adapter merged into ecto_sql. |
| ecto_sql [`Earthfile`](https://github.com/elixir-ecto/ecto_sql/blob/2385763/Earthfile) and [CI workflow](https://github.com/elixir-ecto/ecto_sql/blob/2385763/.github/workflows/ci.yml) | Upstream CI runs Tds integration tests against SQL Server 2019 and 2022. |
| ecto_sql master [`2385763`](https://github.com/elixir-ecto/ecto_sql/commit/2385763) (2026-09-06) | Still sends nil without a type; the bug is unresolved on master. |

## Ecto, ecto_sql and tds documentation

| Reference | Supports |
|---|---|
| [`Ecto.Adapter` `dumpers/2`](https://ecto.hexdocs.pm/Ecto.Adapter.html#c:dumpers/2) | What dumpers receive and return. |
| [`Ecto.Type`](https://ecto.hexdocs.pm/Ecto.Type.html#module-example), [`type/0`](https://ecto.hexdocs.pm/Ecto.Type.html#c:type/0) | Custom types: "nil values are always bypassed and cannot be handled by custom types"; `type/0` gives the underlying primitive. |
| Elixir [Structs](https://hexdocs.pm/elixir/structs.html) | Structs "provide compile-time checks": a `%Tds.Parameter{}` literal needs the module at compile time. |
| [`Ecto.Repo` `insert/2`](https://ecto.hexdocs.pm/Ecto.Repo.html#c:insert/2) | Structs become changesets "with all non-nil fields". |
| [`Ecto.Repo` `update_all/3`](https://ecto.hexdocs.pm/Ecto.Repo.html#c:update_all/3), [`insert_all/3`](https://ecto.hexdocs.pm/Ecto.Repo.html#c:insert_all/3) | Neither updates autogenerated fields such as timestamps. |
| [`Ecto.Query.API` `type/2`](https://ecto.hexdocs.pm/Ecto.Query.API.html#type/2) | Casting a parameter at the database level. |
| [`Ecto.Schema` primitive types](https://ecto.hexdocs.pm/Ecto.Schema.html#module-primitive-types), [`timestamps/1`](https://ecto.hexdocs.pm/Ecto.Schema.html#timestamps/1) | Field types; timestamps default to `:naive_datetime`. |
| [`Ecto.Adapters.Tds`](https://ecto-sql.hexdocs.pm/Ecto.Adapters.Tds.html) | Adapter docs; they don't mention nil parameters. |
| [tds README](https://tds.hexdocs.pm/readme.html) | Elixir to SQL Server type mapping and `%Tds.Parameter{}` usage. |

## Microsoft SQL Server documentation

| Reference | Supports |
|---|---|
| [Data type conversion (Database Engine)](https://learn.microsoft.com/en-us/sql/t-sql/data-types/data-type-conversion-database-engine) | Implicit vs explicit conversion, the conversion chart, and conversion on insert into a column. |
| [CAST and CONVERT](https://learn.microsoft.com/en-us/sql/t-sql/functions/cast-and-convert-transact-sql) | `text` and `image` don't support automatic conversion. |
| [binary and varbinary](https://learn.microsoft.com/en-us/sql/t-sql/data-types/binary-and-varbinary-transact-sql) | Conversions involving binary types. |
| [Database engine errors 0 to 999](https://learn.microsoft.com/en-us/sql/relational-databases/errors-events/database-engine-events-and-errors-0-to-999) | Error texts for 206, 257 and 529. |
| [sp_prepare](https://learn.microsoft.com/en-us/sql/relational-databases/system-stored-procedures/sp-prepare-transact-sql), [sp_executesql](https://learn.microsoft.com/en-us/sql/relational-databases/system-stored-procedures/sp-executesql-transact-sql) | Parameter definitions include a data type. |
| [MS-TDS: RPC Request](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-tds/619c43b6-9495-4a58-9e49-a4950db245b3) | Each RPC parameter carries `TYPE_INFO`. |
| [MS-TDS: Data Type Dependent Data Streams](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-tds/3f983fde-0509-485a-8c40-a9fa6679a828) | NULL is encoded differently per type. |
| [ntext, text, and image](https://learn.microsoft.com/en-us/sql/t-sql/data-types/ntext-text-and-image-transact-sql) | These types are deprecated. |
| [Quickstart: SQL Server Linux containers with Docker](https://learn.microsoft.com/en-us/sql/linux/install-upgrade/quickstart-install-docker) | 2 GB RAM minimum; x86-64 hosts only, emulation such as Rosetta 2 "aren't tested or supported"; `ACCEPT_EULA`; Developer edition by default; `mssql-tools18` path. |
| [Password policy](https://learn.microsoft.com/en-us/sql/relational-databases/security/password-policy) | Requirements for `MSSQL_SA_PASSWORD`. |
| [mssql/server tags on the Microsoft Artifact Registry](https://mcr.microsoft.com/v2/mssql/server/tags/list) | The pinned `2022-CU26-GDR1-ubuntu-22.04` tag. |

## The same class of bug in other clients

| Reference | Supports |
|---|---|
| [microsoft/mssql-jdbc#1269](https://github.com/microsoft/mssql-jdbc/issues/1269) | Generic-typed NULLs don't work for every SQL Server type, even in Microsoft's driver. |
| [spring-projects/spring-framework#15187](https://github.com/spring-projects/spring-framework/issues/15187) | Null `float` parameters fail. |
| [ballerina-platform/ballerina-library#6562](https://github.com/ballerina-platform/ballerina-library/issues/6562) | Null `float` and `date` parameters fail with the same varbinary error. |
| [knex/knex#3347](https://github.com/knex/knex/issues/3347) | An `nvarchar` NULL is refused by a `varbinary` column. |
