import { shallowMount } from '@vue/test-utils';
import ConversationCard from '../ConversationCard.vue';

const defaultChat = {
  id: 1,
  labels: [],
  messages: [],
  priority: null,
  unread_count: 0,
  timestamp: 1700000000,
  created_at: 1700000000,
};

const mountComponent = (chat, currentContact = {}, props = {}) =>
  shallowMount(ConversationCard, {
    props: {
      chat: { ...defaultChat, ...chat },
      currentContact: {
        name: 'Jane Doe',
        thumbnail: '',
        availability_status: 'offline',
        ...currentContact,
      },
      inbox: { id: 1 },
      ...props,
    },
    global: {
      stubs: {
        'fluent-icon': true,
      },
    },
  });

describe('ConversationCard', () => {
  it('does not reserve the labels row when only a persisted SLA policy id is present', () => {
    const wrapper = mountComponent({ sla_policy_id: 1, applied_sla: null });

    expect(wrapper.findComponent({ name: 'CardLabels' }).exists()).toBe(false);
  });

  it('shows the labels row when an active applied SLA is present', () => {
    const wrapper = mountComponent({
      sla_policy_id: 1,
      applied_sla: { id: 1 },
    });

    expect(wrapper.findComponent({ name: 'CardLabels' }).exists()).toBe(true);
  });

  it('does not reserve the labels row when the contact is blocked', () => {
    const wrapper = mountComponent(
      {
        sla_policy_id: 1,
        applied_sla: { id: 1 },
      },
      { blocked: true }
    );

    expect(wrapper.findComponent({ name: 'CardLabels' }).exists()).toBe(false);
  });

  it('does not show the pin icon by default', () => {
    const wrapper = mountComponent({});

    expect(wrapper.findComponent({ name: 'CardPinIcon' }).exists()).toBe(false);
  });

  it('shows the pin icon when the conversation is pinned', () => {
    const wrapper = mountComponent({}, {}, { isPinned: true });

    expect(wrapper.findComponent({ name: 'CardPinIcon' }).exists()).toBe(true);
  });

  it('shows the dynamic root | sector | assignee label without hiding the contact', () => {
    const wrapper = mountComponent(
      {},
      {},
      {
        connecta: { root_unit_name: 'Raiz X', org_unit_name: 'Setor Y' },
        assignee: { name: 'Pessoa Z' },
        showAssignee: true,
      }
    );

    expect(wrapper.text()).toContain('Jane Doe');
    expect(wrapper.text()).toContain('Raiz X | Setor Y | Pessoa Z');
    expect(
      wrapper.find('.connecta-conversation-label').attributes('aria-label')
    ).toBe('Raiz X | Setor Y | Pessoa Z');
  });

  it('does not add the Connecta label without an authorized scope', () => {
    const wrapper = mountComponent({}, {}, { connecta: null });

    expect(wrapper.text()).toContain('Jane Doe');
    expect(wrapper.find('.connecta-conversation-label').exists()).toBe(false);
  });

  it('updates the assignee part natively when the assignee changes', async () => {
    const wrapper = mountComponent(
      {},
      {},
      {
        connecta: { root_unit_name: 'Raiz X', org_unit_name: 'Setor Y' },
        assignee: { name: 'Pessoa Z' },
        showAssignee: true,
      }
    );

    await wrapper.setProps({ assignee: { name: 'Pessoa W' } });

    expect(wrapper.text()).toContain('Raiz X | Setor Y | Pessoa W');
    expect(wrapper.text()).not.toContain('Pessoa Z');
  });
});
