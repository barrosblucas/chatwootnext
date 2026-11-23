import types from '../mutation-types';
import ConversationApi from '../../api/inbox/conversation';
import { debounce } from '@chatwoot/utils';

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

// Create a debounced version of the actual API call function.
// The Bot badge answers travel on their own debouncer: human and Bot badge
// refreshes fire in the same tick (one queue signal refreshes both), and a
// shared trailing debouncer would keep only the last params and silently drop
// the human badges.
const fetchMetaData = async (commit, params, token) => {
  try {
    const response = await ConversationApi.meta(params);
    // A newer signal in the same lane supersedes this answer (tab/account
    // switched, or a later burst re-asked): the older answer must not
    // overwrite current badges. Answers from the other lane carry their own
    // lane sequence and never invalidate this one.
    if (
      token &&
      (token.seq !== statsRequestSeq[token.lane] || token.isStale?.())
    )
      return;
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

// allCount is 0 until a meta request succeeds; under load it stays 0, so treat
// the unknown case as a large account and poll slowest instead of fastest.
export const getMetaDebounceKey = allCount => {
  if (allCount > 2000 || allCount === 0) return 'superLong';
  if (allCount > 100) return 'long';
  return 'default';
};

export const actions = {
  get: ({ commit, state: $state, rootGetters }, params) => {
    const lane = statsRequestLane(params);
    statsRequestSeq[lane] += 1;
    const seq = statsRequestSeq[lane];
    const accountId = rootGetters?.getCurrentAccountId;
    // Stale-account guard: an answer that returns after the agent switched
    // accounts must not write the previous account's counts here.
    const token = {
      lane,
      seq,
      isStale: () =>
        accountId !== undefined &&
        rootGetters?.getCurrentAccountId !== undefined &&
        rootGetters.getCurrentAccountId !== accountId,
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
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
