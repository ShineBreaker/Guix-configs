#!/usr/bin/env bash
# elisp-reload.sh — 加载 .el 到运行中的 Emacs(load-file)
#
# 用法: elisp-reload.sh FILE [FILE2 ...]
#   每个 FILE 可以是 .el 绝对路径,或相对于 REPO_ROOT 的路径
#
# 环境变量:
#   EMACSCLIENT_EXECUTABLE  emacsclient 可执行(默认 emacsclient)
#
# 退出码:
#   0  加载成功
#   1  文件不存在
#   3  emacsclient 调用失败

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
emacsclient_bin="${EMACSCLIENT_EXECUTABLE:-emacsclient}"

elisp_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '"%s"' "$value"
}

if [[ $# -eq 0 ]]; then
  echo "usage: $(basename "$0") FILE [FILE2 ...]" >&2
  echo "  无参数时不加载任何文件(必须显式指定)" >&2
  exit 1
fi

load_forms=""
for input_path in "$@"; do
  if [[ "$input_path" = /* ]]; then
    file_path="$input_path"
  else
    file_path="$REPO_ROOT/$input_path"
  fi

  if [[ ! -f "$file_path" ]]; then
    echo "error: file not found: $file_path" >&2
    exit 1
  fi

  load_forms="$load_forms (load-file $(elisp_escape "$file_path"))"
done

eval_form="(progn$load_forms \"ok\")"
result=$("$emacsclient_bin" --eval "$eval_form" 2>&1) || {
  echo "error: emacsclient failed (is the daemon running?)" >&2
  echo "  detail: $result" >&2
  exit 3
}
