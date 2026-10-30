<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useConfig } from 'dashboard/composables/useConfig';
import connectaAPI from 'dashboard/api/connecta';

const props = defineProps({
  conversationId: { type: [Number, String], required: true },
});
const { t } = useI18n();
const { connectaHumanNumberEnabled } = useConfig();
const scope = ref(null);

const messages = computed(() => {
  if (!scope.value) return [];
  const result = [];
  if (scope.value.state === 'reception')
    result.push(t('CONNECTA.STATUS.RECEPTION'));
  if (scope.value.state === 'pending_activation')
    result.push(t('CONNECTA.STATUS.PENDING_ACTIVATION'));
  if (scope.value.state === 'activation_stuck')
    result.push(t('CONNECTA.STATUS.ACTIVATION_STUCK'));
  if (scope.value.state === 'transferring')
    result.push(t('CONNECTA.STATUS.TRANSFERRING'));
  // Sem transferência, parked é retenção pré-admissão, não transferência.
  if (scope.value.dispatch_state === 'parked') {
    const transferred = [
      'transferring',
      'transferred_out',
      'pending_activation',
      'activation_stuck',
    ].includes(scope.value.state);
    result.push(
      transferred
        ? t('CONNECTA.STATUS.PARKED_TRANSFER')
        : t('CONNECTA.STATUS.PARKED_HELD')
    );
  }
  if (scope.value.dispatch_state === 'uncertain')
    result.push(t('CONNECTA.STATUS.UNCERTAIN'));
  return result;
});

watch(
  () => props.conversationId,
  async id => {
    scope.value = null;
    if (!connectaHumanNumberEnabled || !id) return;
    try {
      const { data } = await connectaAPI.showScope(id);
      scope.value = data;
    } catch (_) {
      scope.value = null;
    }
  },
  { immediate: true }
);
</script>

<template>
  <div
    v-if="messages.length"
    class="border-b border-n-weak bg-n-amber-3 px-4 py-2 text-sm text-n-amber-11"
  >
    <p v-for="message in messages" :key="message">{{ message }}</p>
  </div>
</template>
