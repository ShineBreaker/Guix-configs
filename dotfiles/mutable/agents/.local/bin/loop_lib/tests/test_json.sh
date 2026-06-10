#!/bin/sh
# SPDX-FileCopyrightText: 2026 brokenshine <brokenshine@users.noreply.codeberg.org>
# SPDX-License-Identifier: MIT
#
# test_json.sh — json_get / json_set / json_get_nested 回归测试
# 用法: ./test_json.sh
# 退出码 = 失败的测试数

set -e

_TJ_DIR="$(cd "$(dirname "$0")/.." && pwd)"
_LOOPCTL_LIB_DIR="$_TJ_DIR"
# 加载依赖
. "$_TJ_DIR/log.sh"
. "$_TJ_DIR/common.sh"

_TJ_PASS=0
_TJ_FAIL=0
_TJ_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$_TJ_TMPDIR"' EXIT

_assert_eq() {
	_ae_desc="$1"
	_ae_expected="$2"
	_ae_actual="$3"
	if [ "$_ae_expected" = "$_ae_actual" ]; then
		_TJ_PASS=$((_TJ_PASS + 1))
	else
		_TJ_FAIL=$((_TJ_FAIL + 1))
		printf 'FAIL: %s\n  expected: <%s>\n  actual:   <%s>\n' \
			"$_ae_desc" "$_ae_expected" "$_ae_actual" >&2
	fi
}

# === json_get 测试 ===

# T1: 基本字符串值
cat >"$_TJ_TMPDIR/t1.json" <<'EOF'
{
  "task": "hello world",
  "status": "active"
}
EOF
_assert_eq "json_get: basic string" "hello world" "$(json_get "$_TJ_TMPDIR/t1.json" "task")"
_assert_eq "json_get: basic string 2" "active" "$(json_get "$_TJ_TMPDIR/t1.json" "status")"

# T2: 数字值
cat >"$_TJ_TMPDIR/t2.json" <<'EOF'
{
  "iteration": 42,
  "max": 100
}
EOF
_assert_eq "json_get: number" "42" "$(json_get "$_TJ_TMPDIR/t2.json" "iteration")"
_assert_eq "json_get: number 2" "100" "$(json_get "$_TJ_TMPDIR/t2.json" "max")"

# T3: 含空格和路径的值
cat >"$_TJ_TMPDIR/t3.json" <<'EOF'
{
  "cwd": "/home/user/my project",
  "name": "test"
}
EOF
_assert_eq "json_get: path with space" "/home/user/my project" "$(json_get "$_TJ_TMPDIR/t3.json" "cwd")"

# T4: 缩进 JSON
cat >"$_TJ_TMPDIR/t4.json" <<'EOF'
{
  "name": "my-loop",
  "status": "active",
  "iteration": 5
}
EOF
_assert_eq "json_get: indented string" "my-loop" "$(json_get "$_TJ_TMPDIR/t4.json" "name")"
_assert_eq "json_get: indented number" "5" "$(json_get "$_TJ_TMPDIR/t4.json" "iteration")"

# === json_set 测试 ===

# T5: 设置字符串值（无特殊字符）
cat >"$_TJ_TMPDIR/t5.json" <<'EOF'
{
  "task": "old task",
  "status": "active"
}
EOF
json_set "$_TJ_TMPDIR/t5.json" "task" "new task"
_assert_eq "json_set: simple string" "new task" "$(json_get "$_TJ_TMPDIR/t5.json" "task")"

# T6: 设置含 & 的值（原始 bug）
cat >"$_TJ_TMPDIR/t6.json" <<'EOF'
{
  "task": "old",
  "status": "active"
}
EOF
json_set "$_TJ_TMPDIR/t6.json" "task" "fix bug in /path/to/file & other"
_assert_eq "json_set: value with &" "fix bug in /path/to/file & other" "$(json_get "$_TJ_TMPDIR/t6.json" "task")"

# T7: 设置含多个 & 的值
cat >"$_TJ_TMPDIR/t7.json" <<'EOF'
{
  "task": "old",
  "status": "active"
}
EOF
json_set "$_TJ_TMPDIR/t7.json" "task" "a & b & c & d"
_assert_eq "json_set: multiple &" "a & b & c & d" "$(json_get "$_TJ_TMPDIR/t7.json" "task")"

# T8: 设置数字值
cat >"$_TJ_TMPDIR/t8.json" <<'EOF'
{
  "iteration": 0,
  "max": 50
}
EOF
json_set "$_TJ_TMPDIR/t8.json" "iteration" "10"
_assert_eq "json_set: number" "10" "$(json_get "$_TJ_TMPDIR/t8.json" "iteration")"

# T9: 设置含路径的值
cat >"$_TJ_TMPDIR/t9.json" <<'EOF'
{
  "cwd": "/old/path",
  "status": "active"
}
EOF
json_set "$_TJ_TMPDIR/t9.json" "cwd" "/new/path/to/file"
_assert_eq "json_set: path value" "/new/path/to/file" "$(json_get "$_TJ_TMPDIR/t9.json" "cwd")"

# T10: 设置含 < > 的值（marker）
cat >"$_TJ_TMPDIR/t10.json" <<'EOF'
{
  "completion_marker": "old",
  "status": "active"
}
EOF
json_set "$_TJ_TMPDIR/t10.json" "completion_marker" "<promise>COMPLETE</promise>"
_assert_eq "json_set: marker with angle brackets" "<promise>COMPLETE</promise>" "$(json_get "$_TJ_TMPDIR/t10.json" "completion_marker")"

# T11: Round-trip 测试（写入 → 读取 → 修改 → 读取）
cat >"$_TJ_TMPDIR/t11.json" <<'EOF'
{
  "task": "initial",
  "status": "active",
  "iteration": 0
}
EOF
json_set "$_TJ_TMPDIR/t11.json" "task" "second value"
json_set "$_TJ_TMPDIR/t11.json" "iteration" "5"
_assert_eq "json_set: round-trip task" "second value" "$(json_get "$_TJ_TMPDIR/t11.json" "task")"
_assert_eq "json_set: round-trip iteration" "5" "$(json_get "$_TJ_TMPDIR/t11.json" "iteration")"
_assert_eq "json_set: round-trip status unchanged" "active" "$(json_get "$_TJ_TMPDIR/t11.json" "status")"

# === json_get_nested 测试 ===

# T12: 嵌套字段读取
cat >"$_TJ_TMPDIR/t12.json" <<'EOF'
{
  "run": {
    "input_method": "stdin",
    "timeout_sec": 300
  }
}
EOF
_assert_eq "json_get_nested: string" "stdin" "$(json_get_nested "$_TJ_TMPDIR/t12.json" "run" "input_method")"
_assert_eq "json_get_nested: number" "300" "$(json_get_nested "$_TJ_TMPDIR/t12.json" "run" "timeout_sec")"

# T13: 嵌套字段 — 单行 JSON
cat >"$_TJ_TMPDIR/t13.json" <<'EOF'
{"extract": {"type": "text"}}
EOF
_assert_eq "json_get_nested: single-line" "text" "$(json_get_nested "$_TJ_TMPDIR/t13.json" "extract" "type")"

# === 结果 ===
printf '\n=== Results: %d passed, %d failed ===\n' "$_TJ_PASS" "$_TJ_FAIL"
exit "$_TJ_FAIL"
