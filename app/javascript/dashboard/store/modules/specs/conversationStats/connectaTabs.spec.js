import axios from 'axios';
import { actions, mutations } from '../../conversationStats';
import types from '../../../mutation-types';

global.axios = axios;
vi.mock('axios');
vi.mock('@chatwoot/utils', () => ({
  debounce: vi.fn(fn => fn),
}));

// Connecta dashboard badges: exact per-tab `all_count` totals on their own
// slots. A failure or a pending load stays unknown (null), never a fake
// zero; only a successful zero shows 0. Synthetic fixtures only.
const CONNECTA = params => ({
  ...params,
  connectaDashboard: 'true',
  connectaTab: 'aguardando',
});

describe('#conversationStats Connecta tabs', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  describe('#get routes each tab to its own slot', () => {
    it('commits the exact total of the requested tab only', async () => {
      const commit = vi.fn();
      axios.get.mockResolvedValue({ data: { meta: { all_count: 4 } } });
      actions.get(
        { commit, state: { allCount: 0 }, rootGetters: {} },
        CONNECTA({ status: 'open', inboxId: 1 })
      );
      await vi.waitFor(() => {
        expect(commit).toHaveBeenCalledWith(types.SET_CONNECTA_TAB_META, {
          tab: 'aguardando',
          count: 4,
          accountId: undefined,
          botClassificationUnavailable: undefined,
        });
      });
      expect(commit).not.toHaveBeenCalledWith(
        types.SET_CONV_TAB_META,
        expect.anything()
      );
    });

    it('keeps Bot answers off the human slots', async () => {
      const commit = vi.fn();
      axios.get.mockResolvedValue({ data: { meta: { all_count: 2 } } });
      actions.get(
        { commit, state: { allCount: 0 }, rootGetters: {} },
        {
          status: 'open',
          connectaDashboard: 'true',
          connectaTab: 'bot',
        }
      );
      await vi.waitFor(() => {
        expect(commit).toHaveBeenCalledWith(
          types.SET_CONNECTA_TAB_META,
          expect.objectContaining({ tab: 'bot', count: 2 })
        );
      });
      expect(commit).not.toHaveBeenCalledWith(
        types.SET_BOT_TAB_META,
        expect.anything()
      );
    });

    it('marks the tab on failure instead of faking zero', async () => {
      const commit = vi.fn();
      axios.get.mockRejectedValue(new Error('offline'));
      actions.get(
        { commit, state: { allCount: 0 }, rootGetters: {} },
        CONNECTA({ status: 'open' })
      );
      await vi.waitFor(() => {
        expect(commit).toHaveBeenCalledWith(types.SET_CONNECTA_TAB_ERROR, {
          tab: 'aguardando',
          accountId: undefined,
        });
      });
    });

    it('drops a stale same-tab answer after a fast tab switch', async () => {
      const commit = vi.fn();
      let resolveFirst;
      axios.get.mockImplementationOnce(
        () =>
          new Promise(resolve => {
            resolveFirst = () => resolve({ data: { meta: { all_count: 9 } } });
          })
      );
      const params = CONNECTA({ status: 'open' });
      actions.get({ commit, state: { allCount: 0 }, rootGetters: {} }, params);
      // A newer request for the same tab supersedes the in-flight one.
      axios.get.mockResolvedValueOnce({ data: { meta: { all_count: 1 } } });
      actions.get({ commit, state: { allCount: 0 }, rootGetters: {} }, params);
      resolveFirst();
      await vi.waitFor(() => {
        expect(commit).toHaveBeenCalledWith(
          types.SET_CONNECTA_TAB_META,
          expect.objectContaining({ tab: 'aguardando', count: 1 })
        );
      });
      expect(commit).not.toHaveBeenCalledWith(
        types.SET_CONNECTA_TAB_META,
        expect.objectContaining({ count: 9 })
      );
    });

    it('keeps a sibling tab answer when another tab refetches', async () => {
      const commit = vi.fn();
      let resolveAguardando;
      axios.get.mockImplementationOnce(
        () =>
          new Promise(resolve => {
            resolveAguardando = () =>
              resolve({ data: { meta: { all_count: 5 } } });
          })
      );
      actions.get(
        { commit, state: { allCount: 0 }, rootGetters: {} },
        CONNECTA({ status: 'open' })
      );
      axios.get.mockResolvedValueOnce({ data: { meta: { all_count: 6 } } });
      actions.get(
        { commit, state: { allCount: 0 }, rootGetters: {} },
        { status: 'open', connectaDashboard: 'true', connectaTab: 'minhas' }
      );
      resolveAguardando();
      await vi.waitFor(() => {
        expect(commit).toHaveBeenCalledWith(
          types.SET_CONNECTA_TAB_META,
          expect.objectContaining({ tab: 'minhas', count: 6 })
        );
      });
      expect(commit).toHaveBeenCalledWith(
        types.SET_CONNECTA_TAB_META,
        expect.objectContaining({ tab: 'aguardando', count: 5 })
      );
    });

    it('drops an answer that returns after an account switch', async () => {
      const commit = vi.fn();
      let resolveLate;
      const rootGetters = { getCurrentAccountId: 1 };
      axios.get.mockImplementationOnce(
        () =>
          new Promise(resolve => {
            resolveLate = () => resolve({ data: { meta: { all_count: 8 } } });
          })
      );
      actions.get(
        { commit, state: { allCount: 0 }, rootGetters },
        CONNECTA({ status: 'open' })
      );
      rootGetters.getCurrentAccountId = 2;
      resolveLate();
      await new Promise(setImmediate);
      expect(commit).not.toHaveBeenCalled();
    });

    it('leaves the native path untouched', async () => {
      const commit = vi.fn();
      axios.get.mockResolvedValue({
        data: { meta: { mine_count: 1, unassigned_count: 2, all_count: 3 } },
      });
      actions.get(
        { commit, state: { allCount: 1 }, rootGetters: {} },
        { status: 'open', assigneeType: 'me' }
      );
      await vi.waitFor(() => {
        expect(commit).toHaveBeenCalledWith(types.SET_CONV_TAB_META, {
          mine_count: 1,
          unassigned_count: 2,
          all_count: 3,
        });
      });
      expect(commit).not.toHaveBeenCalledWith(
        types.SET_CONNECTA_TAB_META,
        expect.anything()
      );
    });
  });

  describe('#setConnectaTab', () => {
    it('commits exact totals and flags errors without touching zero', () => {
      const commit = vi.fn();
      actions.setConnectaTab(
        { commit },
        { tab: 'todos', count: 0, accountId: 1 }
      );
      expect(commit).toHaveBeenCalledWith(types.SET_CONNECTA_TAB_META, {
        tab: 'todos',
        count: 0,
        accountId: 1,
      });
      actions.setConnectaTab({ commit }, { tab: 'todos', count: null });
      expect(commit).toHaveBeenCalledWith(types.SET_CONNECTA_TAB_ERROR, {
        tab: 'todos',
        accountId: undefined,
      });
      actions.setConnectaTab({ commit }, { tab: 'nope', count: 3 });
      expect(
        commit.mock.calls.filter(([type]) =>
          [types.SET_CONNECTA_TAB_META, types.SET_CONNECTA_TAB_ERROR].includes(
            type
          )
        )
      ).toHaveLength(2);
    });
  });

  describe('#SET_CONNECTA_TAB_META / #SET_CONNECTA_TAB_ERROR', () => {
    const fresh = () => ({
      connectaCounts: {
        minhas: null,
        aguardando: null,
        todos: null,
        bot: null,
      },
      connectaErrors: {
        minhas: false,
        aguardando: false,
        todos: false,
        bot: false,
      },
      connectaAccountId: 1,
      botClassificationUnavailable: null,
    });

    it('writes only the requested slot and clears its error', () => {
      const state = fresh();
      mutations[types.SET_CONNECTA_TAB_META](state, {
        tab: 'aguardando',
        count: 4,
        accountId: 1,
      });
      expect(state.connectaCounts).toEqual({
        minhas: null,
        aguardando: 4,
        todos: null,
        bot: null,
      });
      expect(state.connectaErrors.aguardando).toBe(false);
    });

    it('keeps the slot unknown on error instead of zeroing it', () => {
      const state = {
        ...fresh(),
        connectaCounts: { ...fresh().connectaCounts, aguardando: 4 },
      };
      mutations[types.SET_CONNECTA_TAB_ERROR](state, {
        tab: 'aguardando',
        accountId: 1,
      });
      expect(state.connectaCounts.aguardando).toBe(4);
      expect(state.connectaErrors.aguardando).toBe(true);
      const unknown = fresh();
      mutations[types.SET_CONNECTA_TAB_ERROR](unknown, {
        tab: 'minhas',
        accountId: 1,
      });
      expect(unknown.connectaCounts.minhas).toBe(null);
    });

    it('resets every slot on an account switch', () => {
      const state = {
        ...fresh(),
        connectaCounts: { ...fresh().connectaCounts, aguardando: 4 },
      };
      mutations[types.SET_CONNECTA_TAB_META](state, {
        tab: 'minhas',
        count: 1,
        accountId: 2,
      });
      expect(state.connectaCounts).toEqual({
        minhas: 1,
        aguardando: null,
        todos: null,
        bot: null,
      });
      expect(state.connectaAccountId).toBe(2);
    });

    it('preserves the Bot classification state per contract', () => {
      const state = fresh();
      mutations[types.SET_CONNECTA_TAB_META](state, {
        tab: 'minhas',
        count: 1,
        accountId: 1,
        botClassificationUnavailable: true,
      });
      expect(state.botClassificationUnavailable).toBe(true);
      mutations[types.SET_CONNECTA_TAB_META](state, {
        tab: 'minhas',
        count: 2,
        accountId: 1,
        botClassificationUnavailable: undefined,
      });
      expect(state.botClassificationUnavailable).toBe(true);
    });
  });
});
