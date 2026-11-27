# Changelog — 2026-11-27

## Intenção da feature
- Intenção: no Chatwoot, limitar a atribuição de chamados aos usuários do próprio departamento (setor); o menu "Atribuir Agente" passa a listar só usuários do setor, agrupados por setor em ordem alfabética.
- Regras de negócio afetadas: atribuição de conversas (endpoint de agentes atribuíveis, POST de assignments com setor, transferência entre setores, guardas em macros/automação e na criação de conversa, elegibilidade do alvo de atribuição).
- Não deve mudar: comportamento de inboxes não Connecta; acesso de administradores nativos; "Atendimento Automático" segue oculto.
- Já feito: backend (endpoint + transferência cross-unit + guardas) na branch fix/assign-by-unit-backend; frontend (pickers por setor) na branch fix/assign-by-unit-frontend; mescladas em fix/assign-by-unit.
- Pendente: validação no GitHub Actions (rspec + frontend); build de imagem em etapa posterior separada.
- Etapa atual: branch de integração fix/assign-by-unit criada sobre a main remota e despachada no Actions.

## Added
- Backend: endpoint GET /api/v1/accounts/:account_id/connecta/assignable_agents?conversation_ids[]=<display_id> (grupos por setor, ordem alfabética pt-BR, sem usuário de recepção CONNECTA_RECEPTION_SENDER_USER_IDS); POST assignments aceita connecta_org_unit_id e move o setor via TransferTransaction (mesma propagação da transferência para o whatsapp-platform) e atribui no destino — só admin nativo ou gerir nos 2 setores (+ transferir na origem pela TransferPolicy); guardas em ActionService (macros/automação) e ConversationBuilder; regra-alvo única AssignmentPolicy.target_eligible?. Specs novas: spec/connecta/assignable_agents_by_unit_spec.rb, cross_unit_assignment_spec.rb, assignment_scope_guards_spec.rb.
- Frontend: menu "Atribuir Agente" agrupa por setor (cabeçalhos não clicáveis, ordem alfabética, None primeiro); sidebar, cmd+K e bulk usam o endpoint novo; cross-department envia connecta_org_unit_id; i18n NO_AGENTS_IN_UNIT pt_BR/en.

## Decisões humanas
- Atendente vê só o setor da conversa; quem tem gerir vê os setores onde tem gerir; admin vê todos; escolher pessoa de outro setor transfere setor + pessoa (só gestor/admin); "Atendimento Automático" oculto; lista em ordem alfabética.
- Com o Actions do Chatwoot grátis, seguir com testes no Actions e imagem local (recomendado): mesclar as 2 branches em uma, push da branch, testes no Actions; build de imagem depois, em etapa separada.

## Base e branches
- Base: origin/main 876b58624c09a7b9c83a12b30dd477dd59c7c29c (conferido: `git ls-remote origin refs/heads/main` == `git rev-parse origin/main`).
- fix/assign-by-unit-backend (dc9df1680) + fix/assign-by-unit-frontend (387514df9) mescladas com --no-ff, sem conflito (nenhum arquivo compartilhado entre as duas).

## Tests
- run_foss_spec.yml despachado no ref fix/assign-by-unit com specs explícitas: spec/connecta/assignable_agents_by_unit_spec.rb, spec/connecta/cross_unit_assignment_spec.rb, spec/connecta/assignment_scope_guards_spec.rb, spec/connecta/scope_policy_query_spec.rb.
- frontend-fe.yml despachado no ref fix/assign-by-unit.
- Falha pré-existente na main, não relacionada: spec/connecta/transfer_activation_spec.rb:168 (runs 45894696016, 45899629106).

## Resultados (round 2, 2026-11-27 ~14:50 UTC, head 7cd4cebc8)
- Round 1 (run 46017848690): lint-backend 20 ofensas no código novo + 4 exemplos falhando (2 de grupo extra Sub A1 para gestor, 2 de crash nil-user no interceptor de reuso). Corrigido em 7cd4cebc8.
- run_foss_spec 46019522562: success — plan, lint-backend, lint-frontend, security-scan e backend-tests (0) todos success; frontend-tests skipped (specs explícitas, sem detecção de diff frontend).
- frontend-fe 46019527570: success (job test).
- Falha pré-existente transfer_activation_spec.rb:168 não apareceu (não estava na lista de specs do dispatch).
