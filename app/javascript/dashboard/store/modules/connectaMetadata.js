import ConnectaAPI from 'dashboard/api/connecta';

export const MAX_BATCH_SIZE = 50;
export const CACHE_TTL_MS = 5 * 60 * 1000;

const normalizeId = id => {
  const normalized = Number(id);
  return Number.isInteger(normalized) && normalized > 0 ? normalized : null;
};

const scopeKey = (scope, id) =>
  `${scope.accountId}:${scope.userId}:${scope.epoch}:${id}`;

const currentKey = ($state, id) => {
  const normalized = normalizeId(id);
  if (!normalized) return null;
  if (!$state.scope.accountId || !$state.scope.userId) return null;
  return scopeKey($state.scope, normalized);
};

const isFresh = entry =>
  Boolean(entry && Date.now() - entry.fetchedAt < CACHE_TTL_MS);

const sameScope = (left, right) =>
  left.accountId === right.accountId &&
  left.userId === right.userId &&
  left.epoch === right.epoch;

const state = {
  records: {},
  checked: {},
  scope: { accountId: null, userId: null, epoch: 0 },
};

export const getters = {
  getMetadata: $state => id => {
    const key = currentKey($state, id);
    const entry = key ? $state.records[key] : null;
    return isFresh(entry) ? entry.data : null;
  },
  isChecked: $state => id => {
    const key = currentKey($state, id);
    return isFresh(key ? $state.checked[key] : null);
  },
  getEpoch: $state => $state.scope.epoch,
};

const normalizeIds = ids => [
  ...new Set(
    (Array.isArray(ids) ? ids : [ids])
      .map(normalizeId)
      .filter(id => id !== null)
  ),
];

export const actions = {
  // Troca de conta/ator limpa o cache: display_id se repete entre contas.
  setScope: ({ commit, state: $state }, { accountId, userId }) => {
    const nextAccount = normalizeId(accountId);
    const nextUser = normalizeId(userId);
    if (
      nextAccount === $state.scope.accountId &&
      nextUser === $state.scope.userId
    ) {
      return;
    }
    commit('RESET');
    commit('SET_SCOPE', { accountId: nextAccount, userId: nextUser });
  },

  reset: ({ commit }) => commit('RESET'),

  // ACL/servidor revogou: descarta tudo e força nova busca para o mesmo ator.
  bumpEpoch: ({ commit }) => commit('BUMP_EPOCH'),

  // Busca em lotes de 50 (limite do servidor). Sequencial para não criar
  // tempestade de requisições; falha de um lote deixa só ele para retry.
  fetch: async ({ commit, state: $state }, ids) => {
    if (!$state.scope.accountId || !$state.scope.userId) return;
    const normalized = normalizeIds(ids);
    if (!normalized.length) return;
    const scope = { ...$state.scope };

    for (let index = 0; index < normalized.length; index += MAX_BATCH_SIZE) {
      const batch = normalized.slice(index, index + MAX_BATCH_SIZE);
      try {
        // Sequencial de propósito: evita tempestade de requisições.
        // eslint-disable-next-line no-await-in-loop
        const { data } = await ConnectaAPI.conversationMetadata(batch);
        // Conta/ator/epoch mudou durante a requisição: a resposta pertence ao
        // escopo antigo e não pode contaminar o novo.
        if (!sameScope($state.scope, scope)) return;
        commit('SET_METADATA', {
          ids: batch,
          conversations: data?.conversations || {},
        });
        commit('MARK_CHECKED', batch);
      } catch (_) {
        // O lote continua não-checado; a próxima mudança de lista tenta de novo.
      }
    }
  },

  invalidate: ({ commit }, id) => {
    const normalized = normalizeId(id);
    if (!normalized) return;
    commit('INVALIDATE', normalized);
  },
};

export const mutations = {
  SET_SCOPE($state, { accountId, userId }) {
    $state.scope = { ...$state.scope, accountId, userId };
  },
  SET_METADATA($state, { ids, conversations }) {
    const now = Date.now();
    const records = { ...$state.records };
    ids.forEach(id => {
      const key = currentKey($state, id);
      if (!key) return;
      const item = conversations[String(id)];
      if (item) {
        records[key] = { data: item, fetchedAt: now };
      } else {
        // A API omitiu/negou: remove qualquer metadado antigo daquele id.
        delete records[key];
      }
    });
    $state.records = records;
  },
  MARK_CHECKED($state, ids) {
    const now = Date.now();
    const checked = { ...$state.checked };
    ids.forEach(id => {
      const key = currentKey($state, id);
      if (key) checked[key] = { fetchedAt: now };
    });
    $state.checked = checked;
  },
  INVALIDATE($state, id) {
    const key = currentKey($state, id);
    if (!key) return;
    const records = { ...$state.records };
    const checked = { ...$state.checked };
    delete records[key];
    delete checked[key];
    $state.records = records;
    $state.checked = checked;
  },
  BUMP_EPOCH($state) {
    $state.scope = { ...$state.scope, epoch: $state.scope.epoch + 1 };
    $state.records = {};
    $state.checked = {};
  },
  RESET($state) {
    $state.records = {};
    $state.checked = {};
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
