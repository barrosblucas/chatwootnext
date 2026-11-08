import axios from 'axios';
import ConnectaAPI from '../connecta';

global.axios = axios;
vi.mock('axios');

describe('ConnectaAPI admission', () => {
  beforeEach(() => {
    axios.post.mockReset();
    window.history.pushState({}, '', '/app/accounts/1/');
  });

  it('sends the explicit nonce and raw files as multipart', async () => {
    axios.post.mockResolvedValue({ data: { id: 55 } });
    const first = new File(['a'], 'a.png', { type: 'image/png' });
    const second = new File(['b'], 'b.png', { type: 'image/png' });

    await ConnectaAPI.admitConversation({
      inboxId: 3,
      contactId: 4,
      sourceId: 'synthetic-source',
      orgUnitId: 'unit-1',
      message: { content: 'ola' },
      idempotencyKey: 'attempt-1',
      files: [first, second],
    });

    const [url, body] = axios.post.mock.calls[0];
    expect(url).toBe(
      '/api/v1/accounts/1/conversations/connecta_manual_admission'
    );
    expect(body).toBeInstanceOf(FormData);
    expect(body.get('idempotency_key')).toBe('attempt-1');
    expect(body.get('message[content]')).toBe('ola');
    expect(body.getAll('message[attachments][]')).toEqual([first, second]);
    expect(body.get('contact_id')).toBe('4');
    expect(body.get('org_unit_id')).toBe('unit-1');
  });
});
