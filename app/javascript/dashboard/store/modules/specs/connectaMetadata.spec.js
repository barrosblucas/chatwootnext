import { beforeEach, describe, expect, it, vi } from 'vitest';
import ConnectaAPI from 'dashboard/api/connecta';
import {
  actions,
  mutations,
  getters,
  CACHE_TTL_MS,
  MAX_BATCH_SIZE,
} from '../connectaMetadata';

vi.mock('dashboard/api/connecta', () => ({
  default: { conversationMetadata: vi.fn() },
}));

const makeState = () => ({
  records: {},
  checked: {},
  scope: { accountId: null, userId: null, epoch: 0 },
});

const contextFor = state => ({
  state,
  commit: (type, payload) => mutations[type](state, payload),
});

const metadata = id => ({
  case_protocol: `PROT-${id}`,
  org_unit_name: `Setor ${id}`,
  root_unit_name: 'Raiz',
});

describe('connectaMetadata store', () => {
  let state;
  let context;

  beforeEach(() => {
    vi.clearAllMocks();
    vi.useRealTimers();
    state = makeState();
    context = contextFor(state);
  });

  it('escopa o cache por conta e ator e reseta na troca', async () => {
    await actions.setScope(context, { accountId: 1, userId: 10 });
    ConnectaAPI.conversationMetadata.mockResolvedValue({
      data: { conversations: { 7: metadata(7) } },
    });
    await actions.fetch(context, [7]);

    expect(getters.getMetadata(state)(7)).toEqual(metadata(7));

    await actions.setScope(context, { accountId: 2, userId: 10 });
    expect(getters.getMetadata(state)(7)).toBeNull();
    expect(getters.isChecked(state)(7)).toBe(false);
  });

  it('descarta resposta em voo quando a conta/ator muda', async () => {
    await actions.setScope(context, { accountId: 1, userId: 10 });
    let resolveFetch;
    ConnectaAPI.conversationMetadata.mockReturnValue(
      new Promise(resolve => {
        resolveFetch = resolve;
      })
    );

    const pending = actions.fetch(context, [7]);
    await actions.setScope(context, { accountId: 2, userId: 10 });
    resolveFetch({ data: { conversations: { 7: metadata(7) } } });
    await pending;

    expect(getters.getMetadata(state)(7)).toBeNull();
    expect(state.records).toEqual({});
  });

  it('divide 51 ids em lotes de 50 e 1', async () => {
    await actions.setScope(context, { accountId: 1, userId: 10 });
    ConnectaAPI.conversationMetadata.mockResolvedValue({
      data: { conversations: {} },
    });
    const ids = Array.from({ length: 51 }, (_, index) => index + 1);

    await actions.fetch(context, ids);

    expect(ConnectaAPI.conversationMetadata).toHaveBeenCalledTimes(2);
    expect(ConnectaAPI.conversationMetadata.mock.calls[0][0]).toHaveLength(
      MAX_BATCH_SIZE
    );
    expect(ConnectaAPI.conversationMetadata.mock.calls[1][0]).toHaveLength(1);
  });

  it('falha parcial deixa só o lote que falhou para retry', async () => {
    await actions.setScope(context, { accountId: 1, userId: 10 });
    ConnectaAPI.conversationMetadata
      .mockResolvedValueOnce({ data: { conversations: { 1: metadata(1) } } })
      .mockRejectedValueOnce(new Error('offline'));
    const ids = Array.from({ length: 51 }, (_, index) => index + 1);

    await actions.fetch(context, ids);

    expect(getters.isChecked(state)(1)).toBe(true);
    expect(getters.isChecked(state)(51)).toBe(false);
    expect(getters.getMetadata(state)(1)).toEqual(metadata(1));
  });

  it('remove metadado antigo quando a API omite o id', async () => {
    await actions.setScope(context, { accountId: 1, userId: 10 });
    ConnectaAPI.conversationMetadata
      .mockResolvedValueOnce({ data: { conversations: { 7: metadata(7) } } })
      .mockResolvedValueOnce({ data: { conversations: {} } });

    await actions.fetch(context, [7]);
    expect(getters.getMetadata(state)(7)).toEqual(metadata(7));
    await actions.fetch(context, [7]);

    expect(getters.getMetadata(state)(7)).toBeNull();
    expect(getters.isChecked(state)(7)).toBe(true);
  });

  it('expira o cache e força nova busca após o TTL', async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-11-08T00:00:00Z'));
    await actions.setScope(context, { accountId: 1, userId: 10 });
    ConnectaAPI.conversationMetadata.mockResolvedValue({
      data: { conversations: { 7: metadata(7) } },
    });
    await actions.fetch(context, [7]);
    expect(getters.getMetadata(state)(7)).toEqual(metadata(7));

    vi.setSystemTime(new Date(Date.now() + CACHE_TTL_MS + 1));
    expect(getters.getMetadata(state)(7)).toBeNull();
    expect(getters.isChecked(state)(7)).toBe(false);
  });

  it('bumpEpoch limpa tudo e incrementa a chave', async () => {
    await actions.setScope(context, { accountId: 1, userId: 10 });
    ConnectaAPI.conversationMetadata.mockResolvedValue({
      data: { conversations: { 7: metadata(7) } },
    });
    await actions.fetch(context, [7]);

    actions.bumpEpoch(context);

    expect(getters.getMetadata(state)(7)).toBeNull();
    expect(getters.isChecked(state)(7)).toBe(false);
    expect(state.scope.epoch).toBe(1);
  });

  it('atualiza setor após reuso/transferência do mesmo display id', async () => {
    await actions.setScope(context, { accountId: 1, userId: 10 });
    ConnectaAPI.conversationMetadata
      .mockResolvedValueOnce({ data: { conversations: { 7: metadata(7) } } })
      .mockResolvedValueOnce({
        data: {
          conversations: {
            7: {
              case_protocol: 'PROT-7',
              org_unit_name: 'Setor Novo',
              root_unit_name: 'Raiz',
            },
          },
        },
      });

    await actions.fetch(context, [7]);
    await actions.invalidate(context, 7);
    await actions.fetch(context, [7]);

    expect(getters.getMetadata(state)(7).org_unit_name).toBe('Setor Novo');
  });

  it('invalida só o id atual', async () => {
    await actions.setScope(context, { accountId: 1, userId: 10 });
    ConnectaAPI.conversationMetadata.mockResolvedValue({
      data: { conversations: { 7: metadata(7), 8: metadata(8) } },
    });
    await actions.fetch(context, [7, 8]);

    await actions.invalidate(context, 7);

    expect(getters.getMetadata(state)(7)).toBeNull();
    expect(getters.getMetadata(state)(8)).toEqual(metadata(8));
  });
});
