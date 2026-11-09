import { flushPromises, shallowMount } from '@vue/test-utils';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import ConnectaSettings from '../ConnectaSettings.vue';

const { getOutboundDispatches } = vi.hoisted(() => ({
  getOutboundDispatches: vi.fn(),
}));

vi.mock('dashboard/api/connecta', () => ({
  default: {
    getOutboundDispatches,
    confirmIdentityLink: vi.fn(),
    resolveOutboundDispatch: vi.fn(),
  },
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

const mockAlert = vi.fn();
vi.mock('dashboard/composables', () => ({
  useAlert: (...args) => mockAlert(...args),
}));

const mountSettings = () => shallowMount(ConnectaSettings);

describe('ConnectaSettings dispatches fetch', () => {
  beforeEach(() => {
    getOutboundDispatches.mockReset();
    mockAlert.mockClear();
  });

  it('stays silent when a linked non nominal admin is denied (403)', async () => {
    getOutboundDispatches.mockRejectedValue({
      response: { status: 403, data: {} },
    });

    const wrapper = mountSettings();
    await flushPromises();

    expect(getOutboundDispatches).toHaveBeenCalledOnce();
    expect(mockAlert).not.toHaveBeenCalled();
    expect(wrapper.text()).toContain('CONNECTA.SETTINGS.NO_DISPATCHES');
  });

  it('still surfaces genuine dispatch failures', async () => {
    getOutboundDispatches.mockRejectedValue({
      response: { status: 500, data: { error: 'boom' } },
    });

    mountSettings();
    await flushPromises();

    expect(mockAlert).toHaveBeenCalledWith('boom');
  });

  it('renders the dispatches returned for a nominal admin', async () => {
    getOutboundDispatches.mockResolvedValue({
      data: { dispatches: [{ id: 9, conversation_id: 12, state: 'parked' }] },
    });

    const wrapper = mountSettings();
    await flushPromises();

    expect(mockAlert).not.toHaveBeenCalled();
    expect(wrapper.text()).toContain('CONNECTA.SETTINGS.DISPATCH_ROW');
  });
});
