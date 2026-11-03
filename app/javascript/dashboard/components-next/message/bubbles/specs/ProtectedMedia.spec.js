import axios from 'axios';
import { defineComponent, ref } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import ImageBubble from '../Image.vue';
import AudioChip from 'dashboard/components-next/message/chips/Audio.vue';
import FileChip from 'dashboard/components-next/message/chips/File.vue';
import GalleryView from 'dashboard/components/widgets/conversation/components/GalleryView.vue';
import { provideMessageContext } from '../../provider.js';
import { MESSAGE_VARIANTS, ORIENTATION } from '../../constants';

vi.mock('axios');
vi.mock('dashboard/composables/loadWithRetry', () => ({
  useLoadWithRetry: () => ({
    isLoaded: { value: true },
    hasError: { value: false },
    loadWithRetry: () => undefined,
  }),
}));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ getters: {} }),
  useStoreGetters: () => ({ getCurrentUser: { value: { id: 1 } } }),
  useMapGetter: () => ({ value: [] }),
  useFunctionGetter: () => () => undefined,
}));

global.axios = axios;

const PROTECTED =
  '/api/v1/accounts/7/connecta_attachments/42/download?token=abc';
const PLAIN_IMAGE = 'https://cdn.example.com/f/photo.png';

const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: { en: {} },
});

const storeMocks = {
  $store: { getters: { getSelectedChatAttachments: [] } },
};

const mountImageBubble = dataUrl => {
  const TestHost = defineComponent({
    components: { ImageBubble },
    setup() {
      provideMessageContext({
        attachments: ref([{ fileType: 'image', dataUrl }]),
        filteredCurrentChatAttachments: ref([]),
        variant: ref(MESSAGE_VARIANTS.AGENT),
        orientation: ref(ORIENTATION.RIGHT),
        contentAttributes: ref({}),
        additionalAttributes: ref({}),
        shouldGroupWithNext: ref(false),
        inReplyTo: ref(null),
        id: ref(1),
        sender: ref({}),
        senderType: ref('user'),
      });
    },
    template: '<ImageBubble />',
  });

  return mount(TestHost, {
    global: {
      plugins: [i18n],
      mocks: { ...storeMocks, $t: key => key },
      stubs: {
        BaseBubble: { template: '<div><slot /></div>' },
        GalleryView: true,
        Button: true,
        Icon: true,
      },
    },
  });
};

describe('protected dashboard media integration', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    if (typeof URL.createObjectURL !== 'function') {
      URL.createObjectURL = () => 'blob:mock-url';
    }
    if (typeof URL.revokeObjectURL !== 'function') {
      URL.revokeObjectURL = () => undefined;
    }
    vi.spyOn(URL, 'createObjectURL').mockReturnValue('blob:mock-url');
    vi.spyOn(URL, 'revokeObjectURL').mockImplementation(() => undefined);
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('image bubble resolves protected bytes through the session client', async () => {
    axios.get.mockResolvedValueOnce({
      data: new Blob(['img'], { type: 'image/png' }),
      headers: {
        'content-type': 'image/png',
        'content-disposition': 'attachment; filename="photo.png"',
      },
    });

    const wrapper = mountImageBubble(PROTECTED);
    await flushPromises();

    expect(axios.get).toHaveBeenCalledWith(
      PROTECTED,
      expect.objectContaining({ responseType: 'blob' })
    );
    const img = wrapper.find('img');
    expect(img.exists()).toBe(true);
    expect(img.attributes('src')).toBe('blob:mock-url');
  });

  it('image bubble leaves plain URLs on the legacy path', async () => {
    const wrapper = mountImageBubble(PLAIN_IMAGE);
    await flushPromises();

    expect(axios.get).not.toHaveBeenCalled();
    expect(wrapper.find('img').attributes('src')).toBe(PLAIN_IMAGE);
  });

  it('audio chip plays protected bytes without a timestamp query', async () => {
    axios.get.mockResolvedValueOnce({
      data: new Blob(['audio'], { type: 'audio/ogg' }),
      headers: { 'content-type': 'audio/ogg' },
    });

    const wrapper = mount(AudioChip, {
      props: { attachment: { fileType: 'audio', dataUrl: PROTECTED } },
      global: {
        plugins: [i18n],
        mocks: { $t: key => key },
        stubs: { Icon: true },
      },
    });
    await flushPromises();

    expect(axios.get).toHaveBeenCalledWith(
      PROTECTED,
      expect.objectContaining({ responseType: 'blob' })
    );
    expect(wrapper.find('source').attributes('src')).toBe('blob:mock-url');
  });

  it('audio chip keeps the timestamp cache-buster on plain absolute URLs', async () => {
    const wrapper = mount(AudioChip, {
      props: {
        attachment: {
          fileType: 'audio',
          dataUrl: 'https://cdn.example.com/f/voice.mp3',
        },
      },
      global: {
        plugins: [i18n],
        mocks: { $t: key => key },
        stubs: { Icon: true },
      },
    });
    await flushPromises();

    expect(axios.get).not.toHaveBeenCalled();
    expect(wrapper.find('source').attributes('src')).toMatch(
      /^https:\/\/cdn\.example\.com\/f\/voice\.mp3\?t=\d+$/
    );
  });

  it('file chip links protected bytes and shows the server filename', async () => {
    axios.get.mockResolvedValueOnce({
      data: new Blob(['pdf'], { type: 'application/pdf' }),
      headers: {
        'content-type': 'application/pdf',
        'content-disposition': 'attachment; filename="doc.pdf"',
      },
    });

    const wrapper = mount(FileChip, {
      props: {
        attachment: { fileType: 'file', dataUrl: PROTECTED, extension: 'pdf' },
      },
      global: {
        plugins: [i18n],
        mocks: { $t: key => key },
        directives: { tooltip: () => undefined },
        stubs: { FileIcon: true, Icon: true },
      },
    });
    await flushPromises();

    expect(wrapper.find('a').attributes('href')).toBe('blob:mock-url');
    expect(wrapper.text()).toContain('doc.pdf');
  });

  it('gallery resolves the active protected item for display', async () => {
    axios.get.mockResolvedValueOnce({
      data: new Blob(['img'], { type: 'image/png' }),
      headers: { 'content-type': 'image/png' },
    });

    const attachment = {
      message_id: 11,
      file_type: 'image',
      data_url: PROTECTED,
      created_at: Date.now(),
      sender: { id: 2, name: 'Agent', thumbnail: '' },
    };

    const wrapper = mount(GalleryView, {
      props: { attachment, allAttachments: [attachment], show: true },
      global: {
        plugins: [i18n],
        mocks: {
          $t: key => key,
          $store: { getters: { getCurrentUser: { id: 1 } } },
        },
        stubs: {
          'woot-modal': { template: '<div><slot /></div>' },
          TeleportWithDirection: { template: '<div><slot /></div>' },
          NextButton: true,
          Avatar: true,
        },
      },
    });
    await flushPromises();

    expect(axios.get).toHaveBeenCalledWith(
      PROTECTED,
      expect.objectContaining({ responseType: 'blob' })
    );
    expect(wrapper.find('img').attributes('src')).toBe('blob:mock-url');
  });
});
