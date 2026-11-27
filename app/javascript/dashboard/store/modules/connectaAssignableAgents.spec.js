import { beforeEach, describe, expect, it, vi } from 'vitest';
import ConnectaAssignableAgentsAPI from '../../api/connectaAssignableAgents';
import storeModule, {
  actions,
  getters,
  mutations,
  types,
} from './connectaAssignableAgents';

vi.mock('../../api/connectaAssignableAgents');

const payload = conversationIds => ({
  grouped: true,
  conversation_org_unit_id: 'u1',
  groups: [
    {
      org_unit_id: 'u1',
      org_unit_name: 'Hospital Municipal',
      agents: [{ id: 1, name: 'Maria' }],
    },
  ],
  requested: conversationIds,
});

describe('connectaAssignableAgents store', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('fetches once per conversation set and caches by sorted ids', async () => {
    ConnectaAssignableAgentsAPI.get.mockResolvedValue({
      data: payload([2, 1]),
    });
    const commit = vi.fn();
    const first = await actions.fetch({ commit }, [2, 1]);
    const second = await actions.fetch({ commit }, [1]);

    expect(ConnectaAssignableAgentsAPI.get).toHaveBeenCalledTimes(2);
    expect(ConnectaAssignableAgentsAPI.get).toHaveBeenNthCalledWith(1, [2, 1]);
    // A second fetch for another conversation hits the endpoint again: no
    // stale list from the previous conversation is reused.
    expect(ConnectaAssignableAgentsAPI.get).toHaveBeenNthCalledWith(2, [1]);
    expect(first.groups[0].orgUnitName).toBe('Hospital Municipal');
    expect(second.groups[0].orgUnitName).toBe('Hospital Municipal');
    expect(commit).toHaveBeenCalledWith(
      types.SET_CONNECTA_ASSIGNABLE_AGENTS,
      expect.objectContaining({ key: '1,2' })
    );
  });

  it('getPayload reads back the exact key (no cross-conversation leak)', () => {
    const $state = {
      records: {
        5: { grouped: false, conversationOrgUnitId: null, groups: [] },
      },
    };
    expect(getters.getPayload($state)([5])).toEqual($state.records[5]);
    expect(getters.getPayload($state)([6])).toBeNull();
  });

  it('mutations store the payload under its key', () => {
    const $state = { records: {}, uiFlags: { isFetching: true } };
    const record = { grouped: false, conversationOrgUnitId: null, groups: [] };
    mutations[types.SET_CONNECTA_ASSIGNABLE_AGENTS]($state, {
      key: '7',
      payload: record,
    });
    mutations[types.SET_CONNECTA_ASSIGNABLE_AGENTS_UI_FLAG]($state, {
      isFetching: false,
    });
    expect($state.records['7']).toBe(record);
    expect($state.uiFlags.isFetching).toBe(false);
  });

  it('is registered in the dashboard store', () => {
    expect(storeModule.namespaced).toBe(true);
  });
});
