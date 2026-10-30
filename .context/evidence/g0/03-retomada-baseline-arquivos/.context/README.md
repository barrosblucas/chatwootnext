# Contexto do projeto — chatwootnext

Índice do `.context/`. É a memória do projeto: estrutura, estado, decisões, armadilhas e histórico ficam aqui, versionados no repositório.
Fatos marcados com `TODO` ainda não foram confirmados no repositório.

## Ordem de leitura
1. `AI-GOVERNANCE.md`: regras obrigatórias (stack, hard rules, gates, testes).
2. `architecture.md`: fronteiras e decisões técnicas principais.
3. `REPOMAP.md`: mapa real das pastas e responsabilidades.
4. `PROJECT_STATE.md`, `gotchas.md` e `decisions/`: quando a tarefa tocar o assunto.

## Política de carga
- Carregar por padrão: os itens 1 a 3.
- NÃO carregar por padrão: `changelog/` e `archive/`. Use só quando a tarefa pedir histórico (ex.: "por que mudamos a regra X?").
- `plans/`: carregue o plano vigente só quando a tarefa for executá-lo.

## Onde registrar cada fato (orientação do template, não regra obrigatória do repo)
As regras de desenvolvimento estão em `AGENTS.md` e `CLAUDE.md`. Esta tabela só indica onde registrar um fato que mudou:

| Mudou | Atualize |
|---|---|
| Qualquer entrega | `changelog/CHANGELOG_AAAA_MM_DD.md` (anexar se o arquivo do dia já existe) |
| Pastas, responsabilidades ou limites de módulo | `REPOMAP.md` |
| Fronteira, stack ou direção técnica | `architecture.md` e, se for decisão, `decisions/NNN-slug.md` + índice |
| Fase do projeto ou entrega concluída | `PROJECT_STATE.md` |
| Armadilha (bug que custou rodada, comportamento não óbvio) | `gotchas.md` |

## Uma regra, um lugar
Cada fato tem uma única fonte dentro do `.context/`. Os outros arquivos apontam para ela, não copiam. Se um doc divergir do código, o código é o estado atual: registre a divergência em `gotchas.md` ou `PROJECT_STATE.md` até uma decisão humana.

## Proibido aqui
Segredos, credenciais, `.env` ou dados pessoais.

## Outros arquivos
Opcionais, conforme o projeto (crie só se fizerem sentido): `OWNERSHIP.md`, `PLATFORM.md`, `integrations/`, `security/`, `studies/`.
Layout: padrão do template (sem `.context/docs/` nem outro layout).
