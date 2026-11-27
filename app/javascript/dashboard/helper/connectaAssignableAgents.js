/**
 * Connecta department-aware assignable agents.
 *
 * Pure helpers over the payload of
 * `GET /api/v1/accounts/:id/connecta/assignable_agents`:
 *
 *   {
 *     grouped: bool,
 *     conversation_org_unit_id: uuid|null,
 *     groups: [
 *       { org_unit_id: uuid|null, org_unit_name: string|null, agents: [...] }
 *     ]
 *   }
 *
 * The server already filters (agents of the conversation's own department, or
 * of the actor's departments for multi-department users / admins) and sorts.
 * Every helper below still sorts defensively with pt-BR collation so a stale
 * or hand-built payload can never show an out-of-order list.
 */

const collator = (a, b) =>
  String(a ?? '').localeCompare(String(b ?? ''), 'pt-BR', {
    sensitivity: 'base',
  });

export const sortAgentsByName = (agents = []) =>
  [...agents].sort((a, b) => collator(a?.name, b?.name));

const sortGroupsByName = (groups = []) =>
  [...groups].sort((a, b) => {
    // A null department name (conversation without a unit) always goes last.
    if (a?.org_unit_name == null && b?.org_unit_name == null) return 0;
    if (a?.org_unit_name == null) return 1;
    if (b?.org_unit_name == null) return -1;
    return collator(a.org_unit_name, b.org_unit_name);
  });

// The automatic-attendance agent must never appear in a manual picker.
const HIDDEN_AGENT_NAMES = [/^atendimento autom[aá]tico$/i];

export const isHiddenAssignableAgent = agent =>
  HIDDEN_AGENT_NAMES.some(pattern => pattern.test(String(agent?.name ?? '')));

const visibleAgents = (agents = []) =>
  agents.filter(agent => !isHiddenAssignableAgent(agent));

export const normalizeAssignableAgentsPayload = (data = {}) => {
  const groups = Array.isArray(data.groups) ? data.groups : [];
  return {
    grouped: data.grouped === true,
    conversationOrgUnitId: data.conversation_org_unit_id ?? null,
    groups: sortGroupsByName(
      groups.map(group => ({
        orgUnitId: group?.org_unit_id ?? null,
        orgUnitName: group?.org_unit_name ?? null,
        agents: sortAgentsByName(visibleAgents(group?.agents)),
      }))
    ),
  };
};

/**
 * Flat alphabetical list for dropdowns (sidebar, cmd+K, bulk).
 * Each agent carries `connectaOrgUnitId`: the org unit of the group it came
 * from when that differs from the conversation's own unit (a cross-department
 * move), otherwise null. Bulk callers ignore the field on purpose.
 */
export const flatAgentsFromPayload = payload => {
  if (!payload) return [];
  const flat = [];
  payload.groups.forEach(group => {
    group.agents.forEach(agent => {
      flat.push({
        ...agent,
        connectaOrgUnitId:
          group.orgUnitId !== payload.conversationOrgUnitId
            ? group.orgUnitId
            : null,
      });
    });
  });
  return sortAgentsByName(flat);
};

/**
 * Entries for the right-click "Atribuir Agente" submenu: "None" is rendered
 * by the caller first; then either a flat list or department headers each
 * followed by their users. Headers are data-only (`{ header: name }`), the
 * caller renders them as non-clickable rows.
 */
export const menuEntriesFromPayload = payload => {
  if (!payload) return [];
  if (!payload.grouped) return flatAgentsFromPayload(payload);
  const entries = [];
  payload.groups.forEach(group => {
    entries.push({ header: group.orgUnitName });
    group.agents.forEach(agent => {
      entries.push({
        ...agent,
        connectaOrgUnitId:
          group.orgUnitId !== payload.conversationOrgUnitId
            ? group.orgUnitId
            : null,
      });
    });
  });
  return entries;
};

export const isMenuHeader = entry => entry != null && 'header' in entry;
