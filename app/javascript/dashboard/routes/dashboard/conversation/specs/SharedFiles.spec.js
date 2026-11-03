import axios from 'axios';
import { mount, flushPromises } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { emitter } from 'shared/helpers/mitt';
import SharedFiles from '../SharedFiles.vue';

vi.mock('axios');
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: vi.fn() }),
  useStoreGetters: () => ({}),
  useMapGetter: key => {
    if (key === 'getSelectedChatAttachments') {
      return {
        value: [
          {
            id: 1,
            data_url: 'https://cdn.example.com/f/a.pdf',
            file_type: 'file',
          },
        ],
      };
    }
    if (key === 'getSelectedChatAttachmentsLoaded') return { value: true };
    return { value: undefined };
  },
  useFunctionGetter: () => () => undefined,
}));

global.axios = axios;

const PROTECTED =
  '/api/v1/accounts/1/connecta_attachments/9/download?token=abc';
const PLAIN = 'https://cdn.example.com/f/report.pdf';

const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: { en: {} },
});

const mountSharedFiles = () =>
  mount(SharedFiles, {
    global: {
      plugins: [i18n],
      mocks: { $t: key => key },
      stubs: {
        GalleryView: true,
        Media: true,
        Files: {
          name: 'Files',
          template: '<div />',
          emits: ['select'],
        },
        Spinner: true,
      },
    },
  });

const selectFile = async (wrapper, attachment) => {
  wrapper
    .findAllComponents({ name: 'Files' })
    .forEach(stub => stub.vm.$emit('select', attachment));
  await flushPromises();
};

describe('SharedFiles file select', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.spyOn(window, 'open').mockImplementation(() => null);
    vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(
      () => undefined
    );
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

  it('downloads protected files through the authenticated session', async () => {
    axios.get.mockResolvedValueOnce({
      data: new Blob(['pdf'], { type: 'application/pdf' }),
      headers: {
        'content-type': 'application/pdf',
        'content-disposition': 'attachment; filename="doc.pdf"',
      },
    });

    await selectFile(mountSharedFiles(), {
      data_url: PROTECTED,
      file_type: 'file',
      extension: 'pdf',
    });

    expect(axios.get).toHaveBeenCalledWith(
      PROTECTED,
      expect.objectContaining({ responseType: 'blob' })
    );
    expect(window.open).not.toHaveBeenCalled();
  });

  it('keeps opening plain URLs in a new tab without new headers', async () => {
    await selectFile(mountSharedFiles(), {
      data_url: PLAIN,
      file_type: 'file',
      extension: 'pdf',
    });

    expect(axios.get).not.toHaveBeenCalled();
    expect(window.open).toHaveBeenCalledWith(
      PLAIN,
      '_blank',
      'noopener,noreferrer'
    );
  });

  it('shows feedback when the protected fetch fails', async () => {
    axios.get.mockRejectedValueOnce({ response: { status: 404 } });
    const emitSpy = vi.spyOn(emitter, 'emit');

    await selectFile(mountSharedFiles(), {
      data_url: PROTECTED,
      file_type: 'file',
      extension: 'pdf',
    });

    expect(window.open).not.toHaveBeenCalled();
    expect(emitSpy).toHaveBeenCalledWith(
      'newToastMessage',
      expect.objectContaining({
        message: 'CONVERSATION_SIDEBAR.SHARED_FILES.DOWNLOAD_ERROR',
      })
    );
  });
});
