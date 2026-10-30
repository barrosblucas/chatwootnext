# Changelog 2026-10-24 — F3–F5 fork

- Implementada ponte de runtime opt-in para as tabelas de produto `connecta_*`, projeção ACL/revogação, ativação de recepção e fluxo de transferência com resumo, barreira de ativação e despacho parked/uncertain.
- Adicionadas rotas autenticadas HMAC, configurações/UI de vínculo, status e reconciliação, além de limpeza do cache no evento de revogação.
- Adicionadas specs para assinatura HMAC e formulário de resumo; escritas, ainda não executadas.
- `CONNECTA_DISPATCH_WAIT_MS` configura a espera pelo despacho (0–30000 ms; padrão 5000).
- Migração apenas escrita, não executada. Nenhum teste, build, lint, servidor ou QR executado.
- Status e limitações detalhados em [evidência F3–F5](../evidence/baileys/f3-f5-fork.md). G0 R1 continua rejeitado e revisão final pendente.
