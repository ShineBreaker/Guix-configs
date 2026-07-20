# Hermes Pi 式部署(editable-checkout, Guix)

> 2026-07-20 起,本用户环境的 Hermes 已从 Nix 迁移到 Pi 式 editable-checkout。
> `hermes-install-layout` 的 Nix 探测路径(`/nix/store/*-hermes-agent-env`)已不再使用
> (hermes.nix 删除 + flake.nix 去掉 hermes-agent input + flake.lock 清孤立节点)。
> 本文件是迁移后的权威部署说明,可直接 copy-modify。

## 关键事实
- **Python 用 uv 自管**(`uv python install 3.11`,对齐上游 install.sh 的
  `PYTHON_VERSION`),不用 Guix 系统 python。Guix python 在 `~/.guix-home/profile`
  下,`blue home` 升级或 `guix gc` 换掉 store 路径后 venv 解释器软链即失效 →
  整库 module 找不到。uv 自管 python 落在 `~/.local/share/uv/python/<版本>/`,
  路径稳定不被 gc(本机经 `/lib64/ld-linux-x86-64.so.2` → nix-ld 运行,已实测)。
- **依赖走 `uv sync --extra all --locked`**(上游 Tier 0,uv.lock 哈希校验);
  失败降级 `uv pip install -e '.[all]'`,最后兜底基础安装。
- editable install 下,`skills/ plugins/ locales/ web_dist` 从 **checkout 目录**
  自动解析,**不需设 `HERMES_BUNDLED_*`** 环境变量(那是 nix sealed-store 路径
  才需要的复杂物)。
- **Electron desktop 已救活**:`hermes-desktop` wrapper 用 `guix shell
  --emulate-fhs` 容器跑 build 出的 Electron 二进制(含 GPU 硬件渲染),
  详见 `desktop-fhs-rescue.md`。TUI(`hermes`)与 desktop 并存。
- 升级: 改 `hermes-version` 的 `tag=` + 跑 `hermes-update`。
  **更新后必须重启 TUI/gateway/desktop**——常驻 gateway 进程内存里持有旧
  模块路径(checkout 一动,`mcp_tool.__file__` 推导的 watchdog 路径即失效,
  MCP server 全报 "can't open file ... No such file or directory")。
  hermes-update 会先 graceful stop gateway,但已开的 TUI 会话/desktop 要手动重开。

## 目录结构
- 启动脚本: `dotfiles/mutable/hermes/.local/bin/{hermes, hermes-update, hermes-version, hermes-desktop, hermes-desktop-manifest.scm}`
  - 由 `blue stow hermes` 部署到 `~/.local/bin/`(GNU Stow 直链,改源即生效)
- runtime(不进仓库, gitignore): `$HERMES_HOME/hermes-agent/`(checkout 直接在
  **顶层**,无 `checkout/` 子层——desktop 壳 `isHermesSourceRoot()` 要求
  `hermes_cli/main.py` 在 `ACTIVE_HERMES_ROOT` 直接下级)+ `venv/` 内嵌
- `HERMES_HOME`: 直接读系统变量(用户已在系统设置 = `$XDG_DATA_HOME/hermes`),
  fallback 仅保险

## `hermes`(wrapper)
```bash
#!/usr/bin/env bash
set -euo pipefail
: "${HERMES_HOME:=${XDG_DATA_HOME:-$HOME/.local/share}/hermes}"
export HERMES_HOME
HERMES_RUNTIME="${HERMES_HOME}/hermes-agent"
HERMES_BIN="${HERMES_RUNTIME}/venv/bin/hermes"
if [[ ! -x "${HERMES_BIN}" ]]; then
  _up="$(dirname "$(readlink -f "$0")")/hermes-update"
  if [[ -x "${_up}" ]]; then
    echo "Hermes 未安装,执行首次安装..." >&2
    "${_up}" || { echo "安装失败" >&2; exit 1; }
  else
    echo "hermes-update 未找到" >&2; exit 1
  fi
fi
# 清掉继承的 PYTHONPATH/PYTHONHOME,防 Guix Python 污染 venv 模块解析
unset PYTHONPATH
unset PYTHONHOME
exec "${HERMES_BIN}" "$@"
```

## `hermes-update`(安装/升级,对齐上游 install.sh 安装模型)
```bash
#!/usr/bin/env bash
set -euo pipefail
REPO_URL="https://github.com/NousResearch/hermes-agent.git"
PYTHON_VERSION="3.11"   # 与上游 install.sh 一致
: "${HERMES_HOME:=${XDG_DATA_HOME:-$HOME/.local/share}/hermes}"
HERMES_RUNTIME="${HERMES_HOME}/hermes-agent"
CHECKOUT="${HERMES_RUNTIME}"          # checkout 直接在顶层
VENV="${HERMES_RUNTIME}/venv"
VERSION_FILE="$(dirname "$(readlink -f "$0")")/hermes-version"
TAG="main"
[[ -f "$VERSION_FILE" ]] && TAG="$(grep -E '^tag=' "$VERSION_FILE" | head -1 | cut -d= -f2-)"
command -v uv >/dev/null 2>&1 || { echo "uv 未安装" >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "git 未安装" >&2; exit 1; }

# 停旧 gateway(布局/venv 变动后旧进程持失效模块路径,MCP 会全挂)
[[ -x "${VENV}/bin/hermes" ]] && "${VENV}/bin/hermes" gateway stop >/dev/null 2>&1 || true

if [[ ! -d "${CHECKOUT}/.git" ]]; then
  mkdir -p "${HERMES_RUNTIME}"
  git clone --depth 1 --branch "${TAG}" "${REPO_URL}" "${CHECKOUT}"
else
  git -C "${CHECKOUT}" fetch --depth 1 origin "${TAG}" || git -C "${CHECKOUT}" fetch origin "${TAG}"
  git -C "${CHECKOUT}" checkout -f "${TAG}" 2>/dev/null || git -C "${CHECKOUT}" checkout -f "origin/${TAG}" 2>/dev/null || true
  git -C "${CHECKOUT}" clean -fdq 2>/dev/null || true
fi

# uv 自管 python(幂等);venv 缺失或解释器非 uv 管理路径时才重建
uv python install "${PYTHON_VERSION}"
_py_real="$(readlink -f "${VENV}/bin/python" 2>/dev/null || true)"
if [[ ! -x "${VENV}/bin/python" ]] || [[ "${_py_real}" != *"uv/python"* ]]; then
  rm -rf "${VENV}"
  uv venv "${VENV}" --python "${PYTHON_VERSION}"
fi
export UV_PYTHON="${VENV}/bin/python" VIRTUAL_ENV="${VENV}"   # 钉死,防继承环境污染

# 分层安装: Tier 0 uv sync --locked(哈希校验) → Tier 1 .[all] → Tier 2 基础
cd "${CHECKOUT}"
if [[ -f uv.lock ]] && UV_PROJECT_ENVIRONMENT="${VENV}" uv sync --extra all --locked; then
  :
elif ! uv pip install -e "${CHECKOUT}[all]"; then
  uv pip install -e "${CHECKOUT}"
fi
"${VENV}/bin/hermes" --version
```
(完整版含 bootstrap-complete 标记写入与重启提示,见仓库
`dotfiles/mutable/hermes/.local/bin/hermes-update`。)

## `hermes-version`(pin)
```
# tag 对应 hermes-agent 仓库 branch 或 release tag
# 锁定 v2026.7.7.2 (= Python 包 0.18.2, 已 POC + 实装验证)
tag=v2026.7.7.2
```

## 踩坑(迁移实战)
- **venv 千万别用 Guix 系统 python**:`uv venv --python python3.12` 会解析到
  `~/.guix-home/profile/bin/python3.12`,profile 一更新 python,venv 解释器软链
  失效 → 全部 module 找不到。用 `uv python install 3.11` + `uv venv --python 3.11`
  (uv 自管,路径稳定)。这是"经常报找不到 module"的结构根因。
- **更新后旧进程持 stale 模块路径**:TUI 是 client + 常驻 gateway 架构,
  `mcp_tool.py` 用 `__file__` 推导 MCP watchdog 脚本路径;checkout 布局变动后
  旧 gateway 仍指向旧路径 → MCP 全挂(日志 `can't open file .../checkout/tools/
  mcp_stdio_watchdog.py`)。hermes-update 先 `hermes gateway stop`,用户再重开
  TUI/desktop。新进程路径推导自动正确。
- `write_file` 不赋 +x → 源文件 `-rw-------`,stow 后软链不可执行。必须 `chmod +x` 源。
- hermes 包带 `.stow-folding` 时,stow 会把整个 `.local/bin` 折叠成软链指向源,
  与其他包(agenote/pi/appimage-run)的单文件软链冲突 → **删 `.stow-folding`** 走默认 no-folding。
- `blue stow hermes` 报 `cannot stow ... over existing target ... since neither a link nor a directory`
  → 目标 `~/.local/bin/hermes` 是旧手动普通文件,先 `rm -f` 再 stow。
- 后台进程非登录 shell,`~/.local/bin` 不在 PATH → 后台用绝对路径调用 `hermes-update`。
- 删 `flake.nix` 的 hermes-agent input 后,手动用 python `json` 手术清 `flake.lock`
  孤立节点 + 反向引用(否则下次 nix 命令去 fetch 已删 input 报错)。
