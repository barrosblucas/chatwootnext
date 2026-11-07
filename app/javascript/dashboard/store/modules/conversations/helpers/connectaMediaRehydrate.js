// Reidratacao de anexos apos o sanitizador realtime de inbox marcada.
//
// O cable de inbox marcada entrega anexos SEM `data_url`/`thumb_url` (o token do
// remetente nao pode viajar para N viewers) com o marcador `connecta_media_resolve`.
// Cada viewer busca sua representacao autorizada no GET autenticado existente
// (`MessageApi.getPreviousMessages`) e escolhe o id EXATO. Nao ha GET individual:
// `MessageFinder` atende janela `after=id-1, before=id+1` (para `id=1`, `after=0`
// e omitido por ser falsy, caindo em `messages_before(2)`, que tambem inclui o 1).
//
// Regras honradas aqui:
// - dedup in-flight por conta/viewer/conversa/mensagem, SEM cache global de dados
//   entre usuarios (o mapa guarda so promises da sessao, nunca payload resolvido);
// - troca de viewer/conta ou logout descarta o resultado (conferido no apply);
// - nunca regredir scalar novo: snapshot antigo nao troca `status`/`content`/
//   `updated_at` mais recente; timestamps iguais com ids de anexo diferentes
//   disparam UMA releitura limitada (mudanca de midia com o GET em voo);
// - snapshot sem `updated_at` (incomparavel) so resolve o placeholder se o
//   conjunto de anexos for identico; caso contrario o placeholder permanece;
// - falha 403/404/rede mantem o placeholder marcado (recuperavel no proximo
//   evento) e nunca reintroduz URL legada.

import MessageApi from 'dashboard/api/inbox/message';

export const CONNECTA_MEDIA_RESOLVE_KEY = 'connecta_media_resolve';

const MAX_HYDRATE_ATTEMPTS = 2;

export const needsConnectaMediaResolve = message => {
  return !!message && message[CONNECTA_MEDIA_RESOLVE_KEY] === true;
};

// So ids ordenados: compara o CONJUNTO de anexos sem olhar URLs.
export const attachmentSignature = message => {
  const attachments = message?.attachments;
  if (!Array.isArray(attachments)) return '';
  return attachments.map(attachment => String(attachment?.id)).join('|');
};

export const withoutResolveMarker = message => {
  if (!message || typeof message !== 'object') return message;
  const copy = { ...message };
  delete copy[CONNECTA_MEDIA_RESOLVE_KEY];
  return copy;
};

const parseMessageTime = value => {
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? parsed : null;
};

// -1|0|1 pela recencia de `updated_at`; null quando incomparavel (nunca clobber).
export const compareUpdatedAt = (current, hydrated) => {
  const currentTime = parseMessageTime(current?.updated_at);
  const hydratedTime = parseMessageTime(hydrated?.updated_at);
  if (currentTime === null || hydratedTime === null) return null;
  if (hydratedTime > currentTime) return 1;
  if (hydratedTime < currentTime) return -1;
  return 0;
};

export const pickExactMessage = (payload, messageId) => {
  if (!Array.isArray(payload)) return undefined;
  return payload.find(item => String(item?.id) === String(messageId));
};

export const windowParamsFor = messageId => {
  const id = Number(messageId);
  if (!Number.isFinite(id)) return null;
  return { after: id - 1, before: id + 1 };
};

export const inflightKeyFor = ({
  accountId,
  userId,
  conversationId,
  messageId,
}) => {
  return [accountId, userId, conversationId, messageId]
    .map(value => String(value ?? ''))
    .join(':');
};

const inflight = new Map();

export const getInflightResolve = key => inflight.get(key);
export const setInflightResolve = (key, entry) => inflight.set(key, entry);
export const deleteInflightResolve = (key, entry) => {
  if (inflight.get(key) === entry) inflight.delete(key);
};
export const clearConnectaMediaInflight = () => inflight.clear();
export const connectaMediaInflightSize = () => inflight.size;

// Mensagens marcadas embutidas em payload de conversa (seed `messages` e preview
// `last_non_activity_message`). Puro: so coleta, o dispatch e do caller.
export const collectMarkedEmbeddedMessages = conversation => {
  if (!conversation || typeof conversation !== 'object') return [];
  const found = [];
  if (Array.isArray(conversation.messages)) {
    conversation.messages.forEach(message => {
      if (needsConnectaMediaResolve(message)) found.push(message);
    });
  }
  if (needsConnectaMediaResolve(conversation.last_non_activity_message)) {
    found.push(conversation.last_non_activity_message);
  }
  return found;
};

export const fetchExactMessage = async ({ conversationId, messageId }) => {
  const window = windowParamsFor(messageId);
  if (!window || conversationId === undefined || conversationId === null) {
    return undefined;
  }
  const {
    data: { payload },
  } = await MessageApi.getPreviousMessages({
    conversationId,
    after: window.after,
    before: window.before,
  });
  return pickExactMessage(payload, messageId);
};

// Decide o destino do snapshot buscado frente ao que o store tem AGORA:
// 'commit' aplica pelo fluxo normal, 'refetch' tenta uma releitura limitada,
// 'keep' mantem o store (placeholder segue recuperavel no proximo evento).
export const decideHydrateApply = (current, fetched) => {
  if (!fetched) return 'keep';
  if (!current) return 'commit';
  if (!needsConnectaMediaResolve(current)) {
    // Store ja hidratado (ex.: merge de update com mesmos anexos): so um
    // snapshot estritamente mais novo justifica trocar.
    return compareUpdatedAt(current, fetched) === 1 ? 'commit' : 'keep';
  }
  const order = compareUpdatedAt(current, fetched);
  if (order === 1) return 'commit';
  if (order === -1) return 'refetch';
  if (order === 0) {
    return attachmentSignature(current) === attachmentSignature(fetched)
      ? 'commit'
      : 'refetch';
  }
  // Incomparavel (snapshot sem `updated_at`): so resolve se os anexos forem
  // exatamente os mesmos; caso contrario o placeholder segue.
  return attachmentSignature(current) === attachmentSignature(fetched)
    ? 'commit'
    : 'keep';
};

export const findStoreMessage = (state, conversationId, messageId) => {
  const chat = (state?.allConversations || []).find(
    conversation => String(conversation?.id) === String(conversationId)
  );
  return chat?.messages?.find(
    message => String(message?.id) === String(messageId)
  );
};

export { MAX_HYDRATE_ATTEMPTS };
