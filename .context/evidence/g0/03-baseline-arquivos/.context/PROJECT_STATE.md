# PROJECT_STATE — chatwootnext

Estado atual: fase, entregas, próximos marcos e pendências. Criado em 2026-10-22.

## Fase atual
Preparação do G0 do plano Baileys (atendimento em número próprio): G0 **ABERTO**. Preparo local executado em 2026-10-22 (`.context/evidence/g0/01-execucao-preparo-e-validacao.md`); spec T0.1 executada (`.context/evidence/g0/02-inventario-t0-1.md`). Nenhuma fase iniciada; nenhuma ACL ou transporte implementado; EVID2..8 não provadas.

## Entregas concluídas
- 2026-10-22: preparo local (não concluído). Correções do Juiz T2 aplicadas e validadas só de forma estática (detalhes no changelog do dia):
  - spec de inventário de rotas `spec/requests/connecta/route_inventory_spec.rb`, com superfícies por área, fronteiras de autenticação, superfícies obrigatórias (incluindo `/cable`, QR/status e o catch-all do SPA);
  - guarda pré-Rails `spec/support/connecta/g0_target_guard.rb`, carregada pelo suporte geral de `rails_helper` e executada só pela spec de inventário;
  - roteiro `scripts/connecta/g0_test_env.sh` (dry-run por padrão; modos `--apply`, `--spec`, `--teardown`) e compose `scripts/connecta/g0-test-services.compose.yml` com autenticação obrigatória.
- 2026-10-22, segunda revisão T2 (REQUIRED_FIXES 1-4, mesmo TASK_ID): fronteiras de autenticação completadas com arquivo:linha; runner checa contexto Docker local antes de qualquer consulta ao daemon e aborta em qualquer modo; recursos do projeto aceitos só por origem Compose (rótulo de projeto e arquivo de configuração); decisões resolvidas registradas. Validado só com docker stub inerte.
- 2026-10-22, execução autorizada (citação no briefing do orquestrador): Ruby 3.4.4 no cache da tarefa; `bundle install` (378 gems, lockfile intacto); Postgres e Redis do projeto healthy em 127.0.0.1; banco `conecta_baileys_g0_test` com schema; `route_inventory_spec` com `3 examples, 0 failures` após reclassificar 22 rotas e corrigir o toolchain (ver gotchas). Passos e falhas: `.context/evidence/g0/01-execucao-preparo-e-validacao.md`.

## Próximos marcos
- Feito com autorização: Ruby 3.4.4 no cache da tarefa; `--apply` (containers); `--spec --apply`. Nada foi instalado globalmente.
- Próximos (não iniciados): T0.2 (ACL), T0.3 (corte), T0.4 (anexos), T0.5 (AgentBot), T0.7 (barreira). T0.6 exige autorização para número de teste. T0.1 executado (`.context/evidence/g0/02-inventario-t0-1.md`).

## Decisões resolvidas
Decididas pelo humano em 2026-10-22. Não reabrir sem nova instrução.
1. **Arquivo `.env` na raiz**: a checagem `no_dotenv_in_root` (`scripts/connecta/g0_test_env.sh:80-87`) roda nos modos `prepare` (`:171`) e `--spec` (`:182`), e reprova se existir `.env` ou `.env.*` (exceto `*.example`), porque o Rails o leria. Com `--apply`, a reprovação aborta antes de qualquer comando (`:199-201`); sem `--apply`, aparece como `falta` e o dry-run segue. `--teardown` não executa essa checagem (`:191-195`). Nenhum arquivo é movido ou renomeado pelo código; mover é ação manual, fora deste preparo.
2. **Abrangência da guarda**: só `route_inventory_spec.rb` executa `Connecta::G0TargetGuard.verify!`. `.rspec` e `spec/rails_helper.rb` não mudam. `rails_helper.rb:34` carrega o módulo pelo suporte geral (só define métodos); só a execução é específica do inventário.
3. **Carga da spec fora do alvo**: a guarda aborta o processo (falha alta). Não há skip silencioso.
4. **Redis no G0**: mantido em `127.0.0.1:56379` para provas futuras que usem Redis real. A spec atual não precisa dele: em `Rails.env.test?` o app usa `MockRedis` (`config/initializers/01_redis.rb:10`).
5. **Segredo sintético**: criado no `--apply` em `~/.cache/connecta-g0-test/synthetic-secret` (0600, fora do repo). Não é versionado nem impresso.

## Decisões pendentes
6. **Frontend**: `pnpm install` saiu do preparo. Se alguma spec de request renderizar views com assets Vite, pode ser necessário reinstalar; não verificado.
7. **Runner não reexecutável após falha parcial**: `--apply` reprova com volume e portas já ocupados (`scripts/connecta/g0_test_env.sh:175-176`). Opções: (A) manter a guarda e reexecutar à mão os passos seguintes com o mesmo ambiente, como feito nesta execução; (B) aceitar volume com rótulo deste projeto e portas ocupadas por containers deste projeto (reexecução segura, mas afrouxa a pré-condição). Recomendação: A neste ciclo.
8. **Super admin com rotas Devise públicas**: cadastro (`POST /super_admin`), recuperação de senha, confirmação e OAuth/SAML do super admin (`.context/evidence/g0/02-inventario-t0-1.md`, riscos). Opções: (A) request de teste no banco G0, com dados sintéticos, para ver se respondem sem credencial; (B) tratar como achado e corrigir a autenticação em fase própria. Recomendação: A primeiro; B com o dono da autenticação.
9. **`/auth/:provider` sem `redirect_whitelist`**: opções: (A) confirmar que é intencional; (B) configurar a whitelist. Recomendação: confirmar com o dono da autenticação antes de mudar.

## Pendências e bloqueadores
- **Plano não lido**: a leitura de `/home/thanos/conectacidade/.worktrees/app-solicitacoes/.context/plans/2026-10-22-atendimento-dois-numeros-baileys.md` foi negada. A matriz §10.1 foi usada só pelo resumo do briefing, então a classificação das superfícies é provisória. Responsável: usuário, para liberar a leitura ou validar a classificação.
- **Spec executada**: `3 examples, 0 failures` em 2026-10-22, alvo G0 (`evidence/g0/01` e `02`). A classificação é por área, não a matriz §10.1 literal, que não foi lida.
- **Ruby 3.4.4 só no cache da tarefa** (`~/.cache/connecta-g0-test/toolchain/`). Fora do PATH global; o mise do usuário segue sem versão de `ruby` nesta worktree.
- **Serviços do G0 em execução** (containers healthy; volume `conecta-baileys-g0-test_g0_postgres`). Para parar: `scripts/connecta/g0_test_env.sh --teardown --apply` (mantém volumes; não executado).
- **Origem Compose validada em daemon real**: labels `com.docker.compose.project` e `config_files` conferidos nos containers (`evidence/g0/01`).
- **Lint**: RuboCop nos dois arquivos Ruby do G0, sem ofensas. ESLint não aplicável (sem JS alterado). shellcheck não instalado.
- **Desenho pendente**: specs concorrentes precisam de conexões reais fora da transação externa e limpeza restrita a `conecta_baileys_g0_test`. Não implementado.
- **Canais sem validação de assinatura encontrada no código** (registrado no inventário, sem correção nesta entrega): Twitter/X POST (`app/controllers/api/v1/webhooks_controller.rb:9-15`), Telegram, SMS, Twilio callback/status/voz. Slack uploads não exige usuário e depende só da chave aleatória do blob (`app/controllers/slack_uploads_controller.rb:15-17`).
- **Achados de autenticação não corrigidos**: decisões pendentes 8 e 9. Fora do escopo desta fase.
- **Segredo sintético** em `~/.cache/connecta-g0-test/synthetic-secret` (0600), criado pelo `--apply`; nunca impresso. Remover só em limpeza autorizada.
