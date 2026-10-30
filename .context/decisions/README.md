# Decisões (ADR-lite)

Uma decisão por arquivo, com número sequencial: `NNN-slug.md`. Para criar uma, copie `000-template.md`.

Status possíveis: `Proposta`, `Aceita` ou `Substituída por NNN`. Decisão substituída não é apagada: ganha o status e aponta para a nova.
Decisão em proposta fica rotulada como proposta até aprovação humana.

| ADR | Título | Status | Data |
|---|---|---|---|
| 001 | Runner aceita só a lista fixa de extras G0 (`connecta_g0_*`) | Aceita | 2026-10-22 |
| 002 | Negação HTTP escopada no spike G0 (404 leitura, 403 escrita, 401 não autenticado) | Aceita | 2026-10-22 |
