import types from '../mutation-types';
import ConversationApi from '../../api/inbox/conversation';
import { debounce } from '@chatwoot/utils';
import {
  CONNECTA_TABS,
  extractConnectaAllCount,
  isConnectaDashboardParams,
  isConnectaTab,
} from 'dashboard/helper/connectaDashboardTabs';

const state = {
  mineCount: 0,
  unAssignedCount: 0,
  allCount: 0,
  // Bot tab badge (eligible count) lives apart so Bot answers never rewrite
  // the human badges sharing this module. botClassificationUnavailable mirrors
  // the server opt-in flag: null = never attempted, false = exclusion applied,
  // true = original list preserved, classification unavailable.
  botCount: 0,
  botClassificationUnavailable: null,
  // Connecta dashboard badges: exact per-tab `all_count` totals, one slot per
  // tab so sibling answers never overwrite each other. null = unknown (never
  // a successful zero): failures and pending loads leave the slot untouched
  // instead of faking a zero badge.
  connectaCounts: { minhas: null, aguardando: null, todos: null, bot: null },
  connectaErrors: {
    minhas: false,
    aguardando: false,
    todos: false,
    bot: false,
  },
  connectaAccountId: null,
};

export const getters = {
  getStats: $state => $state,
};

// Newer badge signals supersede older in-flight answers within their own lane:
// each `get` bumps only its lane sequence and a late answer whose token no
// longer matches is dropped instead of overwriting the current tab's badges.
// Human and Bot answers travel on separate debouncers and resolve in either
// order, so a shared sequence would let one lane invalidate the other.
const statsRequestSeq = { human: 0, bot: 0 };
const statsRequestLane = params =>
  params?.conversationType === 'bot' ? 'bot' : 'human';

// Connecta answers are per-tab exact totals on their own slots: a shared
// human sequence would let one tab's newer request invalidate a sibling's
// answer, so each tab carries its own sequence plus the account guard.
const connectaRequestSeq = { minhas: 0, aguardando: 0, todos: 0, bot: 0 };

// Create a debounced version of the actual API call function.
// The Bot badge answers travel on their own debouncer: human and Bot badge
// refreshes fire in the same tick (one queue signal refreshes both), and a
// shared trailing debouncer would keep only the last params and silently drop
// the human badges.
const fetchMetaData = async (commit, params, token) => {
  try {
    const response = await ConversationApi.meta(params);
    // A newer signal in the same lane/tab supersedes this answer (tab/account
    // switched, or a later burst re-asked): the older answer must not
    // overwrite current badges. Answers from the other lane carry their own
    // lane sequence and never invalidate this one.
    if (
      token &&
      (token.seq !== token.readSeq() || token.isStale?.())
    )
      return;
    // Connecta opt-in answers carry the exact tab total only: they land on
    // that tab's slot and never rewrite the native triple.
    if (token?.connectaTab) {
      const count = extractConnectaAllCount(response);
      if (count === null) {
        commit(types.SET_CONNECTA_TAB_ERROR, { tab: token.connectaTab });
        return;
      }
      commit(types.SET_CONNECTA_TAB_META, {
        tab: token.connectaTab,
        count,
        accountId: token.accountId,
        botClassificationUnavailable:
          response?.data?.meta?.bot_classification_unavailable ??
          response?.data?.data?.meta?.bot_classification_unavailable,
      });
      return;
    }
    const {
      data: { meta },
    } = response;
    // Bot meta answers carry the eligible count for the Bot badge only; they
    // must never rewrite the human badges sharing this module.
    if (params?.conversationType === 'bot') {
      commit(types.SET_BOT_TAB_META, { count: meta.all_count });
    } else {
      commit(types.SET_CONV_TAB_META, meta);
    }
  } catch (error) {
    // A failed badge is unknown, never zero: mark the Connecta tab so the UI
    // can tell an error apart from a successful zero. Stale answers stay
    // silent. Native failures keep the legacy ignore.
    if (token?.connectaTab) {
      if (token.seq !== token.readSeq() || token.isStale?.()) return;
      commit(types.SET_CONNECTA_TAB_ERROR, {
        tab: token.connectaTab,
        accountId: token.accountId,
      });
    }
    // ignore
  }
};

const debouncedFetchMetaData = debounce(fetchMetaData, 1000, false, 5000);
const botDebouncedFetchMetaData = debounce(fetchMetaData, 1000, false, 5000);
const longDebouncedFetchMetaData = debounce(fetchMetaData, 7500, false, 20000);
const superLongDebouncedFetchMetaData = debounce(
  fetchMetaData,
  15000,
  false,
  30000
);

const metaDebouncers = {
  default: debouncedFetchMetaData,
  long: longDebouncedFetchMetaData,
  superLong: superLongDebouncedFetchMetaData,
};

// One trailing debouncer per Connecta tab: badge refreshes for every visible
// tab fire in the same tick, and a shared debouncer would keep only the last
// tab's params and silently drop the rest.
const connectaDebouncedFetchMetaData = Object.fromEntries(
  CONNECTA_TABS.map(tab => [tab, debounce(fetchMetaData, 1000, false, 5000)])
);

// allCount is 0 until a meta request succeeds; under load it stays 0, so treat
// the unknown case as a large account and poll slowest instead of fastest.
export const getMetaDebounceKey = allCount => {
  if (allCount > 2000 || allCount === 0) return 'superLong';
  if (allCount > 100) return 'long';
  return 'default';
};

export const actions = {
  get: ({ commit, state: $state, rootGetters }, params) => {
    const accountId = rootGetters?.getCurrentAccountId;
    // Stale-account guard: an answer that returns after the agent switched
    // accounts must not write the previous account's counts here.
    const isStaleAccount = () =>
      accountId !== undefined &&
      rootGetters?.getCurrentAccountId !== undefined &&
      rootGetters.getCurrentAccountId !== accountId;
    // Connecta opt-in badges: one exact total per visible tab. Each tab has
    // its own sequence (a shared one would drop sibling answers) and its own
    // debounced slot; the component-level queue signal already coalesces
    // bursts, so tabs refresh without collapsing into a single request.
    if (isConnectaDashboardParams(params)) {
      const tab = params.connectaTab;
      connectaRequestSeq[tab] += 1;
      const seq = connectaRequestSeq[tab];
      const token = {
        seq,
        connectaTab: tab,
        accountId,
        readSeq: () => connectaRequestSeq[tab],
        isStale: isStaleAccount,
      };
      connectaDebouncedFetchMetaData[tab](commit, params, token);
      return;
    }
    const lane = statsRequestLane(params);
    statsRequestSeq[lane] += 1;
    const seq = statsRequestSeq[lane];
    const token = {
      lane,
      seq,
      accountId,
      readSeq: () => statsRequestSeq[lane],
      isStale: isStaleAccount,
    };
    const fetch =
      params?.conversationType === 'bot'
        ? botDebouncedFetchMetaData
        : metaDebouncers[getMetaDebounceKey($state.allCount)];
    fetch(commit, params, token);
  },
  set({ commit }, meta) {
    commit(types.SET_CONV_TAB_META, meta);
  },
  setBotMeta({ commit }, { count } = {}) {
    commit(types.SET_BOT_TAB_META, { count });
  },
  // Exact tab total from a Connecta list response (same contract/filter as
  // the badge request): lands on that tab's slot only. A non-numeric total
  // is unknown, never zero.
  setConnectaTab({ commit }, { tab, count, accountId } = {}) {
    if (!isConnectaTab(tab)) return;
    if (typeof count === 'number' && Number.isFinite(count)) {
      commit(types.SET_CONNECTA_TAB_META, { tab, count, accountId });
    } else {
      commit(types.SET_CONNECTA_TAB_ERROR, { tab, accountId });
    }
  },
  setConnectaTabError({ commit }, { tab, accountId } = {}) {
    if (!isConnectaTab(tab)) return;
    commit(types.SET_CONNECTA_TAB_ERROR, { tab, accountId });
  },
};

export const mutations = {
  [types.SET_CONV_TAB_META](
    $state,
    {
      mine_count: mineCount,
      unassigned_count: unAssignedCount,
      all_count: allCount,
      bot_classification_unavailable: botClassificationUnavailable,
    } = {}
  ) {
    $state.mineCount = mineCount;
    $state.allCount = allCount;
    $state.unAssignedCount = unAssignedCount;
    $state.updatedOn = new Date();
    // Only human opt-in answers carry the flag; anything else leaves the last
    // known classification state untouched instead of clearing it.
    if (botClassificationUnavailable !== undefined) {
      $state.botClassificationUnavailable = botClassificationUnavailable;
    }
  },
  [types.SET_BOT_TAB_META]($state, { count } = {}) {
    $state.botCount = count;
    $state.updatedOn = new Date();
  },
  // A new account starts every Connecta slot unknown: the previous
  // account's totals must never render as this account's badges while fresh
  // answers are in flight.
  [types.SET_CONNECTA_TAB_META](
    $state,
    { tab, count, accountId, botClassificationUnavailable } = {}
  ) {
    if (
      accountId !== undefined &&
      $state.connectaAccountId !== accountId
    ) {
      $state.connectaCounts = {
        minhas: null,
        aguardando: null,
        todos: null,
        bot: null,
      };
      $state.connectaErrors = {
        minhas: false,
        aguardando: false,
        todos: false,
        bot: false,
      };
      $state.connectaAccountId = accountId ?? null;
    }
    $state.connectaCounts[tab] = count;
    $state.connectaErrors[tab] = false;
    $state.updatedOn = new Date();
    // Only answers carrying the flag touch the classification state;
    // anything else leaves the last known state instead of clearing it.
    if (botClassificationUnavailable !== undefined) {
      $state.botClassificationUnavailable = botClassificationUnavailable;
    }
  },
  [types.SET_CONNECTA_TAB_ERROR]($state, { tab, accountId } = {}) {
    if (
      accountId !== undefined &&
      $state.connectaAccountId !== accountId
    ) {
      $state.connectaCounts = {
        minhas: null,
        aguardando: null,
        todos: null,
        bot: null,
      };
      $state.connectaErrors = {
        minhas: false,
        aguardando: false,
        todos: false,
        bot: false,
      };
      $state.connectaAccountId = accountId ?? null;
    }
    // The count slot is untouched: unknown stays unknown instead of faking
    // zero, and a previous exact total stays until a fresh answer lands.
    $state.connectaErrors[tab] = true;
    $state.updatedOn = new Date();
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
