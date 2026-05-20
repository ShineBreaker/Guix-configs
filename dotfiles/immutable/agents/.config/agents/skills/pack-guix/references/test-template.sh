#!/usr/bin/env bash
# pack-guix — 单次测试脚本
# 用法: ./test.sh [package.scm] [test-command]

set -euo pipefail

PACKAGE_FILE="${1:-package.scm}"
TEST_CMD="${2:---version}"

# 从 package.scm 推断包名
PKG_NAME=$(grep -oP '^\s*\(name\s+"([^"]+)"' "$PACKAGE_FILE" | head -1 | grep -oP '"\K[^"]+' || echo "unknown")

echo "═══════════════════════════════════════"
echo "  Pack-Guix 测试: $PKG_NAME"
echo "  包文件: $PACKAGE_FILE"
echo "  测试命令: $TEST_CMD"
echo "═══════════════════════════════════════"

# 阶段 1：语法检查
echo ""
echo "[1/5] 语法检查..."
if guile -c "(load-from-path \"$PACKAGE_FILE\")" 2>/dev/null; then
  echo "  ✓ Scheme 语法正确"
else
  echo "  ✗ Scheme 语法错误"
  guile -c "(load-from-path \"$PACKAGE_FILE\")" 2>&1 | head -5
  exit 1
fi

# 阶段 2：Dry-run 构建
echo ""
echo "[2/5] Dry-run 构建..."
if guix build -f "$PACKAGE_FILE" --dry-run 2>&1 | tail -3; then
  echo "  ✓ Dry-run 通过"
else
  echo "  ✗ Dry-run 失败"
  exit 1
fi

# 阶段 3：实际构建
echo ""
echo "[3/5] 实际构建..."
if guix build -f "$PACKAGE_FILE" 2>&1 | tail -10; then
  echo "  ✓ 构建成功"
else
  echo "  ✗ 构建失败"
  exit 1
fi

# 阶段 4：安装验证
echo ""
echo "[4/5] 安装验证..."
if guix shell -f "$PACKAGE_FILE" -- "$PKG_NAME" $TEST_CMD 2>&1; then
  echo "  ✓ 安装验证通过"
else
  echo "  ⚠ 安装验证失败（可能包未提供 $TEST_CMD）"
fi

# 阶段 5：FHS 兼容性检查
echo ""
echo "[5/5] FHS 兼容性检查..."
OUTPUT_PATH=$(guix build -f "$PACKAGE_FILE" 2>/dev/null | tail -1)
if [ -n "$OUTPUT_PATH" ] && [ -d "$OUTPUT_PATH" ]; then
  FHS_ISSUES=0
  find "$OUTPUT_PATH" -type f -executable 2>/dev/null | while read bin; do
    INTERP=$(patchelf --print-interpreter "$bin" 2>/dev/null || true)
    if [ -n "$INTERP" ] && [[ "$INTERP" == *"/lib64/ld-linux"* ]]; then
      echo "  ⚠ $bin 仍使用 FHS 路径: $INTERP"
      FHS_ISSUES=$((FHS_ISSUES + 1))
    fi
  done
  if [ "$FHS_ISSUES" -eq 0 ]; then
    echo "  ✓ 无 FHS 兼容性问题"
  fi
else
  echo "  ⚠ 无法定位构建输出"
fi

echo ""
echo "═══════════════════════════════════════"
echo "  测试完成"
echo "═══════════════════════════════════════"
