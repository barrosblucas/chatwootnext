import { mount, flushPromises } from '@vue/test-utils';
import AudioRecorder from '../AudioRecorder.vue';

// The real WaveSurfer needs canvas/audio; the init paths under test only need
// the plugin surface (start/stop recording + event registration).
const { recordMock, wavesurferMock } = vi.hoisted(() => ({
  recordMock: {
    on: vi.fn(),
    startRecording: vi.fn(),
    stopRecording: vi.fn(),
  },
  wavesurferMock: {
    on: vi.fn(),
    load: vi.fn(),
    destroy: vi.fn(),
    plugins: [],
  },
}));
wavesurferMock.plugins = [recordMock];

vi.mock('wavesurfer.js', () => ({
  default: { create: vi.fn(() => wavesurferMock) },
}));

vi.mock('wavesurfer.js/dist/plugins/record.js', () => ({
  default: { create: vi.fn(() => recordMock) },
}));

const mounted = [];
afterEach(() => {
  while (mounted.length) mounted.pop().unmount();
  vi.restoreAllMocks();
});

const setSecureContext = value => {
  Object.defineProperty(window, 'isSecureContext', {
    value,
    configurable: true,
  });
};

const setMediaDevices = value => {
  Object.defineProperty(window.navigator, 'mediaDevices', {
    value,
    configurable: true,
  });
};

const mountRecorder = async () => {
  const wrapper = mount(AudioRecorder, {
    props: { audioRecordFormat: 'audio/mp3' },
  });
  mounted.push(wrapper);
  await flushPromises();
  return wrapper;
};

const recordError = wrapper => wrapper.emitted('recordError')?.[0]?.[0];

describe('AudioRecorder init', () => {
  it('reports insecure context without touching the mic or marking recording', async () => {
    setSecureContext(false);
    setMediaDevices({ getUserMedia: vi.fn() });
    recordMock.startRecording.mockResolvedValue(undefined);

    const wrapper = await mountRecorder();

    expect(recordMock.startRecording).not.toHaveBeenCalled();
    expect(recordError(wrapper)).toMatchObject({
      code: 'INSECURE_CONTEXT',
    });
    // A stop after a failed init is a no-op: no throw, no second emit.
    wrapper.vm.stopRecording();
    expect(recordMock.stopRecording).not.toHaveBeenCalled();
    expect(wrapper.emitted('recordError')).toHaveLength(1);
  });

  it('reports missing browser API without starting', async () => {
    setSecureContext(true);
    setMediaDevices(undefined);
    recordMock.startRecording.mockResolvedValue(undefined);

    const wrapper = await mountRecorder();

    expect(recordMock.startRecording).not.toHaveBeenCalled();
    expect(recordError(wrapper)).toMatchObject({ code: 'API_UNAVAILABLE' });
  });

  it('maps a denied permission to PERMISSION_DENIED', async () => {
    setSecureContext(true);
    setMediaDevices({ getUserMedia: vi.fn() });
    recordMock.startRecording.mockRejectedValue(
      new DOMException('denied', 'NotAllowedError')
    );

    const wrapper = await mountRecorder();

    expect(recordError(wrapper)).toMatchObject({
      code: 'PERMISSION_DENIED',
    });
    wrapper.vm.stopRecording();
    expect(recordMock.stopRecording).not.toHaveBeenCalled();
  });

  it('maps a missing device to DEVICE_UNAVAILABLE', async () => {
    setSecureContext(true);
    setMediaDevices({ getUserMedia: vi.fn() });
    recordMock.startRecording.mockRejectedValue(
      new DOMException('no device', 'NotFoundError')
    );

    const wrapper = await mountRecorder();

    expect(recordError(wrapper)).toMatchObject({
      code: 'DEVICE_UNAVAILABLE',
    });
  });

  it('maps an unexpected failure to UNKNOWN', async () => {
    setSecureContext(true);
    setMediaDevices({ getUserMedia: vi.fn() });
    recordMock.startRecording.mockRejectedValue(new Error('boom'));

    const wrapper = await mountRecorder();

    expect(recordError(wrapper)).toMatchObject({ code: 'UNKNOWN' });
  });

  it('marks recording only after the mic opens and stops cleanly', async () => {
    setSecureContext(true);
    setMediaDevices({ getUserMedia: vi.fn() });
    recordMock.startRecording.mockResolvedValue(undefined);

    const wrapper = await mountRecorder();

    expect(wrapper.emitted('recordError')).toBeUndefined();
    // stopRecording reaching the plugin proves isRecording flipped to true
    // only after the awaited start resolved.
    wrapper.vm.stopRecording();
    expect(recordMock.stopRecording).toHaveBeenCalledTimes(1);
    // A second stop is a no-op.
    wrapper.vm.stopRecording();
    expect(recordMock.stopRecording).toHaveBeenCalledTimes(1);
  });
});
