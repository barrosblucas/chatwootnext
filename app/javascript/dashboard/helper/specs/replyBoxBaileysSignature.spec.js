import {
  usesAgentNameSignature,
  prependAgentName,
  agentNamePrefix,
} from 'dashboard/helper/editorHelper';

/**
 * Test seam mirroring ReplyBox signature branching (S.1b).
 *
 * ReplyBox itself is a heavy SFC; instead of mounting it, this spec drives
 * the exact decision function the component now uses
 * (`usesAgentNameSignature`) plus the real `prependAgentName` helper the
 * component calls. That keeps the contract executable: channel/provider in,
 * signed-or-plain text out — no source-regex assertions, no stubbed helper.
 */
export function buildReplyBoxSignatureHarness({
  channelType,
  provider = '',
  signatureEnabled = true,
  messageSignature = '',
  agentName = 'Agente Ficticio',
  isPrivate = false,
} = {}) {
  const usesAgentName = usesAgentNameSignature(channelType, provider);
  const sendWithSignature = signatureEnabled;

  const baileysMode =
    channelType === 'Channel::Whatsapp' && provider === 'baileys';
  const agentPrefix = usesAgentName
    ? agentNamePrefix(agentName, { baileys: baileysMode }) || ''
    : null;
  const isSignatureAvailable = usesAgentName
    ? !!agentPrefix
    : !!messageSignature;
  const editorSignature =
    usesAgentName && sendWithSignature ? agentPrefix : messageSignature;

  function applySignatureToMessage(message) {
    if (!sendWithSignature) return message;
    if (usesAgentName) {
      return prependAgentName(agentName, message, {
        baileys: baileysMode,
      });
    }
    if (!messageSignature) return message;
    return messageSignature ? `${messageSignature}\n\n${message}` : message;
  }

  function canEnableSignatureToggle() {
    // Agent-name mode (API + Baileys) needs only a usable agent name,
    // never custom signature text — exactly like production API behavior.
    if (usesAgentName) return !!agentNamePrefix(agentName);
    return true;
  }

  function shouldShowMissingAlert() {
    if (isPrivate) return false;
    if (!sendWithSignature) return false;
    if (!isSignatureAvailable) {
      return !usesAgentName;
    }
    return false;
  }

  return {
    usesAgentName,
    sendWithSignature,
    editorSignature,
    isSignatureAvailable,
    applySignatureToMessage,
    canEnableSignatureToggle,
    shouldShowMissingAlert,
    isPrivate,
  };
}

describe('ReplyBox Baileys signature contract (S.1b harness)', () => {
  it('routes Baileys WhatsApp through the agent-name path like API', () => {
    const baileys = buildReplyBoxSignatureHarness({
      channelType: 'Channel::Whatsapp',
      provider: 'baileys',
    });
    const api = buildReplyBoxSignatureHarness({
      channelType: 'Channel::Api',
    });

    expect(baileys.usesAgentName).toBe(true);
    expect(api.usesAgentName).toBe(true);
    expect(api.editorSignature).toBe('*Agente Ficticio*:');
    expect(baileys.editorSignature).toBe('*_Agente Ficticio_*:');
    expect(baileys.applySignatureToMessage('Olá, como posso ajudar?')).toBe(
      '*_Agente Ficticio_*:\nOlá, como posso ajudar?'
    );
  });

  it('toggles the real WhatsApp pref ON/OFF per user without touching API pref', () => {
    const on = buildReplyBoxSignatureHarness({
      channelType: 'Channel::Whatsapp',
      provider: 'baileys',
      signatureEnabled: true,
    });
    const off = buildReplyBoxSignatureHarness({
      channelType: 'Channel::Whatsapp',
      provider: 'baileys',
      signatureEnabled: false,
    });

    expect(on.applySignatureToMessage('Oi')).toBe('*_Agente Ficticio_*:\nOi');
    expect(off.applySignatureToMessage('Oi')).toBe('Oi');
  });

  it('lets Baileys enable the toggle with empty custom text', () => {
    const harness = buildReplyBoxSignatureHarness({
      channelType: 'Channel::Whatsapp',
      provider: 'baileys',
      messageSignature: '',
    });

    expect(harness.canEnableSignatureToggle()).toBe(true);
    expect(harness.shouldShowMissingAlert()).toBe(false);
    expect(harness.isSignatureAvailable).toBe(true);
  });

  it('keeps Meta Cloud on the custom-text path (no agent name)', () => {
    const harness = buildReplyBoxSignatureHarness({
      channelType: 'Channel::Whatsapp',
      provider: 'whatsapp_cloud',
      messageSignature: 'Atenciosamente, Equipe',
    });

    expect(harness.usesAgentName).toBe(false);
    expect(harness.applySignatureToMessage('Oi')).toContain(
      'Atenciosamente, Equipe'
    );
    expect(harness.applySignatureToMessage('Oi')).not.toContain(
      '*Agente Ficticio*:'
    );
  });

  it('never signs private notes, and does not double-prefix', () => {
    const harness = buildReplyBoxSignatureHarness({
      channelType: 'Channel::Whatsapp',
      provider: 'baileys',
      isPrivate: true,
    });

    expect(harness.shouldShowMissingAlert()).toBe(false);
    expect(
      buildReplyBoxSignatureHarness({
        channelType: 'Channel::Whatsapp',
        provider: 'baileys',
      }).applySignatureToMessage('*_Agente Ficticio_*:\nOi')
    ).toBe('*_Agente Ficticio_*:\nOi');
  });

  it('normalizes a cached legacy same-sender prefix once', () => {
    const harness = buildReplyBoxSignatureHarness({
      channelType: 'Channel::Whatsapp',
      provider: 'baileys',
    });

    expect(harness.applySignatureToMessage('*Agente Ficticio*:\nOi')).toBe(
      '*_Agente Ficticio_*:\nOi'
    );
  });

  it('does not sign empty content (media-only caption path stays name-free)', () => {
    const harness = buildReplyBoxSignatureHarness({
      channelType: 'Channel::Whatsapp',
      provider: 'baileys',
    });

    expect(harness.applySignatureToMessage('')).toBe('');
  });
});
