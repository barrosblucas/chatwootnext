# 007 — Protocolo: busca, identificação na lista e visão por etapas

## Contexto
A transferência humana preserva o protocolo e cria uma conversa nova na mesma inbox. A busca nativa do Chatwoot cobre conteúdo de mensagem, não `custom_attributes`/protocolo; a lista não mostrava o setor autorizado; e não havia uma visão das etapas de um protocolo. O modal de setor da admissão manual existia, mas não estava renderizado no Compose. A nota privada de destino também não pode expor o setor de origem, porque ela é única para todos os leitores do destino e pode vazar uma etapa sem grant.

## Decisão
1. Busca por protocolo é um hook sobre a relação já escopada (`ProtocolSearch`), com wildcard literal, limite de 60 e OR com a busca de mensagem existente. Nunca há lookup global de protocolo.
2. A lista recebe metadados em lote (`ConversationMetadata`) somente para conversas visíveis: `case_protocol`, `state`, `org_unit_name`, `root_unit_name`. O rótulo é dinâmico `Raiz | Setor | Atendente`; assignee vem do meta nativo.
3. A visão por protocolo (`ProtocolView`) lista somente etapas que passam no `Gate#read?` por conversa, com auditoria. Admin nativo vê todas as etapas da conta; agente vê apenas as autorizadas; `admin_nominal` não enumera a etapa `transferred_out` (restrição do endpoint, sem alterar o `Gate` global) e não ganha escrita; `transferir` sozinho não lê.
4. Etapas ocultas não retornam id, nome nem link. O endpoint é a única fonte de navegação condicional entre etapas; a nota privada do destino é genérica e não inclui o setor de origem.
5. O modal de setor é renderizado no `ComposeConversation`, reutiliza os destinos já buscados pelo ator e usa o endpoint dedicado de admissão manual.
6. Sem migração: as colunas existentes (`case_protocol`, `org_unit_id`, `transfer_id`) e o assignee nativo são suficientes.
7. O ciclo de resolução (decisão 005) é pré-requisito de release: a inbox do número humano deve ter `lock_to_single_conversation=false`, comprovado no caminho real de ingestão Baileys; com `true`, a conversa resolvida é reutilizada e a mensagem fica na thread terminal.

## Alternativas consideradas
- Buscar protocolo no cliente após carregar todas as conversas: rejeitado; quebra paginação e pode expor etapas fora do escopo.
- Incluir nome/link da origem na nota privada do destino: rejeitado; a nota é visível a agentes do destino que podem não ter grant na origem.
- Usar labels/teams para identificar setor: rejeitado; não existem no runtime e `team_id` é proibido em inbox marcada.
- Exigir migração/índice de protocolo agora: adiado; o volume atual não justifica e a migração genérica está bloqueada por decisão operacional.

## Consequências
- A busca/visão passa a ser server-side e account-bound; testes de agente A/B, admin nativo, admin nominal, transferir-só e cross-account são obrigatórios.
- O frontend precisa buscar metadados em lote quando a lista muda; transferência nova entra pelo watcher, assignee usa o evento nativo.
- A nota de transferência perde a identificação textual da origem; a navegação passa a depender do protocol view, que respeita o Gate.
- O endpoint de protocolo é somente leitura de metadados/links; não agrega mensagens de outras etapas para operadores.

## Status
Aceita

## Data
2026-11-08
