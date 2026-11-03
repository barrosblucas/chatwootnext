<script setup>
import getUuid from 'widget/helpers/uuid';
import { ref, onMounted, onUnmounted } from 'vue';
import WaveSurfer from 'wavesurfer.js';
import RecordPlugin from 'wavesurfer.js/dist/plugins/record.js';
import { format, intervalToDuration } from 'date-fns';
import { convertAudio } from './utils/audioConversionUtils';

const props = defineProps({
  audioRecordFormat: {
    type: String,
    required: true,
  },
});

const emit = defineEmits([
  'recorderProgressChanged',
  'finishRecord',
  'pause',
  'play',
  'recordError',
]);

const waveformContainer = ref(null);
const wavesurfer = ref(null);
const record = ref(null);
const isRecording = ref(false);
const isPlaying = ref(false);
const hasRecording = ref(false);
const recordedAudioUrl = ref(null);

const formatTimeProgress = time => {
  const duration = intervalToDuration({ start: 0, end: time });
  return format(
    new Date(0, 0, 0, 0, duration.minutes, duration.seconds),
    'mm:ss'
  );
};

const AUDIO_EXTENSION_MAP = {
  'audio/ogg': 'ogg',
  'audio/mp3': 'mp3',
  'audio/mpeg': 'mp3',
  'audio/wav': 'wav',
  'audio/webm': 'webm',
};

const getRecordPluginOptions = audioFormat => {
  const options = {
    scrollingWaveform: true,
    renderRecordedAudio: false,
  };
  if (
    audioFormat === 'audio/ogg' &&
    typeof MediaRecorder !== 'undefined' &&
    MediaRecorder.isTypeSupported('audio/ogg;codecs=opus')
  ) {
    options.mimeType = 'audio/ogg;codecs=opus';
  }
  return options;
};

// Why these exist: startRecording can fail before any audio is captured
// (insecure HTTP origin, missing browser API, denied permission, no device).
// The code travels with the recordError event so the composer can tell the
// agent what actually happened instead of blaming the audio conversion.
const RECORD_ERROR_CODES = {
  INSECURE_CONTEXT: 'INSECURE_CONTEXT',
  API_UNAVAILABLE: 'API_UNAVAILABLE',
  PERMISSION_DENIED: 'PERMISSION_DENIED',
  DEVICE_UNAVAILABLE: 'DEVICE_UNAVAILABLE',
  CONVERSION_FAILED: 'CONVERSION_FAILED',
  UNKNOWN: 'UNKNOWN',
};

const classifyStartError = error => {
  const name = error?.name || '';
  if (name === 'NotAllowedError' || name === 'SecurityError') {
    return RECORD_ERROR_CODES.PERMISSION_DENIED;
  }
  if (
    name === 'NotFoundError' ||
    name === 'OverconstrainedError' ||
    name === 'NotReadableError' ||
    name === 'AbortError'
  ) {
    return RECORD_ERROR_CODES.DEVICE_UNAVAILABLE;
  }
  return RECORD_ERROR_CODES.UNKNOWN;
};

const initWaveSurfer = () => {
  wavesurfer.value = WaveSurfer.create({
    container: waveformContainer.value,
    waveColor: '#1F93FF',
    progressColor: '#6E6F73',
    height: 100,
    barWidth: 2,
    barGap: 1,
    barRadius: 2,
    plugins: [
      RecordPlugin.create(getRecordPluginOptions(props.audioRecordFormat)),
    ],
  });

  wavesurfer.value.on('pause', () => emit('pause'));
  wavesurfer.value.on('play', () => emit('play'));

  record.value = wavesurfer.value.plugins[0];

  wavesurfer.value.on('finish', () => {
    isPlaying.value = false;
  });

  record.value.on('record-end', async blob => {
    try {
      const audioBlob = await convertAudio(blob, props.audioRecordFormat);
      // Use the converted blob's actual type, which may differ from the
      // requested format when the browser can't produce it (e.g. Safari falls
      // back to MP3 instead of OGG). This keeps the filename, content type, and
      // voice-note flag consistent with the real bytes.
      const audioType = audioBlob.type || props.audioRecordFormat;
      const ext = AUDIO_EXTENSION_MAP[audioType] || 'mp3';
      const fileName = `${getUuid()}.${ext}`;
      const file = new File([audioBlob], fileName, {
        type: audioType,
      });
      if (recordedAudioUrl.value) URL.revokeObjectURL(recordedAudioUrl.value);
      recordedAudioUrl.value = URL.createObjectURL(audioBlob);
      wavesurfer.value.load(recordedAudioUrl.value);
      emit('finishRecord', {
        name: file.name,
        type: file.type,
        size: file.size,
        file,
      });
      hasRecording.value = true;
      isRecording.value = false;
    } catch (error) {
      isRecording.value = false;
      hasRecording.value = false;
      emit('recordError', {
        code: RECORD_ERROR_CODES.CONVERSION_FAILED,
        error,
      });
    }
  });

  record.value.on('record-progress', time => {
    emit('recorderProgressChanged', formatTimeProgress(time));
  });
};

const stopRecording = () => {
  // A stop without a running capture is a no-op: the init may have failed
  // and already reported, and a second stop must not throw or re-emit.
  if (!isRecording.value) return;
  isRecording.value = false;
  try {
    record.value?.stopRecording();
  } catch {
    // State is already "stopped", so there is nothing left to report.
  }
};

// Async on purpose: the Record plugin requests the microphone here, which
// rejects on insecure origins, missing APIs, denied permission or absent
// devices. isRecording flips only after the mic is actually open, so the
// composer never shows a frozen 00:00 for a capture that never started.
const startRecording = async () => {
  if (isRecording.value) return;
  // getUserMedia is gated to secure contexts; on plain HTTP there is no
  // prompt and no recording, so report it instead of simulating one.
  if (typeof window !== 'undefined' && window.isSecureContext === false) {
    emit('recordError', { code: RECORD_ERROR_CODES.INSECURE_CONTEXT });
    return;
  }
  if (!navigator?.mediaDevices?.getUserMedia) {
    emit('recordError', { code: RECORD_ERROR_CODES.API_UNAVAILABLE });
    return;
  }
  try {
    // Awaiting covers both a synchronous throw and a rejected promise.
    await record.value.startRecording();
    isRecording.value = true;
  } catch (error) {
    isRecording.value = false;
    emit('recordError', {
      code: classifyStartError(error),
      error,
    });
  }
};

const playPause = () => {
  if (hasRecording.value) {
    wavesurfer.value.playPause();
    isPlaying.value = !isPlaying.value;
  }
};

onMounted(async () => {
  try {
    initWaveSurfer();
    await startRecording();
  } catch (error) {
    // startRecording already reports its own failures; this only guards the
    // init path so a setup throw never becomes an unhandled rejection.
    isRecording.value = false;
    emit('recordError', { code: classifyStartError(error), error });
  }
});

onUnmounted(() => {
  try {
    if (isRecording.value) {
      isRecording.value = false;
      record.value?.stopRecording();
    }
  } catch {
    // Teardown must not throw after the component is already gone.
  }
  if (recordedAudioUrl.value) {
    URL.revokeObjectURL(recordedAudioUrl.value);
    recordedAudioUrl.value = null;
  }
  if (wavesurfer.value) {
    wavesurfer.value.destroy();
    wavesurfer.value = null;
  }
});

defineExpose({ playPause, stopRecording, record });
</script>

<template>
  <div ref="waveformContainer" class="w-full p-1" />
</template>
