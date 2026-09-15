# Upstream history

What has already been tried and said about this bug upstream, and how the fix
in this repo responds to each point. Read this before the PR draft: most of
what a reviewer will ask has come up before.

## Timeline

| Date | Where | What happened |
|---|---|---|
| 2018-04-26 | tds [`97c736b`](https://github.com/elixir-ecto/tds/commit/97c736be2a) | The driver starts declaring parameters with no type and a nil value as `:binary` (varbinary), to fix an Ecto `has_one` nullify case. This is the fallback that causes the bug. |
| 2021-07-06 | [tds#124](https://github.com/elixir-ecto/tds/issues/124) | puruzio reports `Repo.update` setting a `date` field to nil fails with error 257. |
| 2021 | [Elixir Forum](https://elixirforum.com/t/error-on-updating-a-time-field-to-null-using-ecto-with-tds-adapter/40034) | The same error for a `time` field. |
| 2023-03-03 | tds#124 | rschenk traces it to `Tds.Parameter.fix_data_type/1`, notes that switching the fallback to `:string` breaks `varbinary` columns, and suggests adding a NULL parameter type to the driver. |
| 2023-05 | tds#124 | mjaric (tds maintainer) asks for a minimal repo and suggests the fix might belong in Ecto's adapter rather than the driver. rschenk publishes [rschenk/ecto_tds_null_dates](https://github.com/rschenk/ecto_tds_null_dates). |
| 2024-06-07 | [tds#162](https://github.com/elixir-ecto/tds/pull/162) | wojtekmach (elixir-ecto member) opens a PR changing the fallback to `:string`. rschenk points out its test never exercised the changed code. wojtekmach's test script shows `:string` breaks `binary`/`varbinary`, while `:binary` breaks `float`, `real`, `date`, `time` and `text`. |
| 2024-06-10 | tds#124, tds#162 | mjaric: any default for nil breaks some other conversion; a type hint is required. Recommends `type(^value, :date)` in queries, explains that TDS encodes NULL differently per type, and says `:binary_id` support matters most. |
| 2024-06-11 | tds#162, tds#124 | tds#162 closed: "we shouldn't break `:binary_id` and other types". wojtekmach says the issue belongs in `ecto_sql`, and proposes Option 1 (pass the types Ecto already knows down to Tds, with proof-of-concept `wm-types` branches in [ecto](https://github.com/elixir-ecto/ecto/compare/master...wm-types) and [ecto_sql](https://github.com/elixir-ecto/ecto_sql/compare/master...wm-types)) or Option 2 (let users set type hints). |
| 2024-06-13 | tds#124 | mjaric: only Option 1 is needed, but asks whether some code paths could drop the type on its way to the driver. Says a PR will follow. No PR has appeared. |
| 2025-04-03 | [tds#168](https://github.com/elixir-ecto/tds/issues/168) | jaybarra reports `Repo.insert_all` with an explicit nil `datetime2` value fails; works around it by dropping nil keys. No comments; labeled `bug` on 2025-06-06. |
| 2026-02-27 | [tds#183](https://github.com/elixir-ecto/tds/pull/183) | Draft "TDS v3 Internals Redesign" by mjaric. Its `next` branch still declares untyped nils as `:binary`, but still respects an explicit type. |

Both issues are still open, and neither links to a PR.

## How the fix responds

| Point raised | By | Response |
|---|---|---|
| Setting date/time fields to nil fails, including via `insert_all` | puruzio, forum, jaybarra | Fixed for every Ecto date/time type, on `Repo.update`, `insert_all` and `update_all`. |
| The fix may belong in Ecto's adapter, not the driver | mjaric | The change is in `Ecto.Adapters.Tds.dumpers/2`, in `ecto_sql`. |
| Changing the driver's fallback breaks other column types | rschenk, wojtekmach, mjaric | The fallback is untouched. Types other than date/time and float dump exactly as before. |
| `:binary_id` support matters most | mjaric | Unaffected: UUID columns accept nil before and after. |
| NULL can't be encoded without a type; a hint is required | mjaric | The hint comes from the schema field's Ecto type. Nothing is inferred from the nil. |
| Calendar types, float, "and potentially others" | wojtekmach | All calendar types and float are fixed. The only other failure found is `:string` fields on legacy `text`/`ntext` columns, which the fix doesn't cover. |
| Do some code paths drop the type before the driver? | mjaric | Ecto passes every schema-typed value through the adapter's dumpers, so updates, `insert_all` and `update_all` all get typed. Values with no type (queries without a schema, `fragment`, raw SQL) still fail, as before. |
| Don't rely on implicit conversion | mjaric | No new conversions: nils get the same parameter types `ecto_sql` already sends for non-nil values of those fields. |
| `type(^value, :date)` means giving up changesets | abueloshika | Changesets work without it. The fix also makes `type(^nil, :float)` work, which fails today (error 529). |
| Tests passed without exercising the changed code | rschenk | This repo's tests go through `Ecto.Type.adapter_dump/3` and real `Repo` calls against SQL Server. |
| Driver rewrite in progress | mjaric (tds#183) | Compatible: the rewrite still honors an explicitly typed parameter. |

## What reviewers may still question

- **The mechanism.** Maintainers discussed passing types through Ecto itself
  (the `wm-types` branches). This fix uses the adapter's existing dumper hook
  instead, which needs no change to Ecto and covers more paths. Nobody
  upstream has seen this approach yet.
- **`text`/`ntext` columns.** Sending a typed string NULL would fix them, but
  it is close to the rejected tds#162 and would break `:string` fields on
  `varbinary` columns. Left out deliberately.
- **Values without a type.** Queries without a schema, `fragment` and raw SQL
  still need `type/2` or an explicit `%Tds.Parameter{}`. The adapter has no
  type to use there.
