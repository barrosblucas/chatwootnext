import {
  BOT_TAB_KEY,
  isBotTab,
  isBotTabVisible,
  shouldExcludeActiveBot,
} from '../../helper/connectaBotTab';

describe('#connectaBotTab', () => {
  describe('#isBotTab', () => {
    it('matches only the Bot key, never human tabs', () => {
      expect(isBotTab('bot')).toBe(true);
      expect(isBotTab('me')).toBe(false);
      expect(isBotTab('unassigned')).toBe(false);
      expect(isBotTab('all')).toBe(false);
      expect(BOT_TAB_KEY).toBe('bot');
    });
  });

  describe('#isBotTabVisible', () => {
    it('shows on the plain open queue with the runtime flag', () => {
      expect(
        isBotTabVisible({
          connectaEnabled: true,
          conversationType: '',
          status: 'open',
        })
      ).toBe(true);
    });

    it('hides without the runtime flag, never inferring from labels', () => {
      expect(
        isBotTabVisible({
          connectaEnabled: false,
          conversationType: '',
          status: 'open',
        })
      ).toBe(false);
    });

    it('hides on scoped views and non-open statuses', () => {
      expect(
        isBotTabVisible({
          connectaEnabled: true,
          conversationType: 'mention',
          status: 'open',
        })
      ).toBe(false);
      expect(
        isBotTabVisible({
          connectaEnabled: true,
          conversationType: 'participating',
          status: 'open',
        })
      ).toBe(false);
      expect(
        isBotTabVisible({
          connectaEnabled: true,
          conversationType: '',
          status: 'resolved',
        })
      ).toBe(false);
    });
  });

  describe('#shouldExcludeActiveBot', () => {
    it('opts in only the plain open human list', () => {
      expect(
        shouldExcludeActiveBot({
          connectaEnabled: true,
          conversationType: '',
          status: 'open',
          hasFiltersOrFolders: false,
        })
      ).toBe(true);
    });

    it('stays out of filtered, scoped and resolved views', () => {
      const base = {
        connectaEnabled: true,
        conversationType: '',
        status: 'open',
        hasFiltersOrFolders: false,
      };
      expect(
        shouldExcludeActiveBot({ ...base, hasFiltersOrFolders: true })
      ).toBe(false);
      expect(
        shouldExcludeActiveBot({ ...base, conversationType: 'mention' })
      ).toBe(false);
      expect(shouldExcludeActiveBot({ ...base, status: 'resolved' })).toBe(
        false
      );
      expect(shouldExcludeActiveBot({ ...base, connectaEnabled: false })).toBe(
        false
      );
    });
  });
});
