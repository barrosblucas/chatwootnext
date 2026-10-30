# Evidência — assinatura Baileys negrito+itálico (código, 2026-10-28)

Pedido humano: assinatura funcionava como `*Nome*:` mas deve ser negrito+itálico `*_Nome_*:`.
Escopo: SÓ código+testes no fork; SEM deploy (implantação D1 anterior permanece; esta correção pendente).

## Mudança mínima (FE+BE consistentes, API intacta)

- `app/builders/messages/message_builder.rb`: `prepend_agent_name(..., baileys:)`
  com ramo Baileys extraído (`prepend_baileys_agent_name`,
  `legacy_same_sender_prefix?`, `normalize_legacy_agent_prefix`).
  Novo `*_Nome_*:`, idempotente; legado exato do mesmo sender (`*Nome*:\n`)
  normalizado 1x com corpo preservado; `sanitize_agent_name(..., baileys:)`
  remove também `_` só do nome. API default `*Nome*:` intacto; guards
  bot/`AgentBot`/relay/private/inbound/vazio/mídia-caption inalterados.
- `app/javascript/dashboard/helper/editorHelper.js`: `sanitizeAgentName` /
  `agentNamePrefix` / `prependAgentName` com opção `{ baileys }` (default API);
  mesma normalização legado-1x.
- `app/javascript/dashboard/components/widgets/conversation/ReplyBox.vue`:
  3 call sites (`editorSignature`, `isSignatureAvailable`,
  `applySignatureToMessage`) passam `{ baileys: this.isAWhatsAppBaileysChannel }`.
  `formattedSignature` retorna `editorSignature` cru; `ReplyBottomPanel.vue` /
  `Editor.vue` / `composeConversationHelper.js` sem mudança (path API default).
- Docs: append código-bold-italic em
  `.context/changelog/CHANGELOG_2026_10_28.md`; linha factual em
  `.context/architecture.md`; nota código-pronto/deploy-pendente em
  `.context/PROJECT_STATE.md`. Histórico D1/D3 preservado.

## Validação (contagens, sem PII)

- TDD FE: specs novos falharam ANTES (11 failed / 9 passed em 20) e passaram
  DEPOIS do fix.
- `pnpm exec vitest run` (3 specs assinatura + `editorHelper.spec.js`):
  3 arquivos, 122 passed | 23 skipped (skips pré-existentes do editorHelper).
- G0 oficial:
  `scripts/connecta/g0_test_env.sh --spec --apply spec/connecta/baileys_agent_signature_spec.rb`
  → 17 examples, 0 failures (pós-refactor RuboCop; `node` adicionado ao PATH
  do runner pois o script usa `env -i`; script inalterado).
- `spec/builders/messages/message_builder_spec.rb` fora da allowlist G0
  (não forçado, conforme briefing).
- `bundle exec rubocop --force-exclusion` nos 2 Ruby: no offenses
  (após extrair ramo Baileys; 3 ofensas iniciais corrigidas).
- `pnpm exec eslint` nos 5 JS/Vue alterados: limpo (2 prettier autofix).
- `git diff --check`: limpo.
- Toolchains do cache: `ruby 3.4.4`, `node 24.19`; `pnpm install
  --prefer-offline --ignore-scripts` só deps do lockfile (sem new deps).

## Hashes (SHA-256, 16h; nomes fictícios nos testes, sem PII)

- `app/builders/messages/message_builder.rb`: ver `git diff --check`/status final
- `app/javascript/dashboard/helper/editorHelper.js`: idem
- `app/javascript/dashboard/components/widgets/conversation/ReplyBox.vue`: idem
- Specs novos/alterados: `spec/connecta/baileys_agent_signature_spec.rb`,
  `app/javascript/dashboard/helper/specs/baileysAgentSignature.spec.js`,
  `app/javascript/dashboard/helper/specs/replyBoxBaileysSignature.spec.js`,
  `app/javascript/dashboard/helper/specs/editorHelper.spec.js`
- Fora de escopo preservado: manifest SHA pré/pós em BLOCKERS do relatório;
  sem `stash/checkout/reset/restore/commit/push`; monorepo só leitura.

## Limites

- Código pronto para juiz (marco código→deploy local); deploy desta correção
  PENDENTE (não executar build/restart agora). Nenhum dado real tocado.
