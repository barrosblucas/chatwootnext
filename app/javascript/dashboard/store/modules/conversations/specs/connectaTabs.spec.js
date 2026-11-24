import actions from '../actions';
import types from '../../../mutation-types';
import ConversationApi from '../../../../api/inbox/conversation';
import { buildConversationList } from '../helpers/actionHelpers';

// Connecta dashboard list wiring: the list answer sets the active tab's
// exact total and server membership without touching the native triple, and
// reconciliation reads the tab's own membership. Synthetic fixtures only.

vi.mock('../../../../api/inbox/conversation', () => ({
  default: { get: vi.fn(), sync: vi.fn() },
}));

vi.mock('../helpers/actionHelpers', async importOriginal => {
  const original = await importOriginal();
  return {
    ...original,
    buildConversationList: vi.fn(),
  };
});

const connectaFilters = (tab = 'aguardando', extra = {}) => ({
  status: 'open',
  inboxId: 4,
  page: 1,
  connectaDashboard: 'true',
  connectaTab: tab,
  ...extra,
});

describe('conversations actions Connecta tabs', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  describe('fetchAllConversations', () => {
    it('sets the active tab total and membership from the exact answer', async () => {
      ConversationApi.get.mockResolvedValue({
        data: {
          data: {
            meta: { all_count: 4 },
            payload: [{ id: 11 }, { id: 12 }],
          },
        },
      });
      const commit = vi.fn();
      const dispatch = vi.fn();
      await actions.fetchAllConversations({
        commit,
        state: { conversationFilters: connectaFilters() },
        dispatch,
        rootGetters: { getCurrentAccountId: 1 },
      });
      expect(ConversationApi.get).toHaveBeenCalledWith(
        expect.objectContaining({
          connectaDashboard: 'true',
          connectaTab: 'aguardando',
        })
      );
      expect(buildConversationList).toHaveBeenCalledWith(
        expect.anything(),
        expect.anything(),
        expect.anything(),
        'unassigned',
        { skipStatsUpdate: true }
      );
      expect(dispatch).toHaveBeenCalledWith(
        'conversationStats/setConnectaTab',
        { tab: 'aguardando', count: 4, accountId: 1 },
        { root: true }
      );
      expect(commit).toHaveBeenCalledWith(
        types.SET_CONNECTA_TAB_CONVERSATIONS,
        { tab: 'aguardando', ids: [11, 12], page: 1 }
      );
      expect(dispatch).not.toHaveBeenCalledWith(
        'conversationStats/set',
        expect.anything()
      );
    });

    it('marks the tab on list failure instead of faking zero', async () => {
      ConversationApi.get.mockRejectedValue(new Error('offline'));
      const commit = vi.fn();
      const dispatch = vi.fn();
      await actions.fetchAllConversations({
        commit,
        state: { conversationFilters: connectaFilters() },
        dispatch,
        rootGetters: { getCurrentAccountId: 1 },
      });
      expect(dispatch).toHaveBeenCalledWith(
        'conversationStats/setConnectaTabError',
        { tab: 'aguardando', accountId: 1 },
        { root: true }
      );
      expect(commit).not.toHaveBeenCalledWith(
        types.SET_CONNECTA_TAB_CONVERSATIONS,
        expect.anything()
      );
    });

    it('keeps the native list path untouched', async () => {
      ConversationApi.get.mockResolvedValue({
        data: { data: { meta: { all_count: 3 }, payload: [{ id: 1 }] } },
      });
      const commit = vi.fn();
      const dispatch = vi.fn();
      await actions.fetchAllConversations({
        commit,
        state: { conversationFilters: { status: 'open', assigneeType: 'me' } },
        dispatch,
        rootGetters: {},
      });
      expect(buildConversationList).toHaveBeenCalledWith(
        expect.anything(),
        expect.anything(),
        expect.anything(),
        'me'
      );
      expect(dispatch).not.toHaveBeenCalledWith(
        expect.stringContaining('setConnectaTab'),
        expect.anything()
      );
    });
  });

  describe('fetchBotConversations', () => {
    it('feeds the Connecta bot slot from the same exact answer', async () => {
      ConversationApi.get.mockResolvedValue({
        data: { data: { meta: { all_count: 2 }, payload: [{ id: 5 }] } },
      });
      const commit = vi.fn();
      const dispatch = vi.fn();
      await actions.fetchBotConversations(
        { commit, dispatch, rootGetters: { getCurrentAccountId: 1 } },
        connectaFilters('bot')
      );
      expect(dispatch).toHaveBeenCalledWith(
        'conversationStats/setBotMeta',
        { count: 2 },
        { root: true }
      );
      expect(dispatch).toHaveBeenCalledWith(
        'conversationStats/setConnectaTab',
        { tab: 'bot', count: 2, accountId: 1 },
        { root: true }
      );
      expect(commit).toHaveBeenCalledWith(types.SET_BOT_LIST_STATUS, 'empty');
    });

    it('keeps the 503 unavailable state with retry and marks the badge', async () => {
      ConversationApi.get.mockRejectedValue({ response: { status: 503 } });
      const commit = vi.fn();
      const dispatch = vi.fn();
      await actions.fetchBotConversations(
        { commit, dispatch, rootGetters: { getCurrentAccountId: 1 } },
        connectaFilters('bot')
      );
      expect(commit).toHaveBeenCalledWith(
        types.SET_BOT_LIST_STATUS,
        'unavailable'
      );
      expect(dispatch).toHaveBeenCalledWith(
        'conversationStats/setConnectaTabError',
        { tab: 'bot', accountId: 1 },
        { root: true }
      );
    });
  });

  describe('reconcileConversationTab', () => {
    it('reads Connecta human tabs from their own server membership', async () => {
      const rows = [{ id: 11, inbox_id: 4 }];
      ConversationApi.sync.mockResolvedValue({
        data: { payload: rows },
      });
      const commit = vi.fn();
      const getters = {
        getConnectaTabChats: vi.fn(() => rows),
        getConversationById: () => undefined,
      };
      const removed = await actions.reconcileConversationTab(
        { commit, getters, state: {} },
        connectaFilters()
      );
      expect(getters.getConnectaTabChats).toHaveBeenCalledWith(
        'aguardando',
        expect.objectContaining({ connectaTab: 'aguardando' })
      );
      expect(ConversationApi.sync).toHaveBeenCalledWith([11]);
      expect(removed).toEqual([]);
      expect(commit).not.toHaveBeenCalledWith(
        types.REMOVE_CONVERSATIONS,
        expect.anything()
      );
    });
  });
});
