import { describe, it, expect, vi, beforeEach } from 'vitest';
import { mount, flushPromises } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import ResolveAction from '../ResolveAction.vue';
import wootConstants from 'dashboard/constants/globals';
import messages from 'dashboard/i18n';

const mockPush = vi.fn();
const mockRoute = { name: 'home', params: { accountId: '1' } };
vi.mock('vue-router', () => ({
  useRouter: () => ({ push: mockPush }),
  useRoute: () => mockRoute,
}));

const mockUseAlert = vi.fn();
const mockUseAssignmentError = vi.fn();
vi.mock('dashboard/composables', () => ({
  useAlert: (...args) => mockUseAlert(...args),
  useAssignmentError: (...args) => mockUseAssignmentError(...args),
}));

vi.mock('dashboard/composables/emitter', () => ({
  useEmitter: vi.fn(),
}));

vi.mock('dashboard/composables/useConversationRequiredAttributes', () => ({
  useConversationRequiredAttributes: () => ({
    checkMissingAttributes: () => ({ hasMissing: false, missing: [] }),
  }),
}));

let mockConnectaTransferEnabled = true;
vi.mock('dashboard/composables/useConfig', () => ({
  useConfig: () => ({
    get connectaTransferEnabled() {
      return mockConnectaTransferEnabled;
    },
    get connectaHumanNumberEnabled() {
      return false;
    },
  }),
}));

const mockCommit = vi.fn();
const mockDispatch = vi.fn();
const mockMetadataGetter = vi.fn();
let mockSelectedChat = {
  id: 42,
  status: wootConstants.STATUS_TYPE.OPEN,
  custom_attributes: {},
};
let mockAccountId = 1;

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({
    commit: mockCommit,
    dispatch: mockDispatch,
    getters: {
      'connectaMetadata/getMetadata': (...args) => mockMetadataGetter(...args),
    },
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

const mockShowConnectaScope = vi.fn();
vi.mock('dashboard/api/inbox/conversation', () => ({
  default: {
    toggleStatus: vi.fn(),
    showConnectaScope: (...args) => mockShowConnectaScope(...args),
  },
}));

const mockEmit = vi.fn();
vi.mock('shared/helpers/mitt', () => ({
  emitter: { emit: (...args) => mockEmit(...args) },
}));

// Real EN messages so useAlert() resolves the strings the component passes.
const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: { en: messages.en },
});

describe('ResolveAction.vue (saída Connecta pós-resolve)', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockConnectaTransferEnabled = true;
    mockSelectedChat = {
      id: 42,
      status: wootConstants.STATUS_TYPE.OPEN,
      custom_attributes: {},
    };
    mockAccountId = 1;
    mockDispatch.mockResolvedValue({});
    mockMetadataGetter.mockReturnValue(null);
    mockShowConnectaScope.mockRejectedValue({ response: { status: 404 } });
  });

  const mountComponent = () => {
    return mount(ResolveAction, {
      global: {
        plugins: [i18n],
        stubs: {
          TeleportWithDirection: {
            template: '<div><slot /></div>',
          },
        },
      },
    });
  };

  const clickResolve = async wrapper => {
    const resolveButton = wrapper
      .findAll('button')
      .find(button => button.text() === 'Resolve');
    expect(resolveButton).toBeTruthy();
    await resolveButton.trigger('click');
    await flushPromises();
  };

  it('remove da lista e volta para a lista quando há metadado Connecta em cache', async () => {
    mockMetadataGetter.mockReturnValue({ case_protocol: 'BND000007' });
    const wrapper = mountComponent();

    await clickResolve(wrapper);

    expect(mockDispatch).toHaveBeenCalledWith('toggleStatus', {
      conversationId: 42,
      status: wootConstants.STATUS_TYPE.RESOLVED,
      snoozedUntil: undefined,
    });
    expect(mockShowConnectaScope).not.toHaveBeenCalled();
    expect(mockCommit).toHaveBeenCalledWith('REVOKE_CONNECTA_SCOPE', {
      conversation_id: 42,
    });
    expect(mockDispatch).toHaveBeenCalledWith(
      'connectaMetadata/invalidate',
      42
    );
    expect(mockPush).toHaveBeenCalledWith('/app/accounts/1/dashboard');
  });

  it('usa o endpoint de escopo como fallback quando não há metadado em cache', async () => {
    mockMetadataGetter.mockReturnValue(null);
    mockShowConnectaScope.mockResolvedValue({ data: { state: 'active' } });
    const wrapper = mountComponent();

    await clickResolve(wrapper);

    expect(mockShowConnectaScope).toHaveBeenCalledWith(42);
    expect(mockCommit).toHaveBeenCalledWith('REVOKE_CONNECTA_SCOPE', {
      conversation_id: 42,
    });
    expect(mockPush).toHaveBeenCalledWith('/app/accounts/1/dashboard');
  });

  it('mantém o comportamento nativo fora de escopo Connecta', async () => {
    const wrapper = mountComponent();

    await clickResolve(wrapper);

    expect(mockDispatch).toHaveBeenCalledWith(
      'toggleStatus',
      expect.objectContaining({
        status: wootConstants.STATUS_TYPE.RESOLVED,
      })
    );
    expect(mockCommit).not.toHaveBeenCalled();
    expect(mockPush).not.toHaveBeenCalled();
  });

  it('não verifica escopo quando a flag Connecta está desligada', async () => {
    mockConnectaTransferEnabled = false;
    mockMetadataGetter.mockReturnValue({ case_protocol: 'BND000007' });
    const wrapper = mountComponent();

    await clickResolve(wrapper);

    expect(mockShowConnectaScope).not.toHaveBeenCalled();
    expect(mockCommit).not.toHaveBeenCalled();
    expect(mockPush).not.toHaveBeenCalled();
  });

  it('não mascara o resolve quando a saída da lista falha', async () => {
    mockMetadataGetter.mockReturnValue({ case_protocol: 'BND000007' });
    mockPush.mockImplementationOnce(() => {
      throw new Error('navegação falhou');
    });
    const wrapper = mountComponent();

    await clickResolve(wrapper);

    expect(mockUseAlert).toHaveBeenCalled();
    expect(mockUseAssignmentError).not.toHaveBeenCalled();
  });
});
