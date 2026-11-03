import axios from 'axios';
import { defineComponent, ref, nextTick } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import { useProtectedAttachmentUrl } from '../useProtectedAttachmentUrl';

vi.mock('axios');

global.axios = axios;

const PROTECTED =
  '/api/v1/accounts/7/connecta_attachments/42/download?token=abc';
const PLAIN = 'https://cdn.example.com/f/photo.png';

const hostWith = (source, template = '<div />') => {
  return defineComponent({
    setup() {
      const state = useProtectedAttachmentUrl(source);
      return { ...state };
    },
    template,
  });
};

describe('useProtectedAttachmentUrl', () => {
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

  it('passes non-protected URLs through without fetching', async () => {
    const wrapper = mount(hostWith(() => PLAIN));
    await flushPromises();

    expect(wrapper.vm.resolvedUrl).toBe(PLAIN);
    expect(wrapper.vm.isResolving).toBe(false);
    expect(wrapper.vm.resolveError).toBe(null);
    expect(axios.get).not.toHaveBeenCalled();
  });

  it('resolves protected URLs to an ObjectURL with the server filename', async () => {
    axios.get.mockResolvedValueOnce({
      data: new Blob(['bytes'], { type: 'image/png' }),
      headers: {
        'content-type': 'image/png',
        'content-disposition': 'attachment; filename="photo.png"',
      },
    });

    const wrapper = mount(hostWith(() => PROTECTED));
    expect(wrapper.vm.isResolving).toBe(true);
    await flushPromises();

    expect(axios.get).toHaveBeenCalledWith(
      PROTECTED,
      expect.objectContaining({ responseType: 'blob' })
    );
    expect(wrapper.vm.resolvedUrl).toBe('blob:mock-url');
    expect(wrapper.vm.fileName).toBe('photo.png');
    expect(wrapper.vm.isResolving).toBe(false);
    expect(wrapper.vm.resolveError).toBe(null);
  });

  it('surfaces 401/403/404 with the status and stays retryable', async () => {
    axios.get.mockRejectedValueOnce({ response: { status: 403 } });
    const wrapper = mount(hostWith(() => PROTECTED));
    await flushPromises();

    expect(wrapper.vm.resolvedUrl).toBe(null);
    expect(wrapper.vm.resolveError).not.toBe(null);
    expect(wrapper.vm.errorStatus).toBe(403);
    expect(wrapper.vm.isResolving).toBe(false);

    axios.get.mockResolvedValueOnce({
      data: new Blob(['ok']),
      headers: {},
    });
    await wrapper.vm.retry();
    await flushPromises();

    expect(wrapper.vm.resolvedUrl).toBe('blob:mock-url');
    expect(wrapper.vm.resolveError).toBe(null);
  });

  it('ignores stale responses when the source changes mid-flight', async () => {
    let firstResolve;
    const first = new Promise(resolve => {
      firstResolve = resolve;
    });
    axios.get.mockReturnValueOnce(first);
    axios.get.mockResolvedValueOnce({ data: new Blob(['new']), headers: {} });

    const source = ref(PROTECTED);
    const wrapper = mount(hostWith(source));
    source.value = `${PROTECTED}&v=2`;
    await flushPromises();

    expect(wrapper.vm.resolvedUrl).toBe('blob:mock-url');
    expect(axios.get).toHaveBeenCalledTimes(2);

    firstResolve({ data: new Blob(['stale']), headers: {} });
    await flushPromises();

    expect(URL.createObjectURL).toHaveBeenCalledTimes(1);
    expect(wrapper.vm.resolvedUrl).toBe('blob:mock-url');
  });

  it('revokes the previous ObjectURL when the source changes', async () => {
    axios.get.mockResolvedValue({ data: new Blob(['x']), headers: {} });
    const source = ref(PROTECTED);
    const wrapper = mount(hostWith(source));
    await flushPromises();
    expect(wrapper.vm.resolvedUrl).toBe('blob:mock-url');

    vi.mocked(URL.createObjectURL).mockReturnValueOnce('blob:second');
    source.value = `${PROTECTED}&v=3`;
    await flushPromises();

    expect(URL.revokeObjectURL).toHaveBeenCalledWith('blob:mock-url');
    expect(wrapper.vm.resolvedUrl).toBe('blob:second');
  });

  it('aborts in-flight requests and revokes on unmount', async () => {
    axios.get.mockReturnValueOnce(new Promise(() => {}));
    const wrapper = mount(hostWith(() => PROTECTED));
    await nextTick();
    expect(axios.get).toHaveBeenCalledTimes(1);

    wrapper.unmount();
    await flushPromises();

    const [, options] = axios.get.mock.calls[0];
    expect(options.signal.aborted).toBe(true);
  });
});
