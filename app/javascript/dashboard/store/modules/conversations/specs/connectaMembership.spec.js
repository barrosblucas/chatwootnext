import { mutations } from '../index';
import getters from '../getters';
import types from '../../../mutation-types';

// Server membership for the Connecta human tabs: the client predicates
// cannot reproduce Aguardando/Todos, so each tab keeps its own ids and the
// list renders exactly what the tab's completed request returned.
const rows = [
  { id: 11, status: 'open', inbox_id: 4, meta: {}, labels: [] },
  { id: 12, status: 'open', inbox_id: 4, meta: {}, labels: [] },
  { id: 13, status: 'resolved', inbox_id: 4, meta: {}, labels: [] },
];

const rootGetters = {
  getCurrentUser: { id: 7, accounts: [{ id: 1, role: 'agent' }] },
  getCurrentAccountId: 1,
};

describe('Connecta tab membership', () => {
  describe('#SET_CONNECTA_TAB_CONVERSATIONS', () => {
    it('replaces ids on page 1 and unions later pages per tab', () => {
      const state = {
        connectaTabConversationIds: { minhas: [1], aguardando: [], todos: [] },
      };
      mutations[types.SET_CONNECTA_TAB_CONVERSATIONS](state, {
        tab: 'aguardando',
        ids: [11, 12],
        page: 1,
      });
      expect(state.connectaTabConversationIds.aguardando).toEqual([11, 12]);
      mutations[types.SET_CONNECTA_TAB_CONVERSATIONS](state, {
        tab: 'aguardando',
        ids: [12, 13],
        page: 2,
      });
      expect(state.connectaTabConversationIds.aguardando).toEqual([11, 12, 13]);
      expect(state.connectaTabConversationIds.minhas).toEqual([1]);
    });

    it('ignores unknown tabs so no other membership is polluted', () => {
      const state = {
        connectaTabConversationIds: { minhas: [], aguardando: [], todos: [] },
      };
      mutations[types.SET_CONNECTA_TAB_CONVERSATIONS](state, {
        tab: 'bot',
        ids: [11],
        page: 1,
      });
      expect(state.connectaTabConversationIds).toEqual({
        minhas: [],
        aguardando: [],
        todos: [],
      });
    });

    it('clears membership with the cache', () => {
      const state = {
        allConversations: rows,
        selectedChatId: 11,
        botConversationIds: [5],
        botListStatus: 'ready',
        connectaTabConversationIds: {
          minhas: [11],
          aguardando: [12],
          todos: [13],
        },
      };
      mutations[types.EMPTY_ALL_CONVERSATION](state);
      expect(state.connectaTabConversationIds).toEqual({
        minhas: [],
        aguardando: [],
        todos: [],
      });
    });
  });

  describe('#getConnectaTabChats', () => {
    it('lists exactly the tab membership narrowed by the page filters', () => {
      const state = {
        allConversations: rows,
        chatSortFilter: '',
        connectaTabConversationIds: { aguardando: [11, 12, 13] },
      };
      const chats = getters.getConnectaTabChats(
        state,
        {},
        {},
        rootGetters
      )('aguardando', { status: 'open' });
      expect(chats.map(chat => chat.id).sort()).toEqual([11, 12]);
    });

    it('never leaks another tab membership', () => {
      const state = {
        allConversations: rows,
        chatSortFilter: '',
        connectaTabConversationIds: { minhas: [11], aguardando: [12] },
      };
      const mine = getters.getConnectaTabChats(
        state,
        {},
        {},
        rootGetters
      )('minhas', { status: 'open' });
      expect(mine.map(chat => chat.id)).toEqual([11]);
    });
  });
});
