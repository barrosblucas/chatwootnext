# Evidência I.1 — validação código transferência + assinatura (2026-10-28, sem PII)

## Comandos
- `git -C <ORIGFORK> apply --check /tmp/opencode/baileys-agent-signature-complete-20261028.patch` → exit 0
- `git -C <ORIGFORK> apply <patch>` → exit 0 (8 arquivos)
- Ruby (PATH direto `~/.cache/connecta-g0-test/toolchain/mise-data/installs/ruby/3.4.4/bin`):
  `bundle exec rubocop --force-exclusion <6 Ruby>` → sem ofensas
- G0 oficial `scripts/connecta/g0_test_env.sh --spec --apply` (lotes ≤180s):
  - `spec/connecta/runtime_platform_client_wire_spec.rb` → 1 exemplo, 0 falhas (fio real loopback, query não-alfabética com claim)
  - `native_admin_transfer_authority_spec.rb + baileys_agent_signature_spec.rb + runtime_platform_client_contract_spec.rb` → 26 exemplos, 0 falhas
  - `native_admin_runtime_transfer_spec.rb + runtime_transfer_transaction_spec.rb + runtime_hmac_authenticator_spec.rb` → 17 exemplos, 0 falhas
  - `scope_socket_delivery_spec.rb + scope_admin_metadata_pending_spec.rb + scope_socket_spec.rb + scope_policy_query_spec.rb` → 105 exemplos, 0 falhas
- WP (`apps/whatsapp-platform`): `tsx --test tests/humanServiceTransferNotice.test.ts` → 4 pass; `tsc --noEmit` → limpo
- FE: 8 hashes aplicados == isolada (MATCH); Vitest isolada 14 novos pass; regressão 149 pass / 23 skips preexistentes (evidência 28 já validada, configs byte-idênticos); `eslint` 6 arquivos limpo; `git diff --check` limpo

## Hashes (SHA256)
- Patch: `bbe4e5cca358f04d31db38df9e5f7c41fdf335c683895f667c28e67dc9e79505`
- Incident paths (antes/depois, limpos): `schema.ts 7cb8070b…`, `ouvidoria/admin/next-env.d.ts 1862ac4b…`, `WP CHANGELOG_2026_09_04.md ac5354b8…`
- Deploy preservados: `baileys-api/docker-compose.yml 2531733a…`, `e2e/compose.yml 7f8ccd16…`
- `platform_client.rb` inalterado: `c5f6b1d9…`

## Resultado
- Sem mismatch HMAC real → client inalterado. Sem Git restore/stash. Sem deploy. Gate F pendente.
