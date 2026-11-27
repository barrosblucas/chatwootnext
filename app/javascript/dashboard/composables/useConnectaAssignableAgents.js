import { computed, watch } from 'vue';
import { useStore } from 'vuex';
import { useMapGetter } from 'dashboard/composables/store';
import {
  flatAgentsFromPayload,
  menuEntriesFromPayload,
} from 'dashboard/helper/connectaAssignableAgents';

/**
 * Department-aware assignees for one open conversation (sidebar, cmd+K) or
 * for the right-click menu. Fetches are keyed by the exact conversation ids,
 * so opening conversation B after A never shows A's agents.
 *
 * @param {import('vue').ComputedRef|import('vue').Ref|Array} conversationIds
 */
export function useConnectaAssignableAgents(conversationIds) {
  const store = useStore();
  const getPayload = useMapGetter('connectaAssignableAgents/getPayload');
  const uiFlags = useMapGetter('connectaAssignableAgents/getUIFlags');

  const ids = computed(() => {
    const raw = conversationIds?.value ?? conversationIds ?? [];
    return [raw].flat().filter(Boolean);
  });

  const payload = computed(() =>
    ids.value.length ? getPayload.value(ids.value) : null
  );

  const fetchAgents = () => {
    if (!ids.value.length) return Promise.resolve(null);
    return store.dispatch('connectaAssignableAgents/fetch', ids.value);
  };

  watch(ids, fetchAgents, { immediate: true });

  const flatAgents = computed(() => flatAgentsFromPayload(payload.value));
  const menuEntries = computed(() => menuEntriesFromPayload(payload.value));
  const isFetching = computed(() => uiFlags.value.isFetching);

  return {
    payload,
    flatAgents,
    menuEntries,
    isFetching,
    fetchAgents,
  };
}
