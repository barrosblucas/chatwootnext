/* global axios */
import ApiClient from './ApiClient';

// Department-aware assignee source. The backend filters by the actor's
// departments (same department as the conversation, every department of a
// multi-department user, every department for admins) and sorts server-side.
class ConnectaAssignableAgentsApi extends ApiClient {
  constructor() {
    super('connecta/assignable_agents', { accountScoped: true });
  }

  get(conversationIds) {
    return axios.get(this.url, {
      params: { 'conversation_ids[]': conversationIds },
    });
  }
}

export default new ConnectaAssignableAgentsApi();
