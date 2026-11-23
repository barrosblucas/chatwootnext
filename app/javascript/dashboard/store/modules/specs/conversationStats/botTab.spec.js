import axios from 'axios';
import { actions, mutations } from '../../conversationStats';
import types from '../../../mutation-types';

vi.mock('axios');
vi.mock('@chatwoot/utils', () => ({
  debounce: vi.fn(fn => fn),
}));

describe('#conversationStats Bot', () => {
  describe('#SET_CONV_TAB_META', () => {
    it('captures the degraded-classification flag only when the server sends it', () => {
      const state = { botClassificationUnavailable: null };
      mutations[types.SET_CONV_TAB_META](state, {
        mine_count: 1,
        unassigned_count: 2,
        all_count: 3,
      });
      expect(state.botClassificationUnavailable).toBe(null);

      mutations[types.SET_CONV_TAB_META](state, {
        mine_count: 1,
        unassigned_count: 1,
        all_count: 2,
        bot_classification_unavailable: true,
      });
      expect(state.botClassificationUnavailable).toBe(true);

      // A later answer without the flag (unopted view, Bot tab) keeps the
      // last known classification state instead of clearing it.
      mutations[types.SET_CONV_TAB_META](state, {
        mine_count: 1,
        unassigned_count: 1,
        all_count: 2,
      });
      expect(state.botClassificationUnavailable).toBe(true);

      mutations[types.SET_CONV_TAB_META](state, {
        mine_count: 1,
        unassigned_count: 1,
        all_count: 2,
        bot_classification_unavailable: false,
      });
      expect(state.botClassificationUnavailable).toBe(false);
    });
  });

  describe('#SET_BOT_TAB_META', () => {
    it('tracks the Bot badge count apart from the human badges', () => {
      const state = { botCount: 0, allCount: 5 };
      mutations[types.SET_BOT_TAB_META](state, { count: 2 });
      expect(state).toEqual(
        expect.objectContaining({ botCount: 2, allCount: 5 })
      );
    });
  });

  describe('#setBotMeta', () => {
    it('commits the Bot count', () => {
      const commit = vi.fn();
      actions.setBotMeta({ commit }, { count: 4 });
      expect(commit).toHaveBeenCalledWith(types.SET_BOT_TAB_META, {
        count: 4,
      });
    });
  });

  describe('#get Bot meta routing', () => {
    it('routes Bot meta answers to the Bot badge, never to human badges', async () => {
      const commit = vi.fn();
      axios.get.mockResolvedValue({
        data: { meta: { mine_count: 0, unassigned_count: 0, all_count: 2 } },
      });
      actions.get({ commit, state: { allCount: 1 } }, { conversationType: 'bot' });
      await vi.waitFor(() => {
        expect(commit).toHaveBeenCalledWith(types.SET_BOT_TAB_META, {
          count: 2,
        });
      });
      expect(commit).not.toHaveBeenCalledWith(
        types.SET_CONV_TAB_META,
        expect.anything()
      );
    });

    it('keeps routing human meta answers to the human badges', async () => {
      const commit = vi.fn();
      axios.get.mockResolvedValue({
        data: {
          meta: {
            mine_count: 1,
            unassigned_count: 1,
            all_count: 2,
            bot_classification_unavailable: false,
          },
        },
      });
      actions.get(
        { commit, state: { allCount: 1 } },
        { status: 'open', assigneeType: 'unassigned' }
      );
      await vi.waitFor(() => {
        expect(commit).toHaveBeenCalledWith(types.SET_CONV_TAB_META, {
          mine_count: 1,
          unassigned_count: 1,
          all_count: 2,
          bot_classification_unavailable: false,
        });
      });
      expect(commit).not.toHaveBeenCalledWith(
        types.SET_BOT_TAB_META,
        expect.anything()
      );
    });
  });
});
