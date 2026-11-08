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
  admitConversation({
    inboxId,
    contactId,
    sourceId,
    orgUnitId,
    message,
    idempotencyKey,
  }) {
    return axios.post(
      `/api/v1/accounts/${this.accountIdFromRoute}/conversations/connecta_manual_admission`,
      {
        inbox_id: inboxId,
        contact_id: contactId,
        source_id: sourceId,
        org_unit_id: orgUnitId,
        message,
        idempotency_key: idempotencyKey,
      }
    );
  }

  showScope(conversationId) {
    return axios.get(
      `/api/v1/accounts/${this.accountIdFromRoute}/conversations/${conversationId}/connecta_scope`
    );
  }

  // Etapas visíveis do protocolo. O backend filtra por conta/inbox e aplica
  // Gate por etapa; etapas ocultas não retornam id, nome nem link.
  getProtocol(protocol) {
    return axios.get(`${this.url}/protocols/${encodeURIComponent(protocol)}`);
  }

  // Metadados da lista em lote; ids não visíveis são omitidos pelo servidor.
  conversationMetadata(ids) {
    return axios.get(`${this.url}/conversations/metadata`, {
      params: { ids: ids.join(',') },
    });
  }
}

export default new ConnectaApi();
