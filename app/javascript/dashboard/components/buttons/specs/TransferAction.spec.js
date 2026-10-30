import { describe, it, expect, vi, beforeEach, beforeAll } from 'vitest';
import { mount, flushPromises } from '@vue/test-utils';
import TransferAction from '../TransferAction.vue';
import conversationAPI from 'dashboard/api/inbox/conversation';
import types from 'dashboard/store/mutation-types';
import wootConstants from 'dashboard/constants/globals';

const mockPush = vi.fn();
vi.mock('vue-router', () => ({
  useRouter: () => ({ push: mockPush }),
}));

const mockUseAlert = vi.fn();
vi.mock('dashboard/composables', () => ({
  useAlert: (...args) => mockUseAlert(...args),
}));

let mockConnectaTransferEnabled = true;
vi.mock('dashboard/composables/useConfig', () => ({
  useConfig: () => ({
    get connectaTransferEnabled() {
      return mockConnectaTransferEnabled;
    },
  }),
}));

const mockCommit = vi.fn();
let mockSelectedChat = { id: 42, status: wootConstants.STATUS_TYPE.OPEN };
let mockAccountId = 1;

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({
    commit: mockCommit,
  }),
  useStoreGetters: () => ({
    getSelectedChat: {
      get value() {
        return mockSelectedChat;
      },
    },
    getCurrentAccountId: {
      get value() {
        return mockAccountId;
      },
    },
  }),
}));

vi.mock('dashboard/api/inbox/conversation', () => ({
  default: {
    getConnectaTransferDestinations: vi.fn(),
    createConnectaTransfer: vi.fn(),
  },
}));

vi.mock('dashboard/helper/URLHelper', () => ({
  frontendURL: path => `/app/${path}`,
  conversationUrl: ({ accountId, id }) =>
    `accounts/${accountId}/conversations/${id}`,
}));

describe('TransferAction.vue', () => {
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
    mockConnectaTransferEnabled = true;
    mockSelectedChat = { id: 42, status: wootConstants.STATUS_TYPE.OPEN };
    mockAccountId = 1;
  });

  const mountComponent = (options = {}) => {
    return mount(TransferAction, {
      global: {
        stubs: {
          TeleportWithDirection: {
            template: '<div><slot /></div>',
          },
        },
      },
      ...options,
    });
  };

  describe('Visibility', () => {
    it('does not render when connectaTransferEnabled is false', () => {
      mockConnectaTransferEnabled = false;
      const wrapper = mountComponent();
      expect(wrapper.find('button').exists()).toBe(false);
    });

    it('renders when status is OPEN and connectaTransferEnabled is true', () => {
      mockSelectedChat = { id: 42, status: wootConstants.STATUS_TYPE.OPEN };
      const wrapper = mountComponent();
      expect(wrapper.find('button').exists()).toBe(true);
    });

    it('renders when status is PENDING and connectaTransferEnabled is true', () => {
      mockSelectedChat = { id: 42, status: wootConstants.STATUS_TYPE.PENDING };
      const wrapper = mountComponent();
      expect(wrapper.find('button').exists()).toBe(true);
    });

    it('does not render when status is RESOLVED', () => {
      mockSelectedChat = { id: 42, status: wootConstants.STATUS_TYPE.RESOLVED };
      const wrapper = mountComponent();
      expect(wrapper.find('button').exists()).toBe(false);
    });

    it('does not render when status is SNOOZED', () => {
      mockSelectedChat = { id: 42, status: wootConstants.STATUS_TYPE.SNOOZED };
      const wrapper = mountComponent();
      expect(wrapper.find('button').exists()).toBe(false);
    });

    it('does not render when currentChat is null', () => {
      mockSelectedChat = null;
      const wrapper = mountComponent();
      expect(wrapper.find('button').exists()).toBe(false);
    });
  });

  describe('Opening Dialog & Destination Loading', () => {
    it('renders Dialog with overflow-visible set to true', () => {
      const wrapper = mountComponent();
      const dialog = wrapper.findComponent({ name: 'Dialog' });
      expect(dialog.exists()).toBe(true);
      expect(dialog.props('overflowVisible')).toBe(true);
    });

    it('fetches destinations when opening the dialog', async () => {
      const mockDestinations = [
        { departmentId: 'dept-1', displayName: 'Department 1' },
        { department_id: 'dept-2', display_name: 'Department 2' },
      ];

      conversationAPI.getConnectaTransferDestinations.mockResolvedValue({
        data: { destinations: mockDestinations },
      });

      const wrapper = mountComponent();
      await wrapper.find('button').trigger('click');
      await flushPromises();

      expect(
        conversationAPI.getConnectaTransferDestinations
      ).toHaveBeenCalledWith(42);
    });

    it('handles destination fetch error with custom error from response', async () => {
      conversationAPI.getConnectaTransferDestinations.mockRejectedValue({
        response: { data: { error: 'Failed to load destinations' } },
      });

      const wrapper = mountComponent();
      await wrapper.find('button').trigger('click');
      await flushPromises();

      expect(mockUseAlert).toHaveBeenCalledWith('Failed to load destinations');
    });

    it('uses default fallback error message when response error is absent', async () => {
      conversationAPI.getConnectaTransferDestinations.mockRejectedValue(
        new Error('Network Error')
      );

      const wrapper = mountComponent();
      await wrapper.find('button').trigger('click');
      await flushPromises();

      expect(mockUseAlert).toHaveBeenCalledWith(
        'Could not load transfer destinations. Please try again.'
      );
    });
  });

  describe('Transfer Execution', () => {
    it('executes transfer successfully and redirects to new conversation', async () => {
      conversationAPI.getConnectaTransferDestinations.mockResolvedValue({
        data: {
          destinations: [
            { departmentId: 'dept-1', displayName: 'Department 1' },
          ],
        },
      });

      conversationAPI.createConnectaTransfer.mockResolvedValue({
        data: { display_id: 100, target_department_id: 'dept-1' },
      });

      const wrapper = mountComponent();
      await wrapper.find('button').trigger('click');
      await flushPromises();

      const dialog = wrapper.findComponent({ name: 'Dialog' });
      expect(dialog.exists()).toBe(true);

      const combobox = wrapper.findComponent({ name: 'ComboBox' });
      combobox.vm.$emit('update:modelValue', 'dept-1');
      await wrapper.vm.$nextTick();

      dialog.vm.$emit('confirm');
      await flushPromises();

      expect(conversationAPI.createConnectaTransfer).toHaveBeenCalledWith(42, {
        targetDepartmentId: 'dept-1',
      });

      expect(mockCommit).toHaveBeenCalledWith(
        types.CHANGE_CONVERSATION_STATUS,
        {
          conversationId: 42,
          status: wootConstants.STATUS_TYPE.RESOLVED,
          snoozedUntil: null,
        }
      );

      expect(mockUseAlert).toHaveBeenCalledWith(
        'Conversation transferred successfully.'
      );
      expect(mockPush).toHaveBeenCalledWith(
        '/app/accounts/1/conversations/100'
      );
    });

    it('supports new_conversation_id field for redirection fallback', async () => {
      conversationAPI.getConnectaTransferDestinations.mockResolvedValue({
        data: {
          destinations: [
            { department_id: 'dept-2', display_name: 'Department 2' },
          ],
        },
      });

      conversationAPI.createConnectaTransfer.mockResolvedValue({
        data: { new_conversation_id: 200 },
      });

      const wrapper = mountComponent();
      await wrapper.find('button').trigger('click');
      await flushPromises();

      const combobox = wrapper.findComponent({ name: 'ComboBox' });
      combobox.vm.$emit('update:modelValue', 'dept-2');
      await wrapper.vm.$nextTick();

      const dialog = wrapper.findComponent({ name: 'Dialog' });
      dialog.vm.$emit('confirm');
      await flushPromises();

      expect(mockPush).toHaveBeenCalledWith(
        '/app/accounts/1/conversations/200'
      );
    });

    it('does not submit transfer if selectedDepartmentId is empty', async () => {
      const wrapper = mountComponent();
      await wrapper.find('button').trigger('click');
      await flushPromises();

      const dialog = wrapper.findComponent({ name: 'Dialog' });
      dialog.vm.$emit('confirm');
      await flushPromises();

      expect(conversationAPI.createConnectaTransfer).not.toHaveBeenCalled();
    });

    it('handles transfer creation error with custom response error', async () => {
      conversationAPI.getConnectaTransferDestinations.mockResolvedValue({
        data: {
          destinations: [
            { departmentId: 'dept-1', displayName: 'Department 1' },
          ],
        },
      });

      conversationAPI.createConnectaTransfer.mockRejectedValue({
        response: { data: { error: 'Transfer forbidden' } },
      });

      const wrapper = mountComponent();
      await wrapper.find('button').trigger('click');
      await flushPromises();

      const combobox = wrapper.findComponent({ name: 'ComboBox' });
      combobox.vm.$emit('update:modelValue', 'dept-1');
      await wrapper.vm.$nextTick();

      const dialog = wrapper.findComponent({ name: 'Dialog' });
      dialog.vm.$emit('confirm');
      await flushPromises();

      expect(mockUseAlert).toHaveBeenCalledWith('Transfer forbidden');
    });

    it('uses fallback error message on transfer creation failure without response error', async () => {
      conversationAPI.getConnectaTransferDestinations.mockResolvedValue({
        data: {
          destinations: [
            { departmentId: 'dept-1', displayName: 'Department 1' },
          ],
        },
      });

      conversationAPI.createConnectaTransfer.mockRejectedValue(
        new Error('Network Failure')
      );

      const wrapper = mountComponent();
      await wrapper.find('button').trigger('click');
      await flushPromises();

      const combobox = wrapper.findComponent({ name: 'ComboBox' });
      combobox.vm.$emit('update:modelValue', 'dept-1');
      await wrapper.vm.$nextTick();

      const dialog = wrapper.findComponent({ name: 'Dialog' });
      dialog.vm.$emit('confirm');
      await flushPromises();

      expect(mockUseAlert).toHaveBeenCalledWith(
        'Could not transfer the conversation. Please try again.'
      );
    });
  });
});
