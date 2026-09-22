#!/usr/bin/env bash
# replay.sh — `hermes update` 后重放 prefetch fact_id 补丁
# 用法: bash $HERMES_HOME/patches/replay.sh
# 幂等: 上游已含补丁(输出行带 (#id))时直接报 OK 退出
set -u
HERMES_HOME="${HERMES_HOME:-$HOME/.local/share/hermes}"
CHECKOUT="$HERMES_HOME/hermes-agent"
TARGET="$CHECKOUT/plugins/memory/holographic/__init__.py"
PATCH="${BASH_SOURCE[0]%/*}/prefetch-fact-id.patch"

# 1. 已应用或上游已合并 → OK
if grep -q "(#{r.get('fact_id'" "$TARGET" 2>/dev/null; then
  echo "OK: prefetch 已带 fact_id (本地补丁或上游合并)"
  exit 0
fi

# 2. 应用补丁
if git -C "$CHECKOUT" apply --check "$PATCH" 2>/dev/null; then
  git -C "$CHECKOUT" apply "$PATCH" && echo "OK: 补丁已重放"
  exit $?
fi

# 3. 冲突 → 上游改了同一区域, 提示人工 review
echo "CONFLICT: 补丁无法干净应用 (上游可能已修改 prefetch 格式)"
echo "  查看: $TARGET 的 prefetch() 方法 (~line 156-165)"
echo "  补丁: $PATCH"
echo "  手动合并后重跑本脚本验证。"
exit 1
