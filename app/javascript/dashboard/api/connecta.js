/* global axios */
import ApiClient from './ApiClient';

class ConnectaApi extends ApiClient {
  constructor() {
    super('connecta', { accountScoped: true });
  }

  confirmIdentityLink(code) {
    return axios.post(`${this.url}/identity_link`, { code });
  }

  getOutboundDispatches() {
    return axios.get(`${this.url}/outbound_dispatches`);
  }

  resolveOutboundDispatch(id, { state, connectorMessageId }) {
    return axios.patch(`${this.url}/outbound_dispatches/${id}/resolve`, {
      state,
      connector_message_id: connectorMessageId,
    });
  }

  // Admissão manual: destinos elegíveis do ator (WP revalida vínculo+grants).
  // Collection (sem conversationId) com inbox de contexto autorizada no servidor.
  admissionDestinationsForInbox(inboxId) {
    const query = inboxId ? `?inbox_id=${encodeURIComponent(inboxId)}` : '';
    return axios.get(
      `/api/v1/accounts/${this.accountIdFromRoute}/conversations/connecta_manual_admission/destinations${query}`
    );
  }

  // Admissão manual + primeira mensagem UMA VEZ (fork cria/admite/ativa/envia).
  // Anexos vão como upload multipart nativo; signed IDs soltos são recusados
  // pelo servidor, porque não provam vínculo de conta.
  admitConversation({
    inboxId,
    contactId,
    sourceId,
    orgUnitId,
    message,
    idempotencyKey,
    files = [],
  }) {
    const form = new FormData();
    form.append('inbox_id', inboxId ?? '');
    form.append('contact_id', contactId ?? '');
    if (sourceId != null && sourceId !== '') {
      form.append('source_id', sourceId);
    }
    form.append('org_unit_id', orgUnitId ?? '');
    form.append('idempotency_key', idempotencyKey ?? '');
    if (message?.content != null) {
      form.append('message[content]', message.content);
    }
    (message?.attachments || []).forEach(file =>
      form.append('message[attachments][]', file)
    );
    files.forEach(file => form.append('message[attachments][]', file));

    return axios.post(
      `/api/v1/accounts/${this.accountIdFromRoute}/conversations/connecta_manual_admission`,
      form
    );
  }

  showScope(conversationId) {
    return axios.get(
      `/api/v1/accounts/${this.accountIdFromRoute}/conversations/${conversationId}/connecta_scope`
    );
  }

  // Opt-out do bot por número (Etapa 3). Estado lido sob demanda (só quando o
  // menu abre ou a conversa abre); fora de caixa humana o servidor 404.
  showBotOptout(conversationId) {
    return axios.get(
      `/api/v1/accounts/${this.accountIdFromRoute}/conversations/${conversationId}/connecta_bot_optout`
    );
  }

  setBotOptout(conversationId, disabled) {
    return axios.post(
      `/api/v1/accounts/${this.accountIdFromRoute}/conversations/${conversationId}/connecta_bot_optout`,
      { disabled }
    );
  }

  // Etapas visíveis do protocolo. O backend filtra por conta/inbox e aplica
  // Gate por etapa; etapas ocultas não retornam id, nome nem link.
  getProtocol(protocol, { cursor = null, limit = null } = {}) {
    return axios.get(`${this.url}/protocols/${encodeURIComponent(protocol)}`, {
      params: { cursor, limit },
    });
  }

  // Metadados da lista em lote; ids não visíveis são omitidos pelo servidor.
  conversationMetadata(ids) {
    return axios.get(`${this.url}/conversations/metadata`, {
      params: { ids: ids.join(',') },
    });
  }
}

export default new ConnectaApi();
