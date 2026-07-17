#!/usr/bin/env bash
# probe-nix-install.sh —— 探针:输出当前 hermes Nix 部署状态
#
# 用法: ./probe-nix-install.sh
# 输出: hermes-agent-env store 路径、hermes 版本、关键子路径存在性、wrapper 状态

set -euo pipefail

USER_HOME="${HOME:-$(getent passwd "$(id -un)" | cut -d: -f6)}"
HERMES_HOME="${HERMES_HOME:-$USER_HOME/.local/share/hermes}"

echo "═══════════════════════════════════════════════"
echo " Hermes Nix 安装状态探针"
echo " 时间: $(date -Iseconds)"
echo " 用户: $(id -un)@$(hostname)"
echo "═══════════════════════════════════════════════"
echo ""

echo "◆ 1. hermes-agent-env store 路径"
echo "─────────────────────────────────"
HERMES_ENV="$(ls -td /nix/store/*-hermes-agent-env 2>/dev/null | head -1 || true)"
if [ -z "$HERMES_ENV" ]; then
  echo "  ✗ NOT FOUND: 找不到 /nix/store/*-hermes-agent-env"
  echo "    本用户没装 hermes?检查:nix profile list | grep hermes"
  exit 1
fi
echo "  ✓ $HERMES_ENV"
echo ""

echo "◆ 2. hermes 二进制"
echo "─────────────────────────────────"
HERMES_BIN="$HERMES_ENV/bin/hermes"
if [ -x "$HERMES_BIN" ]; then
  echo "  ✓ $HERMES_BIN"
  HERMES_VERSION="$("$HERMES_BIN" --version 2>&1 | head -1 || echo 'unknown')"
  echo "    版本: $HERMES_VERSION"
  echo "    大小: $(stat -c %s "$HERMES_BIN") bytes"
  echo "    mtime: $(stat -c %y "$HERMES_BIN")"
else
  echo "  ✗ NOT EXECUTABLE: $HERMES_BIN"
fi
echo ""

echo "◆ 3. wrapper (PATH 中的 hermes 命令)"
echo "─────────────────────────────────"
if command -v hermes >/dev/null 2>&1; then
  WRAPPER_PATH="$(command -v hermes)"
  echo "  ✓ $WRAPPER_PATH"
  echo "    类型: $([ -L "$WRAPPER_PATH" ] && echo 'symlink' || ([ -f "$WRAPPER_PATH" ] && ([ -x "$WRAPPER_PATH" ] && echo 'script (executable)' || echo 'script (NOT executable!)') || echo 'unknown'))"
  if [ -f "$WRAPPER_PATH" ] && head -3 "$WRAPPER_PATH" | grep -q "hermes-agent-env"; then
    echo "    ✓ wrapper 内容看起来正确(Nix-aware)"
  elif [ -L "$WRAPPER_PATH" ]; then
    SYMLINK_TARGET="$(readlink -f "$WRAPPER_PATH")"
    echo "    → symlink target: $SYMLINK_TARGET"
    if [[ "$SYMLINK_TARGET" == /nix/store/* ]]; then
      echo "    ✓ 直链到 nix-store(也合法)"
    else
      echo "    ⚠ 目标不在 nix-store,可能指向 venv 等已不存在的路径"
    fi
  fi
else
  echo "  ✗ hermes 不在 PATH"
  echo "    修法: 跑 scripts/install-wrapper.sh"
fi
echo ""

echo "◆ 4. HERMES_HOME 状态"
echo "─────────────────────────────────"
echo "  HERMES_HOME=$HERMES_HOME"
if [ -d "$HERMES_HOME" ]; then
  echo "  ✓ 存在"
  echo "    skills/: $(ls -d "$HERMES_HOME/skills"/*/ 2>/dev/null | wc -l) 个分类"
  echo "    cron/jobs.json: $([ -f "$HERMES_HOME/cron/jobs.json" ] && echo '✓' || echo '✗')"
  echo "    state.db: $([ -f "$HERMES_HOME/state.db" ] && echo "✓ ($(stat -c %s "$HERMES_HOME/state.db") bytes)" || echo '✗')"
  echo "    scripts/: $(ls "$HERMES_HOME/scripts" 2>/dev/null | wc -l) 个文件"
  echo "    logs/: $(ls "$HERMES_HOME/logs"/*.log 2>/dev/null | wc -l) 个日志文件"
else
  echo "  ✗ 目录不存在:$HERMES_HOME"
fi
echo ""

echo "◆ 5. cron jobs 状态"
echo "─────────────────────────────────"
if [ -x "$HERMES_BIN" ]; then
  CRON_OUTPUT="$("$HERMES_BIN" cron list 2>&1 || true)"
  if echo "$CRON_OUTPUT" | grep -q "active"; then
    JOB_COUNT="$(echo "$CRON_OUTPUT" | grep -c '\[active\]' || echo 0)"
    ERROR_COUNT="$(echo "$CRON_OUTPUT" | grep -c 'error:' || echo 0)"
    echo "  ✓ 找到 $JOB_COUNT 个活跃 job"
    if [ "$ERROR_COUNT" -gt 0 ]; then
      echo "  ⚠ $ERROR_COUNT 个 job 上次运行有错误"
      echo "$CRON_OUTPUT" | grep -B1 'error:' | head -10
    fi
  else
    echo "  ? hermes cron list 输出异常:"
    echo "$CRON_OUTPUT" | head -10
  fi
else
  echo "  - 跳过(hermes 二进制不可用)"
fi
echo ""

echo "◆ 6. hermes-agent-env 内部关键路径"
echo "─────────────────────────────────"
for sub in \
  "lib/python3.12/site-packages/hermes_cli/main.py" \
  "lib/python3.12/site-packages/cron/scheduler.py" \
  "lib/python3.12/site-packages/cron/jobs.py" \
  "lib/python3.12/site-packages/hermes_state.py" \
  "lib/python3.12/site-packages/hermes_logging.py" \
  "lib/python3.12/site-packages/tools/registry.py" \
  ; do
  if [ -f "$HERMES_ENV/$sub" ]; then
    SIZE=$(stat -c %s "$HERMES_ENV/$sub")
    echo "  ✓ $sub ($SIZE bytes)"
  else
    echo "  ✗ $sub"
  fi
done
echo ""

echo "◆ 7. Nix profile 引用"
echo "─────────────────────────────────"
if command -v nix >/dev/null 2>&1; then
  NIX_PROFILE_PATHS="$(nix-store --query --referrers "$HERMES_BIN" 2>/dev/null | head -3 || true)"
  if [ -n "$NIX_PROFILE_PATHS" ]; then
    echo "$NIX_PROFILE_PATHS" | while read -r p; do
      echo "    $p"
    done
  else
    echo "  (无 referrer — hermes 可能是手动 gc-rooted)"
  fi
else
  echo "  - 跳过(nix 命令不可用)"
fi
echo ""

echo "═══════════════════════════════════════════════"
echo " 探针完成"
echo "═══════════════════════════════════════════════"