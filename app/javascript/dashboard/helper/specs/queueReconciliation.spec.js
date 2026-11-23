// Feature-scoped queue reconciliation: inbound while Bot is not selected,
// event during load with trailing refresh (guard level), Bot-to-human moves on
// assignment/status, reconnect, out-of-order/account isolation and pagination.
import axios from 'axios';
import ActionCableConnector from '../actionCable';
import ReconnectService from '../ReconnectService';
import { emitter } from 'shared/helpers/mitt';
import { actions as statsActions } from '../../store/modules/conversationStats';
import { mutations as conversationMutations } from '../../store/modules/conversations/index';
import types from '../../store/mutation-types';

vi.mock('shared/helpers/mitt', () => ({
  emitter: {
    on: vi.fn(),
    off: vi.fn(),
    emit: vi.fn(),
  },
}));

vi.mock('dashboard/composables/useImpersonation', () => ({
  useImpersonation: () => ({
    isImpersonating: { value: false },
  }),
}));

vi.mock(
  'dashboard/helper/AudioAlerts/DashboardAudioNotificationHelper',
  () => ({
    default: { onNewMessage: vi.fn() },
  })
);

vi.mock('date-fns', () => ({
  differenceInSeconds: vi.fn(() => 0),
}));

vi.mock('dashboard/helper/routeHelpers', () => ({
  isAConversationRoute: vi.fn(() => false),
  isAInboxViewRoute: vi.fn(() => false),
}));

global.axios = axios;
vi.mock('axios');
vi.mock('@chatwoot/utils', () => ({
  debounce: vi.fn(fn => fn),
}));

global.chatwootConfig = { websocketURL: 'wss://test.chatwoot.com' };

const cableStore = () => {
  const dispatch = vi.fn();
  return {
    $store: {
      dispatch,
      getters: {
        getCurrentAccountId: 1,
        getCurrentUserID: 7,
        getCurrentUser: { id: 7 },
        'accounts/isFeatureEnabledonAccount': vi.fn(() => false),
      },
    },
    dispatch,
  };
};

describe('#queueReconciliation cable signals', () => {
  let actionCable;
  let store;

  beforeEach(() => {
    vi.clearAllMocks();
    store = cableStore();
    actionCable = ActionCableConnector.init(store.$store, 'test-token');
  });

  it('inbound message reconciles queues even with another tab selected', () => {
    actionCable.onMessageCreated({
      account_id: 1,
      conversation_id: 11,
      conversation: { last_activity_at: 123 },
    });
    expect(store.dispatch).toHaveBeenCalledWith(
      'addMessage',
      expect.objectContaining({ conversation_id: 11 })
    );
    expect(emitter.emit).toHaveBeenCalledWith('fetch_conversation_stats');
  });

  it.each([
    ['onConversationCreated'],
    ['onStatusChange'],
    ['onConversationUpdated'],
  ])('%s reconciles queues', handler => {
    actionCable[handler]({ id: 5, account_id: 1 });
    expect(emitter.emit).toHaveBeenCalledWith('fetch_conversation_stats');
  });

  it('assignment reconciles queues (Bot to human handoff)', () => {
    actionCable.onAssigneeChanged({
      id: 9,
      account_id: 1,
      meta: { assignee: { id: 7 } },
    });
    expect(store.dispatch).toHaveBeenCalledWith(
      'updateConversation',
      expect.objectContaining({ id: 9 })
    );
    expect(emitter.emit).toHaveBeenCalledWith('fetch_conversation_stats');
  });
});

describe('#queueReconciliation stats guards', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  const flush = async (rounds = 5) => {
    for (let i = 0; i < rounds; i += 1) {
      // eslint-disable-next-line no-await-in-loop
      await Promise.resolve();
    }
  };

  it('drops an older answer that arrives after a newer signal', async () => {
    const resolvers = [];
    axios.get.mockImplementation(
      () => new Promise(resolve => {
        resolvers.push(resolve);
      })
    );
    const commit = vi.fn();
    const rootGetters = { getCurrentAccountId: 1 };
    statsActions.get(
      { commit, state: { allCount: 1 }, rootGetters },
      { status: 'open' }
    );
    statsActions.get(
      { commit, state: { allCount: 1 }, rootGetters },
      { status: 'open' }
    );
    resolvers[1]({ data: { meta: { mine_count: 2 } } });
    await flush();
    resolvers[0]({ data: { meta: { mine_count: 1 } } });
    await flush();
    expect(commit).toHaveBeenCalledTimes(1);
    expect(commit).toHaveBeenCalledWith(types.default.SET_CONV_TAB_META, {
      mine_count: 2,
    });
  });

  it('drops an answer that returns after an account switch', async () => {
    let resolveMeta;
    axios.get.mockImplementation(
      () => new Promise(resolve => {
        resolveMeta = resolve;
      })
    );
    const commit = vi.fn();
    const rootGetters = { getCurrentAccountId: 1 };
    statsActions.get(
      { commit, state: { allCount: 1 }, rootGetters },
      { status: 'open' }
    );
    rootGetters.getCurrentAccountId = 2;
    resolveMeta({ data: { meta: { mine_count: 9 } } });
    await flush();
    expect(commit).not.toHaveBeenCalled();
  });

  it('refreshes human badges and the Bot badge in the same burst', async () => {
    axios.get.mockImplementation(() =>
      Promise.resolve({
        data: {
          meta: {
            mine_count: 1,
            unassigned_count: 1,
            all_count: 2,
          },
        },
      })
    );
    const commit = vi.fn();
    const rootGetters = { getCurrentAccountId: 1 };
    statsActions.get(
      { commit, state: { allCount: 1 }, rootGetters },
      { status: 'open' }
    );
    statsActions.get(
      { commit, state: { allCount: 1 }, rootGetters },
      { status: 'open', conversationType: 'bot' }
    );
    await flush(10);
    expect(commit).toHaveBeenCalledWith(types.default.SET_CONV_TAB_META, {
      mine_count: 1,
      unassigned_count: 1,
      all_count: 2,
    });
    expect(commit).toHaveBeenCalledWith(types.default.SET_BOT_TAB_META, {
      count: 2,
    });
  });
});

describe('#queueReconciliation Bot membership', () => {
  it('removal drops Bot ids so older pages cannot reintroduce the row', () => {
    const state = {
      allConversations: [{ id: 1 }, { id: 2 }, { id: 3 }],
      botConversationIds: [1, 2, 3],
    };
    conversationMutations[types.REMOVE_CONVERSATIONS](state, [1, 3]);
    expect(state.allConversations).toEqual([{ id: 2 }]);
    expect(state.botConversationIds).toEqual([2]);
  });

  it('page 1 replaces Bot membership while later pages union without duplicates', () => {
    const state = { botConversationIds: [1, 2] };
    conversationMutations[types.SET_BOT_CONVERSATIONS](
      state,
      { ids: [2, 3], page: 1 }
    );
    expect(state.botConversationIds).toEqual([2, 3]);
    conversationMutations[types.SET_BOT_CONVERSATIONS](
      state,
      { ids: [3, 4], page: 2 }
    );
    expect(state.botConversationIds).toEqual([2, 3, 4]);
  });
});

describe('#queueReconciliation reconnect', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    window.addEventListener = vi.fn();
  });

  const serviceWithFilters = filters => {
    const store = {
      dispatch: vi.fn(async () => {}),
      getters: { getChatListFilters: filters },
    };
    const router = { currentRoute: { value: { name: '', params: {} } } };
    return { store, service: new ReconnectService(store, router) };
  };

  it('refetches Bot page 1 and badges on reconnect while Bot is selected', async () => {
    const filters = { conversationType: 'bot', status: 'open' };
    const { store, service } = serviceWithFilters(filters);
    await service.fetchConversations();
    expect(store.dispatch).toHaveBeenCalledWith('fetchBotConversations', {
      ...filters,
      page: 1,
    });
    expect(store.dispatch).not.toHaveBeenCalledWith('fetchAllConversations');
    expect(emitter.emit).toHaveBeenCalledWith('fetch_conversation_stats');
  });

  it('keeps the human refetch and adds badges on reconnect', async () => {
    const filters = { assigneeType: 'me', status: 'open' };
    const { store, service } = serviceWithFilters(filters);
    await service.fetchConversations();
    expect(store.dispatch).toHaveBeenCalledWith('fetchAllConversations');
    expect(store.dispatch).not.toHaveBeenCalledWith(
      'fetchBotConversations',
      expect.anything()
    );
    expect(emitter.emit).toHaveBeenCalledWith('fetch_conversation_stats');
  });
});
