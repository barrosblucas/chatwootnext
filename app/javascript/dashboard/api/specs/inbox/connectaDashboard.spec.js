import conversationAPI from '../../inbox/conversation';

// The Connecta dashboard contract travels on both endpoints: the list and
// each visible badge ask `connecta_dashboard=true` (string) with their tab
// and the optional selected sector, next to the identical active filters.
// Synthetic params only; no network.
describe('#ConversationAPI Connecta dashboard contract', () => {
  const originalAxios = window.axios;
  const axiosMock = {
    post: vi.fn(() => Promise.resolve()),
    get: vi.fn(() => Promise.resolve()),
    patch: vi.fn(() => Promise.resolve()),
    delete: vi.fn(() => Promise.resolve()),
  };

  beforeEach(() => {
    window.axios = axiosMock;
    axiosMock.get.mockClear();
  });

  afterEach(() => {
    window.axios = originalAxios;
  });

  it('forwards the opt-in tab on the list endpoint with identical filters', () => {
    conversationAPI.get({
      inboxId: 4,
      status: 'open',
      teamId: 9,
      labels: ['vip'],
      groupType: 'individual',
      sortBy: 'last_activity_at_desc',
      page: 2,
      connectaDashboard: 'true',
      connectaTab: 'aguardando',
    });
    expect(axiosMock.get).toHaveBeenCalledWith('/api/v1/conversations', {
      params: expect.objectContaining({
        inbox_id: 4,
        status: 'open',
        team_id: 9,
        labels: ['vip'],
        group_type: 'individual',
        sort_by: 'last_activity_at_desc',
        page: 2,
        connecta_dashboard: 'true',
        connecta_tab: 'aguardando',
      }),
    });
  });

  it('sends no sector id without a real selection (aggregates)', () => {
    conversationAPI.get({
      status: 'open',
      page: 1,
      connectaDashboard: 'true',
      connectaTab: 'minhas',
    });
    expect(axiosMock.get.mock.calls[0][1].params.connecta_org_unit_id).toBe(
      undefined
    );
  });

  it('forwards a real selected sector when one is passed', () => {
    conversationAPI.get({
      status: 'open',
      page: 1,
      connectaDashboard: 'true',
      connectaTab: 'todos',
      connectaOrgUnitId: 7,
    });
    expect(axiosMock.get.mock.calls[0][1].params.connecta_org_unit_id).toBe(7);
  });

  it('forwards the opt-in tab on the meta endpoint without page or sorting', () => {
    conversationAPI.meta({
      inboxId: 4,
      status: 'open',
      teamId: 9,
      labels: ['vip'],
      groupType: 'individual',
      connectaDashboard: 'true',
      connectaTab: 'todos',
    });
    expect(axiosMock.get).toHaveBeenCalledWith('/api/v1/conversations/meta', {
      params: expect.objectContaining({
        inbox_id: 4,
        status: 'open',
        team_id: 9,
        connecta_dashboard: 'true',
        connecta_tab: 'todos',
      }),
    });
  });

  it('keeps native calls free of the opt-in keys', () => {
    conversationAPI.get({
      inboxId: 1,
      status: 'open',
      assigneeType: 'me',
      page: 1,
    });
    const params = axiosMock.get.mock.calls[0][1].params;
    expect(params.connecta_dashboard).toBe(undefined);
    expect(params.connecta_tab).toBe(undefined);
    expect(params.connecta_org_unit_id).toBe(undefined);
  });
});
