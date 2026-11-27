import axios from 'axios';
import ConnectaAssignableAgentsAPI from '../connectaAssignableAgents';
import ConversationAPI from '../inbox/conversation';

global.axios = axios;
vi.mock('axios');

describe('ConnectaAssignableAgentsAPI', () => {
  beforeEach(() => {
    axios.get.mockReset();
    window.history.pushState({}, '', '/app/accounts/1/');
  });

  it('asks the department endpoint with every selected conversation id', async () => {
    axios.get.mockResolvedValue({ data: { grouped: false, groups: [] } });

    await ConnectaAssignableAgentsAPI.get([7, 3]);

    expect(axios.get).toHaveBeenCalledTimes(1);
    expect(axios.get).toHaveBeenCalledWith(
      '/api/v1/accounts/1/connecta/assignable_agents',
      { params: { 'conversation_ids[]': [7, 3] } }
    );
  });
});

describe('ConversationAPI.assignAgent cross-department move', () => {
  beforeEach(() => {
    axios.post.mockReset();
    window.history.pushState({}, '', '/app/accounts/1/');
  });

  it('omits connecta_org_unit_id inside the conversation department', async () => {
    axios.post.mockResolvedValue({ data: {} });

    await ConversationAPI.assignAgent({
      conversationId: 9,
      agentId: 1,
      assigneeType: 'User',
      connectaOrgUnitId: null,
    });

    expect(axios.post).toHaveBeenCalledWith(
      '/api/v1/accounts/1/conversations/9/assignments',
      {
        assignee_id: 1,
        assignee_type: 'User',
      }
    );
  });

  it('sends connecta_org_unit_id for another-department agents', async () => {
    axios.post.mockResolvedValue({ data: {} });

    await ConversationAPI.assignAgent({
      conversationId: 9,
      agentId: 3,
      assigneeType: 'User',
      connectaOrgUnitId: 'unit-2',
    });

    expect(axios.post).toHaveBeenCalledWith(
      '/api/v1/accounts/1/conversations/9/assignments',
      {
        assignee_id: 3,
        assignee_type: 'User',
        connecta_org_unit_id: 'unit-2',
      }
    );
  });
});
