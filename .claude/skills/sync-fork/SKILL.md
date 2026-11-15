---
name: sync-fork
description: Use this skill when pulling fazer-ai/chatwoot (remote upstream-fazer, branch main) into this fork's main (origin barrosblucas/chatwootnext). Covers preconditions (clean tree, local main == origin/main), sync branch naming, merge with conflict policy for Connecta-protected paths, validation via CI (local Ruby is not installed on this host), and PR back to origin main. Trigger when the user asks to sync with upstream, merge upstream-fazer, or bump the fork to a new upstream version.
allowed-tools: Bash, Read, Edit, Write, Grep, Glob
---

# Sync fork — upstream-fazer → origin (this fork)

This repo (`barrosblucas/chatwootnext`) is a personal fork for the Connecta pilot.
There is exactly one sync direction: pull `fazer-ai/chatwoot` into our `main`.
There is no `chatwoot-pro` merge flow here.

| Remote | URL | Role |
|---|---|---|
| `origin` | `barrosblucas/chatwootnext` | Ours. Work, branches and PRs target `main` here. |
| `upstream-fazer` | `fazer-ai/chatwoot` | Read-only. Sync source only. **Never push to it, never open a PR against it.** |

Upstream's default branch is `main` (verified via `git ls-remote --symref upstream-fazer HEAD`).
If that ever shows another branch, use what it shows and fix this file.

## When to use

- User asks to sync with upstream, merge upstream-fazer, or bump the fork to a new upstream version/tag (past merges: `chore: merge upstream v4.17.0-fazer-ai.110`).
- Resolve conflicts on an in-progress `sync/upstream-fazer-*` branch.

## Preconditions (stop if any fails)

1. Clean tree: `git status --short` shows nothing (note: `script/criar_admin.rb` is untracked by decision — leave it alone, stage explicit paths only).
2. On `main`, and local == remote: `git rev-parse HEAD` == `git rev-parse origin/main` == `git ls-remote origin refs/heads/main`. Fetch first: `git fetch origin '+refs/heads/main:refs/remotes/origin/main'`.
3. If local is behind → fast-forward only. If diverged → STOP and report.

## Steps

1. Fetch upstream: `git fetch upstream-fazer` (read-only; safe).
2. Create the sync branch from origin/main: `git checkout -b sync/upstream-fazer-YYYYMMDD origin/main`.
3. Merge: `git merge upstream-fazer/main --no-ff -m "chore: merge upstream <version-or-date>"`.
4. Resolve conflicts per the policy below. `git mergetool` is fine; never `checkout --theirs .` blindly.
5. Validate (see below), push the branch to origin, open a PR to `origin` `main`.
6. Merge the PR with a merge commit, NEVER squash (keeps upstream as a side merge; `git log --first-parent` stays "our work").

`gh` fork gotcha: `gh` resolves the PR base to the parent repo unless pinned. Run once per clone: `gh repo set-default barrosblucas/chatwootnext`. When unsure: `gh pr create --repo barrosblucas/chatwootnext`.

## Conflict policy

HEAD = ours (`origin/main`), MERGE_HEAD = theirs (`upstream-fazer/main`).
Default: accept upstream, except the Connecta paths below, which keep OURS unless the sync was explicitly authorized to change them:

- `app/services/connecta/**` and `app/models/connecta/**` — Connecta transfer/scope logic.
- `config/initializers/connecta_runtime.rb` (+ `app/services/connecta/**/installer.rb`, `g0_adapter.rb`) — runtime opt-in.
- `app/controllers/api/v1/accounts/conversations/connecta_*`, Connecta frontend under `app/javascript/` — verificar paths in `.context/REPOMAP.md` before resolving.
- `enterprise/` overlay, `script/liberar_premium.rb`, `CUSTOM_BRANDING.md` — fork premium/branding.
- `.github/workflows/publish_ee_github_docker.yml` and other `publish_*` workflows — fork deploy targets.
- `.context/`, `AGENTS.md`, `CLAUDE.md` — fork docs; never take upstream's.
- `db/schema.rb` — regenerate via migration, don't hand-merge both sides (verificar: canonical command in this repo's CONTRIBUTING/CI).

## Validation

- Local Ruby is NOT installed on this host — do not claim local `bundle exec rspec`/`rubocop` runs. Rely on CI after pushing the branch: `Run Chatwoot CE spec` (`run_foss_spec.yml`: specs, RuboCop, Brakeman, ESLint, frontend tests) and i18n (`fazer_ai_i18n.yml`); WhatsApp contract (`fazer_ai_whatsapp_contract.yml`) when vendor files change.
- What does run locally: JS lint/tests (`eslint`, `vitest` — run `vitest` directly, not `pnpm test`, which OOMs with `--no-cache`).
- Before merge: green CI on the PR, plus `git diff --check` clean.

## Never

- Never push to `upstream-fazer`. Never PR against it.
- Never force-push `main`. Never commit directly to `main` — always via PR branch.
- Never copy `.env` values, credentials or municipality config into code, docs or PR text.

## Post-merge

Production deploy is a SEPARATE, explicitly authorized process — not part of this skill.
Pointers only: `docs/runbooks/` (Connecta homologation/contingency), production SHA via `docker exec chatwootnext-rails-1 cat /app/.git_sha`; merge-base checks in `AGENTS.md` ("Base de trabalho"). Rollout specifics: verificar.

## What this skill deliberately does NOT cover

Running the upstream merge itself without being asked, production deploys, secrets handling, `script/` admin one-offs (separate human decision).
