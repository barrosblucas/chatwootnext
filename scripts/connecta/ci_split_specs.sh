#!/usr/bin/env bash
# Split the existing CE shard, without dropping files, before either Rails process boots.
set -euo pipefail

index="$1" total="$2"
shift 2
if [[ ! "$index" =~ ^(0|[1-9][0-9]*)$ || ! "$total" =~ ^[1-9][0-9]*$ ]] || (( index >= total )); then
  echo 'invalid shard' >&2
  exit 1
fi

position=0
for path in "$@"; do
  if [[ ! "$path" =~ ^spec/[A-Za-z0-9_./-]+_spec\.rb$ || "/$path/" == *'/../'* ]] || [ ! -f "$path" ]; then
    echo "invalid spec: $path" >&2
    exit 1
  fi
  if (( position % total != index )); then
    position=$((position + 1))
    continue
  fi
  case "$path" in
    spec/connecta/* | spec/requests/connecta/*) kind=f5 ;;
    *)
      kind=common
      if grep -qF 'G0TargetGuard.verify!' "$path"; then
        echo "guarded spec outside the F5 runner allowlist: $path" >&2
        exit 1
      fi ;;
  esac
  printf '%s\t%s\n' "$kind" "$path"
  position=$((position + 1))
done
