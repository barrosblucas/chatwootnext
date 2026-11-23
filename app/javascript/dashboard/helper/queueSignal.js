// Queue-signal helpers for the open chat list (Bot + human tabs).
//
// `createTrailingGuard` keeps one pending refresh while the list is loading:
// a cable event that lands mid-load marks the refresh as pending instead of
// dropping it, and `settle` replays it once loading clears. The debounced
// caller stays in the component; this only owns the pending flag so it can
// be unit-tested without mounting the list.
//
// `buildBotBadgeFilters` derives the Bot badge request from the current list
// filters so the Bot count refreshes even while another tab is selected: the
// badge asks by server conversation type, never by assignee, and never sends
// the human `excludeActiveBot` opt-in (the server would answer it with zero).
import { BOT_TAB_KEY } from 'dashboard/helper/connectaBotTab';

export const createTrailingGuard = (run, isLoading) => {
  let pending = false;

  const fire = () => {
    if (isLoading()) {
      pending = true;
      return;
    }
    pending = false;
    run();
  };

  const settle = () => {
    if (!isLoading() && pending) fire();
  };

  return { fire, settle };
};

export const buildBotBadgeFilters = (filters = {}) => ({
  ...filters,
  assigneeType: undefined,
  conversationType: BOT_TAB_KEY,
  excludeActiveBot: undefined,
  page: undefined,
});
