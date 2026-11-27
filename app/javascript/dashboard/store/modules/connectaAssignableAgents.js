import ConnectaAssignableAgentsAPI from '../../api/connectaAssignableAgents';
import { normalizeAssignableAgentsPayload } from '../../helper/connectaAssignableAgents';

// Department-aware assignable agents, keyed by conversation id so two open
// conversations never share a stale list. The legacy `inboxAssignableAgents`
// store stays untouched for its other consumers (inbox settings, etc.).
const keyFor = ids =>
  [...new Set((ids ?? []).filter(Boolean))].map(String).sort().join(',');

const state = {
  records: {},
  uiFlags: {
    isFetching: false,
  },
};

export const types = {
  SET_CONNECTA_ASSIGNABLE_AGENTS_UI_FLAG:
    'SET_CONNECTA_ASSIGNABLE_AGENTS_UI_FLAG',
  SET_CONNECTA_ASSIGNABLE_AGENTS: 'SET_CONNECTA_ASSIGNABLE_AGENTS',
};

export const getters = {
  getPayload:
    $state =>
    (conversationIds = []) =>
      $state.records[keyFor([conversationIds].flat())] || null,
  getUIFlags($state) {
    return $state.uiFlags;
  },
};

export const actions = {
  async fetch({ commit }, conversationIds) {
    const ids = [conversationIds].flat().filter(Boolean);
    if (!ids.length) return null;
    const key = keyFor(ids);
    commit(types.SET_CONNECTA_ASSIGNABLE_AGENTS_UI_FLAG, { isFetching: true });
    try {
      const { data } = await ConnectaAssignableAgentsAPI.get(ids);
      const payload = normalizeAssignableAgentsPayload(data);
      commit(types.SET_CONNECTA_ASSIGNABLE_AGENTS, { key, payload });
      return payload;
    } catch (error) {
      throw new Error(error);
    } finally {
      commit(types.SET_CONNECTA_ASSIGNABLE_AGENTS_UI_FLAG, {
        isFetching: false,
      });
    }
  },
};

export const mutations = {
  [types.SET_CONNECTA_ASSIGNABLE_AGENTS_UI_FLAG]($state, data) {
    $state.uiFlags = {
      ...$state.uiFlags,
      ...data,
    };
  },
  [types.SET_CONNECTA_ASSIGNABLE_AGENTS]: ($state, { key, payload }) => {
    $state.records = {
      ...$state.records,
      [key]: payload,
    };
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
