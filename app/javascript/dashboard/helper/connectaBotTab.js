// Pure predicates for the Connecta Bot tab and the human opt-in exclusion.
// The server enforces every row; these only decide what the dashboard asks for,
// so no account, permission or customer identifier ever lives here.
import wootConstants from 'dashboard/constants/globals';

export const BOT_TAB_KEY = wootConstants.ASSIGNEE_TYPE.BOT;

export const isBotTab = tabKey => tabKey === BOT_TAB_KEY;

// The Bot tab only exists on the plain open queue: never on mentions,
// participating, unattended or custom views, and never on resolved or
// advanced-filtered lists, which keep their own semantics untouched.
export const isBotTabVisible = ({
  connectaEnabled,
  conversationType,
  status,
}) => {
  return (
    Boolean(connectaEnabled) &&
    !conversationType &&
    status === wootConstants.STATUS_TYPE.OPEN
  );
};

// Ordinary open human queues opt into the server-side Bot exclusion. Anywhere
// else the server would ignore the flag, so nothing else sends it and no other
// view can trigger the external lookup by accident.
export const shouldExcludeActiveBot = ({
  connectaEnabled,
  conversationType,
  status,
  hasFiltersOrFolders,
}) => {
  return (
    isBotTabVisible({ connectaEnabled, conversationType, status }) &&
    !hasFiltersOrFolders
  );
};
