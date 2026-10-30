<script setup>
import { ref } from 'vue';
import { useI18n } from 'dashboard/composables/i18n';
import connectaAPI from 'dashboard/api/connecta';
import { ExceptionWithMessage } from 'shared/helpers/CustomErrors';

const props = defineProps({
  show: { type: Boolean, default: false },
  inboxId: { type: [Number, String], default: null },
  contactId: { type: [Number, String], default: null },
  sourceId: { type: String, default: null },
  message: { type: Object, default: () => ({}) },
  idempotencyKey: { type: String, default: null },
  title: { type: String, default: '' },
});

const emit = defineEmits(['close', 'admitted', 'error']);

const { t } = useI18n();
const destinations = ref([]);
const selectedUnit = ref(null);
const isLoading = ref(false);
const error = ref(null);
const reuseInfo = ref(null);

const loadDestinations = async conversationId => {
  isLoading.value = true;
  error.value = null;
  try {
    const { data } = await connectaAPI.admissionDestinations(conversationId);
    destinations.value = data.eligible_org_units || [];
    reuseInfo.value = data.reused_from || null;
    if (destinations.value.length === 1) {
      selectedUnit.value = destinations.value[0].id;
    }
    if (destinations.value.length === 0) {
      error.value = t(
        'CONNECTA.MANUAL_ADMISSION.NO_ELIGIBLE_UNIT',
        'Você não tem setor com permissão de atendimento. Fale com seu gestor.'
      );
    }
    return destinations.value;
  } catch (e) {
    error.value =
      e?.response?.data?.error ||
      t(
        'CONNECTA.MANUAL_ADMISSION.LOAD_ERROR',
        'Não foi possível carregar seus setores. Tente novamente.'
      );
    throw e;
  } finally {
    isLoading.value = false;
  }
};

const confirm = async () => {
  if (!selectedUnit.value) {
    error.value = t(
      'CONNECTA.MANUAL_ADMISSION.SELECT_UNIT',
      'Escolha o setor para iniciar o atendimento.'
    );
    return;
  }
  isLoading.value = true;
  error.value = null;
  try {
    const { data } = await connectaAPI.admitConversation({
      inboxId: props.inboxId,
      contactId: props.contactId,
      sourceId: props.sourceId,
      orgUnitId: selectedUnit.value,
      message: props.message,
      idempotencyKey: props.idempotencyKey,
    });
    emit('admitted', data);
  } catch (e) {
    const message =
      e?.response?.data?.error ||
      t(
        'CONNECTA.MANUAL_ADMISSION.ERROR',
        'Não foi possível iniciar o atendimento. Sua mensagem foi preservada — tente novamente.'
      );
    error.value = message;
    emit('error', new ExceptionWithMessage(message));
  } finally {
    isLoading.value = false;
  }
};

const close = () => emit('close');

defineExpose({ loadDestinations });
</script>

<template>
  <div
    v-if="show"
    class="fixed inset-0 z-50 flex items-center justify-center bg-n-black/50"
    @click.self="close"
  >
    <div class="w-full max-w-md rounded-xl bg-n-solid-2 p-6 shadow-xl">
      <h3 class="text-base font-medium text-n-slate-12">
        {{
          title || $t('CONNECTA.MANUAL_ADMISSION.TITLE', 'Iniciar atendimento')
        }}
      </h3>
      <p v-if="reuseInfo" class="mt-1 text-sm text-n-slate-11">
        {{
          $t(
            'CONNECTA.MANUAL_ADMISSION.REUSED',
            'Atendimento existente será reaberto no seu setor.'
          )
        }}
      </p>
      <div
        v-if="isLoading && !destinations.length"
        class="py-4 text-sm text-n-slate-11"
      >
        {{
          $t('CONNECTA.MANUAL_ADMISSION.LOADING', 'Carregando seus setores…')
        }}
      </div>
      <div v-else class="mt-4 space-y-2">
        <button
          v-for="unit in destinations"
          :key="unit.id"
          class="w-full rounded-lg border px-4 py-3 text-left text-sm"
          :class="[
            selectedUnit === unit.id
              ? 'border-n-brand bg-n-brand/10 text-n-slate-12'
              : 'border-n-strong text-n-slate-11 hover:border-n-slate-8',
          ]"
          @click="selectedUnit = unit.id"
        >
          {{ unit.name }}
        </button>
      </div>
      <p v-if="error" class="mt-3 text-sm text-n-ruby-11">{{ error }}</p>
      <div class="mt-5 flex justify-end gap-2">
        <button
          class="rounded-lg px-4 py-2 text-sm text-n-slate-11 hover:bg-n-alpha-2"
          @click="close"
        >
          {{ $t('GENERAL.CANCEL', 'Cancelar') }}
        </button>
        <button
          :disabled="isLoading || !selectedUnit"
          class="rounded-lg bg-n-brand px-4 py-2 text-sm text-white disabled:opacity-50"
          @click="confirm"
        >
          {{
            isLoading
              ? $t('GENERAL.LOADING', 'Enviando…')
              : $t('CONNECTA.MANUAL_ADMISSION.CONFIRM', 'Iniciar')
          }}
        </button>
      </div>
    </div>
  </div>
</template>
