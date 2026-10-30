import { describe, expect, it } from 'vitest';
import types from 'dashboard/store/mutation-types';
import { mutations } from 'dashboard/store/modules/conversations';

const buildState = () => ({
  allConversations: [
    { id: 101, display_id: 101, inbox_id: 11 },
    { id: 202, display_id: 202, inbox_id: 22 },
    { id: 303, display_id: 303, inbox_id: 11 },
  ],
  attachments: {
    101: [{ id: 1 }],
    202: [{ id: 2 }],
    303: [{ id: 3 }],
  },
  selectedChatId: 101,
  conversationParticipants: [{ id: 9 }],
  conversationLastSeen: 123,
});

describe('REVOKE_CONNECTA_SCOPE', () => {
  it('removes only the revoked conversation (display_id payload) and its attachments', () => {
    const state = buildState();
    mutations[types.REVOKE_CONNECTA_SCOPE](state, {
      conversation_id: 202,
      inbox_id: 22,
      account_id: 1,
    });

    expect(state.allConversations.map(c => c.id)).toEqual([101, 303]);
    expect(state.attachments[202]).toBeUndefined();
    expect(state.attachments[101]).toHaveLength(1);
    expect(state.attachments[303]).toHaveLength(1);
    // Selected chat was not revoked: stays open.
    expect(state.selectedChatId).toBe(101);
  });

  it('clears the open window when the selected conversation is revoked', () => {
    const state = buildState();
    mutations[types.REVOKE_CONNECTA_SCOPE](state, {
      conversation_id: 101,
      inbox_id: 11,
      account_id: 1,
    });

    expect(state.allConversations.map(c => c.id)).toEqual([202, 303]);
    expect(state.selectedChatId).toBeNull();
    expect(state.conversationParticipants).toEqual([]);
    expect(state.conversationLastSeen).toBeNull();
  });

  it('ignores payloads without a scope target and unknown ids', () => {
    const state = buildState();
    mutations[types.REVOKE_CONNECTA_SCOPE](state, {});
    mutations[types.REVOKE_CONNECTA_SCOPE](state, {
      conversation_id: 999,
      account_id: 1,
    });

    expect(state.allConversations).toHaveLength(3);
    expect(state.selectedChatId).toBe(101);
  });
});
