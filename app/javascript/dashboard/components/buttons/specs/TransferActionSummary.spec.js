import { beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { flushPromises, mount } from '@vue/test-utils';
import TransferAction from '../TransferAction.vue';
import conversationAPI from 'dashboard/api/inbox/conversation';
import wootConstants from 'dashboard/constants/globals';

const mockPush = vi.fn();
const mockAlert = vi.fn();
const mockCommit = vi.fn();
let mockSelectedChat = { id: 42, status: wootConstants.STATUS_TYPE.OPEN };

vi.mock('vue-router', () => ({ useRouter: () => ({ push: mockPush }) }));
vi.mock('dashboard/composables', () => ({
  useAlert: (...args) => mockAlert(...args),
}));
vi.mock('dashboard/composables/useConfig', () => ({
  useConfig: () => ({
    connectaTransferEnabled: true,
    connectaHumanNumberEnabled: true,
  }),
}));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ commit: mockCommit }),
  useStoreGetters: () => ({
    getSelectedChat: {
      get value() {
        return mockSelectedChat;
      },
    },
    getCurrentAccountId: {
      get value() {
        return 1;
      },
    },
  }),
}));
vi.mock('dashboard/api/inbox/conversation', () => ({
  default: {
    getConnectaTransferDestinations: vi.fn(),
    showConnectaScope: vi.fn(),
    createConnectaTransfer: vi.fn(),
  },
}));
vi.mock('dashboard/helper/URLHelper', () => ({
  frontendURL: path => `/app/${path}`,
  conversationUrl: ({ accountId, id }) =>
    `accounts/${accountId}/conversations/${id}`,
}));

describe('TransferAction summary mode', () => {
  beforeAll(() => {
    if (typeof HTMLDialogElement !== 'undefined') {
      HTMLDialogElement.prototype.showModal = vi.fn(function showModal() {
        this.open = true;
      });
      HTMLDialogElement.prototype.close = vi.fn(function closeDialog() {
        this.open = false;
      });
    }
  });

  beforeEach(() => {
    vi.clearAllMocks();
    mockSelectedChat = { id: 42, status: wootConstants.STATUS_TYPE.OPEN };
    conversationAPI.showConnectaScope.mockResolvedValue({
      data: { can_transfer: true },
    });
    conversationAPI.getConnectaTransferDestinations.mockResolvedValue({
      data: { destinations: [{ id: 'unit-uuid', display_name: 'Setor B' }] },
    });
    conversationAPI.createConnectaTransfer.mockResolvedValue({
      data: { status: 'pending_activation' },
    });
  });

  const mountComponent = () =>
    mount(TransferAction, {
      global: {
        stubs: { TeleportWithDirection: { template: '<div><slot /></div>' } },
      },
    });

  it('keeps transfer disabled until all summary fields are filled and submits only the summary', async () => {
    const wrapper = mountComponent();
    await flushPromises();
    await wrapper.find('button').trigger('click');
    await flushPromises();

    const dialog = wrapper.findComponent({ name: 'Dialog' });
    expect(dialog.props('disableConfirmButton')).toBe(true);
    wrapper
      .findComponent({ name: 'ComboBox' })
      .vm.$emit('update:modelValue', 'unit-uuid');
    const [subjectField, completedField, nextActionField] = wrapper.findAll(
      'textarea.form-textarea'
    );
    expect(subjectField.attributes('maxlength')).toBe('160');
    await subjectField.setValue('Segunda via da conta');
    await completedField.setValue('Dados conferidos com o cidadão.');
    await nextActionField.setValue('Aguardar envio do documento.');
    await wrapper.vm.$nextTick();

    expect(dialog.props('disableConfirmButton')).toBe(false);
    dialog.vm.$emit('confirm');
    await flushPromises();

    expect(conversationAPI.createConnectaTransfer).toHaveBeenCalledWith(42, {
      targetOrgUnitId: 'unit-uuid',
      summary: {
        subject: 'Segunda via da conta',
        completed: 'Dados conferidos com o cidadão.',
        nextAction: 'Aguardar envio do documento.',
      },
    });
    expect(mockPush).not.toHaveBeenCalled();
  });
});
