#!/usr/bin/env bash
# elisp-compile.sh — byte-compile 单个 .el 文件,成功后自动清理 .elc
#
# 用法: elisp-compile.sh FILE
#   FILE 可以是 .el 绝对路径,或相对于 REPO_ROOT 的路径
#
# 环境变量:
#   EMACS_CONFIG_LOAD_PATH  加入 load-path 的目录(默认 REPO_ROOT)
#   EMACSCLIENT_EXECUTABLE  emacsclient 可执行(默认 emacsclient)
#
# 退出码:
#   0  编译成功且已清理 .elc
#   1  文件不存在
#   2  byte-compile 失败
#   3  emacsclient 调用失败

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 脚本在 scripts/,父目录的父目录 = skill 容器根(默认 = ~/.agents/skills/)
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

if [[ $# -ne 1 ]]; then
  echo "usage: $(basename "$0") FILE" >&2
  echo "  FILE: 绝对路径,或相对于 REPO_ROOT ($REPO_ROOT) 的路径" >&2
  exit 1
fi

input_path="$1"
if [[ "$input_path" = /* ]]; then
  file_path="$input_path"
else
  file_path="$REPO_ROOT/$input_path"
fi

if [[ ! -f "$file_path" ]]; then
  echo "error: file not found: $file_path" >&2
  exit 1
fi

load_path="${EMACS_CONFIG_LOAD_PATH:-$REPO_ROOT}"
emacsclient_bin="${EMACSCLIENT_EXECUTABLE:-emacsclient}"

# 把字符串转义成 elisp 双引号字面量(转义 \ 和 ")
elisp_escape() {
  local v="$1"
  v="${v//\\/\\\\}"
  v="${v//\"/\\\"}"
  printf '"%s"' "$v"
}

file_lit=$(elisp_escape "$file_path")
load_lit=$(elisp_escape "$load_path")

# 在 emacsclient 模式下不能调 batch-byte-compile(那是 batch 模式专用)。
# 用 byte-compile-file 同步编译,然后 file-exists-p 判定是否生成了 .elc。
eval_form="(let ((load-path (cons $load_lit load-path)))
              (condition-case err
                  (progn
                    (byte-compile-file $file_lit)
                    (file-exists-p (concat $file_lit \"c\")))
                (error (format \"ERROR: %S\" err))))"

result=$("$emacsclient_bin" --eval "$eval_form" 2>&1) || {
  echo "error: emacsclient failed (is the daemon running?)" >&2
  echo "  detail: $result" >&2
  exit 3
}

if [[ "$result" == "t" ]]; then
  # 编译成功,清理 .elc
  "${SCRIPT_DIR}/clean-up-elc.sh" "$file_path"
  echo "ok: compiled and cleaned $file_path"
  exit 0
else
  echo "error: byte-compile failed for $file_path" >&2
  echo "  $result" >&2
  exit 2
fi
