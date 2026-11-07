import axios from 'axios';
import actions from '../actions';
import { mutations } from '../index';
import {
  attachmentSignature,
  clearConnectaMediaInflight,
  collectMarkedEmbeddedMessages,
  compareUpdatedAt,
  connectaMediaInflightSize,
  decideHydrateApply,
  needsConnectaMediaResolve,
  pickExactMessage,
  windowParamsFor,
} from '../helpers/connectaMediaRehydrate';

vi.mock('axios');
global.axios = axios;

const ACCOUNT_ID = 1;
const VIEWER_ID = 5;
const CONVERSATION_ID = 10;

const markedAttachment = (id = 7) => ({ id, file_type: 'image' });

const markedMessage = (overrides = {}) => ({
  id: 100,
  conversation_id: CONVERSATION_ID,
  content: 'foto',
  message_type: 0,
  status: 'sent',
  created_at: '2026-11-03T10:00:00.000Z',
  updated_at: '2026-11-03T10:00:00.000Z',
  attachments: [markedAttachment()],
  connecta_media_resolve: true,
  ...overrides,
});

const hydratedMessage = (overrides = {}) => {
  const { connecta_media_resolve: _dropped, ...rest } = markedMessage();
  return {
    ...rest,
    attachments: [
      {
        id: 7,
        file_type: 'image',
        data_url:
          '/api/v1/accounts/1/connecta_attachments/7/download?token=proprio',
        thumb_url:
          '/api/v1/accounts/1/connecta_attachments/7/download?thumb=1&token=proprio',
      },
    ],
    ...overrides,
  };
};

const makeCtx = (rootOverrides = {}) => {
  const state = {
    allConversations: [{ id: CONVERSATION_ID, messages: [] }],
    selectedChatId: CONVERSATION_ID,
    attachments: {},
    appliedFilters: [],
    currentInbox: null,
  };
  const rootGetters = {
    getCurrentAccountId: ACCOUNT_ID,
    getCurrentUserID: VIEWER_ID,
    ...rootOverrides,
  };
  const rootState = { route: { name: 'inbox_conversation' } };
  const commit = (type, payload) => mutations[type](state, payload);
  const dispatch = (type, payload) => {
    if (type.includes('/')) return undefined;
    return actions[type](
      { commit, dispatch, state, rootGetters, rootState },
      payload
    );
  };
  return { state, commit, dispatch, rootGetters, rootState };
};

const findMessage = (state, id = 100) =>
  state.allConversations[0].messages.find(
    message => String(message.id) === String(id)
  );

beforeEach(() => {
  vi.clearAllMocks();
  clearConnectaMediaInflight();
});

describe('connectaMediaRehydrate helpers (puros)', () => {
  it('needsConnectaMediaResolve so marca quando o marcador e true', () => {
    expect(needsConnectaMediaResolve(markedMessage())).toBe(true);
    expect(needsConnectaMediaResolve(hydratedMessage())).toBe(false);
    expect(needsConnectaMediaResolve(null)).toBe(false);
    expect(needsConnectaMediaResolve({ connecta_media_resolve: 'sim' })).toBe(
      false
    );
  });

  it('windowParamsFor usa after=id-1/before=id+1 (id 1 usa after 0)', () => {
    expect(windowParamsFor(100)).toEqual({ after: 99, before: 101 });
    expect(windowParamsFor(1)).toEqual({ after: 0, before: 2 });
    expect(windowParamsFor('x')).toBe(null);
  });

  it('pickExactMessage escolhe o id exato fora da primeira posicao', () => {
    const payload = [{ id: 98 }, { id: 100 }, { id: 101 }];
    expect(pickExactMessage(payload, 100)).toEqual({ id: 100 });
    expect(pickExactMessage(payload, 999)).toBe(undefined);
  });

  it('compareUpdatedAt nunca clobber com timestamp ilegivel', () => {
    const base = { updated_at: '2026-11-03T10:00:00.000Z' };
    expect(
      compareUpdatedAt(base, { updated_at: '2026-11-03T10:01:00.000Z' })
    ).toBe(1);
    expect(
      compareUpdatedAt({ updated_at: '2026-11-03T10:01:00.000Z' }, base)
    ).toBe(-1);
    expect(compareUpdatedAt(base, { ...base })).toBe(0);
    expect(compareUpdatedAt(base, { updated_at: 'invalido' })).toBe(null);
    expect(compareUpdatedAt({ updated_at: null }, base)).toBe(null);
  });

  it('decideHydrateApply: commit so com snapshot >= evento; refetch limitado', () => {
    const current = markedMessage();
    const newer = hydratedMessage({
      updated_at: '2026-11-03T10:05:00.000Z',
    });
    expect(decideHydrateApply(current, newer)).toBe('commit');

    const older = hydratedMessage({
      updated_at: '2026-10-03T10:00:00.000Z',
    });
    expect(decideHydrateApply(current, older)).toBe('refetch');

    const sameTimeOtherIds = hydratedMessage({
      attachments: [{ id: 999, file_type: 'image', data_url: 'x' }],
    });
    expect(decideHydrateApply(current, sameTimeOtherIds)).toBe('refetch');

    const hydratedCurrent = hydratedMessage();
    expect(decideHydrateApply(hydratedCurrent, hydratedMessage())).toBe('keep');
    expect(decideHydrateApply(hydratedCurrent, newer)).toBe('commit');
    expect(decideHydrateApply(current, undefined)).toBe('keep');
    expect(decideHydrateApply(undefined, newer)).toBe('commit');
  });

  it('attachmentSignature compara so ids', () => {
    expect(attachmentSignature(markedMessage())).toBe('7');
    expect(attachmentSignature(hydratedMessage())).toBe('7');
    expect(attachmentSignature({})).toBe('');
  });

  it('collectMarkedEmbeddedMessages pega seed e preview', () => {
    const marked = markedMessage();
    expect(
      collectMarkedEmbeddedMessages({
        messages: [{ id: 1 }, marked],
        last_non_activity_message: markedMessage({ id: 200 }),
      })
    ).toHaveLength(2);
    expect(collectMarkedEmbeddedMessages({ messages: [{ id: 1 }] })).toEqual(
      []
    );
    expect(collectMarkedEmbeddedMessages(null)).toEqual([]);
  });
});

describe('resolveConnectaMediaMessage (store)', () => {
  it('hidrata created marcado via janela exata e preserva texto', async () => {
    axios.get.mockResolvedValue({
      data: { meta: {}, payload: [{ id: 99 }, hydratedMessage()] },
    });
    const { state, dispatch } = makeCtx();

    await dispatch('addMessage', markedMessage());

    expect(axios.get).toHaveBeenCalledTimes(1);
    expect(axios.get.mock.calls[0][1]).toEqual({
      params: { before: 101, after: 99 },
    });
    const stored = findMessage(state);
    expect(stored.connecta_media_resolve).toBe(undefined);
    expect(stored.attachments[0].data_url).toContain('token=proprio');
    expect(stored.content).toBe('foto');
    expect(connectaMediaInflightSize()).toBe(0);
  });

  it('created->updated atrasado: nao troca atualizacao nova por snapshot antigo', async () => {
    let releaseGet;
    axios.get.mockReturnValueOnce(
      new Promise(resolve => {
        releaseGet = resolve;
      })
    );
    const { state, dispatch } = makeCtx();

    const first = dispatch('addMessage', markedMessage());
    const updated = markedMessage({
      content: 'foto editada',
      updated_at: '2026-11-03T10:05:00.000Z',
    });
    const second = dispatch('updateMessage', updated);
    // Snapshot antigo resolve depois do update: deve refazer UMA vez.
    releaseGet({ data: { meta: {}, payload: [hydratedMessage()] } });
    axios.get.mockResolvedValueOnce({
      data: {
        meta: {},
        payload: [
          hydratedMessage({
            content: 'foto editada',
            updated_at: '2026-11-03T10:05:00.000Z',
          }),
        ],
      },
    });
    await Promise.all([first, second]);

    expect(axios.get).toHaveBeenCalledTimes(2);
    const stored = findMessage(state);
    expect(stored.content).toBe('foto editada');
    expect(stored.attachments[0].data_url).toContain('token=proprio');
    expect(connectaMediaInflightSize()).toBe(0);
  });

  it('update sobre GET bom mantem URLs proprias sem nova busca', async () => {
    axios.get.mockResolvedValue({
      data: { meta: {}, payload: [hydratedMessage()] },
    });
    const { state, dispatch } = makeCtx();

    await dispatch('addMessage', markedMessage());
    expect(axios.get).toHaveBeenCalledTimes(1);

    await dispatch(
      'updateMessage',
      markedMessage({
        content: 'legenda nova',
        status: 'delivered',
        updated_at: '2026-11-03T10:05:00.000Z',
      })
    );

    expect(axios.get).toHaveBeenCalledTimes(1);
    const stored = findMessage(state);
    expect(stored.content).toBe('legenda nova');
    expect(stored.attachments[0].data_url).toContain('token=proprio');
    expect(stored.connecta_media_resolve).toBe(undefined);
  });

  it('timestamps iguais com ids diferentes disparam releitura limitada', async () => {
    axios.get
      .mockResolvedValueOnce({
        data: { meta: {}, payload: [hydratedMessage()] },
      })
      .mockResolvedValueOnce({
        data: {
          meta: {},
          payload: [
            hydratedMessage({
              attachments: [
                { id: 8, file_type: 'image', data_url: 'nova-url-propria' },
              ],
            }),
          ],
        },
      });
    const { state, dispatch } = makeCtx();

    const pending = dispatch(
      'addMessage',
      markedMessage({ attachments: [markedAttachment(8)] })
    );
    await pending;

    expect(axios.get).toHaveBeenCalledTimes(2);
    expect(findMessage(state).attachments[0].data_url).toBe('nova-url-propria');
  });

  it('dedup corrida: dois eventos rapidos disparam um unico GET', async () => {
    axios.get.mockResolvedValue({
      data: { meta: {}, payload: [hydratedMessage()] },
    });
    const { dispatch } = makeCtx();

    const first = dispatch('addMessage', markedMessage());
    const second = dispatch('updateMessage', markedMessage());
    await Promise.all([first, second]);

    expect(axios.get).toHaveBeenCalledTimes(1);
    expect(connectaMediaInflightSize()).toBe(0);
  });

  it('troca de viewer descarta o resultado (sem compartilhar entre usuarios)', async () => {
    let releaseGet;
    axios.get.mockReturnValueOnce(
      new Promise(resolve => {
        releaseGet = resolve;
      })
    );
    const ctx = makeCtx();
    const pending = ctx.dispatch('addMessage', markedMessage());

    ctx.rootGetters.getCurrentUserID = 999;
    releaseGet({ data: { meta: {}, payload: [hydratedMessage()] } });
    await pending;

    const stored = findMessage(ctx.state);
    expect(stored.attachments[0].data_url).toBe(undefined);
    expect(stored.connecta_media_resolve).toBe(true);
    expect(connectaMediaInflightSize()).toBe(0);
  });

  it('GET negado (403) mantem placeholder sem reintroduzir URL legada', async () => {
    axios.get.mockRejectedValueOnce({ response: { status: 403 } });
    const { state, dispatch } = makeCtx();

    await dispatch('addMessage', markedMessage());

    const stored = findMessage(state);
    expect(stored.connecta_media_resolve).toBe(true);
    expect(stored.attachments[0].data_url).toBe(undefined);
    expect(stored.content).toBe('foto');
    expect(connectaMediaInflightSize()).toBe(0);
  });

  it('mensagem sem marcador segue o fluxo normal sem GET', async () => {
    const { state, dispatch } = makeCtx();
    const plain = hydratedMessage();

    await dispatch('addMessage', { ...plain, message_type: 0 });

    expect(axios.get).not.toHaveBeenCalled();
    expect(findMessage(state).attachments[0].data_url).toContain(
      'token=proprio'
    );
  });

  it('resolve anexos embutidos em conversation created/updated', async () => {
    axios.get.mockResolvedValue({
      data: { meta: {}, payload: [hydratedMessage()] },
    });
    const { state, dispatch } = makeCtx();

    await dispatch('addConversation', {
      id: CONVERSATION_ID,
      inbox_id: 3,
      meta: {},
      messages: [markedMessage()],
      last_non_activity_message: markedMessage({ id: 200 }),
    });

    expect(axios.get).toHaveBeenCalled();
    expect(connectaMediaInflightSize()).toBe(0);
    expect(findMessage(state).attachments[0].data_url).toContain(
      'token=proprio'
    );
  });

  it('id 1 usa after 0 (parametro falsy omitido pelo MessageApi)', async () => {
    axios.get.mockResolvedValue({
      data: { meta: {}, payload: [hydratedMessage({ id: 1 })] },
    });
    const { dispatch } = makeCtx();

    await dispatch('addMessage', markedMessage({ id: 1 }));

    expect(axios.get.mock.calls[0][1]).toEqual({ params: { before: 2 } });
  });
});
