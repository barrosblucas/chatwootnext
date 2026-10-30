# 25 — Validação da transferência final (T0.3/T0.7)

Validação consolidada SOMENTE diagnóstico. Nenhum código alterado nesta tarefa.

## Pré-checagens (sem matar nada)

- `df -h /tmp`: tmpfs 7,6 GB, 5,1 GB usados (67%), 2,6 GB livres.
- Runner G0 residual: nenhum processo `g0_test_env` / `bundle exec rspec` / `rspec.*connecta`
  em execução (só os processos do próprio harness/opencode desta tarefa).
- Binário absoluto: `/home/thanos/.cache/connecta-g0-test/toolchain/mise-data/installs/ruby/3.4.4/bin/ruby`
  existe e responde `RUBY_VERSION = 3.4.4`.
- `flock -n /home/thanos/.cache/connecta-g0-test/spec.lock true`: lock livre antes da execução.
- As 4 specs existem: `spec/connecta/{transfer_cutover,transfer_activation,outbound_dispatch,transfer_integration}_spec.rb`.

## Comando (fila obrigatória, execução única)

```sh
cd /home/thanos/chatwootnext-connecta-g0-prep && PATH=/home/thanos/.cache/connecta-g0-test/toolchain/mise-data/installs/ruby/3.4.4/bin:$PATH flock -w 900 /home/thanos/.cache/connecta-g0-test/spec.lock timeout 300 scripts/connecta/g0_test_env.sh --spec --apply spec/connecta/transfer_cutover_spec.rb spec/connecta/transfer_activation_spec.rb spec/connecta/outbound_dispatch_spec.rb spec/connecta/transfer_integration_spec.rb
```

## Resultado

- Pré-condições do runner: 11/11 `ok` (Docker local, Ruby 3.4.4, sem Dotenv na raiz,
  database.yml → 127.0.0.1:55432/conecta_baileys_g0_test, containers do projeto em execução,
  Postgres 55432 e Redis 56379 escutando, segredo sintético 0600, banco com schema esperado).
- RSpec: **40 examples, 0 failures** (`Finished in 40.07 seconds`, files 5.53 s).
- Exit: **0**. Duração real (parede, incluindo pré-condições): **47 s**.
- Início UTC: 2026-10-24T17:18:22Z.
- Log: `25-logs/transfer-final-1.log` (sanitizado: sem valores de segredos/credenciais;
  as únicas ocorrências de "secret" são as linhas genéricas de DEPRECATION WARNING do Rails
  sobre `Rails.application.secrets`, sem nenhum valor exposto).

## Falhas arquivo:linha

Nenhuma. Execução única, sem repetição, sem correção.

## Infraestrutura

Disponível durante toda a execução; nenhuma recriação/modificação de infra, banco ou schema.
Nenhuma escrita manual de banco. Código/spec preservados.
