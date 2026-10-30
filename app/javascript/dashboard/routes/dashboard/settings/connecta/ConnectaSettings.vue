<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import connectaAPI from 'dashboard/api/connecta';
import Button from 'dashboard/components-next/button/Button.vue';

const { t } = useI18n();
const code = ref('');
const isSubmitting = ref(false);
const isLoadingDispatches = ref(false);
const dispatches = ref([]);
const connectorMessageIds = ref({});

const canSubmitLink = computed(
  () => code.value.trim().length > 0 && !isSubmitting.value
);

const linkIdentity = async () => {
  if (!canSubmitLink.value) return;
  isSubmitting.value = true;
  try {
    await connectaAPI.confirmIdentityLink(code.value.trim());
    code.value = '';
    useAlert(t('CONNECTA.SETTINGS.LINK_SUCCESS'));
  } catch (error) {
    useAlert(error.response?.data?.error || t('CONNECTA.SETTINGS.LINK_ERROR'));
  } finally {
    isSubmitting.value = false;
  }
};

const fetchDispatches = async () => {
  isLoadingDispatches.value = true;
  try {
    const { data } = await connectaAPI.getOutboundDispatches();
    dispatches.value = data.dispatches || [];
  } catch (error) {
    if (error.response?.status !== 403) {
      useAlert(
        error.response?.data?.error || t('CONNECTA.SETTINGS.DISPATCH_ERROR')
      );
    }
  } finally {
    isLoadingDispatches.value = false;
  }
};

const resolveDispatch = async (dispatch, state) => {
  try {
    await connectaAPI.resolveOutboundDispatch(dispatch.id, {
      state,
      connectorMessageId: connectorMessageIds.value[dispatch.id],
    });
    await fetchDispatches();
  } catch (error) {
    useAlert(
      error.response?.data?.error || t('CONNECTA.SETTINGS.DISPATCH_ERROR')
    );
  }
};

onMounted(fetchDispatches);
</script>

<template>
  <main class="flex flex-col gap-6 p-6">
    <section class="flex flex-col gap-3 rounded-xl border border-n-weak p-5">
      <h2 class="text-base font-medium text-n-slate-12">
        {{ t('CONNECTA.SETTINGS.LINK_TITLE') }}
      </h2>
      <p class="text-sm text-n-slate-11">
        {{ t('CONNECTA.SETTINGS.LINK_DESCRIPTION') }}
      </p>
      <div class="flex flex-wrap gap-2">
        <input
          v-model="code"
          class="form-input min-w-64"
          maxlength="64"
          autocomplete="one-time-code"
          :aria-label="t('CONNECTA.SETTINGS.LINK_CODE')"
        />
        <Button
          :label="t('CONNECTA.SETTINGS.LINK_ACTION')"
          :is-loading="isSubmitting"
          :disabled="!canSubmitLink"
          @click="linkIdentity"
        />
      </div>
    </section>

    <section class="flex flex-col gap-3 rounded-xl border border-n-weak p-5">
      <div class="flex items-center justify-between gap-3">
        <div>
          <h2 class="text-base font-medium text-n-slate-12">
            {{ t('CONNECTA.SETTINGS.DISPATCH_TITLE') }}
          </h2>
          <p class="text-sm text-n-slate-11">
            {{ t('CONNECTA.SETTINGS.DISPATCH_DESCRIPTION') }}
          </p>
        </div>
        <Button
          :label="t('CONNECTA.SETTINGS.REFRESH')"
          variant="ghost"
          :is-loading="isLoadingDispatches"
          @click="fetchDispatches"
        />
      </div>
      <p v-if="!dispatches.length" class="text-sm text-n-slate-10">
        {{ t('CONNECTA.SETTINGS.NO_DISPATCHES') }}
      </p>
      <article
        v-for="dispatch in dispatches"
        :key="dispatch.id"
        class="flex flex-col gap-2 rounded-lg bg-n-surface-2 p-4"
      >
        <p class="text-sm text-n-slate-12">
          {{
            t('CONNECTA.SETTINGS.DISPATCH_ROW', {
              conversation: dispatch.conversation_id,
              state: dispatch.state,
            })
          }}
        </p>
        <input
          v-if="dispatch.state === 'uncertain'"
          v-model="connectorMessageIds[dispatch.id]"
          class="form-input"
          :placeholder="t('CONNECTA.SETTINGS.CONNECTOR_ID')"
        />
        <div v-if="dispatch.state === 'uncertain'" class="flex gap-2">
          <Button
            :label="t('CONNECTA.SETTINGS.CONFIRM_ACCEPTED')"
            :disabled="!connectorMessageIds[dispatch.id]"
            @click="resolveDispatch(dispatch, 'accepted')"
          />
          <Button
            :label="t('CONNECTA.SETTINGS.CONFIRM_FAILED')"
            color="slate"
            @click="resolveDispatch(dispatch, 'failed')"
          />
        </div>
      </article>
    </section>
  </main>
</template>
