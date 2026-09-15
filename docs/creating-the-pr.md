# Creating the ecto_sql PR

Step-by-step instructions for submitting the fix to
[elixir-ecto/ecto_sql](https://github.com/elixir-ecto/ecto_sql), written so a
person or Claude can follow them. Steps marked **(confirm)** are visible to
other people: show the exact command and text first, and only run them once the
repo owner agrees.

## What gets submitted

The two patches in [`upstream/ecto_sql/`](../upstream/ecto_sql):

1. **The fix:** `lib/ecto/adapters/tds.ex`, identical to the vendored fix in
   this repo.
2. **Tests:** a unit test in `test/ecto/type_test.exs`, next to the existing
   Tds `adapter_dump` tests, and `integration_test/tds/nil_parameters_test.exs`,
   modeled on `integration_test/tds/constraints_test.exs`.

No CHANGELOG entry: every CHANGELOG commit in ecto_sql is by the maintainer,
so contributors leave it alone.

The PR description is between the `pr-body` markers in [pr-draft.md](pr-draft.md).

## Prerequisites

- SQL Server running from this repo: `docker compose up -d --wait`.
- Elixir 1.15 or later (ecto_sql master requires `~> 1.15`).
- The [GitHub CLI](https://cli.github.com/), signed in: `gh auth status`.

## 1. Check the patches still apply and pass

```sh
bin/verify-upstream
```

It clones ecto_sql master, applies the patches, runs the new tests with the fix
(they must pass) and without it (they must fail). Every line must read `ok`.

If the patches no longer apply because master changed, apply them by hand in
`tmp/verify-upstream/ecto_sql`, resolve the conflict, rerun the tests there,
then regenerate the patches from that checkout and commit them to this repo:

```sh
git -C tmp/verify-upstream/ecto_sql format-patch origin/master..HEAD -o "$PWD/upstream/ecto_sql"
```

## 2. Fork and clone ecto_sql (confirm)

```sh
cd ..
gh repo fork elixir-ecto/ecto_sql --clone
cd ecto_sql
```

This creates the fork under the signed-in account and clones it with two
remotes: `origin` (the fork) and `upstream` (elixir-ecto/ecto_sql).

## 3. Apply the patches on a branch

```sh
git fetch upstream
git switch -c tds-nil-params upstream/master
git am -3 ../tds_repro/upstream/ecto_sql/*.patch
```

## 4. Run ecto_sql's tests

```sh
mix deps.get
mix format --check-formatted
mix test
MSSQL_URL='sa:some!Password@localhost:1433' ECTO_ADAPTER=tds mix test
```

The last command is the full Tds integration suite, the same one ecto_sql's CI
runs against SQL Server 2017 and 2019 (see its `Earthfile`). It drops and
recreates a database named `ecto_test`. Compare any failures against a run on
`upstream/master` without the patches: only failures that appear with the
patches matter. The results from this repo's own run are in pr-draft.md.

## 5. Push the branch (confirm)

```sh
git push -u origin tds-nil-params
```

## 6. Open the PR (confirm)

Extract the description, review it, then open the PR:

```sh
sed -n '/<!-- pr-body:start -->/,/<!-- pr-body:end -->/p' ../tds_repro/docs/pr-draft.md | sed '1d;$d' > /tmp/pr-body.md

gh pr create --repo elixir-ecto/ecto_sql --base master \
  --head "$(gh api user --jq .login):tds-nil-params" \
  --title "Tds: send typed NULL for nil date, time and float params" \
  --body-file /tmp/pr-body.md
```

Check that the repro repository link in the description is reachable by the
public before submitting, or remove it.

## 7. Link the PR from the tds issues (confirm)

The reports live in the tds repo, which the PR won't link automatically. The
comment text is in pr-draft.md.

```sh
gh issue comment 124 --repo elixir-ecto/tds --body "…"
gh issue comment 168 --repo elixir-ecto/tds --body "…"
```

## 8. Record it here

Add the PR link to the status table in the README and to pr-draft.md, and
commit.

## Responding to review

- Push follow-up commits to the same branch; the PR updates itself.
- If a maintainer asks for a different approach, such as passing types through
  Ecto as in the `wm-types` sketch, note it in pr-draft.md and discuss it with
  the repo owner before rewriting anything.
- Keep this repo's vendored fix and `upstream/ecto_sql/` patches in step with
  what the PR ends up containing.
