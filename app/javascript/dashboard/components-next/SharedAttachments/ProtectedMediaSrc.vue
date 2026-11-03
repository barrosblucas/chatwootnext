<script setup>
import { computed, watch } from 'vue';
import { useProtectedAttachmentUrl } from 'dashboard/composables/useProtectedAttachmentUrl';

const props = defineProps({
  url: {
    type: String,
    default: '',
  },
});

const emit = defineEmits(['error']);

const { resolvedUrl, isResolving, resolveError, fileName, retry } =
  useProtectedAttachmentUrl(() => props.url);

const hasError = computed(() => !!resolveError.value);

watch(resolveError, error => {
  if (error) emit('error', error);
});
</script>

<template>
  <slot
    :src="resolvedUrl"
    :is-resolving="isResolving"
    :has-error="hasError"
    :resolve-error="resolveError"
    :file-name="fileName"
    :retry="retry"
  />
</template>
