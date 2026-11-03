<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

import { useMessageContext } from '../provider.js';
import { useProtectedAttachmentUrl } from 'dashboard/composables/useProtectedAttachmentUrl';
import {
  downloadAttachmentFile,
  isProtectedAttachmentUrl,
} from 'dashboard/helper/connectaProtectedMedia';
import BaseAttachmentBubble from './BaseAttachment.vue';
import FileIcon from 'next/icon/FileIcon.vue';

const { attachments } = useMessageContext();

const { t } = useI18n();

const rawUrl = computed(() => {
  return attachments.value[0].dataUrl;
});

const isProtected = computed(() => isProtectedAttachmentUrl(rawUrl.value));

const { fileName: resolvedFileName } = useProtectedAttachmentUrl(rawUrl);

const fileName = computed(() => {
  if (resolvedFileName.value) return resolvedFileName.value;
  if (isProtected.value) return '';
  if (rawUrl.value) {
    const filename = rawUrl.value.substring(rawUrl.value.lastIndexOf('/') + 1);
    return filename || t('CONVERSATION.UNKNOWN_FILE_TYPE');
  }
  return t('CONVERSATION.UNKNOWN_FILE_TYPE');
});

const fileType = computed(() => {
  return fileName.value.split('.').pop();
});

const downloadProtected = async () => {
  const { fileType: type, extension } = attachments.value[0];
  await downloadAttachmentFile({
    url: rawUrl.value,
    fileType: type,
    extension,
    fileName: resolvedFileName.value || undefined,
  });
};

const action = computed(() => {
  if (isProtected.value) {
    return {
      label: t('CONVERSATION.DOWNLOAD'),
      onClick: downloadProtected,
    };
  }
  return {
    href: rawUrl.value,
    label: t('CONVERSATION.DOWNLOAD'),
  };
});
</script>

<template>
  <BaseAttachmentBubble
    icon="i-teenyicons-user-circle-solid"
    icon-bg-color="bg-n-alpha-3 dark:bg-n-alpha-white"
    sender-translation-key="CONVERSATION.SHARED_ATTACHMENT.FILE"
    :content="decodeURI(fileName)"
    :action="action"
  >
    <template #icon>
      <FileIcon :file-type="fileType" class="size-4" />
    </template>
  </BaseAttachmentBubble>
</template>
