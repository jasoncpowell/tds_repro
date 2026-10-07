# Creating the ecto_sql PR

Step-by-step instructions for submitting the fix to
[elixir-ecto/ecto_sql](https://github.com/elixir-ecto/ecto_sql), written so a
person or Claude can follow them. Steps marked **(confirm)** are visible to
other people: show the exact command and text first, and only run them once the
repo owner agrees.

## What gets submitted

The two patches in [`upstream/ecto_sql/`](../upstream/ecto_sql):

1. **The fix:** `lib/ecto/adapters/tds.ex` (the dumpers tag a nil with the
   TDS type a non-nil value of the field is sent as) and `lib/ecto/adapters/tds/connection.ex`
   (`prepare_params/1` passes the tag on as a typed `%Tds.Parameter{}`, and
   `update/5` and `delete/4` still compare a tagged nil filter with
   `IS NULL`), identical to the vendored fix in this repo.
2. **Tests:** unit tests in `test/ecto/type_test.exs`, next to the existing
   Tds `adapter_dump` tests, and in `test/ecto/adapters/tds_test.exs` for
   `prepare_params/1`, `update/5` and `delete/4`, plus
   `integration_test/tds/nil_parameters_test.exs`, modeled on
   `integration_test/tds/constraints_test.exs`.

No CHANGELOG entry: 79 of the 84 commits that touch ecto_sql's `CHANGELOG.md`
(as of master `f049198`) are by its core team, who write the entries, so
contributors leave it alone.

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
(they must pass) and without it (they must fail), and runs ecto_sql's own
`mix test.as_a_dep` with the fix. Every line must read `ok`.

Also run:

```sh
bin/compile-without-tds
```

It compiles the vendored adapter with tds absent from the code path. tds is an
optional dependency of ecto_sql and `lib/ecto/adapters/tds.ex` has no
`Code.ensure_loaded?(Tds)` guard, so a `%Tds.Parameter{}` struct there
breaks every ecto_sql user without the driver. ecto_sql's CI runs `mix test`,
which always has tds available and cannot catch this. Its `mix test.all` alias
also runs `mix test.as_a_dep`, which compiles ecto_sql as a dependency without
tds and does catch it; that is the check `bin/verify-upstream` runs. The
`lib/ecto/adapters/tds.ex` hunk in patch 1 is identical to the vendored file,
so checking the vendored copy checks the patch.

If the patches no longer apply because master changed, apply them by hand in
`tmp/verify-upstream/ecto_sql`, resolve the conflict, rerun the tests there,
then regenerate the patches from that checkout and commit them to this repo:

```sh
git -C tmp/verify-upstream/ecto_sql format-patch origin/master..HEAD -o "$PWD/upstream/ecto_sql"
```

To change the fix itself, commit the change to `vendor/ecto_sql` first, as its
own commit. Then fold it into patch 1, which must stay the single squash of the
vendored fix commits: the script's "without the fix" run restores the files
from before the last commit that touched `tds.ex`. Interactive rebase isn't
needed:

```sh
bin/verify-upstream                          # fresh checkout with the current patches
E=tmp/verify-upstream/ecto_sql
git -C $E reset --hard HEAD~1                # drop the test commit; patch 2 still has it
git diff --relative=vendor/ecto_sql <commit>^ <commit> | git -C $E apply
git -C $E commit -a --amend --no-edit        # or -F <file> for a new message
git -C $E am -3 "$PWD"/upstream/ecto_sql/0002-*.patch
# edit the tests, then: git -C $E commit -a --amend -F <file>
```

Pass messages with `-F` or `--no-edit`: without a terminal, as when Claude
runs this, a bare `--amend` keeps the old message without a word. A message
file replaces the whole message, so keep the `Refs` line and the trailer
below. Run step 4's checks in `$E`, then `git rm upstream/ecto_sql/*.patch`
before regenerating: `format-patch -o` leaves a renamed patch behind, and the script
applies every one. `bin/verify-upstream` starts by deleting
`tmp/verify-upstream`, so don't rerun it until the patches are regenerated.

The outgoing commits carry `Co-authored-by: Claude <noreply@anthropic.com>`:
unversioned, because a product version dates the commit and means nothing to a
reviewer, and lowercase, because that is the spelling every co-author
trailer in ecto_sql's history uses (16 as of master `f049198`). Keep that form when regenerating
the patches; `git format-patch` reproduces whatever the commits say, so check
the trailers after any rebase or amend.

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
mix test.as_a_dep
MSSQL_URL='sa:some!Password@localhost:1433' ECTO_ADAPTER=tds mix test
```

`mix test.as_a_dep` compiles ecto_sql as a dependency without its optional
drivers, which is how a `%Tds.Parameter{}` in `lib/ecto/adapters/tds.ex` would
show up. The last command is the full Tds integration suite, the same one ecto_sql's CI
runs against SQL Server 2019 and 2022 (see its CI workflow). It drops and
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
