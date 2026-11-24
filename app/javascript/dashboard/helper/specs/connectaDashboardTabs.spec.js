import {
  CONNECTA_DASHBOARD_OPT_IN,
  assigneeKeyForConnectaTab,
  buildConnectaListParams,
  buildConnectaMetaParams,
  connectaTabForAssigneeKey,
  countKeyForConnectaTab,
  extractConnectaAllCount,
  extractOrgUnitOptions,
  isConnectaDashboardContext,
  isConnectaDashboardParams,
  isConnectaTab,
  isValidOrgUnitId,
} from '../connectaDashboardTabs';

// Shared list/count mapping for the Connecta dashboard tabs (Correcao 02):
// Minhas <- me, Aguardando <- unassigned, Todos <- all, Bot <- bot. Badges
// and lists ask the same opt-in question; hidden tabs are never asked for.
describe('connectaDashboardTabs', () => {
  describe('tab mapping', () => {
    it.each([
      ['me', 'minhas'],
      ['unassigned', 'aguardando'],
      ['all', 'todos'],
      ['bot', 'bot'],
    ])('maps assignee key %s to connecta tab %s', (key, tab) => {
      expect(connectaTabForAssigneeKey(key)).toBe(tab);
      expect(assigneeKeyForConnectaTab(tab)).toBe(key);
      expect(isConnectaTab(tab)).toBe(true);
    });

    it('returns null for unmapped keys and tabs', () => {
      expect(connectaTabForAssigneeKey('assigned')).toBe(null);
      expect(assigneeKeyForConnectaTab('minha')).toBe(null);
      expect(isConnectaTab('assigned')).toBe(false);
    });

    it('maps each tab to a distinct badge slot', () => {
      expect(countKeyForConnectaTab('minhas')).toBe('mineCount');
      expect(countKeyForConnectaTab('aguardando')).toBe('unAssignedCount');
      expect(countKeyForConnectaTab('todos')).toBe('allCount');
      expect(countKeyForConnectaTab('bot')).toBe('botCount');
      expect(countKeyForConnectaTab('nope')).toBe(null);
    });
  });

  describe('isConnectaDashboardContext', () => {
    it('is true for the plain open queue with the flag on', () => {
      expect(
        isConnectaDashboardContext({
          connectaEnabled: true,
          conversationType: '',
          hasFiltersOrFolders: false,
        })
      ).toBe(true);
    });

    it.each([
      [
        {
          connectaEnabled: false,
          conversationType: '',
          hasFiltersOrFolders: false,
        },
      ],
      [
        {
          connectaEnabled: true,
          conversationType: 'mention',
          hasFiltersOrFolders: false,
        },
      ],
      [
        {
          connectaEnabled: true,
          conversationType: '',
          hasFiltersOrFolders: true,
        },
      ],
    ])('is false outside the plain queue (%o)', context => {
      expect(isConnectaDashboardContext(context)).toBe(false);
    });

    it('does not depend on inbox, team, status or account', () => {
      // Grants are never derived from inbox or team: those stay filters.
      expect(
        isConnectaDashboardContext({
          connectaEnabled: true,
          conversationType: undefined,
          hasFiltersOrFolders: false,
        })
      ).toBe(true);
    });
  });

  describe('isConnectaDashboardParams', () => {
    it('accepts the exact opt-in contract', () => {
      expect(
        isConnectaDashboardParams({
          connectaDashboard: 'true',
          connectaTab: 'aguardando',
        })
      ).toBe(true);
    });

    it.each([
      [{ connectaDashboard: 'true', connectaTab: 'assigned' }],
      [{ connectaDashboard: '1', connectaTab: 'minhas' }],
      [{ connectaDashboard: true, connectaTab: 'minhas' }],
      [{ connectaTab: 'minhas' }],
      [{}],
    ])('rejects %o', params => {
      expect(isConnectaDashboardParams(params)).toBe(false);
    });
  });

  describe('isValidOrgUnitId', () => {
    it.each([[1], ['3'], [42]])('accepts positive integer %o', value => {
      expect(isValidOrgUnitId(value)).toBe(true);
    });

    it.each([[0], [-2], ['abc'], [1.5], [null], [undefined], ['']])(
      'rejects %o (aggregates instead)',
      value => {
        expect(isValidOrgUnitId(value)).toBe(false);
      }
    );
  });

  describe('buildConnectaListParams', () => {
    const filters = {
      inboxId: 4,
      status: 'open',
      teamId: 9,
      labels: ['vip'],
      groupType: 'individual',
      sortBy: 'last_activity_at_desc',
      page: 2,
      assigneeType: 'me',
      conversationType: 'mention',
      excludeActiveBot: 'true',
    };

    it('keeps identical active filters plus sorting and pagination', () => {
      expect(buildConnectaListParams('me', filters)).toEqual({
        inboxId: 4,
        status: 'open',
        teamId: 9,
        labels: ['vip'],
        groupType: 'individual',
        sortBy: 'last_activity_at_desc',
        page: 2,
        connectaDashboard: CONNECTA_DASHBOARD_OPT_IN,
        connectaTab: 'minhas',
      });
    });

    it('maps every visible tab and drops the native selectors', () => {
      expect(buildConnectaListParams('unassigned', filters).connectaTab).toBe(
        'aguardando'
      );
      expect(buildConnectaListParams('all', filters).connectaTab).toBe('todos');
      expect(buildConnectaListParams('bot', filters).connectaTab).toBe('bot');
      const params = buildConnectaListParams('all', filters);
      expect(params.assigneeType).toBeUndefined();
      expect(params.conversationType).toBeUndefined();
      expect(params.excludeActiveBot).toBeUndefined();
    });

    it('sends no org unit id without a real selection (aggregates)', () => {
      const params = buildConnectaListParams('me', filters);
      expect(params.connectaOrgUnitId).toBeUndefined();
    });

    it('forwards a real selected unit and drops malformed ones', () => {
      expect(
        buildConnectaListParams('me', filters, { orgUnitId: 7 })
          .connectaOrgUnitId
      ).toBe(7);
      expect(
        buildConnectaListParams('me', filters, { orgUnitId: 'x' })
          .connectaOrgUnitId
      ).toBeUndefined();
    });

    it('leaves unmapped tabs untouched', () => {
      expect(buildConnectaListParams('assigned', filters)).toEqual(filters);
    });
  });

  describe('buildConnectaMetaParams', () => {
    const filters = {
      inboxId: 4,
      status: 'resolved',
      teamId: 9,
      labels: ['vip'],
      groupType: 'individual',
      sortBy: 'last_activity_at_desc',
      page: 3,
    };

    it('shares the list filters without page and sorting', () => {
      const list = buildConnectaListParams('all', filters);
      const meta = buildConnectaMetaParams('all', filters);
      expect(meta).toEqual({
        inboxId: 4,
        status: 'resolved',
        teamId: 9,
        labels: ['vip'],
        groupType: 'individual',
        connectaDashboard: CONNECTA_DASHBOARD_OPT_IN,
        connectaTab: 'todos',
      });
      expect(meta.page).toBeUndefined();
      expect(meta.sortBy).toBeUndefined();
      expect(meta.connectaTab).toBe(list.connectaTab);
    });
  });

  describe('extractConnectaAllCount', () => {
    it('reads the exact total from the meta envelope', () => {
      expect(
        extractConnectaAllCount({ data: { meta: { all_count: 12 } } })
      ).toBe(12);
    });

    it('reads the exact total from the list envelope', () => {
      expect(
        extractConnectaAllCount({
          data: { data: { meta: { all_count: 7 }, payload: [] } },
        })
      ).toBe(7);
    });

    it.each([[undefined], [null], ['12'], [{ data: { meta: {} } }]])(
      'treats %o as unknown, never zero',
      response => {
        expect(extractConnectaAllCount(response)).toBe(null);
      }
    );

    it('keeps a successful zero', () => {
      expect(
        extractConnectaAllCount({ data: { meta: { all_count: 0 } } })
      ).toBe(0);
    });
  });

  describe('extractOrgUnitOptions', () => {
    it('reads id/name pairs from the catalog envelope', () => {
      expect(
        extractOrgUnitOptions({
          org_units: [
            { id: 3, name: 'Setor A' },
            { id: 5, name: 'Setor B' },
          ],
        })
      ).toEqual([
        { id: 3, name: 'Setor A' },
        { id: 5, name: 'Setor B' },
      ]);
    });

    it('drops malformed entries instead of offering them', () => {
      expect(
        extractOrgUnitOptions({
          org_units: [
            { id: 3, name: 'Setor A' },
            { id: 0, name: 'Zero' },
            { id: -1, name: 'Negativo' },
            { id: 'x', name: 'Texto' },
            { id: 4, name: '' },
            { id: 5 },
            { name: 'Sem id' },
            null,
            'Setor C',
          ],
        })
      ).toEqual([{ id: 3, name: 'Setor A' }]);
    });

    it.each([[undefined], [null], [{}], [{ org_units: null }], ['x']])(
      'treats %o as no authorized sector',
      payload => {
        expect(extractOrgUnitOptions(payload)).toEqual([]);
      }
    );
  });
});
