import { describe, it, expect, vi, beforeEach } from 'vitest';
import { nextTick, reactive } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import ComposeConversation from '../../ComposeConversation.vue';

// Gate de wiring do parcial nativo: monta o Compose real, exercita Submit/Enter
// e cliques DOM, e só substitui IO (store/rede/router), composables de ambiente
// e a UI do formulário filho. runNativeConversation, sendFollowUpBatch,
// withFollowUpRetry e os handlers do componente continuam reais.
withFullI18n('en');

const mocks = vi.hoisted(() => ({
  dispatch: vi.fn(),
  alert: vi.fn(),
  push: vi.fn(),
  admissionDestinations: vi.fn(),
  route: { params: { accountId: '7' } },
  getterValues: {
    'contacts/getContactById': id =>
      id === null || id === undefined
        ? null
        : { id: Number(id), name: `Contact ${id}`, contactInboxes: [] },
    'contacts/getUIFlags': { isFetchingInboxes: false },
    getCurrentUser: {
      id: 44,
      type: 'Agent',
      available_name: 'Agent',
      ui_settings: {},
    },
    'globalConfig/get': {
      baileysWhatsappGroupsEnabled: false,
      directUploadsEnabled: false,
    },
    'contactConversations/getUIFlags': { isCreating: false },
    getMessageSignature: '',
    'inboxes/getInboxes': [],
    'groupMembers/getUIFlags': { isCreating: false },
  },
}));

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: mocks.dispatch }),
  useMapGetter: key => ({ value: mocks.getterValues[key] }),
  useStoreGetters: () => ({}),
  useFunctionGetter: () => ({ value: undefined }),
}));

vi.mock('dashboard/composables', async importOriginal => {
  const actual = await importOriginal();
  return {
    ...actual,
    useAlert: (...args) => mocks.alert(...args),
  };
});

vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({
    fetchSignatureFlagFromUISettings: () => false,
  }),
}));

vi.mock('dashboard/composables/useInboxSignatures', () => ({
  useInboxSignatures: () => ({
    fetchInboxSignatures: () => Promise.resolve(),
    getSignatureForInbox: () => '',
    getSignatureSettingsForInbox: () => null,
  }),
}));

vi.mock('dashboard/api/connecta', () => ({
  default: {
    admissionDestinationsForInbox: (...args) =>
      mocks.admissionDestinations(...args),
    admitConversation: vi.fn(),
  },
}));

vi.mock('vue-router', () => ({
  useRouter: () => ({ push: mocks.push }),
  useRoute: () => mocks.route,
}));

const settle = async () => {
  await flushPromises();
  await nextTick();
  await flushPromises();
};

const nativeInbox = (id = 11) => ({
  id,
  name: `WhatsApp ${id}`,
  channelType: 'Channel::Whatsapp',
  provider: 'whatsapp_cloud',
  sourceId: `source-${id}`,
});

const baileysInbox = (id = 55) => ({
  id,
  name: 'Baileys',
  channelType: 'Channel::Whatsapp',
  provider: 'baileys',
  sourceId: `source-${id}`,
});

const makeAttachment = name => ({
  blobSignedId: `signed-${name}`,
  rawFile: { name: `raw-${name}`, kind: 'raw' },
  resource: {
    name: `${name}.txt`,
    size: 100 + name.charCodeAt(0),
    lastModified: 1000 + name.charCodeAt(0),
    file: `raw-${name}`,
  },
});

const makeFiles = (...names) => names.map(makeAttachment);

const followUpNonce = (conversationId, index, name) =>
  `connecta-followup:${conversationId}:${index}:signed-${name}`;

const installStore = ({
  conversationIds = [901],
  accountId = 7,
  send = () => 'ok',
  admission = () => ({ id: 701, account_id: accountId }),
} = {}) => {
  const state = {
    createCount: 0,
    firstMessageCount: 0,
    admissionCount: 0,
  };

  mocks.dispatch.mockImplementation((action, payload) => {
    switch (action) {
      case 'contactConversations/create': {
        const index = Math.min(state.createCount, conversationIds.length - 1);
        const id = conversationIds[index];
        state.createCount += 1;
        // Every create sends the first message again. lock_to_single only
        // changes whether the server reuses the same conversation id.
        state.firstMessageCount += 1;
        return Promise.resolve({ id, account_id: accountId });
      }
      case 'sendMessageWithData':
        return Promise.resolve().then(() => send(payload));
      case 'contactConversations/createManualAdmission':
        state.admissionCount += 1;
        return Promise.resolve().then(() =>
          admission(payload, state.admissionCount)
        );
      case 'connectaMetadata/refresh':
      case 'inboxes/get':
      default:
        return Promise.resolve();
    }
  });

  return state;
};

const callsFor = action =>
  mocks.dispatch.mock.calls.filter(([name]) => name === action);
const createCalls = () => callsFor('contactConversations/create');
const sendCalls = () =>
  callsFor('sendMessageWithData').map(([, payload]) => payload);
const manualAdmissionCalls = () =>
  callsFor('contactConversations/createManualAdmission');
const metadataRefreshCalls = () => callsFor('connectaMetadata/refresh');

const alertFor = fragment =>
  mocks.alert.mock.calls.find(([message]) =>
    String(message).includes(fragment)
  );

const PopoverStub = {
  name: 'Popover',
  emits: ['show', 'hide'],
  data: () => ({ isOpen: false }),
  methods: {
    show() {
      this.isOpen = true;
      this.$emit('show');
    },
    hide() {
      if (!this.isOpen) return;
      this.isOpen = false;
      this.$emit('hide');
    },
    toggle() {
      if (this.isOpen) this.hide();
      else this.show();
    },
  },
  template: `
    <div>
      <button type="button" data-test="popover-trigger" @click="toggle">
        <slot name="trigger" :is-open="isOpen">open</slot>
      </button>
      <div v-if="isOpen" data-test="popover-content">
        <slot name="content" />
      </div>
    </div>
  `,
};

const RouterLinkStub = {
  props: {
    to: { type: [String, Object], required: true },
  },
  computed: {
    href() {
      return typeof this.to === 'string' ? this.to : this.to?.path;
    },
  },
  template: '<a :href="href"><slot /></a>',
};

const SectorPickerStub = {
  name: 'ConnectaSectorPicker',
  props: {
    show: { type: Boolean, default: false },
  },
  template: '<div v-if="show" data-test="sector-picker"></div>',
};

// The child form already has its own specs. Here it is the UI boundary: the
// test drives the same DOM events an agent would and lets the real Compose
// handlers/build the payload boundary.
const createFormStub = ({
  inboxes = [],
  files = [],
  draft = '',
  contactId = 12,
} = {}) => {
  let seeded = false;

  return {
    name: 'ComposeNewConversationForm',
    props: {
      formState: { type: Object, required: true },
      targetInbox: { type: Object, default: null },
      selectedContact: { type: Object, default: null },
    },
    emits: ['createConversation', 'discard', 'updateTargetInbox'],
    data() {
      return { inboxes, contactId };
    },
    mounted() {
      if (seeded) return;
      seeded = true;
      this.formState.message = draft;
    },
    methods: {
      selectInbox(inbox) {
        this.$emit('updateTargetInbox', inbox);
        this.formState.attachedFiles = [];
      },
      attachFiles() {
        this.formState.attachedFiles = files.slice();
      },
      onInput(event) {
        this.formState.message = event.target.value;
      },
      onKeydown(event) {
        if (event.key !== 'Enter' || event.shiftKey) return;
        event.preventDefault();
        this.submit();
      },
      submit() {
        const inbox = this.targetInbox;
        if (!inbox) return;

        const attached = this.formState.attachedFiles || [];
        const first = attached[0];

        this.$emit('createConversation', {
          payload: {
            inboxId: inbox.id,
            sourceId: inbox.sourceId,
            contactId: Number(this.selectedContact?.id || this.contactId),
            message: { content: this.formState.message },
            files: first ? [first.resource.file] : [],
          },
          followUpFiles: attached.slice(1),
          admissionFiles: first ? [first.rawFile || first.resource.file] : [],
          isFromWhatsApp: false,
        });
      },
    },
    template: `
      <form data-test="child-form" @submit.prevent="submit">
        <div>
          <button
            v-for="inbox in inboxes"
            :key="inbox.id"
            type="button"
            :data-test="'select-inbox-' + inbox.id"
            @click="selectInbox(inbox)"
          >
            inbox {{ inbox.id }}
          </button>
          <button type="button" data-test="attach-files" @click="attachFiles">
            attach
          </button>
          <textarea
            data-test="draft"
            :value="formState.message"
            @input="onInput"
            @keydown="onKeydown"
          ></textarea>
          <button type="submit" data-test="submit">send</button>
          <button type="button" data-test="cancel" @click="$emit('discard')">
            cancel
          </button>
        </div>
        <output data-test="draft-value">{{ formState.message }}</output>
        <output data-test="attachment-count">
          {{ formState.attachedFiles.length }}
        </output>
        <output data-test="target-inbox">
          {{ targetInbox ? targetInbox.id : '' }}
        </output>
      </form>
    `,
  };
};

const mountCompose = async ({ contactId = '12', ...options } = {}) => {
  const formStub = createFormStub(options);

  const wrapper = mount(ComposeConversation, {
    props: { contactId },
    global: {
      stubs: {
        Popover: PopoverStub,
        ComposeNewConversationForm: formStub,
        ConnectaSectorPicker: SectorPickerStub,
        RouterLink: RouterLinkStub,
      },
    },
  });

  await settle();
  await wrapper.find('[data-test="popover-trigger"]').trigger('click');
  await settle();

  return wrapper;
};

const openCompose = async wrapper => {
  await wrapper.find('[data-test="popover-trigger"]').trigger('click');
  await settle();
};

const selectInbox = async (wrapper, inboxId) => {
  await wrapper.find(`[data-test="select-inbox-${inboxId}"]`).trigger('click');
  await settle();
};

const attachFiles = async wrapper => {
  await wrapper.find('[data-test="attach-files"]').trigger('click');
  await settle();
};

const submitForm = async wrapper => {
  await wrapper.find('[data-test="child-form"]').trigger('submit');
  await settle();
};

const pressEnter = async wrapper => {
  await wrapper
    .find('[data-test="draft"]')
    .trigger('keydown', { key: 'Enter' });
  await settle();
};

const clickRetry = async wrapper => {
  const button = wrapper
    .findAll('button')
    .find(candidate => candidate.text().includes('Retry pending attachments'));

  expect(button).toBeTruthy();
  await button.trigger('click');
  await settle();
};

const startNativePartial = async (wrapper, inboxId = 11) => {
  await selectInbox(wrapper, inboxId);
  await attachFiles(wrapper);
  await submitForm(wrapper);
};

beforeEach(() => {
  mocks.route = reactive({ params: { accountId: '7' } });
  mocks.dispatch.mockReset();
  mocks.alert.mockReset();
  mocks.push.mockReset();
  mocks.admissionDestinations.mockReset();
  mocks.admissionDestinations.mockResolvedValue({
    data: { eligible_org_units: [] },
  });
});

describe('ComposeConversation native WhatsApp partial retry', () => {
  it('creates once, blocks resubmit/Enter and retries only the pending follow-up', async () => {
    let failSecondFollowUp = true;
    const store = installStore({
      conversationIds: [901],
      send: pending => {
        const nonce = pending.contentAttributes.connecta_followup_nonce;
        return failSecondFollowUp && nonce.includes(':901:1:')
          ? Promise.reject(new Error('offline'))
          : 'ok';
      },
    });

    const wrapper = await mountCompose({
      inboxes: [nativeInbox(11)],
      files: makeFiles('a', 'b', 'c'),
      draft: 'Olá, cidadão',
    });

    await startNativePartial(wrapper);

    expect(store.createCount).toBe(1);
    expect(store.firstMessageCount).toBe(1);
    const createArg = createCalls()[0][1];
    expect(createArg).toMatchObject({
      params: {
        inboxId: 11,
        contactId: 12,
        message: { content: 'Olá, cidadão' },
        files: ['raw-a'],
      },
      isFromWhatsApp: false,
    });

    const initialSends = sendCalls();
    expect(
      initialSends.map(
        pending => pending.contentAttributes.connecta_followup_nonce
      )
    ).toEqual([
      followUpNonce(901, 0, 'b'),
      followUpNonce(901, 1, 'c'),
      followUpNonce(901, 1, 'c'),
    ]);
    // withFollowUpRetry repeats the exact same pending/echo_id.
    expect(initialSends[1].echo_id).toBe(initialSends[2].echo_id);

    expect(wrapper.text()).toContain(
      'Conversation created, but 1 attachment(s) are pending.'
    );
    expect(
      wrapper.find('a[href="/app/accounts/7/conversations/901"]').exists()
    ).toBe(true);
    expect(alertFor('1 attachment(s) are pending')).toBeTruthy();
    expect(wrapper.find('[data-test="draft-value"]').text().trim()).toBe(
      'Olá, cidadão'
    );
    expect(wrapper.find('[data-test="attachment-count"]').text().trim()).toBe(
      '3'
    );

    await wrapper.find('[data-test="draft"]').setValue('Olá editado');
    await pressEnter(wrapper);
    await submitForm(wrapper);

    expect(createCalls()).toHaveLength(1);
    expect(sendCalls()).toHaveLength(3);
    expect(
      alertFor(
        'There are pending attachments. Retry them or open the created conversation.'
      )
    ).toBeTruthy();
    expect(wrapper.find('[data-test="draft-value"]').text().trim()).toBe(
      'Olá editado'
    );
    expect(
      wrapper.find('a[href="/app/accounts/7/conversations/901"]').exists()
    ).toBe(true);

    await clickRetry(wrapper);
    expect(createCalls()).toHaveLength(1);
    expect(sendCalls()).toHaveLength(5);
    expect(
      sendCalls()
        .slice(3)
        .every(pending =>
          pending.contentAttributes.connecta_followup_nonce.includes(':901:1:')
        )
    ).toBe(true);
    expect(wrapper.text()).toContain(
      'Conversation created, but 1 attachment(s) are pending.'
    );

    failSecondFollowUp = false;
    await clickRetry(wrapper);

    expect(store.createCount).toBe(1);
    expect(store.firstMessageCount).toBe(1);
    const finalSends = sendCalls();
    expect(finalSends).toHaveLength(6);
    expect(finalSends[5].contentAttributes.connecta_followup_nonce).toBe(
      followUpNonce(901, 1, 'c')
    );
    expect(
      finalSends.filter(pending =>
        pending.contentAttributes.connecta_followup_nonce.includes(':901:0:')
      )
    ).toHaveLength(1);

    expect(wrapper.find('[data-test="popover-content"]').exists()).toBe(false);
    expect(wrapper.emitted('close')).toBeTruthy();

    const successAlert = alertFor('The message was sent successfully!');
    expect(successAlert).toBeTruthy();
    expect(successAlert[1]).toMatchObject({
      type: 'link',
      to: '/app/accounts/7/conversations/901',
      message: 'View',
    });
    expect(alertFor('pending attachments were not resent')).toBeFalsy();

    await openCompose(wrapper);
    expect(wrapper.text()).not.toContain('Conversation created, but');
    expect(wrapper.find('[data-test="draft-value"]').text().trim()).toBe('');
    expect(wrapper.find('[data-test="attachment-count"]').text().trim()).toBe(
      '0'
    );
    expect(wrapper.find('[data-test="target-inbox"]').text().trim()).toBe('');
  });

  it('recovers a lost follow-up response with the same pending message', async () => {
    let attempts = 0;
    const store = installStore({
      conversationIds: [901],
      send: pending => {
        const nonce = pending.contentAttributes.connecta_followup_nonce;
        if (nonce.includes(':901:1:')) {
          attempts += 1;
          if (attempts === 1) {
            return Promise.reject(new Error('lost response'));
          }
        }
        return 'ok';
      },
    });

    const wrapper = await mountCompose({
      inboxes: [nativeInbox(11)],
      files: makeFiles('a', 'b', 'c'),
      draft: 'Olá, cidadão',
    });

    await startNativePartial(wrapper);

    expect(store.createCount).toBe(1);
    expect(store.firstMessageCount).toBe(1);
    const sends = sendCalls();
    expect(sends).toHaveLength(3);
    expect(sends[1].echo_id).toBe(sends[2].echo_id);
    expect(sends[1].contentAttributes.connecta_followup_nonce).toBe(
      sends[2].contentAttributes.connecta_followup_nonce
    );

    expect(wrapper.text()).not.toContain('Conversation created, but');
    expect(wrapper.find('[data-test="popover-content"]').exists()).toBe(false);
    expect(alertFor('The message was sent successfully!')).toBeTruthy();
  });

  it('preserves the success path when every follow-up succeeds', async () => {
    const store = installStore({
      conversationIds: [901],
      send: () => 'ok',
    });

    const wrapper = await mountCompose({
      inboxes: [nativeInbox(11)],
      files: makeFiles('a', 'b', 'c'),
      draft: 'Olá, cidadão',
    });

    await startNativePartial(wrapper);

    expect(store.createCount).toBe(1);
    expect(store.firstMessageCount).toBe(1);
    expect(
      sendCalls().map(
        pending => pending.contentAttributes.connecta_followup_nonce
      )
    ).toEqual([followUpNonce(901, 0, 'b'), followUpNonce(901, 1, 'c')]);
    expect(wrapper.text()).not.toContain('Conversation created, but');
    expect(wrapper.find('[data-test="popover-content"]').exists()).toBe(false);

    const successAlert = alertFor('The message was sent successfully!');
    expect(successAlert).toBeTruthy();
    expect(successAlert[1]).toMatchObject({
      type: 'link',
      to: '/app/accounts/7/conversations/901',
    });
    expect(wrapper.emitted('close')).toBeTruthy();
  });
});

describe('ComposeConversation native partial and lock_to_single_conversation', () => {
  // Fixture da API: lock=false cria um id novo a cada create; lock=true reusa o
  // id, mas um segundo create reenviaria a primeira mensagem (firstMessageCount).
  const lockCases = [false, true].map(lockToSingle => {
    const firstId = lockToSingle ? 931 : 901;
    return {
      lockToSingle,
      conversationIds: lockToSingle
        ? [firstId, firstId]
        : [firstId, firstId + 1],
      expectedId: firstId,
    };
  });

  it.each(lockCases)(
    'never creates twice nor resends the first message (lock_to_single=$lockToSingle)',
    async ({ conversationIds, expectedId }) => {
      let failFirstFollowUp = true;
      const store = installStore({
        conversationIds,
        send: pending => {
          const nonce = pending.contentAttributes.connecta_followup_nonce;
          return failFirstFollowUp && nonce.includes(':0:')
            ? Promise.reject(new Error('offline'))
            : 'ok';
        },
      });

      const wrapper = await mountCompose({
        inboxes: [nativeInbox(11)],
        files: makeFiles('a', 'b'),
        draft: 'Olá, cidadão',
      });

      await startNativePartial(wrapper);

      expect(store.createCount).toBe(1);
      expect(store.firstMessageCount).toBe(1);
      expect(
        wrapper
          .find(`a[href="/app/accounts/7/conversations/${expectedId}"]`)
          .exists()
      ).toBe(true);

      failFirstFollowUp = false;
      await clickRetry(wrapper);

      expect(store.createCount).toBe(1);
      expect(store.firstMessageCount).toBe(1);
      expect(
        sendCalls().filter(pending =>
          pending.contentAttributes.connecta_followup_nonce.includes(
            `${expectedId}:0:`
          )
        )
      ).toHaveLength(3);
      expect(
        sendCalls().filter(pending =>
          pending.contentAttributes.connecta_followup_nonce.includes(
            `${expectedId}:1:`
          )
        )
      ).toHaveLength(0);
      expect(alertFor('The message was sent successfully!')).toBeTruthy();
    }
  );
});

describe('ComposeConversation Baileys admission', () => {
  it('routes through manual admission and never calls native create', async () => {
    const store = installStore({
      conversationIds: [901],
      admission: () => ({ id: 701, account_id: 7 }),
      send: () => 'ok',
    });
    mocks.admissionDestinations.mockResolvedValue({
      data: {
        eligible_org_units: [{ id: 3, name: 'Sector A' }],
        reused_from: null,
      },
    });

    const wrapper = await mountCompose({
      inboxes: [baileysInbox(55)],
      files: makeFiles('a', 'b'),
      draft: 'Olá, cidadão',
    });

    await startNativePartial(wrapper, 55);

    expect(createCalls()).toHaveLength(0);
    expect(mocks.admissionDestinations).toHaveBeenCalledTimes(1);
    expect(mocks.admissionDestinations).toHaveBeenCalledWith(55);

    const admissionCall = manualAdmissionCalls()[0][1];
    expect(admissionCall.params).toMatchObject({
      inboxId: 55,
      contactId: 12,
      orgUnitId: 3,
      message: { content: 'Olá, cidadão' },
      files: [{ name: 'raw-a', kind: 'raw' }],
    });
    expect(admissionCall.params.idempotencyKey).toMatch(/^attempt-/);

    expect(sendCalls()).toHaveLength(1);
    expect(sendCalls()[0].contentAttributes.connecta_followup_nonce).toBe(
      followUpNonce(701, 0, 'b')
    );
    expect(sendCalls()[0].conversationId).toBe(701);

    expect(metadataRefreshCalls()).toHaveLength(1);
    expect(metadataRefreshCalls()[0][1]).toBe(701);
    expect(store.admissionCount).toBe(1);

    const successAlert = alertFor('The message was sent successfully!');
    expect(successAlert).toBeTruthy();
    expect(successAlert[1]).toMatchObject({
      type: 'link',
      to: '/app/accounts/7/conversations/701',
    });
    expect(wrapper.text()).not.toContain('Conversation created, but');
  });

  it('keeps the same idempotency key when the same draft admission is retried', async () => {
    const state = installStore({
      admission: (payload, attempt) => {
        if (attempt === 1) {
          return Promise.reject(new Error('timeout'));
        }
        return { id: 701, account_id: 7 };
      },
    });
    mocks.admissionDestinations.mockResolvedValue({
      data: {
        eligible_org_units: [{ id: 3, name: 'Sector A' }],
        reused_from: null,
      },
    });

    const wrapper = await mountCompose({
      inboxes: [baileysInbox(55)],
      files: makeFiles('a'),
      draft: 'Olá, cidadão',
    });

    await startNativePartial(wrapper, 55);

    expect(createCalls()).toHaveLength(0);
    expect(manualAdmissionCalls()).toHaveLength(1);
    expect(alertFor('Could not start service')).toBeTruthy();
    expect(wrapper.find('[data-test="popover-content"]').exists()).toBe(true);

    await submitForm(wrapper);

    expect(createCalls()).toHaveLength(0);
    expect(manualAdmissionCalls()).toHaveLength(2);
    expect(manualAdmissionCalls()[0][1].params.idempotencyKey).toBe(
      manualAdmissionCalls()[1][1].params.idempotencyKey
    );
    expect(state.admissionCount).toBe(2);
    expect(metadataRefreshCalls()).toHaveLength(1);
    expect(metadataRefreshCalls()[0][1]).toBe(701);
    expect(alertFor('The message was sent successfully!')).toBeTruthy();
  });
});

describe('ComposeConversation native partial context', () => {
  const failingPartialSend = pending => {
    const nonce = pending.contentAttributes.connecta_followup_nonce;
    return nonce.includes(':901:1:')
      ? Promise.reject(new Error('offline'))
      : 'ok';
  };

  it('abandons the queue when the compose popover is closed and reopened', async () => {
    const store = installStore({
      conversationIds: [901],
      send: failingPartialSend,
    });

    const wrapper = await mountCompose({
      inboxes: [nativeInbox(11)],
      files: makeFiles('a', 'b', 'c'),
      draft: 'Olá, cidadão',
    });

    await startNativePartial(wrapper);
    expect(store.createCount).toBe(1);

    await wrapper.find('[data-test="popover-trigger"]').trigger('click');
    await settle();

    const abandonAlert = alertFor('pending attachments were not resent');
    expect(abandonAlert).toBeTruthy();
    expect(abandonAlert[1]).toMatchObject({
      type: 'link',
      to: '/app/accounts/7/conversations/901',
      message: 'Open conversation',
    });
    expect(wrapper.find('[data-test="popover-content"]').exists()).toBe(false);

    await openCompose(wrapper);

    expect(wrapper.text()).not.toContain('Conversation created, but');
    expect(store.createCount).toBe(1);
  });

  it('abandons the queue on cancel and starts a fresh attendance after reopening', async () => {
    const store = installStore({
      conversationIds: [901, 902],
      send: failingPartialSend,
    });

    const wrapper = await mountCompose({
      inboxes: [nativeInbox(11)],
      files: makeFiles('a', 'b', 'c'),
      draft: 'Olá, cidadão',
    });

    await startNativePartial(wrapper);
    expect(wrapper.text()).toContain(
      'Conversation created, but 1 attachment(s) are pending.'
    );
    expect(store.createCount).toBe(1);

    await wrapper.find('[data-test="cancel"]').trigger('click');
    await settle();

    const abandonAlert = alertFor('pending attachments were not resent');
    expect(abandonAlert).toBeTruthy();
    expect(abandonAlert[1]).toMatchObject({
      type: 'link',
      to: '/app/accounts/7/conversations/901',
      message: 'Open conversation',
    });
    expect(wrapper.find('[data-test="popover-content"]').exists()).toBe(false);
    expect(wrapper.emitted('close')).toBeTruthy();

    await openCompose(wrapper);

    expect(wrapper.text()).not.toContain('Conversation created, but');
    expect(wrapper.find('[data-test="draft-value"]').text().trim()).toBe('');
    expect(wrapper.find('[data-test="attachment-count"]').text().trim()).toBe(
      '0'
    );

    await selectInbox(wrapper, 11);
    await attachFiles(wrapper);
    await wrapper.find('[data-test="draft"]').setValue('Novo atendimento');
    await submitForm(wrapper);

    expect(store.createCount).toBe(2);
    expect(createCalls()[1][1].params.message.content).toBe('Novo atendimento');
    expect(
      sendCalls().filter(pending =>
        pending.contentAttributes.connecta_followup_nonce.includes(':901:')
      )
    ).toHaveLength(3);
    expect(alertFor('The message was sent successfully!')).toBeTruthy();
  });

  it('abandons the old queue when the inbox changes and does not resend it', async () => {
    const store = installStore({
      conversationIds: [901, 902],
      send: failingPartialSend,
    });

    const wrapper = await mountCompose({
      inboxes: [nativeInbox(11), nativeInbox(22)],
      files: makeFiles('a', 'b', 'c'),
      draft: 'Olá, cidadão',
    });

    await startNativePartial(wrapper);
    await selectInbox(wrapper, 22);

    const abandonAlert = alertFor('pending attachments were not resent');
    expect(abandonAlert).toBeTruthy();
    expect(abandonAlert[1]).toMatchObject({
      type: 'link',
      to: '/app/accounts/7/conversations/901',
    });
    expect(wrapper.text()).not.toContain('Conversation created, but');
    expect(store.createCount).toBe(1);

    await attachFiles(wrapper);
    await wrapper.find('[data-test="draft"]').setValue('Outro atendimento');
    await submitForm(wrapper);

    expect(store.createCount).toBe(2);
    expect(createCalls()[1][1].params.inboxId).toBe(22);
    expect(
      sendCalls().filter(pending =>
        pending.contentAttributes.connecta_followup_nonce.includes(':901:')
      )
    ).toHaveLength(3);
    expect(
      sendCalls().filter(pending =>
        pending.contentAttributes.connecta_followup_nonce.includes(':902:')
      )
    ).toHaveLength(2);
    expect(alertFor('The message was sent successfully!')).toBeTruthy();
  });

  it('abandons the old queue when a different contact is submitted', async () => {
    const store = installStore({
      conversationIds: [901, 902],
      send: failingPartialSend,
    });

    const wrapper = await mountCompose({
      inboxes: [nativeInbox(11)],
      files: makeFiles('a', 'b', 'c'),
      draft: 'Olá, cidadão',
    });

    await startNativePartial(wrapper);
    await wrapper.setProps({ contactId: '13' });
    await settle();

    const abandonAlert = alertFor('pending attachments were not resent');
    expect(abandonAlert).toBeTruthy();
    expect(abandonAlert[1]).toMatchObject({
      type: 'link',
      to: '/app/accounts/7/conversations/901',
    });
    expect(wrapper.text()).not.toContain('Conversation created, but');
    expect(store.createCount).toBe(1);

    await selectInbox(wrapper, 11);
    await attachFiles(wrapper);
    await wrapper.find('[data-test="draft"]').setValue('Outro cidadão');
    await submitForm(wrapper);

    expect(store.createCount).toBe(2);
    expect(createCalls()[1][1].params.contactId).toBe(13);
    expect(
      sendCalls().filter(pending =>
        pending.contentAttributes.connecta_followup_nonce.includes(':901:')
      )
    ).toHaveLength(3);
    expect(
      sendCalls().filter(pending =>
        pending.contentAttributes.connecta_followup_nonce.includes(':902:')
      )
    ).toHaveLength(2);
    expect(alertFor('The message was sent successfully!')).toBeTruthy();
  });

  it('abandons the queue when the route account changes', async () => {
    const store = installStore({
      conversationIds: [901],
      send: failingPartialSend,
    });

    const wrapper = await mountCompose({
      inboxes: [nativeInbox(11)],
      files: makeFiles('a', 'b', 'c'),
      draft: 'Olá, cidadão',
    });

    await startNativePartial(wrapper);
    mocks.route.params.accountId = '8';
    await settle();

    const abandonAlert = alertFor('pending attachments were not resent');
    expect(abandonAlert).toBeTruthy();
    expect(abandonAlert[1]).toMatchObject({
      type: 'link',
      to: '/app/accounts/7/conversations/901',
    });
    expect(wrapper.text()).not.toContain('Conversation created, but');
    expect(store.createCount).toBe(1);
  });
});
