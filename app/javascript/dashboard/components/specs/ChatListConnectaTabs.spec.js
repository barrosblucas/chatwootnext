import { nextTick } from 'vue';
import { createStore } from 'vuex';
import { flushPromises, shallowMount } from '@vue/test-utils';
import { beforeEach, describe, expect, it, vi, afterEach } from 'vitest';
import ChatList from '../ChatList.vue';
import ChatTypeTabs from '../widgets/ChatTypeTabs.vue';
import ConnectaAPI from 'dashboard/api/connecta';

// The sector catalog is hermetic here: an empty catalog hides the filter and
// the aggregate assertions below stay on the no-selection contract.
vi.mock('dashboard/api/connecta', () => ({
  default: { getOrgUnits: vi.fn() },
}));

// Connecta dashboard wiring (Correcao 02): the list and every visible badge
// ask the shared opt-in contract with identical active filters, hidden tabs
// are never asked for, and an unknown badge renders blank instead of a fake
// zero. A real Vuex store carries fake state; router, i18n and window config
// are faked. No real conversation data and no network.

vi.mock('vue-router', () => ({
  useRoute: () => ({ name: 'home', params: { accountId: '1' } }),
  useRouter: () => ({ push: vi.fn() }),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
  useAssignmentError: vi.fn(),
  useTrack: vi.fn(),
}));

const ACTION_TYPES = [
  'setChatListFilters',
  'setChatStatusFilter',
  'setChatSortFilter',
  'setChatGroupTypeFilter',
  'conversationPage/reset',
  'emptyAllConversations',
  'clearConversationFilters',
  'updateChatListFilters',
  'fetchAllConversations',
  'fetchBotConversations',
  'connectaMetadata/setScope',
  'connectaMetadata/fetch',
  'conversationStats/get',
  'conversationStats/setBotMeta',
  'conversationStats/setConnectaTab',
  'conversationStats/setConnectaTabError',
  'reconcileConversationTab',
  'bulkActions/clearSelectedConversationIds',
  'bulkActions/setSelectedConversationIds',
  'bulkActions/removeSelectedConversationIds',
  'campaigns/get',
  'customViews/setActiveConversationFolder',
];

let state = null;
let dispatchCalls = [];
let store = null;
let wrapper = null;

const buildStore = () => {
  state = {
    role: 'agent',
    user: {
      id: 7,
      name: 'Attendant',
      accounts: [{ id: 1, role: 'agent', permissions: ['agent'] }],
    },
    loading: false,
    botStatus: 'empty',
    mineRows: [],
    botRows: [],
    pages: { me: 0, unassigned: 0, all: 0, bot: 0 },
    stats: {
      mineCount: 9,
      unAssignedCount: 9,
      allCount: 9,
      botCount: 9,
      botClassificationUnavailable: null,
      connectaCounts: { minhas: 2, aguardando: 3, todos: 5, bot: 1 },
      connectaErrors: {
        minhas: false,
        aguardando: false,
        todos: false,
        bot: false,
      },
      connectaAccountId: 1,
    },
  };
  dispatchCalls = [];
  store = createStore({
    state,
    getters: {
      getCurrentUser: s => s.user,
      getCurrentRole: s => s.role,
      getCurrentAccountId: () => 1,
      getCurrentUserID: () => 7,
      getUISettings: () => ({}),
      getFilteredConversations: () => [],
      getMineChats: () => () => [],
      getAllStatusChats: () => () => [],
      getUnAssignedChats: () => () => [],
      getBotChats: s => () => s.botRows,
      getConnectaTabChats: () => () => [],
      getParticipatingChats: () => () => [],
      getBotListStatus: s => s.botStatus,
      getChatListLoadingStatus: s => s.loading,
      'conversationPins/getRecords': () => ({}),
      getSelectedInbox: () => ({}),
      'conversationStats/getStats': s => s.stats,
      getAppliedConversationFiltersV2: () => [],
      'customViews/getConversationCustomViews': () => [],
      'customViews/getActiveFolderContactId': () => undefined,
      'agents/getAgents': () => [],
      'teams/getTeams': () => [],
      'inboxes/getInboxes': () => [],
      'inboxes/getInbox': () => () => ({}),
      'campaigns/getAllCampaigns': () => [],
      'labels/getLabels': () => [],
      'accounts/getAccount': () => () => ({ settings: {} }),
      'accounts/isFeatureEnabledonAccount': () => () => false,
      'teams/getTeam': () => () => ({}),
      getConversationById: () => () => undefined,
      'connectaMetadata/isChecked': () => () => false,
      'connectaMetadata/getEpoch': () => 0,
      'bulkActions/getSelectedConversationIds': () => [],
      'attributes/getConversationAttributes': () => [],
      'attributes/getAttributesByModel': () => [],
      'contacts/getContact': () => () => undefined,
      'conversationPage/getCurrentPageFilter': s => tab => s.pages[tab] ?? 0,
      'conversationPage/getHasEndReached': () => () => true,
      'globalConfig/isOnChatwootCloud': () => false,
      'globalConfig/isMetaInboxCreationDisabled': () => false,
      'globalConfig/isMetaMessageSendingDisabled': () => false,
    },
    actions: Object.fromEntries(
      ACTION_TYPES.map(type => [
        type,
        (_, payload) => {
          dispatchCalls.push([type, payload]);
          return Promise.resolve();
        },
      ])
    ),
  });
  state = store.state;
  return store;
};

const setRole = role => {
  state.role = role;
  state.user = {
    id: 7,
    name: 'Attendant',
    accounts: [{ id: 1, role, permissions: [role] }],
  };
};

const mountChatList = async (props = {}) => {
  wrapper = shallowMount(ChatList, {
    global: {
      plugins: [store],
      mocks: { $t: key => key },
    },
    props,
  });
  await flushPromises();
  await nextTick();
  return wrapper;
};

const payloads = action =>
  dispatchCalls
    .filter(([type]) => type === action)
    .map(([, payload]) => payload);
const tabCounts = () =>
  Object.fromEntries(
    wrapper
      .findComponent(ChatTypeTabs)
      .props('items')
      .map(item => [item.key, item])
  );

describe('ChatList Connecta dashboard tabs', () => {
  beforeEach(() => {
    window.chatwootConfig = {
      connectaHumanNumberEnabled: 'true',
      connectaTransferEnabled: 'false',
    };
    buildStore();
    ConnectaAPI.getOrgUnits.mockResolvedValue({ data: { org_units: [] } });
  });

  afterEach(() => {
    wrapper?.unmount();
    wrapper = null;
    delete window.chatwootConfig;
  });

  it('asks the list with the opt-in tab and the identical active filters', async () => {
    setRole('administrator');
    await mountChatList();

    const listPayload = payloads('updateChatListFilters').at(-1);
    expect(listPayload).toMatchObject({
      status: 'open',
      connectaDashboard: 'true',
      connectaTab: 'minhas',
    });
    expect(listPayload.assigneeType).toBeUndefined();
    expect(listPayload.conversationType).toBeUndefined();
    expect(listPayload.excludeActiveBot).toBeUndefined();
    expect(listPayload.connectaOrgUnitId).toBeUndefined();
  });

  it('fetches badges for every visible tab with the list filters (admin: four)', async () => {
    setRole('administrator');
    await mountChatList();

    const badges = payloads('conversationStats/get');
    expect(badges).toHaveLength(4);
    const byTab = Object.fromEntries(
      badges.map(payload => [payload.connectaTab, payload])
    );
    expect(Object.keys(byTab).sort()).toEqual([
      'aguardando',
      'bot',
      'minhas',
      'todos',
    ]);
    const listPayload = payloads('updateChatListFilters').at(-1);
    badges.forEach(badge => {
      expect(badge.connectaDashboard).toBe('true');
      expect(badge.status).toBe(listPayload.status);
      expect(badge.inboxId).toBe(listPayload.inboxId);
      expect(badge.teamId).toBe(listPayload.teamId);
      expect(badge.labels).toBe(listPayload.labels);
      expect(badge.page).toBeUndefined();
      expect(badge.sortBy).toBeUndefined();
    });
  });

  it('never requests hidden tabs for attendants (two badges, no Todos/Bot)', async () => {
    setRole('agent');
    await mountChatList();

    const badges = payloads('conversationStats/get');
    expect(badges).toHaveLength(2);
    expect(badges.map(payload => payload.connectaTab).sort()).toEqual([
      'aguardando',
      'minhas',
    ]);
  });

  it('shows Todos to a Connecta manager without showing Bot', async () => {
    ConnectaAPI.getOrgUnits.mockResolvedValue({
      data: { org_units: [], connecta_manager: true },
    });
    await mountChatList();

    expect(Object.keys(tabCounts())).toContain('all');
    expect(Object.keys(tabCounts())).not.toContain('bot');
  });

  it('shows exact successful totals and blank for unknown instead of fake zero', async () => {
    setRole('administrator');
    await mountChatList();

    const counts = tabCounts();
    expect(counts.me.count).toBe(2);
    expect(counts.unassigned.count).toBe(3);
    expect(counts.all.count).toBe(5);
    expect(counts.bot.count).toBe(1);

    state.stats.connectaCounts = {
      minhas: null,
      aguardando: 0,
      todos: null,
      bot: 1,
    };
    await nextTick();
    const after = tabCounts();
    expect(after.me.count).toBe(null);
    expect(after.unassigned.count).toBe(0);
    expect(after.all.count).toBe(null);
  });

  it('keeps native behavior outside the Connecta queue context', async () => {
    setRole('agent');
    await mountChatList({ conversationType: 'mention' });

    const listPayload = payloads('updateChatListFilters').at(-1);
    expect(listPayload.assigneeType).toBe('me');
    expect(listPayload.connectaDashboard).toBeUndefined();
    expect(listPayload.connectaTab).toBeUndefined();
    expect(payloads('conversationStats/get')).toHaveLength(0);
    const counts = tabCounts();
    // Legacy triple, untouched by the Connecta slots.
    expect(counts.me.count).toBe(9);
    expect(counts.unassigned.count).toBe(9);
  });
});
