#!/usr/bin/env bash
# run-tests.sh — 跑 ERT 测试,通过 emacsclient 走本机 daemon
#
# 用法: run-tests.sh [--test-file FILE]...
#
# 环境变量:
#   EMACS_CONFIG_LOAD_PATH  加入 load-path 的目录(默认 REPO_ROOT)
#   EMACS_TEST_DIR          测试目录(默认 REPO_ROOT/tests)
#   EMACSCLIENT_EXECUTABLE  emacsclient 可执行(默认 emacsclient)
#
# 退出码:
#   0  所有测试通过
#   1  有测试失败
#   2  调用错误(找不到文件、解析失败)
#   3  emacsclient 调用失败
#
# 实现说明:
#   故意不调 ert-run-tests-batch-and-exit —— 那个函数会 kill-emacs,会杀掉
#   用户正在用的 daemon。改用 (ert-run-tests t) 同步跑测试,返回失败数量,
#   由 bash 翻译为退出码。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEST_DIR="${EMACS_TEST_DIR:-$REPO_ROOT/tests}"
LOAD_PATH="${EMACS_CONFIG_LOAD_PATH:-$REPO_ROOT}"
emacsclient_bin="${EMACSCLIENT_EXECUTABLE:-emacsclient}"

SELECTED_TEST_FILES=()

usage() {
  cat <<EOF
Usage: $(basename "$0") [--test-file FILE]...

Run ERT tests under EMACS_TEST_DIR (default: REPO_ROOT/tests).
Goes through \`emacsclient --eval\` against the running Emacs daemon
(does NOT spawn a new Emacs process).

Environment:
  EMACS_CONFIG_LOAD_PATH   Add this path to load-path (default: REPO_ROOT)
  EMACS_TEST_DIR           Test directory (default: REPO_ROOT/tests)
  EMACSCLIENT_EXECUTABLE   emacsclient binary (default: emacsclient)

Options:
  --test-file FILE  Load only the named test file. May be repeated.
                    Accepts a basename like foo-tests.el, a path relative
                    to REPO_ROOT, or an absolute path.
  -h, --help        Show this help text.
EOF
}

resolve_test_file() {
  local candidate="$1"
  if [[ "$candidate" = /* ]]; then
    printf '%s\n' "$candidate"
    return
  fi
  if [[ "$candidate" == */* ]]; then
    printf '%s\n' "$REPO_ROOT/$candidate"
    return
  fi
  printf '%s\n' "$TEST_DIR/$candidate"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --test-file)
      if [[ $# -lt 2 ]]; then
        echo "error: --test-file requires a file argument" >&2
        usage >&2
        exit 2
      fi
      SELECTED_TEST_FILES+=("$(resolve_test_file "$2")")
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

elisp_escape() {
  local v="$1"
  v="${v//\\/\\\\}"
  v="${v//\"/\\\"}"
  printf '"%s"' "$v"
}

load_lit=$(elisp_escape "$LOAD_PATH")
test_files_forms=""
test_files_count=0

if [[ ${#SELECTED_TEST_FILES[@]} -eq 0 ]]; then
  if [[ ! -d "$TEST_DIR" ]]; then
    echo "error: test directory not found: $TEST_DIR" >&2
    echo "  set EMACS_TEST_DIR to override" >&2
    exit 2
  fi
  while IFS= read -r test_file; do
    test_files_forms="$test_files_forms (load $(elisp_escape "$test_file") nil t)"
    test_files_count=$((test_files_count + 1))
  done < <(find "$TEST_DIR" -maxdepth 1 -type f -name '*-tests.el' 2>/dev/null | sort)
else
  for test_file in "${SELECTED_TEST_FILES[@]}"; do
    if [[ ! -f "$test_file" ]]; then
      echo "error: test file not found: $test_file" >&2
      exit 2
    fi
    test_files_forms="$test_files_forms (load $(elisp_escape "$test_file") nil t)"
    test_files_count=$((test_files_count + 1))
  done
fi

if [[ $test_files_count -eq 0 ]]; then
  echo "warning: no test files (*-tests.el) found in $TEST_DIR" >&2
  exit 0
fi

# 用 ert--failed-list 取失败数(Emacs 24+ ert 包内稳定 internal)。
test_form="(let ((load-path (cons $load_lit load-path)))
              (progn
                $test_files_forms
                (length (ert--failed-list (ert-run-tests t)))))"

result=$("$emacsclient_bin" --eval "$test_form" 2>&1) || {
  echo "error: emacsclient failed (is the daemon running?)" >&2
  echo "  detail: $result" >&2
  exit 3
}

# 提取整数(emacsclient 把 elisp 整数渲染为 "0" / "1" / ...)
failed_count=$(printf '%s' "$result" | tr -d '[:space:]' | grep -oE '^[0-9]+$' || true)
if [[ -z "$failed_count" ]]; then
  echo "error: could not parse emacsclient result" >&2
  echo "  raw: $result" >&2
  exit 2
fi

if [[ "$failed_count" -eq 0 ]]; then
  echo "ok: all tests passed ($test_files_count file(s))"
  exit 0
else
  echo "fail: $failed_count test(s) failed ($test_files_count file(s) loaded)" >&2
  exit 1
fi
