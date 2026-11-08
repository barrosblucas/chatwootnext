// Rótulo dinâmico da lista: raiz | setor | atendente. Não conhece município,
// setor nem pessoa; apenas ordena os nomes que o backend autorizou.
export const connectaLabelParts = (connecta, assigneeName) => {
  if (!connecta) return [];
  const units = [connecta.root_unit_name, connecta.org_unit_name]
    .filter(Boolean)
    .filter((unit, index, list) => list.indexOf(unit) === index);
  if (assigneeName) units.push(assigneeName);
  return units;
};

export const connectaLabel = (connecta, assigneeName) =>
  connectaLabelParts(connecta, assigneeName).join(' | ');
