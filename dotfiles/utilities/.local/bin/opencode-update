#!/usr/bin/env bash
set -euo pipefail

CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/opencode.json"

if [ ! -f "$CONFIG" ]; then
  echo "配置文件不存在: $CONFIG" >&2
  exit 1
fi

mapfile -t plugins < <(jq -r '.plugin[]?' "$CONFIG")

if [ ${#plugins[@]} -eq 0 ]; then
  echo "未找到任何插件配置" >&2
  exit 0
fi

total=${#plugins[@]}
current=0
ok=0
fail=0

for plugin in "${plugins[@]}"; do
  current=$((current + 1))
  printf "[%d/%d] 更新 %s ... " "$current" "$total" "$plugin"

  if opencode plugin "$plugin" -f < /dev/null > /dev/null 2>&1; then
    echo "OK"
    ok=$((ok + 1))
  else
    echo "FAIL"
    fail=$((fail + 1))
  fi
done

echo ""
echo "完成: $ok 成功, $fail 失败, 共 $total 个插件"
