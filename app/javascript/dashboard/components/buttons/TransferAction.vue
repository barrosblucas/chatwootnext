<script setup>
import { ref, computed, nextTick, watch } from 'vue';
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
const { connectaTransferEnabled, connectaHumanNumberEnabled } = useConfig();

const dialogRef = ref(null);
const isLoading = ref(false);
const isLoadingDestinations = ref(false);
const destinations = ref([]);
const selectedDepartmentId = ref('');
const loadError = ref(false);
const summary = ref({ subject: '', completed: '', nextAction: '' });
const SUMMARY_LIMITS = { subject: 160, completed: 2000, nextAction: 2000 };
const canTransfer = ref(false);

const currentChat = computed(() => getters.getSelectedChat.value);
const accountId = computed(() => getters.getCurrentAccountId.value);
const hasValidSummary = computed(() =>
  Object.entries(summary.value).every(
    ([key, value]) =>
      value.trim().length > 0 && value.length <= SUMMARY_LIMITS[key]
  )
);

const isVisible = computed(() => {
  if (!connectaTransferEnabled) return false;
  if (connectaHumanNumberEnabled && !canTransfer.value) return false;

  const status = currentChat.value?.status;
  return (
    status === wootConstants.STATUS_TYPE.OPEN ||
    status === wootConstants.STATUS_TYPE.PENDING
  );
});

watch(
  () => currentChat.value?.id,
  async conversationId => {
    canTransfer.value = !connectaHumanNumberEnabled;
    if (!connectaHumanNumberEnabled || !conversationId) return;
    try {
      const { data } = await conversationAPI.showConnectaScope(conversationId);
      canTransfer.value = data.can_transfer === true;
    } catch (_) {
      canTransfer.value = false;
    }
  },
  { immediate: true }
);

const destinationOptions = computed(() =>
  destinations.value.map(destination => ({
    value:
      destination.id || destination.departmentId || destination.department_id,
    label:
      destination.name ||
      destination.display_name ||
      destination.displayName ||
      destination.code,
  }))
);

const selectedDestinationName = computed(() => {
  const destination = destinations.value.find(
    item =>
      (item.id || item.departmentId || item.department_id) ===
      selectedDepartmentId.value
  );

  return (
    destination?.name ||
    destination?.display_name ||
    destination?.displayName ||
    destination?.code ||
    ''
  );
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
  summary.value = { subject: '', completed: '', nextAction: '' };
  destinations.value = [];
  loadError.value = false;
  dialogRef.value?.open();
  await nextTick();
  fetchDestinations();
};

const handleConfirm = async () => {
  if (!selectedDepartmentId.value) return;
  if (connectaHumanNumberEnabled && !hasValidSummary.value) return;

  isLoading.value = true;

  try {
    const { data } = await conversationAPI.createConnectaTransfer(
      currentChat.value.id,
      connectaHumanNumberEnabled
        ? {
            targetOrgUnitId: selectedDepartmentId.value,
            summary: {
              subject: summary.value.subject.trim(),
              completed: summary.value.completed.trim(),
              nextAction: summary.value.nextAction.trim(),
            },
          }
        : { targetDepartmentId: selectedDepartmentId.value }
    );

    store.commit(types.CHANGE_CONVERSATION_STATUS, {
      conversationId: currentChat.value.id,
      status: wootConstants.STATUS_TYPE.RESOLVED,
      snoozedUntil: null,
    });

    useAlert(
      t(
        connectaHumanNumberEnabled
          ? 'CONVERSATION.TRANSFER.AWAITING_ACTIVATION'
          : 'CONVERSATION.TRANSFER.SUCCESS'
      )
    );
    dialogRef.value?.close();

    // A transferência muda o vínculo/setor da conversa sem necessariamente
    // mudar o display_id na lista; invalida e refaz a busca no escopo atual.
    store.dispatch('connectaMetadata/refresh', currentChat.value.id);

    const newConversationId = connectaHumanNumberEnabled
      ? null
      : data.display_id || data.new_conversation_id;
    if (newConversationId) {
      if (Number(newConversationId) !== Number(currentChat.value.id)) {
        store.dispatch('connectaMetadata/refresh', newConversationId);
      }
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
      :disable-confirm-button="
        !selectedDepartmentId ||
        isLoadingDestinations ||
        (connectaHumanNumberEnabled && !hasValidSummary)
      "
      :is-loading="isLoading"
      overflow-visible
      @confirm="handleConfirm"
    >
      <div class="flex flex-col gap-4">
        <!-- [&>button]: fills the ComboBox trigger like form-textarea -->
        <ComboBox
          v-model="selectedDepartmentId"
          class="[&>button]:bg-n-alpha-black2"
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
        <div v-if="connectaHumanNumberEnabled" class="flex flex-col gap-3">
          <p class="text-sm text-n-amber-11">
            {{ t('CONVERSATION.TRANSFER.SUMMARY.HISTORY_WARNING') }}
          </p>
          <label class="flex flex-col gap-1 text-sm text-n-slate-12">
            {{ t('CONVERSATION.TRANSFER.SUMMARY.SUBJECT') }}
            <textarea
              v-model="summary.subject"
              class="form-textarea"
              :maxlength="SUMMARY_LIMITS.subject"
              required
              rows="3"
            />
          </label>
          <label class="flex flex-col gap-1 text-sm text-n-slate-12">
            {{ t('CONVERSATION.TRANSFER.SUMMARY.COMPLETED') }}
            <textarea
              v-model="summary.completed"
              class="form-textarea"
              :maxlength="SUMMARY_LIMITS.completed"
              required
              rows="3"
            />
          </label>
          <label class="flex flex-col gap-1 text-sm text-n-slate-12">
            {{ t('CONVERSATION.TRANSFER.SUMMARY.NEXT_ACTION') }}
            <textarea
              v-model="summary.nextAction"
              class="form-textarea"
              :maxlength="SUMMARY_LIMITS.nextAction"
              required
              rows="3"
            />
          </label>
        </div>
      </div>
    </Dialog>
  </div>
</template>
