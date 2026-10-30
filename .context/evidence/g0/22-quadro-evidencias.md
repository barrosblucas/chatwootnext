# G0 — Quadro final de evidências EVID-1..8 (dossiê G0, 2026-10-24)

**Natureza:** consolidação documental. Nenhuma prova nova foi executada; nenhum código foi alterado.
**Gate G0: ABERTO.** Este quadro não aprova ACL, transporte, pareamento nem Fase 1.
**Base de leitura:** evidências históricas `02`, `05` (anexos + agentbot), `09`, `11`, `12`, `15`, `19`,
`PROJECT_STATE.md` antigo, plano externo §§12–13/17 (lido por `sed -n`, fora da raiz) e código nativo
estável citado em EVID-3/5. Evidências `18`/`21` e `scope/**`, `transfer/**` em mutação por outros
Coders **não** foram usados.

## Decisão de sequência do humano (registrada, não é aceite de risco)

> "com o teste real com QR e qualquer mudança em servidor ou produção só no final, com autorização escrita."

Efeito prático registado: apenas spike sintético agora; **nada de transporte real, QR real, deploy,
servidor ou produção até autorização escrita e validação T0.6**. A postergação autorizada do teste
real **não equivale a aceitar risco de produção**. Se aceitação formal de risco for necessária,
fica como **"decisão humana pendente"** — este documento não a inventa.

## Decisão técnica R-G0-LOCAL-1 (ORQUESTRADOR, 2026-10-24) — só risco reversível local

**Fonte:** ORQUESTRADOR (decisão técnica), não humano. A citação humana acima autoriza
sequência (spike sintético agora; real/QR/servidor/produção só no final, com autorização
escrita); não aceita licença desconhecida nem autoriza uso/distribuição de artefato.

> "Aceito tecnicamente o risco reversível de retrabalho de código local enquanto T0.6
> permanece adiada por direção humana. A continuidade é limitada a desenvolvimento local,
> spike sintético e flags desligadas; não depende de executar o artefato baileys-api
> desconhecido. EVID-2/8 continuam NEEDS-T0.6 (pin/digest/compatibilidade/licença
> desconhecidos), EVID-3/5 continuam parciais. Antes de usar transporte real/QR/servidor/
> produção, exigir autorização escrita e concluir verificações T0.6, incluindo pin/digest,
> licença/dependências, campos e comportamento real. Não há aceite de risco a dados/
> segurança/produção, nem autorização de uso/distribuição de artefato com licença
> desconhecida."

Efeito limitado ao Gate G0:

- Cobre **apenas** o risco reversível de retrabalho local na continuidade LOCAL (código
  local, spike sintético, flags desligadas). Não é aceite de risco a dados, segurança ou
  produção, nem autorização de uso/distribuição do artefato com licença desconhecida.
- Liga-se às linhas EVID-2 e EVID-8 (continuam **NEEDS-T0.6**: versão/digest/
  compatibilidade/licença/dependências/Redis/recursos desconhecidos) e EVID-3 e EVID-5
  (continuam **parciais por leitura de código**, sem prova real) — sem alterar status.
- Desconhecidos e achados 8–11 ficam preservados, sem resolução por inferência (ver
  "Achados não corrigidos" e "Notas de honestidade").
- Bloqueios preservados: **nada de transporte real, QR real, servidor ou produção até
  autorização escrita e validação T0.6** (pin/digest, licença/dependências, campos e
  comportamento real).
- O esclarecimento "decisão humana pendente" acima refere-se às permissões humanas de
  uso/produção/distribuição, que **permanecem pendentes**; R-G0-LOCAL-1 substitui só a
  eventual leitura ambígua de "decisão de risco pendente" quanto à continuidade LOCAL.
- Juiz T2 continua independente para decidir viabilidade e suficiência; nenhum `APPROVED`
  antecipado. `COMPLETED` de spike nunca é lido aqui como `APPROVED` de gate.

## Quadro EVID-1..8

| ID | Pergunta (plano §17) | Resposta verificável | Fonte | Status | Pendência |
|---|---|---|---|---|---|
| EVID-1 | Lista completa de rotas/serviços que expõem conversa, mensagem, anexo, contato. | Inventário executado: **877 rotas**, 0 não classificadas, 11 infra; superfícies por área com fronteiras (ex.: conversas 60, Captain 68, chat interno 39, sockets 1 sem auth na conexão, widget 27, conta/admin 85, super admin 92). 22 rotas reclassificadas com origem verificada (Sprockets, devise_token_auth, Devise super admin, engine AWS SES). Classificação **por área, não a matriz §10.1 literal** (plano não lido na entrega). **Final 34 (sem inventar total novo de rotas): rota nova classificada `GET /api/v1/accounts/:account_id/connecta_attachments/:attachment_id/download` (`connecta/scope/attachment_downloads#show`, Disk local de teste) como superfície `download autorizado de anexo marcado (spike G0; rota desenhada só com o Installer instalado)`; 877 nativas preservadas, sem catch-all nem mandatory novo.** | `.context/evidence/g0/02-inventario-t0-1.md` + spec `spec/requests/connecta/route_inventory_spec.rb` (3 exemplos, 0 falhas, 2026-10-22) + `.context/evidence/g0/31-spec-lint.md` §2 (classificação exata da rota nova; 5 specs zerados) + `34-logs/g2-related.log` (G2 123/0 revalidando o inventário, `route_inventory:204` verde pela 1ª vez) | **Respondida** (limite: matriz §10.1 literal não validada) | nenhuma prova nova; matriz §10.1 segue provisória |
| EVID-2 | Versão do baileys-api compatível com o fork (pin + digest) e mudanças de campo (`qrDataUrl`, `epoch`, `quarantine`, `includeMedia`). | **Desconhecido.** Versão/digest **não fixados**; compatibilidade real desconhecida. Nenhum pin ou digest é afirmado neste dossiê. | plano §T0.6 (tarefa de transporte em ambiente de teste, com autorização humana para número de teste) | **NEEDS-T0.6** | Fixar versão + digest, validar campos e checklist real; só com autorização escrita |
| EVID-3 | Eventos de contatos `lid` trazem telefone? Como a consolidação do fork reage (cria conversa nova?). | **Parcial, só por leitura de código — sem prova real.** O serviço de consolidação existe e cobre: fone+LID no mesmo contato → move conversas e destrói o `contact_inbox` de fone (`contact_inbox_consolidation_service.rb:58-66`); fone+LID em contatos diferentes → move conversas para o contato de fone e migra `source_id` para LID (`:71-92`); só fone → migra para LID (`:94-104`). O handler Baileys extrai `lid` do JID e chama a consolidação (`individual_contact_message_handler.rb:68-79`). Deduplicação de mensagem por `source_id` existe no caminho base (`incoming_message_base_service.rb:42,52`) e no Baileys (`individual_contact_message_handler.rb:23`). **Não se afirma** que evento `lid` traz telefone, nem que conversa nova é/não é criada — sem T0.6 não há prova. | `app/services/whatsapp/contact_inbox_consolidation_service.rb:21-104`, `app/services/whatsapp/baileys_handlers/concerns/individual_contact_message_handler.rb:20-23,68-79`, `app/services/whatsapp/incoming_message_base_service.rb:31-52,304-315` | **Parcial (código)** | T0.6 real: evento `lid` com/sem telefone, reação da consolidação, criação de conversa |
| EVID-4 | Link de anexo antigo continua abrindo? Expira? Há rota autorizada viável? | **Respondida (serviço Disk local de teste) + rota autorizada em código revalidada em spec no final 34.** `file_url`/`thumb_url`/proxy **não expiram** (redirect 302 e proxy 200 em +1 ano); só a URL direta Disk expira em 5 min, mas o redirect emite URL nova a cada acesso → acesso efetivo permanente. Callbacks ActiveStorage não checam usuário nem conta. Rota autorizada (usuário + conta + epoch + Gate, token 5 min, bloqueio legado): **27 exemplos, 0 falhas** no final 34 (`34-logs/d-attachment.log`, lote D), revalidando o código da evidência 20 após o fix de causa-única (`NoMethodError attachments for Account`) e o alinhamento admin (evidência 20 §§9-10; `28-logs/anexos-final-4.log` com 27/0). Limite: S3/GCS/Azure não medidos; storage medido é **Disk local de teste**. | `.context/evidence/g0/05-evid4-anexos.md` (rodadas 4–5: 29 exemplos, 0 falhas) + `.context/evidence/g0/20-t02-anexos.md` (código; §§9-10 fix/alinhamento) + `.context/evidence/g0/34-final-regression.md` (lote D 27/0) | **Respondida (Disk local) + rota autorizada revalidada em spec (final 34)** | Decisão pendente 12 do `PROJECT_STATE.md` (opções A manter / B autorizar na T0.2); S3/GCS/Azure seguem não medidos |
| EVID-5 | Mensagens recebidas com o serviço fora chegam uma vez só depois de reconectar? | **Parcial, só por leitura de código — sem prova real.** Há guarda `find_message_by_source_id` antes de criar nos três caminhos (base `:42,52`, Baileys individual `:23`, recibos/edições/revogações base `:108,142,159`) e lock de contato com limpeza pós-commit no Baileys (`individual_contact_message_handler.rb:42`). **Não se chama isto de prova de deduplicação/reconexão:** sem T0.6 (fora + reconectar + reenvio do provedor) não há garantia de exactly-once; a janela `clear_message_source_id_from_redis` antes do commit (limite T0.3, evidência 10 §6) também segue aberta. | mesmos arquivos de EVID-3 + `.context/evidence/g0/10-t03-corte.md` §6 (janela Redis/commit) | **Parcial (código)** | T0.6 real: cair, reconectar, conferir unicidade; só com autorização escrita |
| EVID-6 | AgentBot: assinatura, repetição, ordem. | **Respondida.** Seleção `[assignee, inbox]` sem duplicata; 1 job por bot com `delivery_id` estável; HMAC-SHA256 `sha256=<hex(timestamp.body)>` + `X-Chatwoot-Timestamp`/`Delivery` + JSON; timeout 5 s ou `WEBHOOK_TIMEOUT`; 429/500 → 3 tentativas, `pending` até esgotar; 404/timeout → 1 tentativa, `open` na hora. **Achado não corrigido:** `retry_on` + `discard_on` do mesmo erro no `WebhookJob` pai anula o retry de 5 tentativas (`app/jobs/webhook_job.rb:4-5`). Ordem global e exactly-once **não provados**; receptor real não testado; `SafeFetch` stubado. | `.context/evidence/g0/05-evid6-agentbot.md` (17 exemplos, rodadas 4–5 com EVID-4) | **Respondida** | Decisão pendente 11 do `PROJECT_STATE.md` (manter 1 tentativa / ativar até 5 com risco de reprocesso) |
| EVID-7 | Recursos próprios do fork (chat interno, agendadas, recorrentes, Captain): quais leem conteúdo de conversa. | **Mapeada nas evidências 11/12/15/19 — com código c7b ainda sem validação. Final 34 (conforme logs, sem afirmar causa): Captain 33/0 em 3 execuções consecutivas e sozinhas no final (`34-logs/c1-captain-1.log`, `c2-captain-2.log`, `c3-captain-3.log`; 33 únicos + 99 execuções); chat interno revalidado no G2 123/0 (`34-logs/g2-related.log`) incluindo `internal_chat_scope_spec.rb` (6 exemplos: chat interno NÃO lê conteúdo de conversa, só `InternalChat::*`); sub-rotas B1/agendadas/recorrentes revalidadas no B 73/0 (`34-logs/b-leftovers.log`).** Socket (ev. 09): 16 eventos no mapa do hook; mention/contagem/notificação/presença fora do filtro inicial, tratados em c2a/c2b (metadados de admin por job próprio; digitação e contato vinculado filtrados; `contact.deleted` com janela de corrida; presença só sinal, sem spec). Captain (ev. 11): FAQ/sessões/inbox_assistant com negativas provadas nas runs 4–5, **mas spec instável no histórico** (verde 2/5, causa não identificada) + **vazamento real Copilot** (`conversation_id` sem checagem chega ao job e ao contexto do modelo). Chat interno (ev. 12): **não lê conteúdo de conversa** (só `InternalChat::*`; 6 exemplos). Complementos B2 (ev. 15): admin/integrações/relatórios sob papel nativo; ACHADO-1 (auditoria `allow` fantasma em `inbox_update`). Complemento c7b (ev. 19): hooks Copilot/Captain/inbox **implementados, explicitamente NÃO VALIDADOS** (nenhum spec executado por instrução do humano; 401→404 e ACHADO-1 como código a provar). | `.context/evidence/g0/09-t02-socket.md` §§2–3/7–8, `.context/evidence/g0/11-t02-captain.md` §§1–4, `.context/evidence/g0/12-t02-chat-interno.md` §§1–4, `.context/evidence/g0/15-t02-b2-complementos.md` §§1–4, `.context/evidence/g0/19-t02-captain-complemento.md` §§1–4, `.context/evidence/g0/34-final-regression.md` (C1/C2/C3 33/0, B 73/0, G2 123/0) | **Parcial** (c7b: código sem prova) | Validar c7b em tarefa posterior; estabilizar spec Captain; fechar `contact.deleted`, presença e ferramentas Copilot |
| EVID-8 | Licença do baileys-api e dependências; requisitos de Redis e recursos. | **Desconhecida.** Nenhuma licença é afirmada neste dossiê: **não inferir licença pelo nome do pacote nem transferir licença de outro repositório.** Requisitos de Redis/recursos também pendem do T0.6 real. | plano §T0.6; §12 ("Licenças: confirmar licença do baileys-api e da versão fixada [EVID-8]") | **NEEDS-T0.6** | Levantar licença do artefato + dependências e requisitos; só com autorização escrita |

## Achados não corrigidos que importam ao Juiz (sem afirmar validação inexistente)

1. **Decisões 8–11 do `PROJECT_STATE.md` (2026-10-22), todas pendentes:** (8) super admin com rotas
   Devise públicas — request de teste vs. tratar como achado; (9) `/auth/:provider` sem
   `redirect_whitelist` — confirmar intenção vs. configurar; (10) teardown+preparo recusa volume
   órfão — manter recusa (recomendado) vs. aceitar com posse fraca; (11) retry genérico do AgentBot —
   manter 1 tentativa (recomendado) vs. ativar 5 com risco de reprocesso sem dedup garantida.
2. **Presença expõe ids da conta sem Gate** (ev. 09 §8.5): `room_channel.rb:19-25` envia
   `{account_id, users: {id: disponibilidade}, contacts: {id: 'online'}}` ao próprio assinante,
   sem passar pelo listener/hook; ids de contatos podem incluir vinculados à inbox marcada
   (sinal, não conteúdo). Sem spec. Decisão pendente: filtrar `contacts` por `ContactVisibility`.
3. **Frontend não validado com payload admin reduzido** (ev. 09 §7.4): nenhum cliente foi testado
   com os metadados `{id, conversation_id/inbox_id, status, org_unit_id, account_id}` (ex.: componente
   que espera `messages`/`meta` pode quebrar com o campo ausente).
4. **Job próprio de metadados separado do job nativo** (ev. 09 §§7.1/7.4): `ActionCableBroadcastJob:26`
   relê `conversation.push_event_data` e trocaria o payload reduzido pelo completo; o spike usa
   `AdminMetadataBroadcastJob` próprio. Produção exige decisão: (A) job próprio ou (B) alterar o job
   nativo (core, fora do escopo).
5. **`POST contacts` com `inbox_id` da inbox marcada não coberto** (ev. 15 §4): passa por
   `ContactInboxBuilder` com `validate_baileys_phone: true` (`contacts_controller.rb:174-182`), pode
   chegar ao transporte; exige stub de transporte e decisão de escopo. Criação sem `inbox_id` (200
   para A/B/membro, sem `display_id`, sem auditoria `conversation`) está provada (ev. 15 §1).
6. **Correção do 401 Captain implementada na evidência 19, ainda sem spec** (ev. 19 §§2–4):
   `CaptainHttpHook#authorize_conversation` (Gate antes do `authorize` nativo; 404 com auditoria
   `captain_show`/`captain_create`) e `InboxHook` (auditoria `allow` só após `super`; fecha o
   ACHADO-1) estão **escritos mas NÃO VALIDADOS** — nenhum spec/RuboCop/build executado por
   instrução do humano. **Não se afirma** que toda divergência Pundit acabou: o 401→404 só valerá
   quando a tarefa de specs provar (casos listados em ev. 19 §4).
7. **Limites herdados que seguem valendo:** canais sem validação de assinatura (Twitter/X POST,
   Telegram, SMS, Twilio) e `unread_counts` fora de escopo parcial (`PROJECT_STATE.md`); menção e
   `participating` corrigidos em c5 por código com specs verdes, mas fora deste quadro (ev. 13);
   T0.3/T0.7a/T0.7b têm provas próprias e não fecham EVID-3/5.

## Notas de honestidade para o Juiz

- Fatos têm fonte; desconhecidos continuam desconhecidos (EVID-2 versão/digest/compatibilidade;
  EVID-8 licença; EVID-3 telefone-em-`lid` e criação de conversa; EVID-5 unicidade pós-reconexão).
- `COMPLETED` de tarefa de spike nunca é lido aqui como `APPROVED` de gate.
- Links locais citados acima existem nesta worktree (conferidos por listagem); o plano externo é
  citado por caminho absoluto legível por `sed -n` e não é link local.
