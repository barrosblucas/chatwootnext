// Focused coverage for the bounded IndexedDB open: a blocked openDB must
// reject instead of hanging list spinners, must stay retryable, and a late
// success must be kept without unhandled rejections. The idb module is mocked
// here so the open can be held pending; real-database behavior stays covered
// in DataManger.spec.js.
import { openDB } from 'idb';
import {
  DataManager,
  DATA_MANAGER_INIT_TIMEOUT_MS,
} from '../../CacheHelper/DataManager';

vi.mock('idb', () => ({
  openDB: vi.fn(),
}));

describe('DataManager init timeout', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    openDB.mockImplementation(() => new Promise(() => {}));
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('rejects bounded when the open hangs and keeps retrying', async () => {
    const manager = new DataManager('hung-account');

    const first = manager.initDb();
    const firstAssertion = expect(first).rejects.toThrow(
      'IndexedDB init timed out'
    );
    await vi.advanceTimersByTimeAsync(DATA_MANAGER_INIT_TIMEOUT_MS);
    await firstAssertion;
    expect(manager.db).toBeNull();

    // The timed-out open does not wedge the manager: the next read retries.
    const second = manager.initDb();
    const secondAssertion = expect(second).rejects.toThrow(
      'IndexedDB init timed out'
    );
    await vi.advanceTimersByTimeAsync(DATA_MANAGER_INIT_TIMEOUT_MS);
    await secondAssertion;
    expect(openDB).toHaveBeenCalledTimes(2);
  });

  it('keeps a late open success for the next read without unhandled rejections', async () => {
    let resolveOpen;
    openDB.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          resolveOpen = resolve;
        })
    );
    const manager = new DataManager('late-account');

    const pending = manager.initDb();
    const assertion = expect(pending).rejects.toThrow(
      'IndexedDB init timed out'
    );
    await vi.advanceTimersByTimeAsync(DATA_MANAGER_INIT_TIMEOUT_MS);
    await assertion;

    // IndexedDB settles after the timeout already fell back to the network.
    resolveOpen({ fake: 'connection' });
    await vi.advanceTimersByTimeAsync(0);
    expect(manager.db).toEqual({ fake: 'connection' });

    // The kept connection answers the next read without opening again.
    await expect(manager.initDb()).resolves.toEqual({ fake: 'connection' });
    expect(openDB).toHaveBeenCalledTimes(1);
  });

  it('shares one open across concurrent reads', async () => {
    const manager = new DataManager('shared-account');

    const first = manager.initDb();
    const second = manager.initDb();
    first.catch(() => {});
    second.catch(() => {});
    await vi.advanceTimersByTimeAsync(DATA_MANAGER_INIT_TIMEOUT_MS);
    await expect(first).rejects.toThrow();
    await expect(second).rejects.toThrow();
    expect(openDB).toHaveBeenCalledTimes(1);
  });
});
