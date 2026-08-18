<script setup>
import { ref, computed, nextTick } from 'vue';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import { useConfig } from 'dashboard/composables/useConfig';
import conversationAPI from 'dashboard/api/inbox/conversation';
import wootConstants from 'dashboard/constants/globals';
import types from 'dashboard/store/mutation-types';
import { frontendURL, conversationUrl } from 'dashboard/helper/URLHelper';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const store = useStore();
const getters = useStoreGetters();
const { t } = useI18n();
const router = useRouter();
const { connectaTransferEnabled } = useConfig();

const dialogRef = ref(null);
const isLoading = ref(false);
const isLoadingDestinations = ref(false);
const destinations = ref([]);
const selectedDepartmentId = ref('');
const loadError = ref(false);

const currentChat = computed(() => getters.getSelectedChat.value);
const accountId = computed(() => getters.getCurrentAccountId.value);

const isVisible = computed(() => {
  if (!connectaTransferEnabled) return false;

  const status = currentChat.value?.status;
  return (
    status === wootConstants.STATUS_TYPE.OPEN ||
    status === wootConstants.STATUS_TYPE.PENDING
  );
});

const destinationOptions = computed(() =>
  destinations.value.map(destination => ({
    value: destination.departmentId || destination.department_id,
    label: destination.displayName || destination.display_name,
  }))
);

const selectedDestinationName = computed(() => {
  const destination = destinations.value.find(
    item =>
      (item.departmentId || item.department_id) === selectedDepartmentId.value
  );

  return destination?.displayName || destination?.display_name || '';
});

const fetchDestinations = async () => {
  isLoadingDestinations.value = true;
  loadError.value = false;

  try {
    const { data } = await conversationAPI.getConnectaTransferDestinations(
      currentChat.value.id
    );
    destinations.value = data.destinations || [];
  } catch (error) {
    loadError.value = true;
    useAlert(
      error.response?.data?.error || t('CONVERSATION.TRANSFER.LOAD_ERROR')
    );
  } finally {
    isLoadingDestinations.value = false;
  }
};

const openDialog = async () => {
  selectedDepartmentId.value = '';
  destinations.value = [];
  loadError.value = false;
  dialogRef.value?.open();
  await nextTick();
  fetchDestinations();
};

const handleConfirm = async () => {
  if (!selectedDepartmentId.value) return;

  isLoading.value = true;

  try {
    const { data } = await conversationAPI.createConnectaTransfer(
      currentChat.value.id,
      { targetDepartmentId: selectedDepartmentId.value }
    );

    store.commit(types.CHANGE_CONVERSATION_STATUS, {
      conversationId: currentChat.value.id,
      status: wootConstants.STATUS_TYPE.RESOLVED,
      snoozedUntil: null,
    });

    useAlert(t('CONVERSATION.TRANSFER.SUCCESS'));
    dialogRef.value?.close();

    const newConversationId = data.display_id || data.new_conversation_id;
    if (newConversationId) {
      router.push(
        frontendURL(
          conversationUrl({
            accountId: accountId.value,
            id: newConversationId,
          })
        )
      );
    }
  } catch (error) {
    useAlert(error.response?.data?.error || t('CONVERSATION.TRANSFER.ERROR'));
  } finally {
    isLoading.value = false;
  }
};
</script>

<template>
  <div v-if="isVisible">
    <Button
      :label="t('CONVERSATION.HEADER.TRANSFER_ACTION')"
      size="sm"
      color="slate"
      icon="i-lucide-arrow-right-left"
      @click="openDialog"
    />
    <Dialog
      ref="dialogRef"
      type="edit"
      :title="t('CONVERSATION.TRANSFER.TITLE')"
      :description="t('CONVERSATION.TRANSFER.DESCRIPTION')"
      :confirm-button-label="t('CONVERSATION.TRANSFER.SUBMIT')"
      :cancel-button-label="t('CONVERSATION.TRANSFER.CANCEL')"
      :disable-confirm-button="!selectedDepartmentId || isLoadingDestinations"
      :is-loading="isLoading"
      overflow-visible
      @confirm="handleConfirm"
    >
      <div class="flex flex-col gap-4">
        <ComboBox
          v-model="selectedDepartmentId"
          :options="destinationOptions"
          :placeholder="t('CONVERSATION.TRANSFER.DESTINATION_PLACEHOLDER')"
          :disabled="isLoadingDestinations || loadError"
          :empty-state="t('CONVERSATION.TRANSFER.EMPTY')"
        />
        <p v-if="selectedDepartmentId" class="text-sm text-n-slate-11">
          {{
            t('CONVERSATION.TRANSFER.CONFIRM', {
              name: selectedDestinationName,
            })
          }}
        </p>
      </div>
    </Dialog>
  </div>
</template>
