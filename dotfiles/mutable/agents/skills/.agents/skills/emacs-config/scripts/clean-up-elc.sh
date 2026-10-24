#!/usr/bin/env bash
# clean-up-elc.sh — 删 .elc 编译产物
#
# 用法: clean-up-elc.sh FILE...
#   FILE 可以是 .el / .elc / 绝对路径 / 相对于 REPO_ROOT 的路径
#
# 退出码:
#   0  全部删除成功(或文件本来就不存在)
#   1  路径既不是 .el 也不是 .elc

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

if [[ $# -lt 1 ]]; then
  echo "usage: $(basename "$0") FILE..." >&2
  echo "  接受 .el / .elc,绝对路径或相对 REPO_ROOT ($REPO_ROOT) 的路径" >&2
  exit 1
fi

for input_path in "$@"; do
  if [[ "$input_path" = /* ]]; then
    resolved_path="$input_path"
  else
    resolved_path="$REPO_ROOT/$input_path"
  fi

  case "$resolved_path" in
    *.el)
      target_path="${resolved_path}c"
      ;;
    *.elc)
      target_path="$resolved_path"
      ;;
    *)
      echo "error: unsupported path: $input_path" >&2
      exit 1
      ;;
  esac

  rm -f "$target_path"
done
