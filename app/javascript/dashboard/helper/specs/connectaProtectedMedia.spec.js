import axios from 'axios';
import {
  isProtectedAttachmentUrl,
  extractFileNameFromContentDisposition,
  fileNameFromUrl,
  fetchProtectedAttachment,
  downloadAttachmentFile,
  withMediaTimestamp,
  withMediaFragment,
} from '../connectaProtectedMedia';
import { downloadFile } from '@chatwoot/utils';

vi.mock('axios');
vi.mock('@chatwoot/utils', () => ({ downloadFile: vi.fn() }));

global.axios = axios;

const PROTECTED =
  '/api/v1/accounts/7/connecta_attachments/42/download?token=abc123';
const ABSOLUTE_PROTECTED = `http://localhost:3000${PROTECTED}`;

describe('connectaProtectedMedia', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    if (!URL.createObjectURL) {
      URL.createObjectURL = () => 'blob:mock';
    }
    if (!URL.revokeObjectURL) {
      URL.revokeObjectURL = () => undefined;
    }
    vi.spyOn(URL, 'createObjectURL').mockReturnValue('blob:mock-url');
    vi.spyOn(URL, 'revokeObjectURL').mockImplementation(() => undefined);
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  describe('isProtectedAttachmentUrl', () => {
    it('matches the exact same-origin download route with query', () => {
      expect(isProtectedAttachmentUrl(PROTECTED)).toBe(true);
    });

    it('matches the absolute same-origin form', () => {
      expect(isProtectedAttachmentUrl(ABSOLUTE_PROTECTED)).toBe(true);
    });

    it('matches the route without query string', () => {
      expect(
        isProtectedAttachmentUrl(
          '/api/v1/accounts/1/connecta_attachments/9/download'
        )
      ).toBe(true);
    });

    it.each([
      ['/api/v1/accounts/7/connecta_attachments/42/preview'],
      ['/api/v1/accounts/7/uploads/42/download'],
      ['/api/v2/accounts/7/connecta_attachments/42/download'],
      ['/api/v1/accounts/abc/connecta_attachments/42/download'],
      ['/api/v1/accounts/7/connecta_attachments/42/download/extra'],
      [
        'https://cdn.example.com/api/v1/accounts/7/connecta_attachments/42/download',
      ],
      ['//evil.example.com/api/v1/accounts/7/connecta_attachments/42/download'],
      ['blob:https://app.example.com/uuid'],
      ['data:image/png;base64,aaa'],
      ['not a url at all %%'],
      [''],
      [null],
      [undefined],
      [42],
    ])('rejects %p', url => {
      expect(isProtectedAttachmentUrl(url)).toBe(false);
    });

    it('rejects cross-origin absolute URLs even on the same path', () => {
      expect(
        isProtectedAttachmentUrl(
          'https://other.example.com/api/v1/accounts/7/connecta_attachments/42/download'
        )
      ).toBe(false);
    });
  });

  describe('extractFileNameFromContentDisposition', () => {
    it('parses RFC 5987 encoded filenames', () => {
      expect(
        extractFileNameFromContentDisposition(
          "attachment; filename*=UTF-8''relat%C3%B3rio.pdf"
        )
      ).toBe('relatório.pdf');
    });

    it('parses quoted filenames', () => {
      expect(
        extractFileNameFromContentDisposition('attachment; filename="a b.ogg"')
      ).toBe('a b.ogg');
    });

    it.each([[null], [undefined], [''], ['inline'], ['attachment']])(
      'returns empty for %p',
      header => {
        expect(extractFileNameFromContentDisposition(header)).toBe('');
      }
    );
  });

  describe('fileNameFromUrl', () => {
    it('returns the last segment for plain URLs', () => {
      expect(fileNameFromUrl('https://cdn.example.com/f/photo.png')).toBe(
        'photo.png'
      );
    });

    it('strips query and fragment', () => {
      expect(fileNameFromUrl('/rails/active_storage/x/y.png?t=1#frag')).toBe(
        'y.png'
      );
    });

    it('returns empty for protected download URLs', () => {
      expect(fileNameFromUrl(PROTECTED)).toBe('');
      expect(fileNameFromUrl(ABSOLUTE_PROTECTED)).toBe('');
    });
  });

  describe('fetchProtectedAttachment', () => {
    it('fetches bytes with the session client and parses headers', async () => {
      const blob = new Blob(['bytes'], { type: 'audio/ogg' });
      axios.get.mockResolvedValueOnce({
        data: blob,
        headers: {
          'content-type': 'audio/ogg',
          'content-disposition': 'attachment; filename="voice.ogg"',
        },
      });

      const result = await fetchProtectedAttachment(PROTECTED);

      expect(axios.get).toHaveBeenCalledWith(
        PROTECTED,
        expect.objectContaining({ responseType: 'blob' })
      );
      expect(result.blob).toBe(blob);
      expect(result.contentType).toBe('audio/ogg');
      expect(result.fileName).toBe('voice.ogg');
    });

    it('propagates 401/403/404 without swallowing the status', async () => {
      const failure = { response: { status: 403, headers: {} } };
      axios.get.mockRejectedValueOnce(failure);
      await expect(fetchProtectedAttachment(PROTECTED)).rejects.toBe(failure);
    });
  });

  describe('downloadAttachmentFile', () => {
    const clickOnAnchor = () => {
      const seen = [];
      vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(
        function clickAnchor() {
          seen.push({
            href: this.href,
            download: this.download,
          });
        }
      );
      return seen;
    };

    it('downloads protected URLs through the authenticated fetch', async () => {
      axios.get.mockResolvedValueOnce({
        data: new Blob(['bytes'], { type: 'application/pdf' }),
        headers: {
          'content-type': 'application/pdf',
          'content-disposition': 'attachment; filename="doc.pdf"',
        },
      });
      const seen = clickOnAnchor();

      await downloadAttachmentFile({
        url: PROTECTED,
        fileType: 'file',
        extension: 'pdf',
      });

      expect(axios.get).toHaveBeenCalledWith(
        PROTECTED,
        expect.objectContaining({ responseType: 'blob' })
      );
      expect(URL.createObjectURL).toHaveBeenCalled();
      expect(seen).toHaveLength(1);
      expect(seen[0].download).toBe('doc.pdf');
      expect(downloadFile).not.toHaveBeenCalled();
    });

    it('delegates plain URLs to the legacy download without new headers', async () => {
      const plain = 'https://cdn.example.com/f/photo.png';

      await downloadAttachmentFile({
        url: plain,
        fileType: 'image',
        extension: 'png',
      });

      expect(axios.get).not.toHaveBeenCalled();
      expect(downloadFile).toHaveBeenCalledWith({
        url: plain,
        type: 'image',
        extension: 'png',
      });
    });
  });

  describe('withMediaTimestamp', () => {
    it('leaves blob: and data: URLs untouched', () => {
      expect(withMediaTimestamp('blob:mock-url')).toBe('blob:mock-url');
      expect(withMediaTimestamp('data:audio/ogg;base64,aaa')).toBe(
        'data:audio/ogg;base64,aaa'
      );
    });

    it('appends t to plain URLs and preserves existing query', () => {
      expect(withMediaTimestamp('/f/a.mp3')).toMatch(/^\/f\/a\.mp3\?t=\d+$/);
      expect(withMediaTimestamp('/f/a.mp3?x=1')).toMatch(
        /^\/f\/a\.mp3\?x=1&t=\d+$/
      );
    });

    it('never throws on relative URLs', () => {
      expect(() => withMediaTimestamp('audio.mp3')).not.toThrow();
    });
  });

  describe('withMediaFragment', () => {
    it('leaves blob: URLs untouched', () => {
      expect(withMediaFragment('blob:mock-url')).toBe('blob:mock-url');
    });

    it('appends the fragment once to plain URLs', () => {
      expect(withMediaFragment('/f/a.mp4')).toBe('/f/a.mp4#t=0.1');
      expect(withMediaFragment('/f/a.mp4#t=0.1')).toBe('/f/a.mp4#t=0.1');
    });
  });
});
