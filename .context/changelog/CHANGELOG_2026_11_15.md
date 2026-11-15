# Changelog 2026-11-15

## Docs

- `.claude/skills/sync-fork/SKILL.md`: rewritten 454 → 75 lines for the real remotes (`origin → barrosblucas/chatwootnext`, `upstream-fazer → fazer-ai/chatwoot`, upstream default branch `main`). Single sync direction; preconditions (clean tree, local main == origin/main); branch `sync/upstream-fazer-YYYYMMDD`; merge-commit (never squash) PR to origin main with `gh` fork-gotcha pin; conflict policy keeping Connecta paths (`app/services/connecta/**`, `config/initializers/connecta_runtime.rb`, enterprise overlay, `publish_*` workflows, `.context/`) on ours unless deliberate; validation via CI (local Ruby not installed on this host; JS lint/tests run locally); post-merge deploy out of scope (pointers to `docs/runbooks/` only). Removed the 2026-11-14 mismatch banner (obsolete) and the `chatwoot-pro` flow (does not exist in this clone). Unknowns marked "verificar", no invented facts.
- Base: `4b579c8da` (local HEAD == `origin/main` == `ls-remote` before edit).

## Tests

- Not run: docs-only change; validation is `git diff --check` + CI on push (`run_foss_spec.yml`, `fazer_ai_i18n.yml`).

## CI

- `ci: pin ubuntu-24.04 runners so ruby 3.4.4 is available`: `run_foss_spec.yml` jobs `lint-backend`, `security-scan`, `backend-tests` pinned `runs-on: ubuntu-latest` → `ubuntu-24.04`. Root cause: `ubuntu-latest` now resolves to 26.04 and ruby-builder ships 3.4.4 only for 22.04/24.04 (verified via `releases/tags/ruby-3.4.4`: 22.04 + 24.04 x64/arm64, no 26.04 asset), so `ruby/setup-ruby@v1` failed with "Unavailable version 3.4.4 for ruby on ubuntu-26.04". App Ruby untouched (`.ruby-version` still 3.4.4). Non-Ruby jobs (`plan`, `lint-frontend`, `frontend-tests`) stay on `ubuntu-latest`. Base: `61fab368e` (local HEAD == `origin/main` == `ls-remote` before edit).
