// Shared Connecta dashboard tab contract (Correcao 02).
//
// Single source for the opt-in list/count mapping used by ChatList, the API
// layer and the conversation stores, so a tab badge and its list always ask
// the same question. API contract: `connecta_dashboard=true` (string),
// `connecta_tab=minhas|aguardando|todos|bot`, optional
// `connecta_org_unit_id` positive integer for a real selected sector.
// Without a selection nothing travels and the server aggregates every sector
// the actor is authorized for. Grants are never derived from inbox or team.
//
// The dashboard sector filter offers the authorized catalog options from
// `GET .../connecta/org_units` (id/name of the enabled sectors the actor may
// read, same boundary as the selected filter; the existing transfer/admission
// pickers stay per-conversation). Without a selection nothing travels and the
// server aggregates every authorized sector. Grants are never derived from
// inbox or team.
import wootConstants from 'dashboard/constants/globals';
import { BOT_TAB_KEY } from 'dashboard/helper/connectaBotTab';

export const CONNECTA_DASHBOARD_OPT_IN = 'true';

export const CONNECTA_TABS = Object.freeze([
  'minhas',
  'aguardando',
  'todos',
  'bot',
]);

// Native assignee-tab key -> Connecta tab. `unassigned` is the Aguardando
// seat: triaged conversations with a sector and a generated protocol, not the
// native never-assigned predicate (the server owns membership either way).
const ASSIGNEE_KEY_TO_CONNECTA_TAB = Object.freeze({
  [wootConstants.ASSIGNEE_TYPE.ME]: 'minhas',
  [wootConstants.ASSIGNEE_TYPE.UNASSIGNED]: 'aguardando',
  [wootConstants.ASSIGNEE_TYPE.ALL]: 'todos',
  [BOT_TAB_KEY]: 'bot',
});

const CONNECTA_TAB_TO_COUNT_KEY = Object.freeze({
  minhas: 'mineCount',
  aguardando: 'unAssignedCount',
  todos: 'allCount',
  bot: 'botCount',
});

export const connectaTabForAssigneeKey = key =>
  ASSIGNEE_KEY_TO_CONNECTA_TAB[key] ?? null;

const CONNECTA_TAB_TO_ASSIGNEE_KEY = Object.freeze(
  Object.fromEntries(
    Object.entries(ASSIGNEE_KEY_TO_CONNECTA_TAB).map(([key, tab]) => [tab, key])
  )
);

export const assigneeKeyForConnectaTab = tab =>
  CONNECTA_TAB_TO_ASSIGNEE_KEY[tab] ?? null;

export const countKeyForConnectaTab = tab =>
  CONNECTA_TAB_TO_COUNT_KEY[tab] ?? null;

export const isConnectaTab = tab => CONNECTA_TABS.includes(tab);

// The Connecta queue context reuses the existing plain-queue marker: the
// global human-number flag with no conversation type and no advanced
// filter/folder narrowing. Status stays a filter (Todos spans active+closed),
// inbox/team/labels stay filters, sorting and pagination stay native.
export const isConnectaDashboardContext = ({
  connectaEnabled,
  conversationType,
  hasFiltersOrFolders,
}) => {
  return (
    Boolean(connectaEnabled) &&
    !conversationType &&
    !hasFiltersOrFolders
  );
};

export const isConnectaDashboardParams = (params = {}) =>
  params?.connectaDashboard === CONNECTA_DASHBOARD_OPT_IN &&
  isConnectaTab(params?.connectaTab);

// Only a positive integer travels; anything else aggregates (absent).
export const isValidOrgUnitId = value => {
  const id = typeof value === 'string' ? Number(value) : value;
  return Number.isInteger(id) && id > 0;
};

const pickBaseFilters = (filters = {}) => {
  const picked = {};
  if (filters.inboxId !== undefined) picked.inboxId = filters.inboxId;
  if (filters.status !== undefined) picked.status = filters.status;
  if (filters.teamId !== undefined) picked.teamId = filters.teamId;
  if (filters.labels !== undefined) picked.labels = filters.labels;
  if (filters.groupType !== undefined) picked.groupType = filters.groupType;
  return picked;
};

// List params for one visible tab: identical active filters to the badge
// request, plus native sorting/pagination. Native assignee/conversation type
// and the legacy Bot exclusion are dropped: under the opt-in the server
// ignores them and they would only suggest a different question.
export const buildConnectaListParams = (
  filters = {},
  assigneeKey,
  { orgUnitId } = {}
) => {
  const tab = connectaTabForAssigneeKey(assigneeKey);
  if (!tab) return { ...filters };
  const params = {
    ...pickBaseFilters(filters),
    ...(filters.sortBy !== undefined ? { sortBy: filters.sortBy } : {}),
    ...(filters.page !== undefined ? { page: filters.page } : {}),
    connectaDashboard: CONNECTA_DASHBOARD_OPT_IN,
    connectaTab: tab,
  };
  if (isValidOrgUnitId(orgUnitId)) {
    params.connectaOrgUnitId = Number(orgUnitId);
  }
  return params;
};

// Badge params for one visible tab: the same active filters as the list
// above, without page/sorting (the meta endpoint takes neither).
export const buildConnectaMetaParams = (
  filters = {},
  assigneeKey,
  { orgUnitId } = {}
) => {
  const tab = connectaTabForAssigneeKey(assigneeKey);
  if (!tab) return { ...pickBaseFilters(filters) };
  const params = {
    ...pickBaseFilters(filters),
    connectaDashboard: CONNECTA_DASHBOARD_OPT_IN,
    connectaTab: tab,
  };
  if (isValidOrgUnitId(orgUnitId)) {
    params.connectaOrgUnitId = Number(orgUnitId);
  }
  return params;
};

// Exact tab total per the response envelope: meta answers carry
// `meta.all_count`, list answers carry `data.meta.all_count`. Anything else
// (missing, non-numeric) is unknown, never zero.
export const extractConnectaAllCount = response => {
  const meta =
    response?.data?.meta ?? response?.data?.data?.meta ?? response?.meta;
  const count = meta?.all_count ?? meta?.allCount;
  return typeof count === 'number' && Number.isFinite(count) ? count : null;
};

// Sector catalog options for the dashboard filter: the server answers
// `{ org_units: [{ id, name }] }` with only the enabled sectors the actor may
// read. Malformed entries are dropped, never offered as a choice; anything
// but that envelope is no authorized sector.
const toOrgUnitId = value => {
  const id = typeof value === 'string' ? Number(value) : value;
  return Number.isInteger(id) && id > 0 ? id : null;
};

export const extractOrgUnitOptions = (payload = {}) => {
  const rows = Array.isArray(payload?.org_units) ? payload.org_units : [];
  return rows
    .filter(
      row =>
        row &&
        typeof row === 'object' &&
        toOrgUnitId(row.id) !== null &&
        typeof row.name === 'string' &&
        row.name.length > 0
    )
    .map(row => ({ id: toOrgUnitId(row.id), name: row.name }));
};
