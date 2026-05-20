#!/usr/bin/env bash
# pack-guix — 持续测试脚本
# 用法: ./watch-test.sh [package.scm] [test-command]

set -euo pipefail

PACKAGE_FILE="${1:-package.scm}"
TEST_CMD="${2:---version}"

PKG_NAME=$(grep -oP '^\s*\(name\s+"([^"]+)"' "$PACKAGE_FILE" | head -1 | grep -oP '"\K[^"]+' || echo "unknown")

echo "═══════════════════════════════════════"
echo "  Pack-Guix 持续测试: $PKG_NAME"
echo "  监控文件: $PACKAGE_FILE"
echo "  Ctrl+C 退出"
echo "═══════════════════════════════════════"

run_test() {
  echo ""
  echo "[$(date '+%H:%M:%S')] 触发测试..."

  echo ">>> Dry-run..."
  if ! guix build -f "$PACKAGE_FILE" --dry-run >/dev/null 2>&1; then
    echo "  ✗ Dry-run 失败"
    return 1
  fi
  echo "  ✓ Dry-run 通过"

  echo ">>> 构建..."
  if ! guix build -f "$PACKAGE_FILE" >/dev/null 2>&1; then
    echo "  ✗ 构建失败"
    return 1
  fi
  echo "  ✓ 构建成功"

  echo ">>> 运行测试..."
  guix shell -f "$PACKAGE_FILE" -- "$PKG_NAME" $TEST_CMD 2>&1 | tail -1
  echo "--- 完成 ---"
}

# 首次运行
run_test

# 监控文件变化
inotifywait -m -e modify -e create -e delete \
  --format '%w%f' "$PACKAGE_FILE" 2>/dev/null | while read changed; do
  sleep 0.5
  run_test
done
