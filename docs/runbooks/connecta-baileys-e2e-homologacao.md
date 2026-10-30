# Roteiro E2E — homologação do atendimento em dois números (T8.1)

> **NÃO EXECUTADO — exige homologação e autorização humana.**
> Nenhum passo abaixo foi rodado; não há evidência preenchida. Dados 100%
> sintéticos; número de homologação dedicado; produção fora do alcance.
> Pré-requisitos: F1–F7 completos; inbox física criada com escopo `enforce`
> antes de adicionar membros; admins nominais; webhooks inventariados;
> gates 15.1/15.2 do plano respeitados.

Fonte: plano canônico §15.1 (positivos 1–9; negativos 1–15).

## Como usar

Para cada passo: confira a pré-condição, execute o comando/ação, compare com o
resultado esperado e preencha o campo de evidência (data/hora, operador,
protocolo(s), prints/logs anexados). Qualquer divergência = FAIL, abortar a
sequência e registrar no relatório (não "contar teste unitário" como evidência).

## POSITIVOS (9)

### P-1. CTA → mensagem com código → setor sugerido → protocolo → resposta
- Pré-condição: CTA ativo (`HUMAN_SERVICE_MODE=external_number`); stack em `enforce`.
- Ação: no bot oficial, tocar o CTA; enviar mensagem com o código; aceitar o setor sugerido.
- Esperado: protocolo gerado; setor recebe; resposta do setor chega ao cidadão pelo número humano.
- Evidência: [ ] NÃO EXECUTADO · protocolo: ____ · prints: ____

### P-2. Entrada direta → triagem → setor → protocolo
- Pré-condição: número humano pareado (`connection: open`); recepção configurada (`CONNECTA_RECEPTION_ORG_UNIT_ID` / `HUMAN_SERVICE_RECEPTION_UNIT_ID`).
- Ação: mensagem direta ao número humano (sem CTA).
- Esperado: triagem cria caso no setor correto com protocolo; cidadão recebe confirmação.
- Evidência: [ ] NÃO EXECUTADO · protocolo: ____ · prints: ____

### P-3. Entrada direta → "Não sei" → recepção humana → transferência com resumo
- Pré-condição: mesma de P-2; agente de recepção de plantão.
- Ação: cidadão responde "Não sei"; recepção transfere ao setor com resumo obrigatório (assunto + ações feitas + próxima ação).
- Esperado: setor recebe resumo + mensagens novas; protocolo mantido.
- Evidência: [ ] NÃO EXECUTADO · protocolo: ____ · resumo conferido: ____

### P-4. Dois agentes do mesmo setor respondem sem atribuição
- Pré-condição: dois agentes com escopo do setor; conversa sem atribuição.
- Ação: ambos enviam respostas em sequência.
- Esperado: ambas entregues ao cidadão pelo número humano; sem conflito de atribuição; auditoria registra os dois atores.
- Evidência: [ ] NÃO EXECUTADO · protocolo: ____ · atores: ____

### P-5. Transferência A→B com resumo, mensagens e anexos novos
- Pré-condição: caso ativo no setor A; setor B existente.
- Ação: transferir A→B com resumo; enviar mensagens e anexos novos após a transferência.
- Esperado: B vê resumo + mensagens novas; anexos novos chegam; protocolo igual (não gera protocolo novo).
- Evidência: [ ] NÃO EXECUTADO · protocolo: ____ · anexos: ____

### P-6. Gestor de secretaria vê casos de unidades filhas; não consegue agir
- Pré-condição: gestor com escopo de secretaria; casos em unidades filhas.
- Ação: gestor abre casos das filhas no Chatwoot e no painel.
- Esperado: visualiza; qualquer ação (responder, encerrar, transferir, atribuir, gerir membros) é negada.
- Evidência: [ ] NÃO EXECUTADO · gestor: ____ · negações conferidas: ____

### P-7. Admin geral abre etapa antiga; auditoria registrada
- Pré-condição: admin geral nominal; caso com etapas antigas.
- Ação: admin abre etapa antiga (somente leitura/auditoria).
- Esperado: acesso permitido; evento de auditoria registrado com ator e timestamp.
- Evidência: [ ] NÃO EXECUTADO · admin: ____ · evento: ____

### P-8. Encerramento → mensagem nova do cidadão → protocolo novo
- Pré-condição: caso ativo com protocolo P.
- Ação: encerrar o caso; cidadão envia nova mensagem.
- Esperado: novo caso com protocolo P' ≠ P; caso antigo permanece encerrado e auditado.
- Evidência: [ ] NÃO EXECUTADO · P: ____ · P': ____

### P-9. Reinício do baileys-api e do fork sem perder mensagem; mídia ida e volta
- Pré-condição: autorização humana com servidor/escopo; tráfego sintético em curso.
- Ação: reiniciar baileys-api e fork (runbook T7.2 §4); enviar imagem, áudio e documento nos dois sentidos durante a janela.
- Esperado: nenhuma mensagem perdida; mídias (imagem, áudio, documento) entregues ida e volta após o restart.
- Evidência: [ ] NÃO EXECUTADO · janela: ____ · mídias conferidas: ____

## NEGATIVOS (15 — devem falhar com segurança)

### N-1. Agente de A não alcança conversa de B por nenhum caminho
- Pré-condição: agente só com escopo de A; conversa ativa em B.
- Ação: tentar URL direta, busca, contatos, socket, notificação, anexo antigo, transcript, export e relatório da conversa de B.
- Esperado: TODAS as vias negadas (erro/403/vazio), sem vazamento de conteúdo.
- Evidência: [ ] NÃO EXECUTADO · vias testadas (9/9): ____

### N-2. Origem após transferência perde todo acesso
- Pré-condição: transferência A→B concluída.
- Ação: como agente de A, tentar enviar, ler, baixar anexo antigo, receber socket e ver contato da conversa transferida.
- Esperado: tudo negado; mensagens novas gravadas só em B; origem nunca reaberta.
- Evidência: [ ] NÃO EXECUTADO · resultado: ____

### N-3. Gestor não executa ações
- Pré-condição: gestor de secretaria (P-6).
- Ação: tentar enviar, encerrar, transferir, atribuir e gerir membros.
- Esperado: todas negadas.
- Evidência: [ ] NÃO EXECUTADO · resultado: ____

### N-4. Gestor de origem após transferência para fora do escopo (P-9 do plano)
- Pré-condição: transferência para setor fora do escopo do gestor de origem.
- Ação: gestor de origem tenta abrir/agir na conversa transferida.
- Esperado: negado.
- Evidência: [ ] NÃO EXECUTADO · resultado: ____

### N-5. Sem papel / vínculo inválido
- Pré-condição: (a) membro da inbox sem papel; (b) usuário sem vínculo; (c) vínculo só por e-mail.
- Ação: cada um tenta ler a conversa do número humano.
- Esperado: todos negados; vínculo por e-mail não autoriza.
- Evidência: [ ] NÃO EXECUTADO · casos (a)(b)(c): ____

### N-6. Ator/setor forjado em chamada direta à API
- Pré-condição: acesso à API da plataforma e do fork com credenciais de teste.
- Ação: forjar `actor_chatwoot_user_id`, `org_unit_id` ou `account_id` divergente.
- Esperado: 403 (conta divergente de `CONNECTA_ACCOUNT_ID`), sem efeito colateral.
- Evidência: [ ] NÃO EXECUTADO · respostas: ____

### N-7. Dois casos para o mesmo cidadão (duplicidade)
- Pré-condição: cidadão sintético único.
- Ação: (a) dois canais ao mesmo tempo; (b) clique repetido no CTA; (c) webhook duplicado.
- Esperado: 1 caso (idempotência por versão); sem conversa/ticket externo extra.
- Evidência: [ ] NÃO EXECUTADO · casos criados: ____ (esperado 1)

### N-8. Código de outro telefone / vencido / alterado
- Pré-condição: códigos emitidos para o telefone T.
- Ação: confirmar com código de outro telefone, código vencido e código alterado.
- Esperado: todos recusados; nenhum vínculo criado.
- Evidência: [ ] NÃO EXECUTADO · tentativas (3/3 negadas): ____

### N-9. Transferência concorrente
- Pré-condição: caso ativo transferível.
- Ação: disparar em paralelo transferência + mensagem + envio + encerramento + outra transferência.
- Esperado: exatamente uma transferência vence; demais operações seguem a transação (retidas ou recusadas sem duplicar caso nem reenviar).
- Evidência: [ ] NÃO EXECUTADO · vencedor: ____ · demais: ____

### N-10. Plataforma fora durante triagem e transferência
- Pré-condição: casos sintéticos em triagem e em transferência.
- Ação: derrubar a plataforma (ambiente de homologação) nas duas janelas.
- Esperado: transporte `unknown`; commit remoto falhando ⇒ destino fica
  `pending_activation` invisível a agentes; mensagens novas gravadas nele; origem nunca reaberta.
- Evidência: [ ] NÃO EXECUTADO · estados: ____

### N-11. Agente/gestor tentando ver QR ou status de conexão
- Pré-condição: agente e gestor logados.
- Ação: tentar abrir QR (`qr_data_url`), `/status`, `/status/auth` ou painel de conexão.
- Esperado: negado/oculto (admin-only); nenhum QR exibido.
- Evidência: [ ] NÃO EXECUTADO · resultado: ____

### N-12. Corrida um escritor legado + um novo (admissão única)
- Pré-condição: stack com legado (handoff Chatwoot; onde houver, Ticketz) e modo novo ativos; admissão `enforce`.
- Ação: handoff legado e aceitação no número humano simultâneos para a mesma identidade; repetir com `pn` e `lid` consolidados da mesma identidade.
- Esperado: 1 caso; nenhuma conversa/ticket externo extra. Legado `legacy_unmapped` ⇒ nova admissão bloqueada, sem protocolo retroativo.
- Evidência: [ ] NÃO EXECUTADO · casos: ____ · tickets externos: ____

### N-13. Revogação com fila de sync pausada e socket aberto
- Pré-condição: sessão escopada ativa com socket aberto; outbox para o fork pausada.
- Ação: revogar papel/vínculo; observar painel e plataforma.
- Esperado: painel nega já; plataforma mostra `revocation_pending` (nunca "confirmada");
  sem heartbeat no limite, fork nega todo acesso escopado; revogação de emergência
  no fork derruba o socket na hora. Ao retomar: ack, socket desconectado,
  requisição/job/token de download antigos negados.
- Evidência: [ ] NÃO EXECUTADO · sequência: ____

### N-14. Rollback com agente de equipe ainda vinculado e link de anexo antigo
- Pré-condição: agente com vínculo de equipe/membro da inbox; link antigo de anexo.
- Ação: aplicar contenção `admin_only`; tentar abrir conversa, busca, contato e anexo por link antigo; tentar reabrir acesso via `shared_token`.
- Esperado: tudo negado; nenhuma etapa reabre acesso por `shared_token`.
- Evidência: [ ] NÃO EXECUTADO · resultado: ____

### N-15. Worker de envio atrasado + transferência
- Pré-condição: `SendReplyJob` com mensagem `queued` pausado.
- Ação: iniciar transferência com o despacho pendente.
- Esperado: mensagem `parked`, nada despachado depois; despacho `dispatching`
  sem resposta ⇒ `uncertain`, transferência retida, sem reenvio e sem "cancelado".
- Evidência: [ ] NÃO EXECUTADO · estados do despacho: ____

## Critério de aceite T8.1

Todos os 24 itens acima com evidência preenchida (data/hora, operador,
protocolos, anexos de log/print) e resultado conforme o esperado. Qualquer
FAIL aborta a homologação e gera item de correção antes de T8.2/T8.3.
