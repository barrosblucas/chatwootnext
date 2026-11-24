import { nextTick, ref } from 'vue';
import { createStore } from 'vuex';
import { flushPromises, shallowMount } from '@vue/test-utils';
import { beforeEach, describe, expect, it, vi, afterEach } from 'vitest';
import ChatList from '../ChatList.vue';
import ConnectaAPI from 'dashboard/api/connecta';

// Dashboard sector filter (Setor): the select offers only the authorized
// catalog options, the selection travels through the shared builders for the
// visible-tab list and badge paths, clearing restores the aggregate, and
// stale catalog answers never leak across account changes. No network.
vi.mock('dashboard/api/connecta', () => ({
  default: { getOrgUnits: vi.fn() },
}));

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

let accountIdRef = ref(1);
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
      getCurrentAccountId: () => accountIdRef.value,
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

const sectorSelect = () => wrapper.find('select');

const CATALOG = [
  { id: 3, name: 'Setor A' },
  { id: 5, name: 'Setor B' },
];

describe('ChatList Connecta sector filter', () => {
  beforeEach(() => {
    window.chatwootConfig = {
      connectaHumanNumberEnabled: 'true',
      connectaTransferEnabled: 'false',
    };
    accountIdRef = ref(1);
    buildStore();
    ConnectaAPI.getOrgUnits.mockReset();
    ConnectaAPI.getOrgUnits.mockResolvedValue({ data: { org_units: CATALOG } });
  });

  afterEach(() => {
    wrapper?.unmount();
    wrapper = null;
    delete window.chatwootConfig;
  });

  it('asks the account catalog once and offers only its options', async () => {
    await mountChatList();

    expect(ConnectaAPI.getOrgUnits).toHaveBeenCalledTimes(1);
    expect(sectorSelect().exists()).toBe(true);
    expect(sectorSelect().attributes('aria-label')).toBe(
      'CONNECTA.SECTOR_FILTER.LABEL'
    );
    expect(
      sectorSelect()
        .findAll('option')
        .map(o => o.attributes('value'))
    ).toEqual(['', '3', '5']);
  });

  it('never calls the catalog outside the Connecta queue context', async () => {
    await mountChatList({ conversationType: 'mention' });

    expect(ConnectaAPI.getOrgUnits).not.toHaveBeenCalled();
    expect(sectorSelect().exists()).toBe(false);
  });

  it('selecting a sector filters the list and badges and resets pagination', async () => {
    await mountChatList();
    dispatchCalls.length = 0;

    await sectorSelect().setValue('3');
    await flushPromises();
    await nextTick();

    expect(payloads('conversationPage/reset')).toHaveLength(1);
    const listPayload = payloads('updateChatListFilters').at(-1);
    expect(listPayload.connectaOrgUnitId).toBe(3);
    expect(listPayload.connectaTab).toBe('minhas');
    const badges = payloads('conversationStats/get');
    expect(badges.length).toBeGreaterThan(0);
    badges.forEach(badge => {
      expect(badge.connectaOrgUnitId).toBe(3);
    });
  });

  it('selecting a UUID sector travels as an exact string, never NaN', async () => {
    const uuid = '123e4567-e89b-12d3-a456-426614174000';
    ConnectaAPI.getOrgUnits.mockResolvedValue({
      data: { org_units: [{ id: uuid, name: 'Setor U' }] },
    });
    await mountChatList();
    dispatchCalls.length = 0;

    await sectorSelect().setValue(uuid);
    await flushPromises();
    await nextTick();

    expect(payloads('conversationPage/reset')).toHaveLength(1);
    const listPayload = payloads('updateChatListFilters').at(-1);
    expect(listPayload.connectaOrgUnitId).toBe(uuid);
    const badges = payloads('conversationStats/get');
    expect(badges.length).toBeGreaterThan(0);
    badges.forEach(badge => {
      expect(badge.connectaOrgUnitId).toBe(uuid);
    });
  });

  it('clearing the selection omits the id and restores the aggregate', async () => {
    await mountChatList();
    await sectorSelect().setValue('3');
    dispatchCalls.length = 0;

    await sectorSelect().setValue('');
    await flushPromises();

    const listPayload = payloads('updateChatListFilters').at(-1);
    expect(listPayload.connectaOrgUnitId).toBeUndefined();
    const badges = payloads('conversationStats/get');
    expect(badges.length).toBeGreaterThan(0);
    badges.forEach(badge => {
      expect(badge.connectaOrgUnitId).toBeUndefined();
    });
  });

  it('shows a disabled loading select while the catalog is pending', async () => {
    ConnectaAPI.getOrgUnits.mockReturnValueOnce(new Promise(() => {}));
    await mountChatList();

    expect(sectorSelect().exists()).toBe(true);
    expect(sectorSelect().attributes('disabled')).toBeDefined();
  });

  it('hides the filter on catalog error without touching the aggregate', async () => {
    ConnectaAPI.getOrgUnits.mockRejectedValueOnce(new Error('down'));
    await mountChatList();

    expect(sectorSelect().exists()).toBe(false);
    const listPayload = payloads('updateChatListFilters').at(-1);
    expect(listPayload.connectaDashboard).toBe('true');
    expect(listPayload.connectaOrgUnitId).toBeUndefined();
  });

  it('drops a stale catalog answer after an account switch', async () => {
    let resolveFirst;
    ConnectaAPI.getOrgUnits.mockReturnValueOnce(
      new Promise(resolve => {
        resolveFirst = resolve;
      })
    );
    let resolveSecond;
    ConnectaAPI.getOrgUnits.mockReturnValueOnce(
      new Promise(resolve => {
        resolveSecond = resolve;
      })
    );
    await mountChatList();
    expect(ConnectaAPI.getOrgUnits).toHaveBeenCalledTimes(1);

    accountIdRef.value = 2;
    await nextTick();
    await flushPromises();
    expect(ConnectaAPI.getOrgUnits).toHaveBeenCalledTimes(2);

    resolveFirst({ data: { org_units: [{ id: 9, name: 'Stale' }] } });
    await flushPromises();
    await nextTick();
    expect(
      sectorSelect()
        .findAll('option')
        .map(o => o.text())
    ).not.toContain('Stale');

    resolveSecond({ data: { org_units: CATALOG } });
    await flushPromises();
    await nextTick();
    expect(
      sectorSelect()
        .findAll('option')
        .map(o => o.attributes('value'))
    ).toEqual(['', '3', '5']);
  });

  it('changing accounts clears the selection', async () => {
    await mountChatList();
    await sectorSelect().setValue('3');
    expect(sectorSelect().element.value).toBe('3');

    accountIdRef.value = 2;
    await nextTick();
    await flushPromises();
    await nextTick();

    expect(sectorSelect().exists()).toBe(true);
    expect(sectorSelect().element.value).toBe('');
  });
});
