import { nextTick } from 'vue';
import { createStore } from 'vuex';
import { flushPromises, shallowMount } from '@vue/test-utils';
import { beforeEach, describe, expect, it, vi, afterEach } from 'vitest';
import ChatList from '../ChatList.vue';
import ChatTypeTabs from '../widgets/ChatTypeTabs.vue';

// Focused regression specs for the Connecta queue-tab scope (Correcao 02):
// account administrators see Minhas/Aguardando/Todos/Bot, standard
// attendants see only Minhas/Aguardando, a stale admin-only selection falls
// back to Minhas without fetching the hidden tab, and the Bot empty message
// only represents the rendered Bot list. A real Vuex store carries fake
// state; router, i18n and window config are faked. No real conversation
// data and no network.

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
      mineCount: 2,
      unAssignedCount: 3,
      allCount: 5,
      botCount: 1,
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
      getMineChats: s => () => s.mineRows,
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
      'attributes/getAttributesByModel': () => () => [],
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
  // Mutate through the store's reactive proxy so computed tabs, the visible
  // list and the empty message converge; raw-object writes would bypass it.
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

const mountChatList = async () => {
  wrapper = shallowMount(ChatList, {
    global: {
      plugins: [store],
      mocks: { $t: key => key },
    },
  });
  await flushPromises();
  await nextTick();
  return wrapper;
};

const tabItems = () => wrapper.findComponent(ChatTypeTabs).props('items');
const tabKeys = () => tabItems().map(item => item.key);
const activeTab = () => wrapper.findComponent(ChatTypeTabs).props('activeTab');
const botEmptyVisible = () =>
  wrapper.findAll('p').some(p => p.text().includes('CHAT_LIST.BOT_LIST_EMPTY'));
const fetchCalls = action =>
  dispatchCalls.filter(([type]) => type === action).length;

describe('ChatList Connecta queue-tab scope', () => {
  beforeEach(() => {
    window.chatwootConfig = {
      connectaHumanNumberEnabled: 'true',
      connectaTransferEnabled: 'false',
    };
    buildStore();
  });

  afterEach(() => {
    wrapper?.unmount();
    wrapper = null;
    delete window.chatwootConfig;
  });

  it('shows Minhas/Aguardando/Todos/Bot with store counts for administrators', async () => {
    setRole('administrator');
    await mountChatList();

    expect(tabKeys()).toEqual(['me', 'unassigned', 'all', 'bot']);
    const byKey = Object.fromEntries(tabItems().map(item => [item.key, item]));
    expect(byKey.me.count).toBe(2);
    expect(byKey.unassigned.count).toBe(3);
    expect(byKey.all.count).toBe(5);
    expect(byKey.bot.count).toBe(1);
  });

  it('shows only Minhas/Aguardando for standard attendants', async () => {
    setRole('agent');
    await mountChatList();

    expect(tabKeys()).toEqual(['me', 'unassigned']);
  });

  it('falls back to Minhas without fetching the hidden tab when the role loses it', async () => {
    setRole('administrator');
    await mountChatList();
    dispatchCalls = [];

    // Minhas already has a page, so the fallback reset stays silent.
    state.pages.me = 1;
    await wrapper.findComponent(ChatTypeTabs).vm.$emit('chatTabChange', 'bot');
    await nextTick();
    expect(activeTab()).toBe('bot');
    expect(fetchCalls('fetchBotConversations')).toBe(1);

    // The account now scopes the user as attendant: Todos/Bot disappear and
    // the stale Bot selection falls back to Minhas with no hidden fetch.
    setRole('agent');
    await nextTick();
    await flushPromises();

    expect(tabKeys()).toEqual(['me', 'unassigned']);
    expect(activeTab()).toBe('me');
    expect(fetchCalls('fetchBotConversations')).toBe(1);
    expect(fetchCalls('fetchAllConversations')).toBe(0);
  });

  it('shows the Bot empty message only for the rendered Bot list', async () => {
    setRole('administrator');
    await mountChatList();
    await wrapper.findComponent(ChatTypeTabs).vm.$emit('chatTabChange', 'bot');
    await nextTick();

    // Empty Bot list, request finished: the message shows.
    expect(botEmptyVisible()).toBe(true);

    // Populated Bot list after a view change: the message hides.
    state.botRows = [{ id: 11 }, { id: 12 }];
    await nextTick();
    expect(botEmptyVisible()).toBe(false);

    // Loading with no rows yet: the message hides until the request lands.
    state.botRows = [];
    state.loading = true;
    await nextTick();
    expect(botEmptyVisible()).toBe(false);
    state.loading = false;
    await nextTick();
    expect(botEmptyVisible()).toBe(true);

    // Another view with the same finished status: the message hides.
    await wrapper.findComponent(ChatTypeTabs).vm.$emit('chatTabChange', 'me');
    await nextTick();
    expect(botEmptyVisible()).toBe(false);
  });
});
