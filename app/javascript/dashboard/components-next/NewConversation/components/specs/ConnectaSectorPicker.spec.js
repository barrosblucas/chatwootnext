import { flushPromises, mount } from '@vue/test-utils';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import ConnectaSectorPicker from '../ConnectaSectorPicker.vue';

const { admissionDestinations, admitConversation } = vi.hoisted(() => ({
  admissionDestinations: vi.fn(),
  admitConversation: vi.fn(),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));
vi.mock('dashboard/api/connecta', () => ({
  default: {
    admissionDestinations,
    admissionDestinationsForInbox: vi.fn().mockResolvedValue({
      data: { eligible_org_units: [] },
    }),
    admitConversation,
  },
}));

const mountPicker = (props = {}) =>
  mount(ConnectaSectorPicker, {
    props: {
      show: true,
      inboxId: 3,
      contactId: 4,
      sourceId: 'synthetic-source',
      message: { content: 'ola' },
      idempotencyKey: 'attempt-1',
      ...props,
    },
    global: {
      mocks: { $t: key => key },
    },
  });

describe('ConnectaSectorPicker', () => {
  beforeEach(() => {
    admissionDestinations.mockReset();
    admitConversation.mockReset();
  });

  it('admits with the listed sector and emits the conversation', async () => {
    admitConversation.mockResolvedValue({ data: { id: 55, account_id: 1 } });

    const wrapper = mountPicker({
      units: [{ id: 'unit-1', name: 'Setor Um' }],
    });
    await flushPromises();

    await wrapper.find('div.space-y-2 button').trigger('click');
    const buttons = wrapper.findAll('button');
    await buttons[buttons.length - 1].trigger('click');
    await flushPromises();

    expect(admitConversation).toHaveBeenCalledWith(
      expect.objectContaining({
        orgUnitId: 'unit-1',
        inboxId: 3,
        contactId: 4,
        sourceId: 'synthetic-source',
        idempotencyKey: 'attempt-1',
      })
    );
    expect(wrapper.emitted('admitted')?.[0]).toEqual([{ id: 55, account_id: 1 }]);
  });

  it('shows an actionable error when the actor has no eligible sector', async () => {
    const wrapper = mountPicker({ units: [] });
    await flushPromises();

    expect(wrapper.text()).toContain('CONNECTA.MANUAL_ADMISSION.NO_ELIGIBLE_UNIT');
  });
});
