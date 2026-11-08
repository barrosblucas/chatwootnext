import { connectaLabel, connectaLabelParts } from '../connectaLabel';

describe('connectaLabel', () => {
  it('builds the dynamic root | sector | assignee label', () => {
    expect(
      connectaLabel(
        { root_unit_name: 'Raiz X', org_unit_name: 'Setor Y' },
        'Pessoa Z'
      )
    ).toBe('Raiz X | Setor Y | Pessoa Z');
  });

  it('does not repeat the root when it is also the current sector', () => {
    expect(
      connectaLabelParts(
        { root_unit_name: 'Raiz X', org_unit_name: 'Raiz X' },
        null
      )
    ).toEqual(['Raiz X']);
  });

  it('omits everything when there is no authorized scope', () => {
    expect(connectaLabel(null, 'Pessoa Z')).toBe('');
  });
});
