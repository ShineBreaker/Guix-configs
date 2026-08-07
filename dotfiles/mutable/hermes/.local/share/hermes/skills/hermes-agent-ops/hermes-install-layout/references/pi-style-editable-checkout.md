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
- 升级: 直接跑 `hermes-update`(委托官方 `hermes update`,跟 main;透传参数如
  `--branch NAME` / `--check` / `--backup` 等)。**放弃 pin-tag 模型**(不再有
  `hermes-version` 文件)。更新后 herd 管理的 `hermes-backend` / `hermes-gateway`
  会被 `hermes-update` 自动 restart 加载新代码,但**已开的 TUI 会话/desktop 窗口
  持旧代码路径,需手动重开**——常驻 gateway 进程内存里持有旧模块路径(checkout
  一动,`mcp_tool.__file__` 推导的 watchdog 路径即失效,MCP server 全报 "can't
  open file ... No such file or directory")。

## 目录结构
- 启动脚本: `dotfiles/mutable/hermes/.local/bin/{hermes, hermes-update, hermes-desktop, hermes-desktop-manifest.scm}`
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

## `hermes-update`(安装/升级,委托官方 `hermes update`,跟 main)
```bash
#!/usr/bin/env bash
set -euo pipefail
REPO_URL="https://github.com/NousResearch/hermes-agent.git"
PYTHON_VERSION="3.11"
: "${HERMES_HOME:=${XDG_DATA_HOME:-$HOME/.local/share}/hermes}"
HERMES_RUNTIME="${HERMES_HOME}/hermes-agent"
CHECKOUT="${HERMES_RUNTIME}"
VENV="${HERMES_RUNTIME}/venv"
HERMES_HERD_SERVICES=(hermes-backend hermes-gateway)
command -v uv >/dev/null 2>&1 || { echo "uv 未安装" >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "git 未安装" >&2; exit 1; }

# 【路径 A: 首次安装】官方 update 在 checkout 不存在时报 "Not a git repository",
# 故首装由本脚本完成: clone main + uv 自管 python + 分层装依赖 + 写 bootstrap 标记。
if [[ ! -d "${CHECKOUT}/.git" ]]; then
  git clone --depth 1 --branch main "${REPO_URL}" "${CHECKOUT}"
  uv python install "${PYTHON_VERSION}"
  uv venv "${VENV}" --python "${PYTHON_VERSION}"
  export UV_PYTHON="${VENV}/bin/python" VIRTUAL_ENV="${VENV}"
  cd "${CHECKOUT}"
  if [[ -f uv.lock ]] && UV_PROJECT_ENVIRONMENT="${VENV}" uv sync --extra all --locked; then
    :  # Tier 0: 走 uv.lock 哈希校验
  elif ! uv pip install -e "${CHECKOUT}[all]"; then
    uv pip install -e "${CHECKOUT}"   # Tier 2 兜底
  fi
  # 写 .hermes-bootstrap-complete(desktop 壳靠它跳过 GitHub bootstrap)
  ...
  exit 0
fi

# 【路径 B: 已装 → 委托官方 update】
# B.1 停旧 gateway(官方不管;旧进程持失效模块路径,MCP 全挂)
[[ -x "${VENV}/bin/hermes" ]] && "${VENV}/bin/hermes" gateway stop >/dev/null 2>&1 || true

# B.2 uv 隔离: 预置 $HERMES_HOME/bin/uv → 系统 uv 的 symlink,阻止官方 ensure_uv
#     从 astral.sh 下载独立 managed uv(官方只查该路径是否存在,不查 PATH)
_uv_managed="${HERMES_HOME}/bin/uv"
[[ -n "$(command -v uv)" && ! -e "${_uv_managed}" ]] && ln -s "$(command -v uv)" "${_uv_managed}"

# B.3 委托官方 update(透传所有参数: --check / --branch NAME / --backup / --yes ...)
# 不用 exec: 成功后需 herd restart 收尾。官方接管 fetch→pull(syntax guard+rollback)
# →依赖重装→config 迁移→skills sync(已被 .no-bundled-skills 跳过)→desktop build(hash stamp 跳过)
"${VENV}/bin/hermes" update "$@"

# B.4 herd restart(让常驻 backend/gateway 加载新代码; --check 时跳过)
for _svc in "${HERMES_HERD_SERVICES[@]}"; do herd restart "${_svc}"; done
```
(完整版含退出码处理 / --check 跳过重启 / 首装 bootstrap 标记写入,见仓库
`dotfiles/mutable/hermes/.local/bin/hermes-update`。)

> **为什么委托官方 update**: 官方 update 在 editable 安装下能正确定位 checkout
> (`PROJECT_ROOT = Path(__file__).parent.parent` 直指 checkout 源码),判为 `git`
> 安装走标准 `git pull` + 依赖重装路径。它自带我们旧脚本缺的能力: pre-update
> backup、post-pull syntax guard + 自动 rollback、venv 健康检查 + 修复、config
> 迁移、cron jobs 安全网。我们只补它做不了的: 首次安装 + 停旧 gateway + uv 隔离
> + herd restart。

## 验证 `hermes-update` 是否真的跑过(取证指纹)

> **2026-08-04 模型变更**: 委托官方 `hermes update` 后,`.hermes-bootstrap-complete`
> 只在**首次安装**时由本脚本写一次(官方 update 不碰它)。它不再能证明"最近一次
> update 跑过",只能证明"首装完成"。要确认最近 update,看 git log + herd 服务状态。

诊断 hermes 行为不符预期(命令找不到、版本不是预期、build 错误地指向老源)时:

**1. 确认首装标记存在(desktop 壳靠它跳过 GitHub bootstrap)**:
```bash
cat "$HERMES_HOME/hermes-agent/.hermes-bootstrap-complete"
# pinnedCommit 是首装时的 HEAD(后续 update 不刷新此字段)
```

**2. 确认最近 update 真的拉了新代码**(委托官方后,看 git 而非标记):
```bash
git -C "$HERMES_HOME/hermes-agent" log --oneline -3          # HEAD 是否前进
git -C "$HERMES_HOME/hermes-agent" log -1 --format='%ci'     # 最近 commit 时间
herd status hermes-backend                                    # 重启时间应晚于该 commit
```

**交叉校验**:

| 信号 | 期望 | 含义 |
|---|---|---|
| `HEAD` ↔ `origin/main` | `git rev-parse HEAD` == `git rev-parse origin/main` | 本地已追平远端 |
| `venv/bin/python` ↔ `~/.local/share/uv/python/...` | `readlink -f` 指向 uv 自管 python | venv 是 uv 自管而非 Guix |
| herd 服务重启时间 ↔ HEAD commit 时间 | 服务 `启动于` 晚于 commit 时间 | hermes-update 的 B.4 herd restart 跑过了 |

`desktop.json` / `desktop-build-stamp.json` 是 **electron 壳独立构建**的 timestamp,
官方 update 在 `apps/desktop/` 源变了时会触发 `desktop --build-only`(content-hash
stamp 不匹配),源没变则秒过。`builtAt` 比 HEAD commit 早是正常情况(用户先 update
源码,desktop build 由 stamp 决定是否重跑);反向才是 **desktop 没重 build 就在跑**
的征兆——源码最新但壳仍持旧模块路径,典型症状 electron UI 找不到某个新版 hermes
CLI 暴露的命令。要修:`hermes desktop --build-only`,然后重开 `hermes-desktop` 进程。

## 写 Hermes config 的两条规则(踩坑 2026-07-21)

**1. `~/.local/share/hermes/config.yaml` 是受保护的**——Hermes 的 `patch` /
`write_file` 工具会直接拒绝,报 *Refusing to write to Hermes config file: ...
Agent cannot modify security-sensitive configuration*. 这是 **故意设计**,不要
绕(改 hermes 源码注释掉守护 → 下次 update 被回滚)。正确路径:

```bash
hermes config set <key> <value>     # 写入(未知 key 会告警,但仍写入)
hermes config get <key>             # 回读校验
hermes config unset <key>           # 移除(整个条目消失,不是清值)
```

**2. `cli-config.yaml.example` 的缩进是误导**——example 里 `busy_input_mode`
缩进两格,看上去属于上一个 `agent:` 块,实际**它属于 `display:`** 块(后者
在 example 里排在 `agent:` 之后、跨很多页)。`hermes config set agent.busy_input_mode steer`
会被 `hermes config` 自己的 schema 校验拒绝,提示 *"not a recognized config key
— Did you mean: agent.image_input_mode"*——这是**正确键路径**的最权威信号,
比对照 yaml 缩进可靠。

要确认任意 key 的真实归属,直接在仓库 `hermes-agent` clone 里跑:

```bash
grep -rn 'save_config_value\\|"\\w*\\.\\w*"\\s*,' hermes_cli/cli_commands_mixin.py \
  | grep <key候选词>
```

源码里 `save_config_value("display.busy_input_mode", arg)` 就是写入位置,
完整路径(`display.busy_input_mode`)由这里确定,**比看 yaml example 缩进靠谱**。

三步稳健流程:

```bash
# 1. 用 hermes config get 测一把,看是不是已经被认
hermes config get <candidate_key>                    # 已设过 → 回值;未设 → "Config key not set"

# 2. 写入,观察 schema 校验输出
hermes config set <candidate_key> <value>            # ← 警示行即权威键路径提示

# 3. 回读 + 直接读 yaml,确认写入位置正确(避免把孤儿 key 写到错误块下)
hermes config get <candidate_key>
grep -n "^  <candidate_key_short>:" ~/.local/share/hermes/config.yaml
```

如果误写了孤儿 key(例:`agent.busy_input_mode`),`hermes config unset` 干净
移除该行(不留空键);yaml 文件结构不被破坏。

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
