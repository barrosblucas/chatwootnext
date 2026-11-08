<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { frontendURL, conversationUrl } from 'dashboard/helper/URLHelper';
import ConnectaAPI from 'dashboard/api/connecta';
import { connectaLabel } from 'dashboard/helper/connectaLabel';

const props = defineProps({
  show: { type: Boolean, default: false },
  protocol: { type: String, default: '' },
  currentConversationId: { type: [Number, String], default: null },
});

const emit = defineEmits(['close']);

const { t, te } = useI18n();
const router = useRouter();
const accountId = useMapGetter('getCurrentAccountId');
const stages = ref([]);
const isLoading = ref(false);
const error = ref(null);

const title = computed(() => t('CONNECTA.PROTOCOL.TITLE'));
const hasStages = computed(() => stages.value.length > 0);

const load = async () => {
  if (!props.show || !props.protocol) return;
  isLoading.value = true;
  error.value = null;
  try {
    const { data } = await ConnectaAPI.getProtocol(props.protocol);
    stages.value = data?.stages || [];
  } catch (_) {
    stages.value = [];
    error.value = t('CONNECTA.PROTOCOL.LOAD_ERROR');
  } finally {
    isLoading.value = false;
  }
};

const stateLabel = value => {
  const key = `CONNECTA.PROTOCOL.STATES.${value}`;
  return te(key) ? t(key) : value;
};

const stageLabel = stage =>
  connectaLabel(
    {
      root_unit_name: stage.root_unit_name,
      org_unit_name: stage.org_unit_name,
    },
    stage.assignee_name
  );

const isCurrent = stage =>
  String(stage.conversation_id) === String(props.currentConversationId);

const openStage = stage => {
  router.push(
    frontendURL(
      conversationUrl({
        accountId: accountId.value,
        id: stage.conversation_id,
      })
    )
  );
  emit('close');
};

const close = () => emit('close');

const onKeydown = event => {
  if (event.key === 'Escape' && props.show) close();
};

watch(() => [props.show, props.protocol], load, { immediate: true });

onMounted(() => document.addEventListener('keydown', onKeydown));
onBeforeUnmount(() => document.removeEventListener('keydown', onKeydown));
</script>

<template>
  <div
    v-if="show"
    class="fixed inset-0 z-50 flex items-start justify-center p-4 bg-n-alpha-black2"
    role="dialog"
    aria-modal="true"
    :aria-label="title"
    @click.self="close"
  >
    <div class="w-full max-w-2xl mt-12 overflow-hidden rounded-xl bg-n-solid-2 shadow-xl">
      <header class="flex items-center justify-between gap-3 border-b border-n-weak px-4 py-3">
        <div class="min-w-0">
          <h3 class="truncate text-base font-medium text-n-slate-12">
            {{ title }}
          </h3>
          <p class="mt-0.5 truncate font-mono text-xs text-n-slate-11">
            {{ protocol }}
          </p>
        </div>
        <button
          type="button"
          class="rounded-md p-1 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
          :aria-label="t('CONNECTA.PROTOCOL.CLOSE')"
          @click="close"
        >
          <span aria-hidden="true">×</span>
        </button>
      </header>

      <div class="max-h-[60vh] overflow-y-auto p-3">
        <p v-if="isLoading" class="px-2 py-4 text-sm text-n-slate-11">
          {{ t('CONNECTA.PROTOCOL.LOADING') }}
        </p>
        <p v-else-if="error" class="px-2 py-4 text-sm text-n-ruby-11">
          {{ error }}
        </p>
        <p v-else-if="!hasStages" class="px-2 py-4 text-sm text-n-slate-11">
          {{ t('CONNECTA.PROTOCOL.EMPTY') }}
        </p>
        <ul v-else class="space-y-2">
          <li v-for="stage in stages" :key="stage.conversation_id">
            <button
              type="button"
              class="flex w-full flex-col gap-1 rounded-lg border px-3 py-2 text-left transition-colors"
              :class="
                isCurrent(stage)
                  ? 'border-n-brand bg-n-brand/10'
                  : 'border-n-weak hover:bg-n-alpha-1'
              "
              :aria-current="isCurrent(stage) ? 'true' : undefined"
              @click="openStage(stage)"
            >
              <span class="flex min-w-0 items-center gap-2">
                <span class="font-mono text-xs text-n-slate-11">
                  #{{ stage.conversation_id }}
                </span>
                <span class="truncate text-sm font-medium text-n-slate-12">
                  {{ stageLabel(stage) }}
                </span>
                <span
                  v-if="isCurrent(stage)"
                  class="ml-auto rounded-full bg-n-brand/15 px-2 py-0.5 text-xs text-n-brand"
                >
                  {{ t('CONNECTA.PROTOCOL.CURRENT') }}
                </span>
              </span>
              <span class="text-xs text-n-slate-11">
                {{ stateLabel(stage.state) }}
                <template v-if="stage.assignee_name">
                  · {{ stage.assignee_name }}
                </template>
              </span>
            </button>
          </li>
        </ul>
      </div>
    </div>
  </div>
</template>
