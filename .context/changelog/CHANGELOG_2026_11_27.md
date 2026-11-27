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

## Build EE no Actions (2026-11-27, head a21f6ac7c)
- Build local OOM compilando grpc-1.72.0 (5 GB); produção ficou saudável. Decisão humana: build no Actions na branch fix/assign-by-unit.
- Workflow publish_ee_github_docker.yml despinado nesta branch: EXPECTED_BRANCH=fix/assign-by-unit, PINNED_BASE=876b58624c09a7b9c83a12b30dd477dd59c7c29c (commit "ci: permite build EE da branch fix/assign-by-unit").
- Run 46042728693 (workflow_dispatch no ref fix/assign-by-unit): completed/success (~21 min); tag ee-src-a21f6ac7c4d75417765d5e2cd036e54aef142662; digest sha256:5bce4aac0866eb065ecfc695a1003d522c98fd42d0d8ba9c244f9f619ef65aea.
- Imagem verificada por pull: /app/.git_sha=a21f6ac7c4d75417765d5e2cd036e54aef142662; controller connecta/assignable_agents_controller.rb presente; "Nenhum agente disponível neste setor" presente em /app/public/vite/assets/DashboardIcon-jQ-vbGBE.js.
- Sem migrations: 876b58624..head -- db/migrate vazio. Rollout preparado (não executado) em /home/thanos/conectacidade/.runtime/rollout-chatwoot-a21f6ac-20261127/.

## Main pareada com produção (2026-11-27)
- main fast-forward para 857d5ba3c1bcb93adfb38984b5a5cca0574ced94; produção a21f6ac; workflow publish_ee_github_docker.yml fica pinado em fix/assign-by-unit/PINNED_BASE 876b586 — próximo build EE precisa re-pinar (mesmo padrão de antes).

## Fix builder-nil-user: reuso sem usuário logado (branch fix/builder-nil-user, sobre 0a84d08)
- Causa raiz: `ConversationReuse::BuilderInterceptor#find_reusable_conversation` passava `Current.user` (nil no create da API pública) ao Gate; `Projection#verified?` chamava `user.id` → NoMethodError (500). Pré-existente em 876b586; alcançável só via create público em inbox Channel::Api marcada como escopo com atendimento aberto (inbox 8 Channel::Api sem escopo; WhatsApp inbound usa Conversation.create!, sem builder).
- Fix A1 (`app/services/connecta/scope/conversation_reuse.rb`): `Current.user.nil?` → `open_conversation` (reusa a consulta de resolução, sem Gate nem auditoria) e `super` quando não há escopo; `resolve` com usuário inalterado (extraído `open_scope`/`open_conversation`, mesma semântica Denied). Com mensagem no reuso sem write, Denied mantido como no caminho com usuário (API pública só envia custom_attributes, ramo inalcançável por ela).
- Fix A2 (`gate.rb`/`projection.rb`): `decide` nega sem usuário sem gravar auditoria (user_id NOT NULL) e loga `connecta_scope_deny_no_user`; `verified?` false e `granted_paths` vazio para nil; `assignee_allowed?` com `&.`. Sem mudança para usuário não-nil.
- Specs: `spec/connecta/builder_interceptor_nil_user_spec.rb` (5 exemplos: reuso público duplo sem 500/RecordNotUnique; create sem escopo; Gate nil nega leitura/escrita; sem linha de auditoria; Projection nil nega).
- Aguardando próximo deploy do Chatwoot; não mergeado na main para não desparear de produção.
