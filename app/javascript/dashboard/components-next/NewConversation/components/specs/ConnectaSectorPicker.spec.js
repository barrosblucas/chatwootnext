import { flushPromises, mount } from '@vue/test-utils';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import ConnectaSectorPicker from '../ConnectaSectorPicker.vue';

const { admitConversation } = vi.hoisted(() => ({
  admitConversation: vi.fn(),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));
vi.mock('dashboard/api/connecta', () => ({
  default: { admitConversation },
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
    admitConversation.mockReset();
  });

  it('admits with the listed sector, files and emits the conversation', async () => {
    admitConversation.mockResolvedValue({ data: { id: 55, account_id: 1 } });
    const firstFile = new File(['a'], 'a.png', { type: 'image/png' });
    const followUp = new File(['b'], 'b.png', { type: 'image/png' });

    const wrapper = mountPicker({
      units: [{ id: 'unit-1', name: 'Setor Um' }],
      files: [firstFile],
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
        files: [firstFile],
      })
    );
    expect(admitConversation).not.toHaveBeenCalledWith(
      expect.objectContaining({ files: [followUp] })
    );
    expect(wrapper.emitted('admitted')?.[0]).toEqual([
      { id: 55, account_id: 1 },
    ]);
  });

  it('shows an actionable error when the actor has no eligible sector', async () => {
    const wrapper = mountPicker({ units: [] });
    await flushPromises();

    expect(wrapper.text()).toContain(
      'CONNECTA.MANUAL_ADMISSION.NO_ELIGIBLE_UNIT'
    );
  });

  it('shows a load error instead of calling a missing fallback when units are absent', async () => {
    const wrapper = mountPicker({ units: null });
    await flushPromises();

    expect(wrapper.text()).toContain('CONNECTA.MANUAL_ADMISSION.LOAD_ERROR');
    expect(admitConversation).not.toHaveBeenCalled();
  });
});
