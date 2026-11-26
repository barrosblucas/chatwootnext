# Changelog — 2026-11-26

## Intenção da feature
- Intenção: restringir atendimentos por responsável e permitir supervisão por gestor de unidade.
- Regras de negócio afetadas: atribuição, liberação, transferência, visibilidade, métricas e atualizações realtime.
- Não deve mudar: comportamento de inboxes não Connecta e acesso de administradores nativos.
- Já feito: escopo por responsável, permissão `gerir`, fila e reivindicação de respostas.
- Pendente: correções da revisão em lote, proteção de atribuição, relatórios, revogação e escritas concorrentes.
- Etapa atual: testes de regressão antes das correções.

## Changed
- Base `d0b3ab77f678cf6ed168d6ab40b6017b90864467`: limita visibilidade e escrita por responsável, permite gestão por unidade, aplica a política de atribuição e entrega transferências entre unidades sem responsável.
- Aceita `gerir` nos catálogos de grants Connecta.
- A fila Aguardando exclui conversas atribuídas; gestores têm a aba Todos para os setores autorizados.
- A primeira resposta humana reivindica o atendimento sob lock; colegas que perdem acesso recebem `scope.revoked`, sem conteúdo.

## Tests
- Adicionada cobertura de visibilidade, atribuição, transferência, sync, lock de resposta, destinatários realtime e aba de gestor; execução no GitHub Actions.
- Dividido o teste de destinatários realtime, preservando as verificações e respeitando o limite de expectativas.
