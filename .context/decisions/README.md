# Decisões (ADR-lite)

Uma decisão por arquivo, com número sequencial: `NNN-slug.md`. Para criar uma, copie `000-template.md`.

Status possíveis: `Proposta`, `Aceita` ou `Substituída por NNN`. Decisão substituída não é apagada: ganha o status e aponta para a nova.
Decisão em proposta fica rotulada como proposta até aprovação humana.

| ADR | Título | Status | Data |
|---|---|---|---|
| 001 | Runner aceita só a lista fixa de extras G0 (`connecta_g0_*`) | Aceita | 2026-10-22 |
| 002 | Negação HTTP escopada no spike G0 (404 leitura, 403 escrita, 401 não autenticado) | Aceita | 2026-10-22 |
| 003 | Escopo de contato na busca e leitura em manutenção (spike G0) | Aceita | 2026-10-30 |
| 004 | Envio em recepção só pelo usuário de serviço; parked vira falha visível (menos em manutenção) | Aceita | 2026-11-02 |
| 005 | Ciclo de vida do escopo na resolução/reabertura (closed terminal) | Aceita | 2026-11-02 |
