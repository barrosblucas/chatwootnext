import ConnectaAPI from 'dashboard/api/connecta';

const state = {
  records: {},
  checked: {},
};

export const getters = {
  getMetadata: $state => id => $state.records[Number(id)] || null,
  isChecked: $state => id => Boolean($state.checked[Number(id)]),
};

export const actions = {
  // Busca em lote (uma requisição por página/evento). O backend devolve só
  // conversas visíveis; ids sem escopo entram em checked para não repetir.
  fetch: async ({ commit }, ids) => {
    const normalized = [
      ...new Set(
        (Array.isArray(ids) ? ids : [ids])
          .map(id => Number(id))
          .filter(id => Number.isInteger(id) && id > 0)
      ),
    ];
    if (!normalized.length) return;
    let loaded = false;
    try {
      const { data } = await ConnectaAPI.conversationMetadata(normalized);
      commit('SET_METADATA', data?.conversations || {});
      loaded = true;
    } catch (_) {
      // A lista continua sem o rótulo; a próxima mudança de lista tenta de novo.
    } finally {
      if (loaded) commit('MARK_CHECKED', normalized);
    }
  },

  invalidate: ({ commit }, id) => {
    const normalized = Number(id);
    if (Number.isInteger(normalized) && normalized > 0) {
      commit('INVALIDATE', normalized);
    }
  },
};

export const mutations = {
  SET_METADATA($state, conversations) {
    $state.records = { ...$state.records, ...conversations };
  },
  MARK_CHECKED($state, ids) {
    $state.checked = {
      ...$state.checked,
      ...ids.reduce((result, id) => ({ ...result, [id]: true }), {}),
    };
  },
  INVALIDATE($state, id) {
    const records = { ...$state.records };
    const checked = { ...$state.checked };
    delete records[id];
    delete checked[id];
    $state.records = records;
    $state.checked = checked;
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
