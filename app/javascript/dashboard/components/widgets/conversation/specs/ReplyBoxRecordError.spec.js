import {
  AUDIO_RECORD_CONVERSION_ERROR_KEY,
  AUDIO_RECORD_INIT_ERROR_KEYS,
  resolveRecordErrorKey,
} from '../helpers/audioRecordError';

describe('resolveRecordErrorKey', () => {
  it.each([
    ['INSECURE_CONTEXT', 'CONVERSATION.REPLYBOX.AUDIO_INIT_INSECURE_CONTEXT'],
    ['API_UNAVAILABLE', 'CONVERSATION.REPLYBOX.AUDIO_INIT_UNAVAILABLE'],
    ['PERMISSION_DENIED', 'CONVERSATION.REPLYBOX.AUDIO_INIT_PERMISSION_DENIED'],
    [
      'DEVICE_UNAVAILABLE',
      'CONVERSATION.REPLYBOX.AUDIO_INIT_DEVICE_UNAVAILABLE',
    ],
    ['UNKNOWN', 'CONVERSATION.REPLYBOX.AUDIO_INIT_FAILED'],
  ])('maps init failure %s to an honest message key', (code, key) => {
    expect(resolveRecordErrorKey(code)).toBe(key);
  });

  it.each([
    ['conversion failure', 'CONVERSION_FAILED'],
    ['legacy payload without a code', undefined],
    ['missing payload', null],
  ])('keeps blaming the conversion for %s', (_, code) => {
    expect(resolveRecordErrorKey(code)).toBe(AUDIO_RECORD_CONVERSION_ERROR_KEY);
  });

  it('covers every init code the recorder can emit', () => {
    expect(Object.keys(AUDIO_RECORD_INIT_ERROR_KEYS).sort()).toEqual(
      [
        'API_UNAVAILABLE',
        'DEVICE_UNAVAILABLE',
        'INSECURE_CONTEXT',
        'PERMISSION_DENIED',
        'UNKNOWN',
      ].sort()
    );
  });
});
