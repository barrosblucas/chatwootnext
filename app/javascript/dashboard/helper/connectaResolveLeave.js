// Saída da conversa escopada após Resolver (UX igual à da transferência).
//
// Quando o operador resolve uma conversa sob enforcement Connecta, o chamado
// sai da lista/store dele e a tela volta para a lista da aba atual — o mesmo
// destino da transferência (TransferAction). É só frontend: nada é revogado
// no servidor (sem `scope.revoked`, sem unassign; o relatório CSAT continua
// atribuído via `csat_survey_responses.assigned_agent_id`).
import conversationAPI from 'dashboard/api/inbox/conversation';
import wootConstants from 'dashboard/constants/globals';
import { emitter } from 'shared/helpers/mitt';
import types from 'dashboard/store/mutation-types';
import {
  isOnFoldersView,
  isOnMentionsView,
  isOnParticipatingView,
  isOnUnattendedView,
} from 'dashboard/store/modules/conversations/helpers/actionHelpers';
import { conversationListPageURL } from './URLHelper';

// Mesmo destino da transferência: depois que a conversa sai do escopo do
// atendente, volta para a lista da aba de onde ele partiu (filtros
// preservados). Extraído de TransferAction.vue sem mudança de comportamento.
export const navigateToConversationList = (router, route, accountId) => {
  const {
    params: {
      accountId: routeAccountId,
      inbox_id: inboxId,
      label,
      teamId,
      id: folderId,
    },
    name,
  } = route;

  let conversationType = '';
  if (isOnMentionsView({ route: { name } })) {
    conversationType = wootConstants.CONVERSATION_TYPE.MENTION;
  } else if (isOnParticipatingView({ route: { name } })) {
    conversationType = wootConstants.CONVERSATION_TYPE.PARTICIPATING;
  } else if (isOnUnattendedView({ route: { name } })) {
    conversationType = wootConstants.CONVERSATION_TYPE.UNATTENDED;
  }
  router.push(
    conversationListPageURL({
      accountId: routeAccountId ?? accountId,
      conversationType,
      customViewId: isOnFoldersView({ route: { name } }) ? folderId : undefined,
      inboxId,
      label,
      teamId,
    })
  );
};

// Conversa sob enforcement Connecta: os mesmos sinais que a
// lista/transferência já usam — metadado em cache da lista; fora do cache, o
// endpoint de escopo (200 = tem escopo legível, inclusive `closed`, que
// continua legível; 404 = sem escopo ou sem acesso).
export const isConnectaScopedConversation = async (store, conversationId) => {
  const cached = store.getters['connectaMetadata/getMetadata'];
  if (typeof cached === 'function' && cached(conversationId)) return true;

  try {
    await conversationAPI.showConnectaScope(conversationId);
    return true;
  } catch (_) {
    return false;
  }
};

// Pós-resolve bem-sucedido com status RESOLVED: fora de escopo Connecta nada
// muda; com escopo, remove a conversa da lista/store (só local) e, se era a
// conversa aberta, volta para a lista. Best-effort: nunca rejeita.
export const leaveConnectaConversationAfterResolve = async ({
  store,
  router,
  route,
  accountId,
  conversationId,
  connectaEnabled,
  isOpenConversation,
}) => {
  if (!connectaEnabled) return false;

  const scoped = await isConnectaScopedConversation(store, conversationId);
  if (!scoped) return false;

  try {
    store.commit(types.REVOKE_CONNECTA_SCOPE, {
      conversation_id: conversationId,
    });
    store.dispatch('connectaMetadata/invalidate', conversationId);
    emitter.emit('fetch_conversation_stats');
    if (isOpenConversation) {
      navigateToConversationList(router, route, accountId);
    }
    return true;
  } catch (_) {
    return false;
  }
};
