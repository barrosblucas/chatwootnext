import { describe, it, expect, vi, beforeEach } from 'vitest';
import {
  navigateToConversationList,
  isConnectaScopedConversation,
  leaveConnectaConversationAfterResolve,
} from '../connectaResolveLeave';
import conversationAPI from 'dashboard/api/inbox/conversation';
import types from 'dashboard/store/mutation-types';

vi.mock('dashboard/api/inbox/conversation', () => ({
  default: {
    showConnectaScope: vi.fn(),
  },
}));

const mockEmit = vi.fn();
vi.mock('shared/helpers/mitt', () => ({
  emitter: { emit: (...args) => mockEmit(...args) },
}));

describe('connectaResolveLeave', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  const buildStore = (metadata = null, withGetter = true) => ({
    commit: vi.fn(),
    dispatch: vi.fn(),
    getters: withGetter
      ? { 'connectaMetadata/getMetadata': vi.fn().mockReturnValue(metadata) }
      : {},
  });

  describe('navigateToConversationList', () => {
    it('volta para o dashboard da conta na visão padrão', () => {
      const router = { push: vi.fn() };
      const route = { name: 'home', params: { accountId: '1' } };

      navigateToConversationList(router, route, 1);

      expect(router.push).toHaveBeenCalledWith('/app/accounts/1/dashboard');
    });

    it('preserva a aba de menções', () => {
      const router = { push: vi.fn() };
      const route = {
        name: 'conversation_mentions',
        params: { accountId: '7' },
      };

      navigateToConversationList(router, route, 7);

      expect(router.push).toHaveBeenCalledWith(
        '/app/accounts/7/mentions/conversations'
      );
    });

    it('preserva o filtro da inbox atual', () => {
      const router = { push: vi.fn() };
      const route = {
        name: 'inbox_conversation',
        params: { accountId: '3', inbox_id: '9' },
      };

      navigateToConversationList(router, route, 3);

      expect(router.push).toHaveBeenCalledWith('/app/accounts/3/inbox/9');
    });
  });

  describe('isConnectaScopedConversation', () => {
    it('usa o metadado em cache sem chamar a API', async () => {
      const store = buildStore({ case_protocol: 'BND000001' });

      await expect(isConnectaScopedConversation(store, 42)).resolves.toBe(true);
      expect(conversationAPI.showConnectaScope).not.toHaveBeenCalled();
    });

    it('consulta o endpoint de escopo quando não há metadado em cache', async () => {
      const store = buildStore(null);
      conversationAPI.showConnectaScope.mockResolvedValue({
        data: { state: 'active' },
      });

      await expect(isConnectaScopedConversation(store, 42)).resolves.toBe(true);
      expect(conversationAPI.showConnectaScope).toHaveBeenCalledWith(42);
    });

    it('retorna false quando o endpoint nega (404)', async () => {
      const store = buildStore(null);
      conversationAPI.showConnectaScope.mockRejectedValue({
        response: { status: 404 },
      });

      await expect(isConnectaScopedConversation(store, 42)).resolves.toBe(
        false
      );
    });
  });

  describe('leaveConnectaConversationAfterResolve', () => {
    const baseArgs = (store, overrides = {}) => ({
      store,
      router: { push: vi.fn() },
      route: { name: 'home', params: { accountId: '1' } },
      accountId: 1,
      conversationId: 42,
      connectaEnabled: true,
      isOpenConversation: true,
      ...overrides,
    });

    it('não faz nada com a flag Connecta desligada (sem nem checar escopo)', async () => {
      const store = buildStore({ case_protocol: 'BND000001' });

      const left = await leaveConnectaConversationAfterResolve(
        baseArgs(store, { connectaEnabled: false })
      );

      expect(left).toBe(false);
      expect(conversationAPI.showConnectaScope).not.toHaveBeenCalled();
      expect(store.commit).not.toHaveBeenCalled();
    });

    it('não faz nada fora de escopo Connecta', async () => {
      const store = buildStore(null);
      conversationAPI.showConnectaScope.mockRejectedValue({
        response: { status: 404 },
      });

      const left = await leaveConnectaConversationAfterResolve(baseArgs(store));

      expect(left).toBe(false);
      expect(store.commit).not.toHaveBeenCalled();
      expect(store.dispatch).not.toHaveBeenCalled();
    });

    it('remove da lista e navega quando a conversa aberta é escopada', async () => {
      const store = buildStore({ case_protocol: 'BND000001' });
      const args = baseArgs(store);

      const left = await leaveConnectaConversationAfterResolve(args);

      expect(left).toBe(true);
      expect(store.commit).toHaveBeenCalledWith(types.REVOKE_CONNECTA_SCOPE, {
        conversation_id: 42,
      });
      expect(store.dispatch).toHaveBeenCalledWith(
        'connectaMetadata/invalidate',
        42
      );
      expect(mockEmit).toHaveBeenCalledWith('fetch_conversation_stats');
      expect(args.router.push).toHaveBeenCalledWith(
        '/app/accounts/1/dashboard'
      );
    });

    it('remove da lista sem navegar quando a conversa não é a aberta', async () => {
      const store = buildStore({ case_protocol: 'BND000001' });
      const args = baseArgs(store, { isOpenConversation: false });

      const left = await leaveConnectaConversationAfterResolve(args);

      expect(left).toBe(true);
      expect(store.commit).toHaveBeenCalledWith(types.REVOKE_CONNECTA_SCOPE, {
        conversation_id: 42,
      });
      expect(args.router.push).not.toHaveBeenCalled();
    });
  });
});
