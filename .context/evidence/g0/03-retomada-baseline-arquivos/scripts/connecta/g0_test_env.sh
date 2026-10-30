#!/usr/bin/env bash
# Roteiro do ambiente de testes G0 (Connecta/Baileys).
# Padrão: dry-run. Imprime os comandos e verifica pré-condições; não altera nada.
#
#   scripts/connecta/g0_test_env.sh                    dry-run do preparo (padrão)
#   scripts/connecta/g0_test_env.sh --apply            executa o preparo (exige autorização humana)
#   scripts/connecta/g0_test_env.sh --spec [SPEC...]   dry-run das specs no alvo G0 (padrão: inventário de rotas)
#   scripts/connecta/g0_test_env.sh --spec --apply [SPEC...] executa as specs no alvo G0 (exige autorização humana)
#   scripts/connecta/g0_test_env.sh --teardown --apply para o projeto de serviços (volumes ficam)
#
# SPEC: só *_spec.rb regulares em spec/connecta/ ou spec/requests/connecta/ (sem '..' nem links simbólicos).
# --apply é repetível: recursos são reutilizados só com propriedade comprovada (rótulo e contêiner da origem Compose).
# Órfão, recurso de outro worktree ou segredo ausente com recursos existentes => aborta. Schema só é carregado em banco vazio.
#
# Alvos exatos: projeto compose conecta-baileys-g0-test; banco conecta_baileys_g0_test;
# Postgres em 127.0.0.1:55432; Redis em 127.0.0.1:56379 (db 0).
# Isolamento: o script se re-executa com ambiente vazio (env -i), então nenhuma variável herdada chega ao Rails.
# Arquivo Dotenv na raiz faz o script recusar: o Rails o leria, e aqui ele não é lido nem alterado.
# Segredo sintético: criado no --apply em $SECRET_FILE (fora do repo, 0600); nunca impresso nem versionado.
# Não executa pnpm/husky, não instala Ruby, não altera configuração Git. Dependências vão para .bundle/gems (ignorado pelo git).
set -euo pipefail

if [ "${G0_CLEAN_ENV:-}" != "$$" ]; then
  exec env -i PATH="$PATH" HOME="$HOME" USER="${USER:-}" LANG="${LANG:-C.UTF-8}" \
    MISE_NOT_FOUND_AUTO_INSTALL=0 G0_CLEAN_ENV="$$" bash "$0" "$@"
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

PROJECT=conecta-baileys-g0-test
DB_NAME=conecta_baileys_g0_test
PG_PORT=55432
REDIS_PORT=56379
COMPOSE_FILE="$ROOT/scripts/connecta/g0-test-services.compose.yml"
COMPOSE=(docker compose -p "$PROJECT" -f "$COMPOSE_FILE")
SECRET_DIR="$HOME/.cache/connecta-g0-test"
SECRET_FILE="$SECRET_DIR/synthetic-secret"

export RAILS_ENV=test
export CONNECTA_G0_RUNNER="$PROJECT"
export POSTGRES_HOST=127.0.0.1
export POSTGRES_PORT="$PG_PORT"
export POSTGRES_USERNAME=postgres
export POSTGRES_DATABASE="$DB_NAME"
export REDIS_URL="redis://127.0.0.1:$REDIS_PORT/0"
export BUNDLE_GEMFILE="$ROOT/Gemfile"
export BUNDLE_PATH="$ROOT/.bundle/gems"
export BUNDLE_FROZEN=true

MODE=prepare
APPLY=0
SPEC_ARGS=()
for arg in "$@"; do
  case "$arg" in
    --apply) APPLY=1 ;;
    --teardown | --spec)
      [ "$MODE" = prepare ] || { echo "uso: escolha um só modo (--teardown ou --spec)" >&2; exit 2; }
      MODE="${arg#--}" ;;
    -*) echo "uso: $0 [--spec [SPEC...] | --teardown] [--apply]" >&2; exit 2 ;;
    *) SPEC_ARGS+=("$arg") ;;
  esac
done
if [ "$MODE" != spec ] && [ "${#SPEC_ARGS[@]}" -gt 0 ]; then echo "uso: caminhos de spec só valem com --spec" >&2; exit 2; fi
SPEC_FILES=(spec/requests/connecta/route_inventory_spec.rb)
if [ "${#SPEC_ARGS[@]}" -gt 0 ]; then SPEC_FILES=("${SPEC_ARGS[@]}"); fi

FAILED=0
check() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "ok:    $label"
  else
    echo "falta: $label"
    FAILED=1
  fi
}

# run() imprime o comando e só o executa com --apply.
run() {
  printf '+ %s\n' "$*"
  [ "$APPLY" -eq 1 ] || return 0
  "$@"
}

ruby_is_3_4_4() { [ "$(ruby -e 'print RUBY_VERSION' 2>/dev/null)" = "3.4.4" ]; }

no_dotenv_in_root() {
  local file
  for file in "$ROOT"/.env "$ROOT"/.env.*; do
    if [ -e "$file" ] && [[ "$(basename "$file")" != *.example ]]; then
      return 1
    fi
  done
}

# Lê o alvo efetivo de config/database.yml sem subir o Rails. Sidekiq é stub porque o ERB o referencia.
database_target_is_g0() {
  ruby -ryaml -rerb -e '
    module Sidekiq; def self.server? = false; end
    cfg = YAML.safe_load(ERB.new(File.read("config/database.yml")).result, aliases: true).fetch("test")
    target = %w[host port database username].map { |key| cfg[key].to_s }
    exit(target == %w[127.0.0.1 55432 conecta_baileys_g0_test postgres] ? 0 : 1)
  '
}

docker_is_local() {
  local host
  host="$(docker context inspect --format '{{.Endpoints.docker.Host}}' 2>/dev/null)" && [[ "$host" == unix://* ]]
}
port_is_free() { ! (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; }
port_is_open() { (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; }
# Porta já publicada por contêiner do projeto em 127.0.0.1 (a propriedade dos contêineres é checada em project_resources_owned).
port_is_ours() {
  local id
  for id in $(docker ps -q --filter "label=com.docker.compose.project=$PROJECT"); do
    docker port "$id" | grep -q "127.0.0.1:$1\$" && return 0
  done
  return 1
}
port_is_free_or_ours() { port_is_free "$1" || port_is_ours "$1"; }
volume_is_absent() { ! docker volume inspect "$1" >/dev/null 2>&1; }
VOLUME_NAME="${PROJECT}_g0_postgres"
# Volume existente só é aceito com rótulo do projeto e contêiner da origem Compose montando-o. Volume órfão é recusado.
volume_is_ours() {
  local id ids
  docker volume inspect "$1" >/dev/null 2>&1 || return 1
  [ "$(docker volume inspect -f '{{index .Labels "com.docker.compose.project"}}' "$1")" = "$PROJECT" ] || return 1
  ids="$(docker ps -aq --filter "volume=$1")" && [ -n "$ids" ] || return 1
  for id in $ids; do container_is_ours "$id" || return 1; done
}
volume_is_absent_or_ours() { volume_is_absent "$1" || volume_is_ours "$1"; }

# Origem: o Compose grava projeto e arquivo de configuração nos contêineres. Caminho normalizado com pwd -P (sem realpath -m, ausente no macOS).
canonical_path() { (cd "$(dirname "$1")" 2>/dev/null && printf '%s/%s\n' "$(pwd -P)" "$(basename "$1")"); }
COMPOSE_ORIGIN="$(canonical_path "$COMPOSE_FILE")"

# Allowlist de specs: arquivo regular *_spec.rb sob spec/connecta ou spec/requests/connecta, sem '..' e sem link simbólico.
spec_is_allowed() {
  local re='^spec/(connecta|requests/connecta)/[A-Za-z0-9_/.-]+_spec\.rb$' canonical
  [[ "$1" =~ $re ]] && [[ "$1" != *..* ]] && [ -f "$ROOT/$1" ] && [ ! -L "$ROOT/$1" ] || return 1
  canonical="$(canonical_path "$ROOT/$1")" || return 1
  case "$canonical" in
    "$(pwd -P)/spec/connecta/"* | "$(pwd -P)/spec/requests/connecta/"*) ;;
    *) return 1 ;;
  esac
}

container_is_ours() {
  local project files
  project="$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project"}}' "$1")" || return 1
  files="$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project.config_files"}}' "$1")" || return 1
  [ "$project" = "$PROJECT" ] && [ "$(canonical_path "$files")" = "$COMPOSE_ORIGIN" ]
}

# O Compose não grava arquivo de configuração em redes: a origem é a dos contêineres anexados. Rede sem contêiner é recusada.
network_is_ours() {
  local attached cid
  [ "$(docker network inspect -f '{{index .Labels "com.docker.compose.project"}}' "$1")" = "$PROJECT" ] || return 1
  attached="$(docker network inspect -f '{{range $cid, $endpoint := .Containers}}{{$cid}} {{end}}' "$1")" || return 1
  [ -n "$attached" ] || return 1
  for cid in $attached; do container_is_ours "$cid" || return 1; done
}

# Seleção por nome e por rótulo do projeto. Qualquer recurso de outra origem reprova a checagem (antes de up, down e da spec).
project_resources_owned() {
  local ids id
  ids="$({ docker ps -aq --filter "name=$PROJECT" &&
           docker ps -aq --filter "label=com.docker.compose.project=$PROJECT"; } | sort -u)" || return 1
  for id in $ids; do container_is_ours "$id" || return 1; done
  ids="$({ docker network ls -q --filter "name=$PROJECT" &&
           docker network ls -q --filter "label=com.docker.compose.project=$PROJECT"; } | sort -u)" || return 1
  for id in $ids; do network_is_ours "$id" || return 1; done
}

project_containers_running() {
  [ "$(docker ps -q --filter "label=com.docker.compose.project=$PROJECT" --filter status=running | wc -l | tr -d ' ')" -ge 2 ]
}

# Recursos do projeto já existentes (contêiner, rede ou volume), inclusive restos de execução parcial.
project_has_resources() {
  [ -n "$(docker ps -aq --filter "label=com.docker.compose.project=$PROJECT")" ] ||
    [ -n "$(docker network ls -q --filter "label=com.docker.compose.project=$PROJECT")" ] ||
    ! volume_is_absent "$VOLUME_NAME"
}

secret_is_ready() { [ ! -e "$SECRET_FILE" ] || [ "$(stat -c %a "$SECRET_FILE")" = 600 ]; }
secret_is_present() { [ -f "$SECRET_FILE" ] && [ "$(stat -c %a "$SECRET_FILE")" = 600 ]; }
# Com recursos do projeto, o segredo precisa existir: regenerá-lo deixaria o volume do Postgres inacessível.
secret_is_consistent() { ! project_has_resources || secret_is_present; }

create_secret() {
  umask 077
  mkdir -p "$SECRET_DIR"
  head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n' > "$SECRET_FILE"
  chmod 600 "$SECRET_FILE"
}

# Exporta o segredo só para os processos filhos (Compose, Postgres, Redis e a spec). Nunca é impresso.
export_secret() {
  G0_SYNTHETIC_SECRET="$(cat "$SECRET_FILE")"
  export G0_SYNTHETIC_SECRET
  export POSTGRES_PASSWORD="$G0_SYNTHETIC_SECRET"
  export REDIS_PASSWORD="$G0_SYNTHETIC_SECRET"
}

# Listas esperadas, lidas só do repo (db/schema.rb e db/migrate), ordenadas em C.
schema_list() {
  case "$1" in
    tables) grep -oE '^ *create_table "[^"]+"' db/schema.rb | sed -E 's/.*"([^"]+)"/\1/' ;;
    extensions) grep -oE 'enable_extension "[^"]+"' db/schema.rb | sed -E 's/.*"([^"]+)"/\1/' ;;
    versions) ls db/migrate/*.rb | sed -E 's#.*/([0-9]+)_[^/]*$#\1#' ;;
  esac | LC_ALL=C sort
}

db_diverges() { echo "diverge: $1 difere de db/schema.rb" >&2; echo diverge; }

# Estado do banco pelo catálogo, dentro do contêiner Postgres do projeto (senha não vai na linha de comando; só SELECT).
# Saída: unreachable | empty | match | diverge. "match" exige tabelas, migrações, extensões e schema_sha1 iguais ao repo.
db_state() {
  local cid tables
  cid="$(docker ps -q --filter "label=com.docker.compose.project=$PROJECT" --filter "label=com.docker.compose.service=postgres")"
  [ -n "$cid" ] || { echo unreachable; return 0; }
  db_query() { docker exec "$cid" psql -X -At -U postgres -d "$DB_NAME" -c "$1"; }
  tables="$(db_query "select count(*) from pg_tables where schemaname = 'public'")" || { echo unreachable; return 0; }
  [ "$tables" != 0 ] || { echo empty; return 0; }
  [ "$(db_query "select tablename from pg_tables where schemaname = 'public' and tablename not in ('schema_migrations', 'ar_internal_metadata')" | LC_ALL=C sort)" = "$(schema_list tables)" ] || { db_diverges tabelas; return 0; }
  [ "$(db_query "select version from schema_migrations" | LC_ALL=C sort)" = "$(schema_list versions)" ] || { db_diverges migrações; return 0; }
  [ "$(db_query "select extname from pg_extension" | LC_ALL=C sort)" = "$(schema_list extensions)" ] || { db_diverges extensões; return 0; }
  [ "$(db_query "select value from ar_internal_metadata where key = 'schema_sha1'")" = "$(ruby -rdigest -e 'print Digest::SHA1.file("db/schema.rb").hexdigest')" ] || { db_diverges schema_sha1; return 0; }
  echo match
}

db_matches_schema() { [ "$(db_state)" = match ]; }

echo "== Pré-condições ($MODE, apply=$APPLY)"
# Primeiro de tudo: contexto Docker pela configuração do cliente, sem consultar o daemon. Remoto aborta em qualquer modo, inclusive dry-run.
if docker_is_local; then
  echo "ok:    contexto Docker local (endpoint unix://)"
else
  echo "Abortado antes de qualquer consulta ao daemon: contexto Docker não é local (endpoint unix://)." >&2
  exit 1
fi
case "$MODE" in
  prepare)
    check "Ruby 3.4.4 (.ruby-version) no PATH deste repo, sem instalação automática" ruby_is_3_4_4
    check "nenhum arquivo Dotenv na raiz (o Rails leria; não é lido nem alterado)" no_dotenv_in_root
    check "alvo efetivo de config/database.yml (test) = 127.0.0.1:$PG_PORT/$DB_NAME" database_target_is_g0
    check "Docker daemon acessível" docker info
    check "porta $PG_PORT livre ou já publicada pelo projeto (Postgres)" port_is_free_or_ours "$PG_PORT"
    check "porta $REDIS_PORT livre ou já publicada pelo projeto (Redis)" port_is_free_or_ours "$REDIS_PORT"
    check "volume $VOLUME_NAME ausente ou comprovadamente deste projeto (rótulo e contêiner da origem)" volume_is_absent_or_ours "$VOLUME_NAME"
    check "containers e redes do projeto (nome ou rótulo) são deste worktree (projeto e arquivo Compose)" project_resources_owned
    check "segredo sintético ausente ou com permissão 0600 (fora do repo)" secret_is_ready
    check "segredo sintético existente se já houver recursos do projeto (nunca regenerar)" secret_is_consistent
    ;;
  spec)
    for spec in "${SPEC_FILES[@]}"; do
      spec_is_allowed "$spec" || { echo "Abortado: spec fora da allowlist G0: $spec" >&2; exit 2; }
    done
    check "Ruby 3.4.4 (.ruby-version) no PATH deste repo, sem instalação automática" ruby_is_3_4_4
    check "nenhum arquivo Dotenv na raiz (o Rails leria; não é lido nem alterado)" no_dotenv_in_root
    check "alvo efetivo de config/database.yml (test) = 127.0.0.1:$PG_PORT/$DB_NAME" database_target_is_g0
    check "Docker daemon acessível" docker info
    check "containers e redes do projeto (nome ou rótulo) são deste worktree (projeto e arquivo Compose)" project_resources_owned
    check "containers do projeto em execução" project_containers_running
    check "Postgres do projeto escutando em 127.0.0.1:$PG_PORT" port_is_open "$PG_PORT"
    check "Redis do projeto escutando em 127.0.0.1:$REDIS_PORT" port_is_open "$REDIS_PORT"
    check "segredo sintético presente com permissão 0600" secret_is_present
    check "banco de teste com schema esperado (sem recarga automática)" db_matches_schema
    ;;
  teardown)
    check "Docker daemon acessível" docker info
    check "containers e redes do projeto (nome ou rótulo) são deste worktree (projeto e arquivo Compose)" project_resources_owned
    check "segredo sintético presente (o Compose exige a variável para ler o arquivo)" secret_is_present
    ;;
esac

if [ "$FAILED" -eq 1 ]; then
  if [ "$APPLY" -eq 1 ]; then
    echo "Abortado antes de qualquer comando: pré-condições não atendidas." >&2
    exit 1
  fi
  echo "Dry-run: itens 'falta' precisam estar 'ok' antes de --apply."
fi

case "$MODE" in
  prepare)
    echo "== Segredo sintético (fora do repo, conteúdo não exibido)"
    if [ -e "$SECRET_FILE" ]; then
      echo "ok:    existente em $SECRET_FILE"
    elif [ "$APPLY" -eq 1 ]; then
      create_secret
      echo "criado: $SECRET_FILE (0600)"
    else
      echo "+ criar $SECRET_FILE (0600, aleatório; só com --apply)"
    fi
    if [ "$APPLY" -eq 1 ]; then export_secret; fi

    echo "== Preparo (repetível: recursos com propriedade comprovada são reutilizados)"
    run "${COMPOSE[@]}" config --quiet
    run "${COMPOSE[@]}" up -d --wait
    run bundle install
    echo "== Banco (verificação somente leitura; carga só em banco vazio)"
    case "$(db_state)" in
      match) echo "ok:    banco $DB_NAME com schema esperado ($(schema_list tables | wc -l | tr -d ' ') tabelas, $(schema_list versions | wc -l | tr -d ' ') migrações); sem carga" ;;
      empty)
        run bundle exec rails db:schema:load
        if [ "$APPLY" -eq 1 ] && [ "$(db_state)" != match ]; then
          echo "Abortado: após db:schema:load o banco não confere com db/schema.rb." >&2
          exit 1
        fi ;;
      unreachable)
        [ "$APPLY" -eq 0 ] || { echo "Abortado: Postgres do projeto não respondeu à verificação do banco." >&2; exit 1; }
        echo "falta: verificação do banco (Postgres do projeto ainda não está no ar em dry-run)" ;;
      diverge)
        [ "$APPLY" -eq 0 ] || { echo "Abortado: banco existente diverge de db/schema.rb; nada foi carregado nem alterado." >&2; exit 1; }
        echo "falta: banco existente igual ao schema versionado" ;;
    esac
    echo "== Validação pendente (não executada aqui; use --spec)"
    echo "   scripts/connecta/g0_test_env.sh --spec --apply"
    ;;
  spec)
    if [ "$APPLY" -eq 1 ]; then export_secret; fi
    echo "== Specs no alvo G0: ${SPEC_FILES[*]}"
    run bundle exec rspec "${SPEC_FILES[@]}"
    ;;
  teardown)
    if [ "$APPLY" -eq 1 ]; then export_secret; fi
    echo "== Teardown (sem -v: volumes são preservados)"
    run "${COMPOSE[@]}" down
    ;;
esac
