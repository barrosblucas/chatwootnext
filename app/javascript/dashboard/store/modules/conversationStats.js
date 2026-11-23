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

// Create a debounced version of the actual API call function
const fetchMetaData = async (commit, params) => {
  try {
    const response = await ConversationApi.meta(params);
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
  get: ({ commit, state: $state }, params) => {
    metaDebouncers[getMetaDebounceKey($state.allCount)](commit, params);
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
