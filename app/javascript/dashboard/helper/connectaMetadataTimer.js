// Timer único do refresh de metadados do Connecta. O callback decide o que
// está vencido pelo TTL do store; o retorno limpa o intervalo no unmount.
export const startConnectaMetadataTimer = (refresh, intervalMs = 60000) => {
  const timer = setInterval(refresh, intervalMs);
  return () => clearInterval(timer);
};
