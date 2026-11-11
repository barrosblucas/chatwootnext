import { flushPromises, shallowMount } from '@vue/test-utils';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import ContextMenu from '../Index.vue';

const { showBotOptout, setBotOptout, showConfirmation, alertMock } = vi.hoisted(
  () => ({
    showBotOptout: vi.fn(),
    setBotOptout: vi.fn(),
    showConfirmation: vi.fn(),
    alertMock: vi.fn(),
  })
);

vi.mock('dashboard/api/connecta', () => ({
  default: { showBotOptout, setBotOptout },
}));

vi.mock('dashboard/composables/useAdmin', () => ({
  useAdmin: () => ({ isAdmin: false }),
}));

vi.mock('dashboard/composables', async importOriginal => ({
  ...(await importOriginal()),
  useAlert: (...args) => alertMock(...args),
}));

const MenuItemStub = {
  template:
    '<button class="menu-item-stub" :data-key="option.key">{{ option.label }}</button>',
  props: ['option', 'variant'],
};

const ConfirmationModalStub = {
  template: '<div class="confirm-stub" />',
  methods: { showConfirmation },
};

const storeGetters = {
  'labels/getLabels': [],
  'teams/getTeams': [],
  'inboxAssignableAgents/getUIFlags': {},
  'inboxAssignableAgents/getAssignableAgents': () => [],
  getCurrentUser: {},
  getCurrentAccountId: 1,
};

const mountMenu = (props = {}) =>
  shallowMount(ContextMenu, {
    props: { chatId: 123, inboxId: 5, status: 'open', ...props },
    global: {
      mocks: {
        $t: key => key,
        $store: { getters: storeGetters, dispatch: vi.fn() },
      },
      stubs: {
        MenuItem: MenuItemStub,
        ConfirmationModal: ConfirmationModalStub,
      },
    },
  });

const botItem = wrapper =>
  wrapper
    .findAll('.menu-item-stub')
    .find(node => node.attributes('data-key') === 'bot-optout');

describe('ContextMenu bot opt-out', () => {
  beforeEach(() => {
    window.chatwootConfig = { connectaHumanNumberEnabled: 'true' };
    showBotOptout.mockReset().mockResolvedValue({ data: { disabled: false } });
    setBotOptout.mockReset().mockResolvedValue({ data: { disabled: true } });
    showConfirmation.mockReset().mockResolvedValue(true);
    alertMock.mockReset();
  });

  it('shows the disable label when the bot is enabled', async () => {
    const wrapper = mountMenu();
    await flushPromises();

    expect(showBotOptout).toHaveBeenCalledWith(123);
    expect(botItem(wrapper).text()).toBe('CONNECTA.BOT_OPTOUT.DISABLE');
  });

  it('shows the enable label when the bot is disabled', async () => {
    showBotOptout.mockResolvedValue({ data: { disabled: true } });
    const wrapper = mountMenu();
    await flushPromises();

    expect(botItem(wrapper).text()).toBe('CONNECTA.BOT_OPTOUT.ENABLE');
  });

  it('asks for confirmation and disables the bot', async () => {
    const wrapper = mountMenu();
    await flushPromises();

    await botItem(wrapper).trigger('click');
    await flushPromises();

    expect(showConfirmation).toHaveBeenCalled();
    expect(setBotOptout).toHaveBeenCalledWith(123, true);
    expect(alertMock).toHaveBeenCalledWith(
      'CONNECTA.BOT_OPTOUT.SUCCESS_DISABLED'
    );
    expect(wrapper.emitted('botOptoutChanged')).toEqual([[true]]);
    expect(wrapper.emitted('close')).toBeTruthy();
  });

  it('re-enables the bot without confirmation', async () => {
    showBotOptout.mockResolvedValue({ data: { disabled: true } });
    setBotOptout.mockResolvedValue({ data: { disabled: false } });
    const wrapper = mountMenu();
    await flushPromises();

    await botItem(wrapper).trigger('click');
    await flushPromises();

    expect(showConfirmation).not.toHaveBeenCalled();
    expect(setBotOptout).toHaveBeenCalledWith(123, false);
    expect(wrapper.emitted('botOptoutChanged')).toEqual([[false]]);
  });

  it('does nothing when the confirmation is dismissed', async () => {
    showConfirmation.mockResolvedValue(false);
    const wrapper = mountMenu();
    await flushPromises();

    await botItem(wrapper).trigger('click');
    await flushPromises();

    expect(setBotOptout).not.toHaveBeenCalled();
    expect(wrapper.emitted('botOptoutChanged')).toBeFalsy();
  });

  it('alerts on failure without emitting', async () => {
    setBotOptout.mockRejectedValue(new Error('down'));
    const wrapper = mountMenu();
    await flushPromises();

    await botItem(wrapper).trigger('click');
    await flushPromises();

    expect(alertMock).toHaveBeenCalledWith('CONNECTA.BOT_OPTOUT.ERROR');
    expect(wrapper.emitted('botOptoutChanged')).toBeFalsy();
  });

  it('hides the item when the platform lookup fails', async () => {
    showBotOptout.mockRejectedValue({ response: { status: 404 } });
    const wrapper = mountMenu();
    await flushPromises();

    expect(botItem(wrapper)).toBeUndefined();
  });

  it('hides the item when the human-number flag is off', async () => {
    window.chatwootConfig = {};
    const wrapper = mountMenu();
    await flushPromises();

    expect(showBotOptout).not.toHaveBeenCalled();
    expect(botItem(wrapper)).toBeUndefined();
  });
});
