import axios from 'axios';
import actions from '../../conversations/actions';
import getters from '../../conversations/getters';
import { mutations } from '../../conversations/index';
import types from '../../../mutation-types';

vi.mock('axios');

const rows = [
  { id: 11, inbox_id: 7, status: 'open', meta: {} },
  { id: 12, inbox_id: 7, status: 'open', meta: { assignee: { id: 2 } } },
  { id: 13, inbox_id: 7, status: 'open', meta: { assignee: { id: 1 } } },
  { id: 14, inbox_id: 9, status: 'resolved', meta: {} },
];

const rootGetters = {
  getCurrentUser: { id: 1, accounts: [{ id: 1, role: 'agent' }] },
  getCurrentAccountId: 1,
};

describe('#Bot tab store', () => {
  describe('#getBotChats', () => {
    it('returns only server-confirmed ids with no client assignee predicate', () => {
      const state = {
        allConversations: rows,
        botConversationIds: [11, 12, 13],
      };
      const result = getters.getBotChats(
        state,
        {},
        {},
        rootGetters
      )({ status: 'open' });
      // 12 is assigned to someone else and 13 to me: both stay, because the
      // server is the authority on Bot membership.
      expect(result.map(c => c.id).sort()).toEqual([11, 12, 13]);
    });

    it('drops rows no longer confirmed and applies page filters', () => {
      const state = {
        allConversations: rows,
        botConversationIds: [11, 14],
      };
      const result = getters.getBotChats(
        state,
        {},
        {},
        rootGetters
      )({ status: 'open' });
      expect(result.map(c => c.id)).toEqual([11]);
    });

    it('returns an empty list when nothing was confirmed', () => {
      const state = { allConversations: rows, botConversationIds: [] };
      expect(
        getters.getBotChats(state, {}, {}, rootGetters)({ status: 'open' })
      ).toEqual([]);
    });
  });

  describe('#bot mutations', () => {
    it('replaces membership on page 1 and unions on later pages', () => {
      const state = { botConversationIds: [11], botListStatus: 'idle' };
      mutations[types.SET_BOT_CONVERSATIONS](state, { ids: [12], page: 1 });
      expect(state.botConversationIds).toEqual([12]);
      mutations[types.SET_BOT_CONVERSATIONS](state, { ids: [12, 13], page: 2 });
      expect(state.botConversationIds).toEqual([12, 13]);
    });

    it('tracks the tab status and clears it with the cache', () => {
      const state = {
        allConversations: [{ id: 1 }],
        selectedChatId: 1,
        botConversationIds: [1],
        botListStatus: 'ready',
      };
      mutations[types.SET_BOT_LIST_STATUS](state, 'loading');
      expect(state.botListStatus).toBe('loading');
      mutations[types.EMPTY_ALL_CONVERSATION](state);
      expect(state.botConversationIds).toEqual([]);
      expect(state.botListStatus).toBe('idle');
    });
  });

  describe('#fetchBotConversations', () => {
    let commit;
    let dispatch;

    beforeEach(() => {
      commit = vi.fn();
      dispatch = vi.fn();
      vi.clearAllMocks();
    });

    const okResponse = {
      data: {
        data: {
          payload: [rows[0]],
          meta: { mine_count: 0, unassigned_count: 1, all_count: 1 },
        },
      },
    };

    it('commits rows, badge count and ready status on success', async () => {
      axios.get.mockResolvedValue(okResponse);
      await actions.fetchBotConversations({ commit, dispatch }, { page: 1 });
      expect(commit).toHaveBeenCalledWith(types.SET_LIST_LOADING_STATUS);
      expect(commit).toHaveBeenCalledWith(types.SET_BOT_CONVERSATIONS, {
        ids: [11],
        page: 1,
      });
      expect(commit).toHaveBeenCalledWith(types.SET_BOT_LIST_STATUS, 'ready');
      expect(dispatch).toHaveBeenCalledWith(
        'conversationStats/setBotMeta',
        { count: 1 },
        { root: true }
      );
      // Shared human badges are never written from a Bot answer.
      expect(dispatch).not.toHaveBeenCalledWith(
        'conversationStats/set',
        expect.anything()
      );
    });

    it('marks empty instead of unavailable on a genuine empty tab', async () => {
      axios.get.mockResolvedValue({
        data: { data: { payload: [], meta: { all_count: 0 } } },
      });
      await actions.fetchBotConversations({ commit, dispatch }, { page: 1 });
      expect(commit).toHaveBeenCalledWith(types.SET_BOT_LIST_STATUS, 'empty');
    });

    it('marks unavailable on 503 and keeps the previous list untouched', async () => {
      axios.get.mockRejectedValue({ response: { status: 503 } });
      await actions.fetchBotConversations({ commit, dispatch }, { page: 1 });
      expect(commit).toHaveBeenCalledWith(
        types.SET_BOT_LIST_STATUS,
        'unavailable'
      );
      expect(commit).not.toHaveBeenCalledWith(
        types.SET_BOT_CONVERSATIONS,
        expect.anything()
      );
    });

    it('marks a plain error on non-503 failures', async () => {
      axios.get.mockRejectedValue({ response: { status: 500 } });
      await actions.fetchBotConversations({ commit, dispatch }, { page: 1 });
      expect(commit).toHaveBeenCalledWith(types.SET_BOT_LIST_STATUS, 'error');
    });

    it('drops a stale answer that arrives after a newer Bot request', async () => {
      let resolveFirst;
      axios.get.mockImplementationOnce(
        () => new Promise(resolve => (resolveFirst = resolve))
      );
      const first = actions.fetchBotConversations(
        { commit, dispatch },
        { page: 1 }
      );
      axios.get.mockResolvedValueOnce(okResponse);
      await actions.fetchBotConversations({ commit, dispatch }, { page: 1 });
      resolveFirst(okResponse);
      await first;
      const membershipCommits = commit.mock.calls.filter(
        ([type]) => type === types.SET_BOT_CONVERSATIONS
      );
      expect(membershipCommits).toHaveLength(1);
    });
  });
});
