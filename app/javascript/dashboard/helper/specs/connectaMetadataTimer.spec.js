import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { startConnectaMetadataTimer } from '../connectaMetadataTimer';

describe('startConnectaMetadataTimer', () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());

  it('dispara no intervalo e para no cleanup, sem timer vazado', () => {
    const refresh = vi.fn();
    const stop = startConnectaMetadataTimer(refresh, 60000);

    vi.advanceTimersByTime(180000);
    expect(refresh).toHaveBeenCalledTimes(3);

    stop();
    vi.advanceTimersByTime(180000);
    expect(refresh).toHaveBeenCalledTimes(3);
  });
});
