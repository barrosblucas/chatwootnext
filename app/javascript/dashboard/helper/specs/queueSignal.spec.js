import {
  buildBotBadgeFilters,
  createTrailingGuard,
} from '../queueSignal';

describe('#queueSignal', () => {
  describe('#createTrailingGuard', () => {
    it('runs immediately when the list is idle', () => {
      const run = vi.fn();
      const guard = createTrailingGuard(run, () => false);
      guard.fire();
      expect(run).toHaveBeenCalledTimes(1);
    });

    it('defers the refresh while loading and replays one trailing refresh on settle', () => {
      const run = vi.fn();
      let loading = true;
      const guard = createTrailingGuard(run, () => loading);
      guard.fire();
      guard.fire();
      expect(run).not.toHaveBeenCalled();
      guard.settle();
      expect(run).not.toHaveBeenCalled();
      loading = false;
      guard.settle();
      expect(run).toHaveBeenCalledTimes(1);
      guard.settle();
      expect(run).toHaveBeenCalledTimes(1);
    });
  });

  describe('#buildBotBadgeFilters', () => {
    it('asks by server conversation type even while another tab is selected', () => {
      const filters = buildBotBadgeFilters({
        inboxId: 3,
        status: 'open',
        assigneeType: 'me',
        excludeActiveBot: 'true',
        page: 4,
      });
      expect(filters).toEqual(
        expect.objectContaining({
          inboxId: 3,
          status: 'open',
          conversationType: 'bot',
        })
      );
      expect(filters.assigneeType).toBeUndefined();
      expect(filters.excludeActiveBot).toBeUndefined();
      expect(filters.page).toBeUndefined();
    });
  });
});
