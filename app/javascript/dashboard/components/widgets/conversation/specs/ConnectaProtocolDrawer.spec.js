import { flushPromises, mount } from '@vue/test-utils';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import ConnectaProtocolDrawer from '../ConnectaProtocolDrawer.vue';

const { push, getProtocol } = vi.hoisted(() => ({
  push: vi.fn(),
  getProtocol: vi.fn(),
}));

vi.mock('vue-router', () => ({ useRouter: () => ({ push }) }));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ({ value: 7 }),
}));
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key, te: () => true }),
}));
vi.mock('dashboard/api/connecta', () => ({
  default: { getProtocol },
}));
vi.mock('dashboard/helper/URLHelper', () => ({
  frontendURL: path => path,
  conversationUrl: ({ id }) => `/conversations/${id}`,
}));

const mountDrawer = (props = {}) =>
  mount(ConnectaProtocolDrawer, {
    props: {
      show: true,
      protocol: 'PROT1',
      currentConversationId: 11,
      ...props,
    },
  });

describe('ConnectaProtocolDrawer', () => {
  beforeEach(() => {
    push.mockReset();
    getProtocol.mockReset();
  });

  it('renders only the stages returned by the server and links each one', async () => {
    getProtocol.mockResolvedValue({
      data: {
        stages: [
          {
            conversation_id: 11,
            state: 'active',
            root_unit_name: 'Raiz X',
            org_unit_name: 'Setor Y',
            assignee_name: 'Pessoa Z',
          },
        ],
      },
    });

    const wrapper = mountDrawer();
    await flushPromises();

    expect(getProtocol).toHaveBeenCalledWith('PROT1');
    expect(wrapper.text()).toContain('#11');
    expect(wrapper.text()).toContain('Raiz X | Setor Y | Pessoa Z');
    expect(wrapper.text()).not.toContain('#12');

    await wrapper.find('ul button').trigger('click');
    expect(push).toHaveBeenCalledWith('/conversations/11');
    expect(wrapper.emitted('close')).toBeTruthy();
  });

  it('shows the empty state when no stage is visible', async () => {
    getProtocol.mockResolvedValue({ data: { stages: [] } });

    const wrapper = mountDrawer();
    await flushPromises();

    expect(wrapper.text()).toContain('CONNECTA.PROTOCOL.EMPTY');
  });

  it('shows a generic error without rendering stale stages', async () => {
    getProtocol.mockRejectedValue(new Error('denied'));

    const wrapper = mountDrawer();
    await flushPromises();

    expect(wrapper.text()).toContain('CONNECTA.PROTOCOL.LOAD_ERROR');
    expect(wrapper.text()).not.toContain('#11');
  });
});
