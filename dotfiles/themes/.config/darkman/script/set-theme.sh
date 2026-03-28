#!/usr/bin/env bash

set -euo pipefail

usage() {
  printf 'Usage: %s <light|dark>\n' "${0##*/}" >&2
  exit 1
}

if [[ $# -ne 1 ]]; then
  usage
fi

mode="$1"
if [[ "$mode" != "light" && "$mode" != "dark" ]]; then
  usage
fi

if ! command -v jq >/dev/null 2>&1; then
  printf 'Error: jq is required but not found in PATH.\n' >&2
  exit 1
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
root_dir="$(cd -- "${script_dir}/.." && pwd)"
json_file="${script_dir}/config.json"
template_dir="${root_dir}/config"
target_root="${HOME}/.config"

if [[ ! -f "$json_file" ]]; then
  printf 'Error: config file not found: %s\n' "$json_file" >&2
  exit 1
fi

if [[ ! -d "$template_dir" ]]; then
  printf 'Error: template directory not found: %s\n' "$template_dir" >&2
  exit 1
fi

map_lines="$(
  jq -r --arg mode "$mode" '
    .[$mode] as $selected
    | if $selected == null then
        error("mode not found in config.json")
      else
        ($selected + ($selected.colors // {}) + {mode: $mode})
        | del(.colors)
        | to_entries[]
        | [.key, (.value|tostring)]
        | @tsv
      end
  ' "$json_file"
)"

if [[ -z "$map_lines" ]]; then
  printf 'Error: no variables resolved for mode "%s".\n' "$mode" >&2
  exit 1
fi

declare -A kv=()
sed_script="$(mktemp)"
cleanup() {
  rm -f -- "$sed_script"
}
trap cleanup EXIT

while IFS=$'\t' read -r key value; do
  [[ -z "$key" ]] && continue
  kv["$key"]="$value"
  key_pattern="$(printf '%s' "$key" | sed -e 's/[][(){}.^$*+?|\\-]/\\&/g')"
  value_repl="$(printf '%s' "$value" | sed -e 's/[|&\\]/\\&/g')"
  printf 's|\\$\\$%s\\$\\$|%s|g\n' "$key_pattern" "$value_repl" >> "$sed_script"
done <<< "$map_lines"

while IFS= read -r -d '' src; do
  rel="${src#${template_dir}/}"
  dst="${target_root}/${rel}"
  dst_dir="$(dirname -- "$dst")"
  mkdir -p -- "$dst_dir"

  while IFS= read -r placeholder; do
    [[ -z "$placeholder" ]] && continue
    pkey="${placeholder#\$\$}"
    pkey="${pkey%\$\$}"
    if [[ -z "${kv[$pkey]+_}" ]]; then
      printf 'Error: undefined placeholder "%s" in %s\n' "$placeholder" "$src" >&2
      exit 1
    fi
  done < <(grep -oE '\$\$[A-Za-z0-9_-]+\$\$' "$src" | sort -u || true)

  # Force overwrite even if noclobber is enabled in the caller environment.
  sed -f "$sed_script" "$src" >| "$dst"
  chmod --reference="$src" "$dst" 2>/dev/null || true
done < <(find "$template_dir" -type f -print0)
