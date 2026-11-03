import { describe, it, expect } from 'vitest';
import {
  usesAgentNameSignature,
  prependAgentName,
  agentNamePrefix,
} from 'dashboard/helper/editorHelper';

describe('usesAgentNameSignature (Baileys S.1b)', () => {
  it('returns true for API inboxes regardless of provider', () => {
    expect(usesAgentNameSignature('Channel::Api')).toBe(true);
    expect(usesAgentNameSignature('Channel::Api', 'baileys')).toBe(true);
    expect(usesAgentNameSignature('Channel::Api', 'whatsapp_cloud')).toBe(true);
  });

  it('returns true only for Baileys WhatsApp inboxes', () => {
    expect(usesAgentNameSignature('Channel::Whatsapp', 'baileys')).toBe(true);
  });

  it('returns false for other WhatsApp providers', () => {
    expect(usesAgentNameSignature('Channel::Whatsapp', 'whatsapp_cloud')).toBe(
      false
    );
    expect(usesAgentNameSignature('Channel::Whatsapp', 'default')).toBe(false);
    expect(usesAgentNameSignature('Channel::Whatsapp', 'zapi')).toBe(false);
    expect(usesAgentNameSignature('Channel::Whatsapp', '')).toBe(false);
    expect(usesAgentNameSignature('Channel::Whatsapp')).toBe(false);
  });

  it('returns false for non-API, non-WhatsApp channels', () => {
    expect(usesAgentNameSignature('Channel::Email', 'baileys')).toBe(false);
    expect(usesAgentNameSignature('Channel::WebWidget')).toBe(false);
    expect(usesAgentNameSignature('Channel::Telegram')).toBe(false);
    expect(usesAgentNameSignature(undefined, 'baileys')).toBe(false);
    expect(usesAgentNameSignature(null, 'baileys')).toBe(false);
  });
});

describe('Baileys signature is bold-italic, API default untouched', () => {
  it('produces the **_Nome_**: prefix for Baileys (wire: *_Nome_*:)', () => {
    expect(agentNamePrefix('Agente Ficticio', { baileys: true })).toBe(
      '**_Agente Ficticio_**:'
    );
    expect(prependAgentName('Agente Ficticio', 'Olá', { baileys: true })).toBe(
      '**_Agente Ficticio_**:\nOlá'
    );
  });

  it('keeps the shared API default exactly as before', () => {
    expect(agentNamePrefix('Agente Ficticio')).toBe('*Agente Ficticio*:');
    expect(prependAgentName('Agente Ficticio', 'Olá')).toBe(
      '*Agente Ficticio*:\nOlá'
    );
  });

  it('stays idempotent when content already carries the new prefix', () => {
    const content = '**_Agente Ficticio_**:\nOlá';
    expect(
      prependAgentName('Agente Ficticio', content, { baileys: true })
    ).toBe(content);
  });

  it('normalizes the legacy same-sender prefix once, preserving body bytes', () => {
    expect(
      prependAgentName('Agente Ficticio', '*Agente Ficticio*:\nOlá', {
        baileys: true,
      })
    ).toBe('**_Agente Ficticio_**:\nOlá');
  });

  it('normalizes a standalone legacy prefix without fabricating a body', () => {
    expect(
      prependAgentName('Agente Ficticio', '*Agente Ficticio*:', {
        baileys: true,
      })
    ).toBe('**_Agente Ficticio_**:');
  });

  it('upgrades the interim single-star prefix once, preserving body bytes', () => {
    expect(
      prependAgentName('Agente Ficticio', '*_Agente Ficticio_*:\nOlá', {
        baileys: true,
      })
    ).toBe('**_Agente Ficticio_**:\nOlá');
  });

  it('upgrades a standalone interim single-star prefix without fabricating a body', () => {
    expect(
      prependAgentName('Agente Ficticio', '*_Agente Ficticio_*:', {
        baileys: true,
      })
    ).toBe('**_Agente Ficticio_**:');
  });

  it('keeps a foreign legacy prefix and prepends the current sender', () => {
    expect(
      prependAgentName('Agente Ficticio', '*Outro Ficticio*:\nOlá', {
        baileys: true,
      })
    ).toBe('**_Agente Ficticio_**:\n*Outro Ficticio*:\nOlá');
  });

  it('does not fabricate a name-only message from empty content', () => {
    expect(prependAgentName('Agente Ficticio', '', { baileys: true })).toBe('');
    expect(prependAgentName('Agente Ficticio', '   ', { baileys: true })).toBe(
      '   '
    );
  });

  it('sanitizes the agent name like the backend gate, also stripping underscores', () => {
    expect(
      prependAgentName('  Agente *_Ficticio_*  ', 'Olá', { baileys: true })
    ).toBe('**_Agente Ficticio_**:\nOlá');
  });

  it('does not strip underscores from the message body', () => {
    expect(
      prependAgentName('Agente Ficticio', 'conta _pendente_ ok', {
        baileys: true,
      })
    ).toBe('**_Agente Ficticio_**:\nconta _pendente_ ok');
  });
});
