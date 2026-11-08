<script setup>
import { reactive, ref, computed, onMounted, onUnmounted, watch } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { useRouter, useRoute } from 'vue-router';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useInboxSignatures } from 'dashboard/composables/useInboxSignatures';
import { useAlert } from 'dashboard/composables';
import { parseAPIErrorResponse } from 'dashboard/store/utils/api';
import { ExceptionWithMessage } from 'shared/helpers/CustomErrors';
import { debounce } from '@chatwoot/utils';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import {
  createContactSearcher,
  createNewContact,
  fetchContactableInboxes,
  followUpPendingMessage,
  processContactableInboxes,
  mergeInboxDetails,
  runNativeConversation,
  sendFollowUpBatch,
  withFollowUpRetry,
} from 'dashboard/components-next/NewConversation/helpers/composeConversationHelper';
import { frontendURL, conversationUrl } from 'dashboard/helper/URLHelper';
import { pendingGroupNavigation } from 'dashboard/helper/pendingGroupNavigation';

import Popover from 'dashboard/components-next/popover/Popover.vue';
import connectaAPI from 'dashboard/api/connecta';
import ComposeNewConversationForm from 'dashboard/components-next/NewConversation/components/ComposeNewConversationForm.vue';
import ComposeNewGroupForm from 'dashboard/components-next/NewConversation/components/ComposeNewGroupForm.vue';
import ConnectaSectorPicker from 'dashboard/components-next/NewConversation/components/ConnectaSectorPicker.vue';

const props = defineProps({
  contactId: {
    type: String,
    default: null,
  },
  align: {
    type: String,
    default: 'end',
  },
});

const emit = defineEmits(['close']);

const searchContacts = createContactSearcher();
const store = useStore();
const { t } = useI18n();
const router = useRouter();
const route = useRoute();

const { fetchSignatureFlagFromUISettings } = useUISettings();

const popoverRef = ref(null);
const contacts = ref([]);
const selectedContact = ref(null);
const targetInbox = ref(null);
const isCreatingContact = ref(false);
const isFetchingInboxes = ref(false);
const isSearching = ref(false);
const composeMode = ref('conversation');
const groupFormRef = ref(null);

// Admissão manual Baileys (micro passo 3): modal de setor + envio via endpoint
// dedicado. Texto/anexos preservados: nada é limpo até o sucesso.
const showSectorPicker = ref(false);
const sectorDestinations = ref([]);
const sectorReuseInfo = ref(null);
const pendingAdmissionPayload = ref(null);
const admissionAttemptKey = ref(null);
const isAdmitting = ref(false);
// Caminho nativo: a conversa e a primeira mensagem já foram criadas; só os
// anexos de acompanhamento ficaram pendentes. Nunca reentra no create.
const nativePartial = ref(null);

const isBaileysMarkedInbox = computed(() => {
  const inbox = targetInbox.value;
  return (
    inbox?.channelType === 'Channel::Whatsapp' && inbox?.provider === 'baileys'
  );
});

const formState = reactive({
  message: '',
  subject: '',
  ccEmails: '',
  bccEmails: '',
  attachedFiles: [],
});

// O nonce é estável apenas enquanto o rascunho não muda: retry do mesmo
// conteúdo deduplica; conteúdo/anexo novo depois de uma falha ganha nonce novo
// e não pode retornar a mensagem anterior. Não regenera durante o envio.
watch(
  () => [formState.message, formState.attachedFiles],
  () => {
    if (!isAdmitting.value) admissionAttemptKey.value = null;
  },
  { deep: true }
);

const clearFormState = () => {
  Object.assign(formState, {
    subject: '',
    ccEmails: '',
    bccEmails: '',
    attachedFiles: [],
  });
};

const contactById = useMapGetter('contacts/getContactById');
const contactsUiFlags = useMapGetter('contacts/getUIFlags');
const currentUser = useMapGetter('getCurrentUser');
const globalConfig = useMapGetter('globalConfig/get');
const uiFlags = useMapGetter('contactConversations/getUIFlags');
const messageSignature = useMapGetter('getMessageSignature');
const inboxesList = useMapGetter('inboxes/getInboxes');
const groupUiFlags = useMapGetter('groupMembers/getUIFlags');

const groupCreationInboxes = computed(() =>
  inboxesList.value.filter(inbox => inbox.allow_group_creation)
);

const isGroupMode = computed(() => composeMode.value === 'group');
const hasGroupInboxes = computed(() => groupCreationInboxes.value.length > 0);
const isGroupsDisabled = computed(
  () => !globalConfig.value.baileysWhatsappGroupsEnabled
);
const isSuperAdmin = computed(() => currentUser.value.type === 'SuperAdmin');

const {
  fetchInboxSignatures,
  getSignatureForInbox,
  getSignatureSettingsForInbox,
} = useInboxSignatures();

fetchInboxSignatures();

const resolvedMessageSignature = computed(() => {
  if (!targetInbox.value?.id) return messageSignature.value;
  return getSignatureForInbox(targetInbox.value.id);
});

const resolvedSignatureSettings = computed(() => {
  if (!targetInbox.value?.id) return null;
  return getSignatureSettingsForInbox(targetInbox.value.id);
});

const sendWithSignature = computed(() =>
  fetchSignatureFlagFromUISettings(targetInbox.value?.channelType)
);

const directUploadsEnabled = computed(
  () => globalConfig.value.directUploadsEnabled
);

const activeContact = computed(() => contactById.value(props.contactId));

const conversationPath = conversation =>
  frontendURL(
    conversationUrl({
      accountId: conversation.account_id || route.params.accountId,
      id: conversation.id,
    })
  );

const partialConversationPath = computed(() => {
  const conversation = nativePartial.value?.conversation;
  return conversation ? conversationPath(conversation) : null;
});

const samePartialContext = () => {
  const partial = nativePartial.value;
  if (!partial) return true;

  return (
    String(partial.scope.accountId) === String(route.params.accountId) &&
    String(partial.scope.contactId) === String(selectedContact.value?.id) &&
    String(partial.scope.inboxId) === String(targetInbox.value?.id)
  );
};

const samePartialTarget = payload => {
  const partial = nativePartial.value;
  if (!partial) return false;

  return (
    String(partial.scope.accountId) === String(route.params.accountId) &&
    String(partial.scope.contactId) ===
      String(payload.contactId || payload.contact_id) &&
    String(partial.scope.inboxId) ===
      String(payload.inboxId || payload.inbox_id)
  );
};

const forgetNativePartial = ({ notify = false } = {}) => {
  const partial = nativePartial.value;
  if (!partial) return;
  nativePartial.value = null;
  if (!notify) return;

  useAlert(t('CONNECTA.MANUAL_ADMISSION.PARTIAL_ABANDONED'), {
    type: 'link',
    to: conversationPath(partial.conversation),
    message: t('CONNECTA.MANUAL_ADMISSION.OPEN_CONVERSATION'),
  });
};

// O parcial nativo só vale para o MESMO atendimento (conta+contato+inbox).
// Trocar de contexto/novo atendimento descarta a fila com aviso explícito;
// alterar apenas o rascunho preserva a fila para o retry.
watch(
  () => [
    route.params.accountId,
    selectedContact.value?.id,
    targetInbox.value?.id,
  ],
  () => {
    if (nativePartial.value && !samePartialContext()) {
      forgetNativePartial({ notify: true });
    }
  }
);

const resetContacts = () => {
  contacts.value = [];
};

const onContactSearch = debounce(
  async query => {
    isSearching.value = true;
    contacts.value = [];
    try {
      const results = await searchContacts(query);
      // null means the request was aborted (a newer search is in-flight),
      if (results === null) return;
      contacts.value = results;
      isSearching.value = false;
    } catch (error) {
      isSearching.value = false;
      useAlert(t('COMPOSE_NEW_CONVERSATION.CONTACT_SEARCH.ERROR_MESSAGE'));
    }
  },
  400,
  false
);

const handleSelectedContact = async ({ value, action, ...rest }) => {
  let contact;
  if (action === 'create') {
    isCreatingContact.value = true;
    try {
      contact = await createNewContact(value);
      isCreatingContact.value = false;
    } catch (error) {
      isCreatingContact.value = false;
      const message = parseAPIErrorResponse(error);
      useAlert(
        typeof message === 'string'
          ? message
          : t('COMPOSE_NEW_CONVERSATION.CONTACT_CREATE.ERROR_MESSAGE')
      );
      return;
    }
  } else {
    contact = rest;
  }
  selectedContact.value = contact;
  contacts.value = [];
  if (contact?.id) {
    isFetchingInboxes.value = true;
    try {
      const contactableInboxes = await fetchContactableInboxes(contact.id);
      // Merge the processed contactableInboxes with the inboxesList
      selectedContact.value.contactInboxes = mergeInboxDetails(
        contactableInboxes,
        inboxesList.value
      );

      isFetchingInboxes.value = false;
    } catch (error) {
      isFetchingInboxes.value = false;
    }
  }
};

const handleTargetInbox = inbox => {
  targetInbox.value = inbox;
  if (!inbox) clearFormState();
  resetContacts();
};

const clearSelectedContact = () => {
  selectedContact.value = null;
  targetInbox.value = null;
  clearFormState();
};

const closeCompose = () => {
  popoverRef.value?.hide();
};

const discardCompose = () => {
  // Fechar/descartar encerra o attempt: avisa que a conversa existe e que os
  // pendentes não serão reenviados neste ciclo; nunca retry de outro contexto.
  forgetNativePartial({ notify: true });
  clearFormState();
  formState.message = '';
  closeCompose();
};

const switchMode = mode => {
  if (composeMode.value === mode) return;
  composeMode.value = mode;
  selectedContact.value = null;
  targetInbox.value = null;
  clearFormState();
  formState.message = '';
  resetContacts();
  groupFormRef.value?.resetForm();
};

const createGroup = async ({ inboxId, subject, participants }) => {
  try {
    const data = await store.dispatch('groupMembers/createGroup', {
      inbox_id: inboxId,
      subject,
      participants,
    });
    pendingGroupNavigation.set(data.group_jid);
    groupFormRef.value?.resetForm();
    discardCompose();
    useAlert(t('GROUP.CREATE.SUCCESS_MESSAGE'));
  } catch {
    useAlert(t('GROUP.CREATE.ERROR_MESSAGE'));
  }
};

// The conversation carries the first attachment; anything else the agent picked follows
// it as its own message. Only channels that cannot carry more than one per message get
// here with a non-empty list — see splitAttachmentsForChannel.
// Chained rather than fired together, so the attachments arrive in the order they were
// picked: WhatsApp orders by arrival, and a Promise.all reorders them for the contact.
const sendFollowUpFile = (conversationId, index, file) => {
  const pendingMessage = followUpPendingMessage({
    conversationId,
    index,
    file,
    directUploadsEnabled: directUploadsEnabled.value,
  });

  // O mesmo pending/echo_id e o mesmo nonce nas duas tentativas: a resposta
  // perdida é deduplicada no servidor e a linha otimista é substituída.
  return withFollowUpRetry(() =>
    store.dispatch('sendMessageWithData', pendingMessage)
  );
};

const sendFollowUpFiles = (conversationId, followUpFiles) =>
  followUpFiles.reduce(
    (previous, file, index) =>
      previous.then(() => sendFollowUpFile(conversationId, index, file)),
    Promise.resolve()
  );

const fetchSectorDestinations = async payload => {
  // Destinos são do ATOR (vínculo+grants revalidados no WP), não da conversa:
  // endpoint collection com inbox de contexto (show? autorizada no servidor).
  // Nenhuma conversa é criada aqui — a criação SEM mensagem acontece dentro
  // da transação de admissão no fork, depois da escolha do setor.
  const inboxId = payload.inboxId || payload.inbox_id;
  const { data } = await connectaAPI.admissionDestinationsForInbox(inboxId);
  sectorDestinations.value = data.eligible_org_units || [];
  sectorReuseInfo.value = data.reused_from || null;
  pendingAdmissionPayload.value = payload;
  return sectorDestinations.value;
};

const completeAdmission = data => {
  const action = {
    type: 'link',
    to: `/app/accounts/${data.account_id}/conversations/${data.id}`,
    message: t('COMPOSE_NEW_CONVERSATION.FORM.GO_TO_CONVERSATION'),
  };
  showSectorPicker.value = false;
  pendingAdmissionPayload.value = null;
  sectorDestinations.value = [];
  discardCompose();
  admissionAttemptKey.value = null;
  store.dispatch('connectaMetadata/refresh', data.id);
  useAlert(t('COMPOSE_NEW_CONVERSATION.FORM.SUCCESS_MESSAGE'), action);
};

const closeSectorPicker = () => {
  showSectorPicker.value = false;
  pendingAdmissionPayload.value = null;
};

const sendAdmissionFollowUps = async (data, followUpFiles) => {
  if (!followUpFiles.length) return true;
  try {
    await sendFollowUpFiles(data.id, followUpFiles);
    return true;
  } catch (_) {
    // Draft/nonce/batch preservados: o mesmo attempt key e os mesmos nonces
    // tornam o reenvio idempotente (a mensagem já enviada não duplica).
    useAlert(
      t(
        'CONNECTA.MANUAL_ADMISSION.FOLLOW_UP_ERROR',
        'Atendimento iniciado, mas alguns anexos não foram enviados. Tente novamente; os anexos já enviados não duplicam.'
      )
    );
    return false;
  }
};

const onSectorAdmitted = async data => {
  const followUpFiles = pendingAdmissionPayload.value?.followUpFiles || [];
  showSectorPicker.value = false;
  const followUpsSent = await sendAdmissionFollowUps(data, followUpFiles);
  if (!followUpsSent) {
    showSectorPicker.value = true;
    return;
  }
  completeAdmission(data);
};

const admitWithSector = async (
  payload,
  orgUnitId,
  admissionFiles = [],
  followUpFiles = []
) => {
  if (payload.files?.length && !admissionFiles.length) {
    useAlert(
      t(
        'CONNECTA.MANUAL_ADMISSION.ATTACHMENT_UNAVAILABLE',
        'O anexo não pôde ser preparado. Remova o arquivo e selecione novamente antes de iniciar.'
      )
    );
    return false;
  }
  let data;
  try {
    data = await store.dispatch('contactConversations/createManualAdmission', {
      params: {
        inboxId: payload.inboxId || payload.inbox_id,
        contactId: payload.contactId || payload.contact_id,
        sourceId: payload.sourceId || payload.source_id,
        orgUnitId,
        message: payload.message,
        idempotencyKey: admissionAttemptKey.value,
        files: admissionFiles,
      },
    });
  } catch (error) {
    // Draft/anexos preservados: não limpa o form no erro, só alerta.
    useAlert(
      error instanceof ExceptionWithMessage
        ? error.data
        : t(
            'CONNECTA.MANUAL_ADMISSION.ERROR',
            'Não foi possível iniciar o atendimento. Sua mensagem foi preservada — tente novamente.'
          )
    );
    return false;
  }

  const followUpsSent = await sendAdmissionFollowUps(data, followUpFiles);
  if (!followUpsSent) return false;

  completeAdmission(data);
  return true;
};

// Fluxo Baileys: busca destinos elegíveis; 1 setor admite direto, >1 abre o
// modal, 0 mostra erro acionável. Nonce estável por attempt evita duplicar a
// primeira mensagem em double-click/retry (dedupe server por source_id).
const createBaileysConversation = async (
  payload,
  followUpFiles = [],
  admissionFiles = []
) => {
  if (!admissionAttemptKey.value) {
    admissionAttemptKey.value = `attempt-${Date.now()}-${Math.random().toString(36).slice(2, 10)}`;
  }
  if (payload.files?.length && !admissionFiles.length) {
    useAlert(
      t(
        'CONNECTA.MANUAL_ADMISSION.ATTACHMENT_UNAVAILABLE',
        'O anexo não pôde ser preparado. Remova o arquivo e selecione novamente antes de iniciar.'
      )
    );
    return false;
  }
  isAdmitting.value = true;
  try {
    const destinations = await fetchSectorDestinations(payload);
    if (!destinations.length) {
      useAlert(
        t(
          'CONNECTA.MANUAL_ADMISSION.NO_ELIGIBLE_UNIT',
          'Você não tem setor com permissão de atendimento. Fale com seu gestor.'
        )
      );
      return false;
    }
    if (destinations.length === 1) {
      return admitWithSector(
        payload,
        destinations[0].id,
        admissionFiles,
        followUpFiles
      );
    }
    pendingAdmissionPayload.value = {
      ...payload,
      admissionFiles,
      followUpFiles,
    };
    showSectorPicker.value = true;
    return true;
  } catch (error) {
    useAlert(
      error instanceof ExceptionWithMessage
        ? error.data
        : t('COMPOSE_NEW_CONVERSATION.FORM.ERROR_MESSAGE')
    );
    return false;
  } finally {
    isAdmitting.value = false;
  }
};

const partialToastAction = conversation => ({
  type: 'link',
  to: conversationPath(conversation),
  message: t('CONNECTA.MANUAL_ADMISSION.OPEN_CONVERSATION'),
});

const retryNativeFollowUps = async () => {
  const partial = nativePartial.value;
  if (!partial) return false;

  const pending = await sendFollowUpBatch({
    conversationId: partial.conversation.id,
    items: partial.pending,
    send: sendFollowUpFile,
  });

  if (pending.length) {
    nativePartial.value = { ...partial, pending };
    useAlert(
      t('CONNECTA.MANUAL_ADMISSION.PARTIAL_SUCCESS', {
        count: pending.length,
      }),
      partialToastAction(partial.conversation)
    );
    return false;
  }

  nativePartial.value = null;
  discardCompose();
  useAlert(t('COMPOSE_NEW_CONVERSATION.FORM.SUCCESS_MESSAGE'), {
    type: 'link',
    to: conversationPath(partial.conversation),
    message: t('COMPOSE_NEW_CONVERSATION.FORM.GO_TO_CONVERSATION'),
  });
  return true;
};

const createConversation = async ({
  payload,
  followUpFiles = [],
  admissionFiles = [],
  isFromWhatsApp,
}) => {
  // Partial success nativo: a conversa e a primeira mensagem já existem. Um
  // novo submit nunca pode chamar create de novo (segunda conversa ou reenvio
  // da primeira mensagem). O retry é a ação explícita dos anexos pendentes.
  // Um parcial de OUTRO atendimento não bloqueia este: descarta com aviso.
  if (nativePartial.value) {
    if (samePartialTarget(payload)) {
      useAlert(t('CONNECTA.MANUAL_ADMISSION.PARTIAL_BLOCKED'));
      return false;
    }
    forgetNativePartial({ notify: true });
  }
  // Inbox Baileys marcada: resolve setores ANTES de enviar (1 auto, >1 modal,
  // 0 erro acionável). Nunca envia no POST nativo antes da admissão.
  if (isBaileysMarkedInbox.value && !payload?.skipConnectaAdmission) {
    return createBaileysConversation(payload, followUpFiles, admissionFiles);
  }
  try {
    const { conversation, pending } = await runNativeConversation({
      payload,
      followUpFiles,
      isFromWhatsApp,
      create: createPayload =>
        store.dispatch('contactConversations/create', {
          params: createPayload.payload,
          isFromWhatsApp: createPayload.isFromWhatsApp,
        }),
      sendFollowUp: sendFollowUpFile,
    });
    if (pending.length) {
      nativePartial.value = {
        conversation,
        pending,
        scope: {
          accountId: route.params.accountId,
          contactId: payload.contactId || payload.contact_id,
          inboxId: payload.inboxId || payload.inbox_id,
        },
      };
      useAlert(
        t('CONNECTA.MANUAL_ADMISSION.PARTIAL_SUCCESS', {
          count: pending.length,
        }),
        partialToastAction(conversation)
      );
      return true;
    }
    const action = {
      type: 'link',
      to: conversationPath(conversation),
      message: t('COMPOSE_NEW_CONVERSATION.FORM.GO_TO_CONVERSATION'),
    };
    discardCompose();
    useAlert(t('COMPOSE_NEW_CONVERSATION.FORM.SUCCESS_MESSAGE'), action);
    return true; // Return success
  } catch (error) {
    useAlert(
      error instanceof ExceptionWithMessage
        ? error.data
        : t('COMPOSE_NEW_CONVERSATION.FORM.ERROR_MESSAGE')
    );
    return false; // Return failure
  }
};

const onPopoverShow = () => {
  // Flag to prevent triggering drag n drop while compose is open
  emitter.emit(BUS_EVENTS.NEW_CONVERSATION_MODAL, true);
  // Cache-aware refetch, so newly synced WhatsApp templates show up here
  // even if the account-cache-invalidated websocket event was missed.
  store.dispatch('inboxes/get');
};

const onPopoverHide = () => {
  if (nativePartial.value) forgetNativePartial({ notify: true });
  composeMode.value = 'conversation';
  if (!props.contactId) {
    selectedContact.value = null;
  }
  targetInbox.value = null;
  resetContacts();
  groupFormRef.value?.resetForm();
  emitter.emit(BUS_EVENTS.NEW_CONVERSATION_MODAL, false);
  emit('close');
};

watch(
  activeContact,
  (currentContact, previousContact) => {
    if (currentContact && props.contactId) {
      // Reset on contact change
      if (currentContact?.id !== previousContact?.id) {
        clearSelectedContact();
        clearFormState();
        formState.message = '';
      }

      // First process the contactable inboxes to get the right structure
      const processedInboxes = processContactableInboxes(
        currentContact.contactInboxes || []
      );
      // Then Merge processedInboxes with the inboxes list
      selectedContact.value = {
        ...currentContact,
        contactInboxes: mergeInboxDetails(processedInboxes, inboxesList.value),
      };
    }
  },
  { immediate: true, deep: true }
);

const navigateToGroup = ({ conversationId }) => {
  const url = frontendURL(
    conversationUrl({
      accountId: route.params.accountId,
      id: conversationId,
    })
  );
  router.push({ path: url });
};

onMounted(() => {
  resetContacts();
  emitter.on(BUS_EVENTS.NAVIGATE_TO_GROUP, navigateToGroup);
});

onUnmounted(() => {
  emitter.off(BUS_EVENTS.NAVIGATE_TO_GROUP, navigateToGroup);
});
</script>

<template>
  <Popover
    ref="popoverRef"
    :align="align"
    :show-content-border="false"
    :close-on-scroll="false"
    @show="onPopoverShow"
    @hide="onPopoverHide"
  >
    <template #default="{ isOpen }">
      <slot name="trigger" :is-open="isOpen" />
    </template>
    <template #content>
      <div class="w-full md:w-[42rem] flex flex-col min-w-0">
        <div
          v-if="hasGroupInboxes"
          class="flex gap-1 px-4 pt-3 pb-0 bg-n-alpha-3 border border-b-0 border-n-strong backdrop-blur-[100px] rounded-t-xl"
        >
          <button
            class="px-3 py-1.5 text-sm font-medium rounded-t-lg border-b-2 transition-colors"
            :class="
              !isGroupMode
                ? 'text-n-brand border-n-brand bg-n-alpha-2'
                : 'text-n-slate-11 border-transparent hover:text-n-slate-12'
            "
            @click="switchMode('conversation')"
          >
            {{ t('COMPOSE_NEW_CONVERSATION.TAB_CONVERSATION') }}
          </button>
          <button
            class="px-3 py-1.5 text-sm font-medium rounded-t-lg border-b-2 transition-colors"
            :class="
              isGroupMode
                ? 'text-n-brand border-n-brand bg-n-alpha-2'
                : 'text-n-slate-11 border-transparent hover:text-n-slate-12'
            "
            @click="switchMode('group')"
          >
            {{ t('COMPOSE_NEW_CONVERSATION.TAB_GROUP') }}
          </button>
        </div>
        <div
          v-if="!isGroupMode && nativePartial"
          class="mx-4 mt-3 rounded-lg border border-n-amber-7 bg-n-amber-2 p-3 text-sm text-n-slate-12"
        >
          <p>
            {{
              t('CONNECTA.MANUAL_ADMISSION.PARTIAL_SUCCESS', {
                count: nativePartial.pending.length,
              })
            }}
          </p>
          <div class="mt-2 flex flex-wrap items-center gap-3">
            <button
              type="button"
              class="font-medium text-n-brand"
              @click="retryNativeFollowUps"
            >
              {{ t('CONNECTA.MANUAL_ADMISSION.RETRY_ATTACHMENTS') }}
            </button>
            <router-link
              v-if="partialConversationPath"
              :to="partialConversationPath"
              class="font-medium text-n-blue-10"
              @click="forgetNativePartial()"
            >
              {{ t('CONNECTA.MANUAL_ADMISSION.OPEN_CONVERSATION') }}
            </router-link>
          </div>
        </div>
        <ComposeNewConversationForm
          v-if="!isGroupMode"
          :form-state="formState"
          :class="{ '!rounded-t-none !border-t-0': hasGroupInboxes }"
          :contacts="contacts"
          :contact-id="contactId"
          :is-loading="isSearching"
          :current-user="currentUser"
          :selected-contact="selectedContact"
          :target-inbox="targetInbox"
          :is-creating-contact="isCreatingContact"
          :is-fetching-inboxes="isFetchingInboxes"
          :is-direct-uploads-enabled="directUploadsEnabled"
          :contact-conversations-ui-flags="uiFlags"
          :contacts-ui-flags="contactsUiFlags"
          :message-signature="resolvedMessageSignature"
          :send-with-signature="sendWithSignature"
          :signature-settings="resolvedSignatureSettings"
          @search-contacts="onContactSearch"
          @reset-contact-search="resetContacts"
          @update-selected-contact="handleSelectedContact"
          @update-target-inbox="handleTargetInbox"
          @clear-selected-contact="clearSelectedContact"
          @create-conversation="createConversation"
          @discard="discardCompose"
        />
        <ComposeNewGroupForm
          v-else
          ref="groupFormRef"
          class="!rounded-t-none !border-t-0"
          :inboxes="groupCreationInboxes"
          :is-creating="groupUiFlags.isCreating"
          :is-groups-disabled="isGroupsDisabled"
          :is-super-admin="isSuperAdmin"
          @create-group="createGroup"
          @discard="discardCompose"
        />
        <ConnectaSectorPicker
          :show="showSectorPicker"
          :inbox-id="
            pendingAdmissionPayload?.inboxId ||
            pendingAdmissionPayload?.inbox_id ||
            null
          "
          :contact-id="
            pendingAdmissionPayload?.contactId ||
            pendingAdmissionPayload?.contact_id ||
            null
          "
          :source-id="
            pendingAdmissionPayload?.sourceId ||
            pendingAdmissionPayload?.source_id ||
            null
          "
          :message="pendingAdmissionPayload?.message || null"
          :idempotency-key="admissionAttemptKey"
          :files="pendingAdmissionPayload?.admissionFiles || []"
          :units="sectorDestinations"
          :reuse-info="sectorReuseInfo"
          :title="t('CONNECTA.MANUAL_ADMISSION.TITLE')"
          @close="closeSectorPicker"
          @admitted="onSectorAdmitted"
        />
      </div>
    </template>
  </Popover>
</template>
