import { describe, expect, it } from 'vitest';
import {
  flatAgentsFromPayload,
  isHiddenAssignableAgent,
  isMenuHeader,
  menuEntriesFromPayload,
  normalizeAssignableAgentsPayload,
  sortAgentsByName,
} from '../connectaAssignableAgents';

const agent = (id, name, extra = {}) => ({
  id,
  name,
  confirmed: true,
  role: 'agent',
  account_id: 1,
  email: `${id}@example.com`,
  availability_status: 'online',
  ...extra,
});

describe('normalizeAssignableAgentsPayload', () => {
  it('sorts groups by name and agents by name (pt-BR)', () => {
    const payload = normalizeAssignableAgentsPayload({
      grouped: true,
      conversation_org_unit_id: 'u2',
      groups: [
        {
          org_unit_id: 'u2',
          org_unit_name: 'CADSUS',
          agents: [agent(2, 'Zuleica'), agent(1, 'Ana')],
        },
        {
          org_unit_id: 'u1',
          org_unit_name: 'Hospital Municipal',
          agents: [agent(3, 'Mário')],
        },
      ],
    });

    expect(payload.grouped).toBe(true);
    expect(payload.conversationOrgUnitId).toBe('u2');
    expect(payload.groups.map(g => g.orgUnitName)).toEqual([
      'CADSUS',
      'Hospital Municipal',
    ]);
    expect(payload.groups[0].agents.map(a => a.name)).toEqual([
      'Ana',
      'Zuleica',
    ]);
  });

  it('sorts accent-insensitively (Mariana before Melissa, Juscilaine after Juliana)', () => {
    const sorted = sortAgentsByName([
      agent(1, 'Melissa Santos'),
      agent(2, 'Mariana Kruel'),
      agent(3, 'Juscilaine Fontes'),
      agent(4, 'Juliana Faustina'),
    ]);
    expect(sorted.map(a => a.name)).toEqual([
      'Juliana Faustina',
      'Juscilaine Fontes',
      'Mariana Kruel',
      'Melissa Santos',
    ]);
  });

  it('hides "Atendimento Automático" and tolerates a missing payload', () => {
    expect(isHiddenAssignableAgent(agent(9, 'Atendimento Automático'))).toBe(
      true
    );
    expect(isHiddenAssignableAgent(agent(9, 'Atendimento Automatico'))).toBe(
      true
    );
    expect(isHiddenAssignableAgent(agent(1, 'Maria'))).toBe(false);

    const payload = normalizeAssignableAgentsPayload({
      grouped: false,
      conversation_org_unit_id: null,
      groups: [
        {
          org_unit_id: null,
          org_unit_name: null,
          agents: [agent(9, 'Atendimento Automático'), agent(1, 'Maria')],
        },
      ],
    });
    expect(payload.groups[0].agents.map(a => a.name)).toEqual(['Maria']);
    expect(normalizeAssignableAgentsPayload().groups).toEqual([]);
  });
});

describe('flatAgentsFromPayload', () => {
  it('returns an alphabetical list and tags only the other-unit agents', () => {
    const flat = flatAgentsFromPayload(
      normalizeAssignableAgentsPayload({
        grouped: true,
        conversation_org_unit_id: 'u1',
        groups: [
          {
            org_unit_id: 'u1',
            org_unit_name: 'Hospital Municipal',
            agents: [agent(2, 'Maria da Silva')],
          },
          {
            org_unit_id: 'u2',
            org_unit_name: 'CADSUS',
            agents: [agent(1, 'Fulano de Tal')],
          },
        ],
      })
    );

    expect(flat.map(a => a.name)).toEqual(['Fulano de Tal', 'Maria da Silva']);
    expect(
      flat.find(a => a.name === 'Maria da Silva').connectaOrgUnitId
    ).toBeNull();
    expect(flat.find(a => a.name === 'Fulano de Tal').connectaOrgUnitId).toBe(
      'u2'
    );
  });

  it('returns [] without a payload', () => {
    expect(flatAgentsFromPayload(null)).toEqual([]);
  });
});

describe('menuEntriesFromPayload', () => {
  it('returns a flat alphabetical list when grouped=false', () => {
    const entries = menuEntriesFromPayload(
      normalizeAssignableAgentsPayload({
        grouped: false,
        conversation_org_unit_id: null,
        groups: [
          {
            org_unit_id: null,
            org_unit_name: null,
            agents: [agent(1, 'Melissa Santos'), agent(2, 'Juliana Faustina')],
          },
        ],
      })
    );

    expect(entries.some(isMenuHeader)).toBe(false);
    expect(entries.map(a => a.name)).toEqual([
      'Juliana Faustina',
      'Melissa Santos',
    ]);
  });

  it('returns department headers followed by their users when grouped=true', () => {
    const entries = menuEntriesFromPayload(
      normalizeAssignableAgentsPayload({
        grouped: true,
        conversation_org_unit_id: 'u1',
        groups: [
          {
            org_unit_id: 'u2',
            org_unit_name: 'CADSUS',
            agents: [agent(3, 'Tal de Fulano'), agent(4, 'Fulano de Tal')],
          },
          {
            org_unit_id: 'u1',
            org_unit_name: 'Hospital Municipal',
            agents: [agent(2, 'João da Silva'), agent(1, 'Maria da Silva')],
          },
        ],
      })
    );

    expect(entries).toEqual([
      { header: 'CADSUS' },
      expect.objectContaining({
        name: 'Fulano de Tal',
        connectaOrgUnitId: 'u2',
      }),
      expect.objectContaining({
        name: 'Tal de Fulano',
        connectaOrgUnitId: 'u2',
      }),
      { header: 'Hospital Municipal' },
      expect.objectContaining({
        name: 'João da Silva',
        connectaOrgUnitId: null,
      }),
      expect.objectContaining({
        name: 'Maria da Silva',
        connectaOrgUnitId: null,
      }),
    ]);
    expect(entries.filter(isMenuHeader)).toHaveLength(2);
  });
});
