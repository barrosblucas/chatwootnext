#!/usr/bin/env bash
# Testes inertes do runner G0 (scripts/connecta/g0_test_env.sh): docker e bundle são stubs no PATH e respondem
# a partir de um estado falso em /tmp. Nenhum contêiner, volume, banco ou segredo real é tocado; cada chamada
# é registrada em calls.log. As respostas do banco espelham db/schema.rb e db/migrate do repo: isto prova o
# fluxo de decisão do runner, não o banco real (a prova real está em 05-execucao-repetivel.md).
#   bash .context/evidence/g0/04-runner-stub-tests.sh     (código 1 se algum caso falhar)
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../../.." && pwd -P)"
RUBY_BIN="$HOME/.cache/connecta-g0-test/toolchain/mise-data/installs/ruby/3.4.4/bin"
WORK="$(mktemp -d /tmp/g0-stub-XXXXXX)"
WORK="$(cd "$WORK" && pwd -P)"
trap 'case "$WORK" in /tmp/g0-stub-*) rm -rf -- "$WORK" ;; esac' EXIT
PASS=0
FAIL=0
SKIP=0

[ -x "$RUBY_BIN/ruby" ] || { echo "Ruby 3.4.4 do cache não encontrado; abortado" >&2; exit 1; }
mkdir -p "$WORK/bin"

cat > "$WORK/bin/docker" <<'STUB'
#!/usr/bin/env bash
# Stub de docker: estado em $HOME/stub-state. Nunca chama o daemon real.
S="$HOME/stub-state"
log() { printf 'docker %s\n' "$*" >> "$S/calls.log"; }
collect_filters() { FILTERS=(); while [ $# -gt 0 ]; do if [ "$1" = --filter ]; then FILTERS+=("$2"); shift; fi; shift; done; }
schema_list() {
  local repo
  repo="$(cat "$S/repo")"
  case "$1" in
    tables) grep -oE '^ *create_table "[^"]+"' "$repo/db/schema.rb" | sed -E 's/.*"([^"]+)"/\1/' ;;
    extensions) grep -oE 'enable_extension "[^"]+"' "$repo/db/schema.rb" | sed -E 's/.*"([^"]+)"/\1/' ;;
    versions) ls "$repo/db/migrate/"*.rb | sed -E 's#.*/([0-9]+)_[^/]*$#\1#' ;;
  esac | LC_ALL=C sort
}
case "$1" in
  context) log "context $*"; cat "$S/endpoint"; exit 0 ;;
  info) log info; exit 0 ;;
  compose) log "compose ${*:2}"; exit 0 ;;
  ps)
    shift; collect_filters "$@"; log "ps $*"
    while IFS='|' read -r id name project conf service ports vols; do
      [ -n "$id" ] || continue
      ok=1
      for f in "${FILTERS[@]}"; do
        case "$f" in
          name=*) [[ "$name" == *"${f#name=}"* ]] || ok=0 ;;
          label=com.docker.compose.project=*) [ "$project" = "${f#label=com.docker.compose.project=}" ] || ok=0 ;;
          label=com.docker.compose.service=*) [ "$service" = "${f#label=com.docker.compose.service=}" ] || ok=0 ;;
          volume=*) [[ ",$vols," == *",${f#volume=},"* ]] || ok=0 ;;
          status=running) ;;
          *) ok=0 ;;
        esac
      done
      [ "$ok" = 1 ] && echo "$id"
    done < "$S/containers"
    exit 0 ;;
  inspect)
    log "inspect $*"; fmt="$3"; id="$4"
    row="$(grep -m1 "^$id|" "$S/containers")" || { echo "Error: No such object: $id" >&2; exit 1; }
    IFS='|' read -r _ _ project conf _ _ _ <<< "$row"
    case "$fmt" in
      *config_files*) echo "$conf" ;;
      *) echo "$project" ;;
    esac
    exit 0 ;;
  port)
    log "port $2"
    row="$(grep -m1 "^$2|" "$S/containers")" || exit 0
    IFS='|' read -r _ _ _ _ _ ports _ <<< "$row"
    printf '%s\n' "$ports" | tr ';' '\n' | sed '/^$/d'
    exit 0 ;;
  network)
    case "$2" in
      ls)
        shift 2; collect_filters "$@"; log "network ls $*"
        while IFS='|' read -r name project attached; do
          [ -n "$name" ] || continue
          ok=1
          for f in "${FILTERS[@]}"; do
            case "$f" in
              name=*) [[ "$name" == *"${f#name=}"* ]] || ok=0 ;;
              label=com.docker.compose.project=*) [ "$project" = "${f#label=com.docker.compose.project=}" ] || ok=0 ;;
              *) ok=0 ;;
            esac
          done
          [ "$ok" = 1 ] && echo "$name"
        done < "$S/networks"
        exit 0 ;;
      inspect)
        log "network inspect $*"; fmt="$4"; name="$5"
        row="$(grep -m1 "^$name|" "$S/networks")" || exit 1
        IFS='|' read -r _ project attached <<< "$row"
        case "$fmt" in
          *Containers*) echo "$attached" ;;
          *) echo "$project" ;;
        esac
        exit 0 ;;
    esac ;;
  volume)
    case "$2" in
      inspect)
        log "volume inspect $*"
        if [ "$3" = -f ]; then fmt="$4"; name="$5"; else fmt=""; name="$3"; fi
        row="$(grep -m1 "^$name|" "$S/volumes")" || { echo "Error: No such volume: $name" >&2; exit 1; }
        IFS='|' read -r _ project <<< "$row"
        [ -z "$fmt" ] || echo "$project"
        exit 0 ;;
    esac ;;
  exec)
    log "exec $2 $(printf '%s ' "${@:3}" | cut -c1-140)"
    mode="$(cat "$S/db")"
    [ "$mode" != unreachable ] || exit 2
    query="${*: -1}"
    empty=0; [ "$mode" = empty ] && [ ! -f "$S/db_loaded" ] && empty=1
    rogue=0; [ "$mode" = diverge ] && rogue=1
    case "$query" in
      *"count(*) from pg_tables"*) if [ "$empty" = 1 ]; then echo 0; else echo 112; fi ;;
      *"select tablename from pg_tables"*) schema_list tables; if [ "$rogue" = 1 ]; then echo rogue_table; fi ;;
      *"from schema_migrations"*) schema_list versions ;;
      *"from pg_extension"*) schema_list extensions ;;
      *schema_sha1*) if [ "$rogue" = 1 ]; then echo 0000; else sha1sum "$(cat "$S/repo")/db/schema.rb" | cut -d' ' -f1; fi ;;
      *) echo "stub: consulta não prevista" >&2; exit 97 ;;
    esac
    exit 0 ;;
  *) log "NÃO PREVISTO docker $*"; exit 99 ;;
esac
STUB

cat > "$WORK/bin/bundle" <<'STUB'
#!/usr/bin/env bash
# Stub de bundle: só registra. "exec rails db:schema:load" marca o banco como carregado.
S="$HOME/stub-state"
printf 'bundle %s\n' "$*" >> "$S/calls.log"
if [ "$*" = "exec rails db:schema:load" ]; then touch "$S/db_loaded"; fi
exit 0
STUB
chmod 700 "$WORK/bin/docker" "$WORK/bin/bundle"

CFG_REL=scripts/connecta/g0-test-services.compose.yml
TROOT="$WORK/root"
S=""
OUT=""
CODE=""

record() { # record ok|fail|skip <descrição> [motivo]
  case "$1" in
    ok) PASS=$((PASS + 1)); echo "PASS $2" ;;
    fail) FAIL=$((FAIL + 1)); echo "FAIL $2: ${3:-}" ;;
    skip) SKIP=$((SKIP + 1)); echo "SKIP $2: ${3:-}" ;;
  esac
}

new_case() { # zera HOME e o estado falso; o repo de referência é o real
  rm -rf -- "$WORK/home"
  S="$WORK/home/stub-state"
  mkdir -p "$S" "$WORK/home/.cache/connecta-g0-test"
  echo "$REPO" > "$S/repo"
  echo unix:///var/run/docker.sock > "$S/endpoint"
  echo match > "$S/db"
  : > "$S/containers"; : > "$S/volumes"; : > "$S/networks"; : > "$S/calls.log"
}

use_troot() { # raiz temporária: cópia do runner e do compose, para casos de .env, alvo e allowlist
  rm -rf -- "$TROOT"
  mkdir -p "$TROOT/scripts/connecta" "$TROOT/config"
  cp "$REPO/scripts/connecta/g0_test_env.sh" "$REPO/scripts/connecta/g0-test-services.compose.yml" "$TROOT/scripts/connecta/"
  cp "$REPO/config/database.yml" "$TROOT/config/"
  echo "$TROOT" > "$S/repo"
}

ours_state() { # recursos do projeto com origem = raiz indicada ($1), portas como no compose real
  local cfg="$1/$CFG_REL"
  printf '%s\n' \
    "pgid|conecta-baileys-g0-test-postgres-1|conecta-baileys-g0-test|$cfg|postgres|5432/tcp -> 127.0.0.1:55432|conecta-baileys-g0-test_g0_postgres" \
    "rdid|conecta-baileys-g0-test-redis-1|conecta-baileys-g0-test|$cfg|redis|6379/tcp -> 127.0.0.1:56379|" > "$S/containers"
  echo "conecta-baileys-g0-test_g0_postgres|conecta-baileys-g0-test" > "$S/volumes"
  echo "conecta-baileys-g0-test_default|conecta-baileys-g0-test|pgid rdid" > "$S/networks"
}

SECRET() { echo "$WORK/home/.cache/connecta-g0-test/synthetic-secret"; }
new_secret() { head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n' > "$(SECRET)"; chmod 600 "$(SECRET)"; }
sha_of() { sha256sum "$1" | cut -d' ' -f1; }

run_runner() { # run_runner <raiz> <args...> → CODE e OUT
  local root="$1"
  shift
  OUT="$WORK/out.txt"
  PATH="$WORK/bin:$RUBY_BIN:$PATH" HOME="$WORK/home" bash "$root/scripts/connecta/g0_test_env.sh" "$@" >"$OUT" 2>&1 </dev/null
  CODE=$?
}

expect() { # expect <descrição> <exit> <regex na saída|-> <regex que deve estar no log|-> <regex proibido no log|->
  local why=""
  [ "$CODE" = "$2" ] || why="exit $CODE, esperado $2"
  if [ "$3" != - ] && ! grep -qE -- "$3" "$OUT"; then why="${why:+$why; }saída sem /$3/"; fi
  if [ "$4" != - ] && ! grep -qE -- "$4" "$S/calls.log"; then why="${why:+$why; }log sem /$4/"; fi
  if [ "$5" != - ] && grep -qE -- "$5" "$S/calls.log"; then why="${why:+$why; }log contém /$5/"; fi
  if [ -z "$why" ]; then record ok "$1"; else record fail "$1" "$why"; fi
}

port_open() { (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; }

echo "== Caso 1: retomada com recursos próprios e banco esperado"
new_case; ours_state "$REPO"; new_secret; SHA0="$(sha_of "$(SECRET)")"
run_runner "$REPO"
expect "dry-run prepare: banco esperado, nenhum comando de compose executado" 0 "banco conecta_baileys_g0_test com schema esperado" - "compose .*up"
run_runner "$REPO" --apply
expect "apply repetido: reutiliza recursos, sem carga de schema" 0 "sem carga" "compose .*up -d --wait" "schema:load"
if [ "$(sha_of "$(SECRET)")" = "$SHA0" ]; then record ok "segredo existente preservado (mesmo hash, sem regenerar)"; else record fail "segredo preservado" "hash mudou"; fi

echo "== Caso 2: banco vazio em volume próprio recebe carga única"
new_case; ours_state "$REPO"; new_secret; echo empty > "$S/db"
run_runner "$REPO" --apply
expect "banco vazio: schema carregado e revalidado" 0 - "bundle exec rails db:schema:load" -
if [ "$(grep -c 'schema:load' "$S/calls.log")" = 1 ]; then record ok "carga executada exatamente uma vez"; else record fail "carga única" "contagem $(grep -c 'schema:load' "$S/calls.log")"; fi

echo "== Caso 3: divergências do banco abortam sem carga"
new_case; ours_state "$REPO"; new_secret; echo diverge > "$S/db"
run_runner "$REPO" --apply
expect "tabela fora do schema: aborta sem carga" 1 "Abortado: banco existente diverge" - "schema:load"
new_case; ours_state "$REPO"; new_secret; echo unreachable > "$S/db"
run_runner "$REPO" --apply
expect "Postgres não responde à verificação: aborta" 1 "não respondeu à verificação" - "schema:load"

echo "== Caso 4: posse de volume, contêiner e rede"
new_case; new_secret
echo "conecta-baileys-g0-test_g0_postgres|conecta-baileys-g0-test" > "$S/volumes"
run_runner "$REPO" --apply
expect "volume órfão (sem contêiner montando): recusado" 1 "falta: volume conecta-baileys-g0-test_g0_postgres ausente ou comprovadamente" - "compose .*up"
new_case; new_secret
echo "conecta-baileys-g0-test_g0_postgres|outro-projeto" > "$S/volumes"
echo "pgid|conecta-baileys-g0-test-postgres-1|outro-projeto|/outro/worktree/$CFG_REL|postgres|5432/tcp -> 127.0.0.1:55432|conecta-baileys-g0-test_g0_postgres" > "$S/containers"
run_runner "$REPO" --apply
expect "volume de outro projeto com contêiner de outra origem: recusado" 1 "falta: volume conecta-baileys-g0-test_g0_postgres ausente ou comprovadamente" - "compose .*up"
new_case; new_secret; ours_state "/outro/worktree"
run_runner "$REPO" --apply
expect "contêiner com origem Compose de outro worktree: recusado" 1 "falta: containers e redes do projeto" - "compose .*up"

echo "== Caso 5: segredo e permissões"
new_case; ours_state "$REPO"
run_runner "$REPO" --apply
expect "recursos existentes sem segredo: aborta sem regenerar" 1 "falta: segredo sintético existente se já houver recursos" - "compose .*up"
if [ ! -e "$(SECRET)" ]; then record ok "segredo não foi criado sobre recursos existentes"; else record fail "segredo não criado" "arquivo apareceu"; fi
new_case; ours_state "$REPO"; new_secret; chmod 644 "$(SECRET)"
run_runner "$REPO" --apply
expect "segredo com permissão 644: aborta" 1 "falta: segredo sintético ausente ou com permissão 0600" - "compose .*up"

echo "== Caso 6: contexto Docker remoto"
new_case; ours_state "$REPO"; new_secret; echo "tcp://10.0.0.5:2376" > "$S/endpoint"
run_runner "$REPO" --apply
expect "contexto remoto: aborta antes de qualquer consulta ao daemon" 1 "contexto Docker não é local" "^docker context" "^docker (info|ps|inspect|network|volume|port|exec|compose)|^bundle"

echo "== Caso 7: porta ocupada sem dono do projeto"
if port_open 55432; then
  new_case; new_secret
  run_runner "$REPO" --apply
  expect "porta 55432 ocupada e sem contêiner do projeto: aborta" 1 "falta: porta 55432 livre ou já publicada" - "compose .*up"
else
  record skip "porta 55432 ocupada sem dono" "porta real não está em uso; cenário depende das portas reais"
fi

echo "== Caso 8: .env e alvo do banco (cópia temporária, fora do repo)"
new_case; use_troot; ours_state "$TROOT"; new_secret; : > "$TROOT/.env"
run_runner "$TROOT" --apply
expect ".env na raiz: aborta antes de qualquer comando" 1 "falta: nenhum arquivo Dotenv" - "compose .*up|^bundle"
rm -f -- "$TROOT/.env"
if grep -q 'POSTGRES_PORT' "$TROOT/config/database.yml"; then
  sed -i 's/POSTGRES_PORT/G0_STUB_PORTA_ERRADA/' "$TROOT/config/database.yml"
  run_runner "$TROOT" --apply
  expect "config do banco aponta para outra porta: aborta" 1 "falta: alvo efetivo de config/database.yml" - "compose .*up|^bundle"
else
  record fail "config do banco com POSTGRES_PORT" "padrão não encontrado em config/database.yml"
fi

echo "== Caso 9: allowlist de specs"
for p in '../../x_spec.rb' 'spec/models/x_spec.rb' 'spec/connecta/x.rb' '/etc/x_spec.rb' 'spec/connecta/../../x_spec.rb' 'spec/connecta/a b_spec.rb' 'spec/connecta/nao_existe_spec.rb'; do
  new_case; ours_state "$REPO"; new_secret
  run_runner "$REPO" --spec --apply "$p"
  expect "spec recusada: $p" 2 "spec fora da allowlist" "^docker context" "rspec|compose|^docker (info|ps|exec)"
done
new_case; ours_state "$REPO"; new_secret
run_runner "$REPO" --spec --apply -x
expect "opção desconhecida com --spec: uso" 2 "uso:" - "rspec"
new_case; ours_state "$REPO"; new_secret
run_runner "$REPO" spec/requests/connecta/route_inventory_spec.rb
expect "caminho de spec sem --spec: uso inválido" 2 "caminhos de spec só valem com --spec" - "rspec|docker"
use_troot_symlink() {
  mkdir -p "$TROOT/spec/connecta"
  echo "" > "$WORK/real_spec.rb"
  ln -sf "$WORK/real_spec.rb" "$TROOT/spec/connecta/link_spec.rb"
}
new_case; use_troot; use_troot_symlink; ours_state "$TROOT"; new_secret
run_runner "$TROOT" --spec --apply spec/connecta/link_spec.rb
expect "link simbólico em spec/connecta: recusado" 2 "spec fora da allowlist" - "rspec"

echo "== Caso 10: specs no alvo G0"
new_case; ours_state "$REPO"; new_secret
run_runner "$REPO" --spec --apply spec/requests/connecta/route_inventory_spec.rb
expect "spec da allowlist roda no alvo G0 com o comando exato" 0 "route_inventory_spec" "^bundle exec rspec spec/requests/connecta/route_inventory_spec.rb$" -
new_case; ours_state "$REPO"; new_secret; echo diverge > "$S/db"
run_runner "$REPO" --spec --apply
expect "spec sem schema esperado: não executa" 1 "falta: banco de teste com schema esperado" - "rspec"

echo
echo "RESUMO: PASS=$PASS FAIL=$FAIL SKIP=$SKIP"
[ "$FAIL" -eq 0 ]
