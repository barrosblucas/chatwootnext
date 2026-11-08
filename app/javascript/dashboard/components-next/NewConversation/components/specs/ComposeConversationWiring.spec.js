import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

// Regressão do wiring comprovado quebrado: o componente existia, mas não era
// importado nem renderizado no ComposeConversation. O comportamento de abrir
// e confirmar é coberto em ConnectaSectorPicker.spec.js; este teste impede que
// o modal volte a ficar fora do template.
describe('ComposeConversation sector picker wiring', () => {
  it('imports and renders ConnectaSectorPicker bound to showSectorPicker', () => {
    const source = readFileSync(
      resolve(
        process.cwd(),
        'app/javascript/dashboard/components-next/NewConversation/ComposeConversation.vue'
      ),
      'utf8'
    );

    expect(source).toContain(
      "import ConnectaSectorPicker from 'dashboard/components-next/NewConversation/components/ConnectaSectorPicker.vue'"
    );
    expect(source).toContain('<ConnectaSectorPicker');
    expect(source).toContain(':show="showSectorPicker"');
    expect(source).toContain(
      ':files="pendingAdmissionPayload?.admissionFiles || []"'
    );
    expect(source).toContain('@admitted="onSectorAdmitted"');
  });

  it('keeps follow-up files for the Baileys path after admission', () => {
    const source = readFileSync(
      resolve(
        process.cwd(),
        'app/javascript/dashboard/components-next/NewConversation/ComposeConversation.vue'
      ),
      'utf8'
    );

    expect(source).toContain(
      'return createBaileysConversation(payload, followUpFiles, admissionFiles);'
    );
    expect(source).toContain(
      'await sendAdmissionFollowUps(data, followUpFiles);'
    );
    expect(source).toContain('files: admissionFiles');
    expect(source).toContain('connectaMetadata/refresh');
  });
});
