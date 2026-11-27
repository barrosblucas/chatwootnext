import { flushPromises, shallowMount } from '@vue/test-utils';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import ContextMenu from '../Index.vue';
import { normalizeAssignableAgentsPayload } from 'dashboard/helper/connectaAssignableAgents';

const { fetchAssignableAgents } = vi.hoisted(() => ({
  fetchAssignableAgents: vi.fn(),
}));

vi.mock('dashboard/composables/useAdmin', () => ({
  useAdmin: () => ({ isAdmin: false }),
}));

vi.mock('dashboard/composables', async importOriginal => {
  const mod = await importOriginal();
  return { ...mod, useAlert: (...args) => args };
});

const MenuItemStub = {
  template:
    '<button class="menu-item-stub" :class="variant">{{ option.label }}</button>',
  props: ['option', 'variant'],
};

const agentStubs = wrapper =>
  wrapper.findAll('.menu-item-stub.agent').map(node => node.text());

const clickAgent = async (wrapper, name) => {
  const node = wrapper
    .findAll('.menu-item-stub.agent')
    .find(item => item.text() === name);
  expect(node).toBeTruthy();
  await node.trigger('click');
  await flushPromises();
};

const mountMenu = payload =>
  shallowMount(ContextMenu, {
    props: { chatId: 42, inboxId: 5, status: 'open' },
    global: {
      renderStubDefaultSlot: true,
      mocks: {
        $t: key => key,
        $store: {
          getters: {
            'labels/getLabels': [],
            'teams/getTeams': [],
            'connectaAssignableAgents/getUIFlags': { isFetching: false },
            'connectaAssignableAgents/getPayload': () =>
              normalizeAssignableAgentsPayload(payload),
            getCurrentUser: {
              id: 1,
              accounts: [{ id: 1, availability_status: 'online' }],
            },
            getCurrentAccountId: 1,
          },
          dispatch: fetchAssignableAgents,
        },
      },
      stubs: {
        MenuItem: MenuItemStub,
        ConfirmationModal: { template: '<div />' },
      },
    },
  });

describe('ContextMenu department-aware assignees', () => {
  beforeEach(() => {
    fetchAssignableAgents.mockClear();
  });

  it('fetches the department list for the open conversation', async () => {
    const wrapper = mountMenu({ grouped: false, groups: [] });
    await flushPromises();
    expect(fetchAssignableAgents).toHaveBeenCalledWith(
      'connectaAssignableAgents/fetch',
      [42]
    );
    expect(wrapper).toBeTruthy();
  });

  it('shows None plus a flat alphabetical list when grouped=false', async () => {
    const wrapper = mountMenu({
      grouped: false,
      conversation_org_unit_id: null,
      groups: [
        {
          org_unit_id: null,
          org_unit_name: null,
          agents: [
            { id: 4, name: 'Melissa Santos' },
            { id: 1, name: 'Mariana Kruel' },
            { id: 3, name: 'Juscilaine Fontes' },
            { id: 2, name: 'Juliana Faustina' },
          ],
        },
      ],
    });
    await flushPromises();

    expect(agentStubs(wrapper)).toEqual([
      'None',
      'Juliana Faustina',
      'Juscilaine Fontes',
      'Mariana Kruel',
      'Melissa Santos',
    ]);
  });

  it('groups by department with non-clickable headers when grouped=true', async () => {
    const wrapper = mountMenu({
      grouped: true,
      conversation_org_unit_id: 'u1',
      groups: [
        {
          org_unit_id: 'u2',
          org_unit_name: 'CADSUS',
          agents: [
            { id: 4, name: 'Tal de Fulano' },
            { id: 3, name: 'Fulano de Tal' },
          ],
        },
        {
          org_unit_id: 'u1',
          org_unit_name: 'Hospital Municipal',
          agents: [
            { id: 2, name: 'João da Silva' },
            { id: 1, name: 'Maria da Silva' },
          ],
        },
      ],
    });
    await flushPromises();

    expect(agentStubs(wrapper)).toEqual([
      'None',
      'Fulano de Tal',
      'Tal de Fulano',
      'João da Silva',
      'Maria da Silva',
    ]);

    const headers = wrapper
      .findAll('p.cursor-default')
      .map(node => node.text())
      .filter(text => text.length > 0);
    expect(headers).toEqual(['CADSUS', 'Hospital Municipal']);

    // Headers are plain rows: clicking one assigns nobody.
    const header = wrapper
      .findAll('p.cursor-default')
      .find(node => node.text() === 'CADSUS');
    await header.trigger('click');
    await flushPromises();
    expect(wrapper.emitted('assignAgent')).toBeFalsy();
  });

  it('sends connecta_org_unit_id only for another-department agents', async () => {
    const wrapper = mountMenu({
      grouped: true,
      conversation_org_unit_id: 'u1',
      groups: [
        {
          org_unit_id: 'u2',
          org_unit_name: 'CADSUS',
          agents: [{ id: 3, name: 'Fulano de Tal' }],
        },
        {
          org_unit_id: 'u1',
          org_unit_name: 'Hospital Municipal',
          agents: [{ id: 1, name: 'Maria da Silva' }],
        },
      ],
    });
    await flushPromises();

    await clickAgent(wrapper, 'Maria da Silva');
    expect(wrapper.emitted('assignAgent')[0][0]).toMatchObject({
      id: 1,
      connectaOrgUnitId: null,
    });

    await clickAgent(wrapper, 'Fulano de Tal');
    expect(wrapper.emitted('assignAgent')[1][0]).toMatchObject({
      id: 3,
      connectaOrgUnitId: 'u2',
    });
  });
});
