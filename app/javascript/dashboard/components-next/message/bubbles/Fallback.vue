<script setup>
import { computed } from 'vue';
import BaseBubble from './Base.vue';
import FormattedContent from './Text/FormattedContent.vue';
import { useProtectedAttachmentUrl } from 'dashboard/composables/useProtectedAttachmentUrl';
import { useMessageContext } from '../provider.js';

const { attachments, content } = useMessageContext();

const attachment = computed(() => attachments.value?.[0] || {});
const rawUrl = computed(
  () => attachment.value.dataUrl || attachment.value.data_url
);
const { resolvedUrl, fileName: resolvedFileName } =
  useProtectedAttachmentUrl(rawUrl);
const url = computed(() => resolvedUrl.value);
const title = computed(
  () =>
    attachment.value.fallbackTitle ||
    attachment.value.fallback_title ||
    resolvedFileName.value ||
    rawUrl.value
);
</script>

<template>
  <BaseBubble class="p-3" data-bubble-name="fallback">
    <FormattedContent v-if="content" :content="content" class="mb-2" />
    <a
      v-if="url"
      :href="url"
      target="_blank"
      rel="noopener noreferrer"
      class="block max-w-[320px] truncate text-sm text-n-brand underline"
    >
      {{ title }}
    </a>
    <span v-else class="text-sm text-n-slate-11">
      {{ title }}
    </span>
  </BaseBubble>
</template>
