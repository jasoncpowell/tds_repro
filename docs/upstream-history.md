# Upstream history

What has already been tried and said about this bug upstream, and how the fix
in this repo responds to each point. Read this before the PR draft: most of
what a reviewer will ask has come up before. Checked against GitHub, Hex and
the Elixir Forum on 2026-09-15; every link is also in [references.md](references.md).

## Timeline

| Date | Where | What happened |
|---|---|---|
| 2018-04-26 | tds [`97c736b`](https://github.com/elixir-ecto/tds/commit/97c736be2a) | Milan Jaric (mjaric) adds the `fix_data_type/1` clause that gives a parameter with no type and a nil value the type `:binary`, commented "should fix ecto has_one, on_change :nulify issue". This is the fallback behind the bug. |
| 2020-03-10 | [ecto_sql#184](https://github.com/elixir-ecto/ecto_sql/pull/184) | The Tds adapter is merged into ecto_sql. |
| 2021-02-18 | [tds#119](https://github.com/elixir-ecto/tds/issues/119), [ecto_sql#302](https://github.com/elixir-ecto/ecto_sql/issues/302) | Related but different: `Ecto.Adapters.SQL.query/4` gets the wrong inferred type for raw parameters. Shows the same underlying fragility of inferring parameter types from values. |
| 2021-05-27 | [Elixir Forum](https://elixirforum.com/t/error-on-updating-a-time-field-to-null-using-ecto-with-tds-adapter/40034) | enrico reports that updating a `time` field to NULL fails with error 257 while inserts work. No replies. |
| 2021-07-06 | [tds#124](https://github.com/elixir-ecto/tds/issues/124) | puruzio reports `Repo.update/2` setting a `date` field to nil fails with errors 8180 and 257. |
| 2023-03-03 | [tds#124](https://github.com/elixir-ecto/tds/issues/124#issuecomment-1452901953) | rschenk traces it to `Tds.Parameter.fix_data_type/1`, notes that switching the fallback to `:string` breaks `varbinary` columns, and suggests adding a NULL parameter type to the driver. |
| 2023-05-13 | [tds#124](https://github.com/elixir-ecto/tds/issues/124#issuecomment-1546648200) | mjaric (tds maintainer) asks for a minimal repo and suggests the fix might belong in the Ecto adapter rather than the driver. rschenk publishes [rschenk/ecto_tds_null_dates](https://github.com/rschenk/ecto_tds_null_dates) on [2023-05-22](https://github.com/elixir-ecto/tds/issues/124#issuecomment-1557647492). |
| 2023-06-21 | [ecto#4214](https://github.com/elixir-ecto/ecto/pull/4214), [ecto_sql#528](https://github.com/elixir-ecto/ecto_sql/pull/528) | Andrea Leopardi changes Ecto to pass nil through adapter dumpers and loaders (released in Ecto 3.11.0, 2023-11-14), and adjusts the Tds loaders for it; José Valim follows up in [`22be184`](https://github.com/elixir-ecto/ecto_sql/commit/22be18491f). Not about this bug, but it is what makes a fix in the adapter's dumpers possible. |
| 2023-10-03 | [tds#124](https://github.com/elixir-ecto/tds/issues/124#issuecomment-1745349569) | mlooney works around it by changing the column type to a string. |
| 2024-04-24 | [ecto_sql#579](https://github.com/elixir-ecto/ecto_sql/pull/579) | `%Tds.Parameter{}` structs are accepted as `Repo.query/3` parameters (ecto_sql 3.12.0), which the raw SQL workaround relies on. |
| 2024-06-07 | [tds#162](https://github.com/elixir-ecto/tds/pull/162) | wojtekmach (elixir-ecto member) opens a PR changing the fallback to `:string` (branch [`wm-nil-as-type-string`](https://github.com/elixir-ecto/tds/tree/wm-nil-as-type-string)). rschenk [points out](https://github.com/elixir-ecto/tds/pull/162#issuecomment-2155050557) its test never exercised the changed code. |
| 2024-06-10 | [tds#162](https://github.com/elixir-ecto/tds/pull/162#issuecomment-2157626223) | wojtekmach's test script shows `:string` breaks `binary`/`varbinary`, while `:binary` breaks `float`, `real`, `date`, `time` and `text`. |
| 2024-06-10 | tds#124, tds#162 | mjaric: [any default for nil breaks some other conversion](https://github.com/elixir-ecto/tds/issues/124#issuecomment-2158154829), use `type(^value, :date)`; [don't rely on implicit conversion](https://github.com/elixir-ecto/tds/issues/124#issuecomment-2158171077); [changesets already have types](https://github.com/elixir-ecto/tds/issues/124#issuecomment-2159096305); [TDS stores NULL differently per type](https://github.com/elixir-ecto/tds/issues/124#issuecomment-2159179856); and on tds#162, [`:binary_id` support matters most](https://github.com/elixir-ecto/tds/pull/162#issuecomment-2159217692). abueloshika [asks](https://github.com/elixir-ecto/tds/issues/124#issuecomment-2158604830) whether `type/2` means giving up changesets. |
| 2024-06-11 | tds#162, tds#124 | tds#162 [closed](https://github.com/elixir-ecto/tds/pull/162#issuecomment-2160077979): "we shouldn't break `:binary_id` and other types". wojtekmach [says](https://github.com/elixir-ecto/tds/issues/124#issuecomment-2160155402) the issue belongs in ecto_sql, and proposes Option 1 (pass the types Ecto already knows down to Tds, with proof-of-concept `wm-types` branches in [ecto](https://github.com/elixir-ecto/ecto/compare/24f914a...wm-types) and [ecto_sql](https://github.com/elixir-ecto/ecto_sql/compare/2385763...wm-types), both a single "wip" commit) or Option 2 (let users set type hints). |
| 2024-06-13 | [tds#124](https://github.com/elixir-ecto/tds/issues/124#issuecomment-2165036413) | mjaric: only Option 1 is needed, but asks whether some code paths could drop the type on its way to the driver. In a [second comment](https://github.com/elixir-ecto/tds/issues/124#issuecomment-2166618540) points at `fix_data_type/1` and says a PR will follow. No PR has appeared. |
| 2025-04-03 | [tds#168](https://github.com/elixir-ecto/tds/issues/168) | jaybarra reports `Repo.insert_all/3` with an explicit nil `utc_datetime` value fails against a `datetime2` column; works around it by dropping nil keys. No comments; labeled `bug` on 2025-06-06. |
| 2026-02-27 | [tds#183](https://github.com/elixir-ecto/tds/pull/183) | Draft "TDS v3 Internals Redesign" by mjaric. Its [`next`](https://github.com/elixir-ecto/tds/tree/next) branch still declares untyped nils as `:binary`, but still respects an explicit type. |
| 2026-05 to 2026-09 | Hex, GitHub | Latest releases are ecto_sql 3.14.0 (2026-05-19), ecto 3.14.2 and tds 2.3.8 (2026-05-18). tds's changelog on master lists a v2.4.0 (2026-08-19) that isn't on Hex yet and doesn't touch parameter types. ecto_sql master ([`2385763`](https://github.com/elixir-ecto/ecto_sql/commit/2385763), 2026-09-06) still has the bug. |

Both issues are still open, and neither links to a PR.

## How the fix responds

| Point raised | By | Response |
|---|---|---|
| Setting date/time fields to nil fails, including via `insert_all` | puruzio, enrico, jaybarra | Fixed for every Ecto date/time type, on `Repo.update`, `insert_all` and `update_all`. |
| The fix may belong in Ecto's adapter, not the driver | mjaric | The change is in `Ecto.Adapters.Tds.dumpers/2`, in ecto_sql. |
| Changing the driver's fallback breaks other column types | rschenk, wojtekmach, mjaric | The fallback is untouched. Types other than date/time and float dump exactly as before. |
| `:binary_id` support matters most | mjaric | Unaffected: UUID columns accept nil before and after. |
| NULL can't be encoded without a type; a hint is required | mjaric | The hint comes from the schema field's Ecto type. Nothing is inferred from the nil. |
| Calendar types, float, "and potentially others" | wojtekmach | All calendar types and float are fixed. The only other failure found is `:string` fields on legacy `text`/`ntext` columns, which the fix doesn't cover. |
| Do some code paths drop the type before the driver? | mjaric | Ecto passes every schema-typed value through the adapter's dumpers (since ecto#4214), so updates, `insert_all` and `update_all` all get typed. Values with no type (queries on a table name, `fragment`, raw SQL) still fail, as before. |
| Don't rely on implicit conversion | mjaric | No new conversions: nils get the same parameter types ecto_sql already sends for non-nil values of those fields. |
| `type(^value, :date)` means giving up changesets | abueloshika | Changesets work without it. The fix also makes `type(^nil, :float)` work, which fails today (error 529). |
| Tests passed without exercising the changed code | rschenk | This repo's tests go through `Ecto.Type.adapter_dump/3` and real `Repo` calls against SQL Server, and the upstream tests do the same. |
| Driver rewrite in progress | mjaric (tds#183) | Compatible: the rewrite still honors an explicitly typed parameter. |

## The same class of bug elsewhere

Every SQL Server client that sends NULL without a real type runs into the same
conversion rules, which supports mjaric's point that the type has to come from
the layer that knows it:

- [microsoft/mssql-jdbc#1269](https://github.com/microsoft/mssql-jdbc/issues/1269) (2020): Microsoft's own JDBC driver accepts `setNull` with a generic type "for most data types, but not all of them".
- [spring-projects/spring-framework#15187](https://github.com/spring-projects/spring-framework/issues/15187) (2013): null parameters fail "ONLY for float datatype" on SQL Server.
- [ballerina-platform/ballerina-library#6562](https://github.com/ballerina-platform/ballerina-library/issues/6562) (2024): null `float` and `date` parameters fail with "Operand type clash: varbinary is incompatible with float", for the same reason.
- [knex/knex#3347](https://github.com/knex/knex/issues/3347) (2019): the mirror image, an `nvarchar` NULL refused by a `varbinary` column, which is why tds#162's `:string` default was rejected.

## What reviewers may still question

- **The mechanism.** Maintainers discussed passing types through Ecto itself
  (the `wm-types` branches). This fix uses the adapter's existing dumper hook
  instead, which needs no change to Ecto and covers more paths. Nobody
  upstream has seen this approach yet.
- **`text`/`ntext` columns.** Sending a typed string NULL would fix them, but
  it is close to the rejected tds#162 and would break `:string` fields on
  `varbinary` columns. Left out deliberately; Microsoft has also [deprecated](https://learn.microsoft.com/en-us/sql/t-sql/data-types/ntext-text-and-image-transact-sql)
  these types.
- **Values without a type.** Queries on a table name instead of a schema,
  `fragment` and raw SQL still need `type/2` or an explicit `%Tds.Parameter{}`.
  The adapter has no type to use there.
