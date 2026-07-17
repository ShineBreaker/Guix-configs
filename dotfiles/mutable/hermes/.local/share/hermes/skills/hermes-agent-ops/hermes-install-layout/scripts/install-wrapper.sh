#!/usr/bin/env bash
# install-wrapper.sh —— 一键装 ~/.local/bin/hermes wrapper(Nix/Guix 用户必备)
#
# 用法: ./install-wrapper.sh
# 作用: 探测 /nix/store/*-hermes-agent-env/bin/hermes,建 wrapper 在 ~/.local/bin/
# 验证: which hermes → /home/<user>/.local/bin/hermes;hermes --version → 正常输出

set -euo pipefail

USER_HOME="${HOME:-$(getent passwd "$(id -un)" | cut -d: -f6)}"
WRAPPER_DIR="$USER_HOME/.local/bin"
WRAPPER_PATH="$WRAPPER_DIR/hermes"

# 探测 hermes-agent-env
HERMES_BIN="$(ls -t /nix/store/*-hermes-agent-env/bin/hermes 2>/dev/null | head -1 || true)"

if [ -z "$HERMES_BIN" ] || [ ! -x "$HERMES_BIN" ]; then
  echo "ERROR: 找不到 /nix/store/*-hermes-agent-env/bin/hermes" >&2
  echo "  本 skill 假设 hermes 通过 Nix 部署。如果是 pip/uv 装的,本 skill 不适用。" >&2
  echo "  验证:" >&2
  echo "    ls /nix/store/ | grep hermes-agent-env" >&2
  echo "    nix profile list  # 看 hermes 是否在 profile 里" >&2
  exit 1
fi

# 确保 wrapper 目录存在
mkdir -p "$WRAPPER_DIR"

# 写 wrapper
cat > "$WRAPPER_PATH" <<'WRAPPER_EOF'
#!/usr/bin/env bash
# Hermes wrapper —— Hermes Agent 通过 Nix 管理,装在 /nix/store/-hermes-agent-env/bin/hermes。
# nix store path 是 hash 化的,会随 nix profile update 变化,所以这里探测最新的
# hermes-agent-env 路径并 exec 它。NIX profile 不在 PATH 中,所以需要这个 wrapper。
unset PYTHONPATH
unset PYTHONHOME
HERMES_BIN="$(ls -t /nix/store/*-hermes-agent-env/bin/hermes 2>/dev/null | head -1)"
if [ -z "$HERMES_BIN" ] || [ ! -x "$HERMES_BIN" ]; then
  echo "hermes: 找不到 /nix/store/*-hermes-agent-env/bin/hermes" >&2
  echo "  提示: hermes 是 Nix 管理的,运行 'nix profile list' 查看当前 profile" >&2
  exit 127
fi
exec "$HERMES_BIN" "$@"
WRAPPER_EOF

chmod +x "$WRAPPER_PATH"

# 验证
echo "Wrapper 已安装: $WRAPPER_PATH"
echo ""
echo "验证 1 — which hermes:"
if command -v hermes >/dev/null 2>&1; then
  command -v hermes
else
  echo "  WARN: hermes 不在 PATH(可能 ~/.local/bin 不在当前 shell 的 PATH)"
  echo "  修法: export PATH=\"$WRAPPER_DIR:\$PATH\" 加进 ~/.bashrc"
fi

echo ""
echo "验证 2 — hermes --version:"
if "$WRAPPER_PATH" --version 2>&1 | head -5; then
  echo "  OK"
else
  echo "  FAIL: wrapper 安装了但执行报错,见上方 stderr"
  exit 1
fi

echo ""
echo "验证 3 — wrapper 探测到的真实 hermes 路径:"
echo "  $HERMES_BIN"
echo "  (wrapper 运行时也会再探测一次,见 wrapper 内容)"