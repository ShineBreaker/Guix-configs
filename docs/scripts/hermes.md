<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# hermes — Pi 式 editable-checkout 启动与 update / desktop 增强子命令

源码 `dotfiles/mutable/agents/hermes/.local/bin/{hermes,hermes-acp}` 与 `.local/libexec/{hermes-lib.sh,hermes-update,hermes-desktop}` · 部署 `~/.local/bin/hermes`、`~/.local/bin/hermes-acp` 与 `~/.local/libexec/*`（mutable，改源即时生效） · 调用方：终端直接调用；ACP 宿主（Zed 等）按命令名寻址 `hermes-acp`

wrapper 只做注入与分发：布局常量全部来自 `hermes-lib.sh`（`HERMES_HOME` 一处 export），首参把 `update` / `desktop` 分发进 libexec，`hermes-acp` 是一行 `exec hermes acp`。运行时是 editable checkout（`$HERMES_HOME/hermes-agent`），venv 与 bootstrap 产物不进仓库。

## 布局

| 常量                                                | 值                                                                               | 说明                                                                       |
| --------------------------------------------------- | -------------------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| `HERMES_HOME`                                       | `$HERMES_HOME/hermes-agent` 之外即 `${XDG_DATA_HOME:-$HOME/.local/share}/hermes` | **统一 export**，desktop 壳靠它推导 `ACTIVE_HERMES_ROOT`                   |
| `HERMES_RUNTIME` / `HERMES_CHECKOUT`                | `$HERMES_HOME/hermes-agent`                                                      | checkout 直接落顶层不嵌套，是 desktop 壳 `isHermesSourceRoot` 要求的源码根 |
| `HERMES_VENV` / `HERMES_CLI_BIN`                    | `$HERMES_RUNTIME/venv`、`…/venv/bin/hermes`                                      | venv 由 `hermes-update` 生成，不进仓库                                     |
| `HERMES_DESKTOP_RELEASE_DIR` / `HERMES_DESKTOP_BIN` | `$HERMES_CHECKOUT/apps/desktop/release/linux-unpacked` 及其下的 `Hermes`         | electron-builder 产物                                                      |
| `HERMES_MANIFEST`                                   | `$HERMES_HOME/manifest.scm`                                                      | 容器 `--manifest`                                                          |
| `HERMES_DATA_HOME` / `HERMES_HICOLOR_ROOT`          | `$XDG_DATA_HOME` 默认值、`…/icons/hicolor`                                       | 图标路径解析收在 lib                                                       |

`HERMES_HOME` 必须 export：desktop 的 PRESERVE 正则要把它透传进容器，壳的 `main.cjs` 抓不到就 fallback 到默认 `~/.hermes`，容器内便找不到安装。

`hermes-lib.sh` 是三类逻辑的单一真理源：布局常量；XDG data home 与 hicolor 图标路径解析 + `hermes_install_icon_1024`（仓库只给 1024 px 源图，面板请求小尺寸解析失败）；FHS 容器边界配置。约定**只做赋值与函数定义，不设 shell 选项，副作用幂等**。容器边界语义对齐 `appimage-run_lib` 的 `gui-env`/`container` 两份 scheme，但刻意独立维护（部署域不同）。

## hermes 与 hermes-acp

```bash
hermes [args...]    # venv CLI 透传；未安装时先 bootstrap
hermes acp          # ACP 模式（hermes-acp 内部就是 exec hermes acp）
```

- **拦截即覆写**：上游原生也有 `hermes update` 与 `hermes desktop`，首参分发遮蔽为 Guix 增强版；原生行为经 `${HERMES_CLI_BIN} update|desktop` 直调 venv 触达（libexec 内部本就直调 venv，不经本 wrapper，无递归）。
- **首跑 lazy bootstrap**：venv CLI 缺失时调 `hermes-update` 走首次安装，失败即退出而不静默降级。
- **启动前 `unset PYTHONPATH PYTHONHOME`**：防 Guix Python 的环境变量漏进 venv。
- **`hermes-acp` 文件名不可改**：ACP 宿主按命令名寻址 agent（准入规则见 `dotfiles/mutable/AGENTS.md`）。它历史上由 `hermes update` 写入 `~/.local/bin/`（硬编码绝对路径），现已收编进仓库随 stow 部署；若官方 update 流程重写该文件，restow 后须核对软链未被真身覆盖。

## hermes update

```bash
hermes update              # 已装 → 委托官方 update；未装 → 首次安装
hermes update --check      # 官方参数原样透传
hermes update --branch X   # 同上（官方 flag 由 fish 补全列举）
```

设计是**放弃 pin-tag 跟 main**。已安装路径整套委托给官方 `hermes update`，本脚本只补官方做不了的、与 Guix 布局强相关的四件事：

- **首次安装**：官方 update 在 checkout 不存在时报错退出，故自办 `git clone --depth 1 --branch main` → `uv python install 3.11` → `uv venv`（Python 版本须与上游 `install.sh` 的 `PYTHON_VERSION` 一致）→ 分层安装（`uv sync --extra all --locked` 哈希校验，失败降级到 `uv pip install -e .[all]`，再降级到基础 `-e .`）→ 写 bootstrap 标记。必须用 uv 自管 Python：Guix profile 的 python store 路径会被升级/gc 换掉，venv 软链随之失效。
- **更新前停旧 gateway**：旧进程内的模块路径指向更新前 checkout，pull 后必失效；shepherd respawn 出的新实例由收尾统一处理。
- **uv 隔离**：官方 `ensure_uv()` 只查 `$HERMES_HOME/bin/uv` 是否存在，缺了就从 astral.sh 下载独立 uv 偏离 Guix 系统 uv。预置一个指向系统 uv 的 symlink 后，官方 `resolve_uv()` 的 `is_file()` follow symlink 返回真即用系统 uv。
- **更新后恢复 herd 常驻服务**：停服务 → 清官方野实例（`pkill` 官方 update 自己拉起的脱离 shepherd 的进程）→ `herd enable` + `start`。

配套动作：

- **bootstrap 标记**：desktop 壳的 `isBootstrapComplete()` 要求 `${HERMES_RUNTIME}/.hermes-bootstrap-complete` 是 `schemaVersion=1` + `pinnedCommit`（HEAD 前 7 位）+ `pinnedBranch` 的合法 JSON，否则回退去跑官方 `install.sh`。首次安装由本脚本写，官方 update 不碰。
- **hicolor 图标生成**：见 lib 的图标安装（首装走批量尺寸生成，更新走 1024 px 覆盖，幂等）。

## managed-node

desktop build 需要一套 node，但不进 PATH 以免污染 Guix toolchain，单独 provision 到 `$HERMES_HOME/node`。

- **不能依赖官方 `ensure_node`**：它只查 node 版本、不查 npm 版本，而本机的故障正卡在 npm（checkout 里 root `package.json` 的 `engines.npm` 约束很窄，Guix npm 可能落进禁止区间 → backend web build `EBADENGINE` → crash-loop）。
- **provision 方式**：source `${HERMES_RUNTIME}/scripts/lib/node-bootstrap.sh` 后调 `_nb_install_bundled_node`，带 `HERMES_NODE_SKIP_LINKS=1`（不软链进 `~/.local/bin`，避免 shadow Guix toolchain）。
- **幂等**：`$HERMES_HOME/node/bin/node` 可执行即跳过；bootstrap 脚本缺失或调用失败都只告警不中断，让 backend 的 crash-loop 成为可见症状。

## hermes desktop

```bash
hermes desktop               # 容器内启动 Electron 壳
hermes desktop --build-only  # 直调 venv 原生子命令打 release/linux-unpacked
```

Pi 式 editable-checkout 下纯 checkout + uv 安装不含 build 过的 Electron 二进制，故先用 `hermes desktop --build-only` 打 release（首跑 npm install + electron-builder，几分钟；之后 `node_modules` 留在 checkout 内，重 build 很快），再用 `guix shell --container --emulate-fhs --network` 补 FHS 系统库跑起来。

流程顺序链不可换：**session init → GUI 解析 → share 旗标**——`hermes_session_env_init` 提供 `RT_DIR` 与 `WAYLAND_DISPLAY` 默认值（不硬编码 `wayland-0`，否则 expose 不存在的 socket），`hermes_gui_env_resolve` 依赖它定 Ozone 后端并解析主题与输入法，`hermes_build_share_flags` 再依赖前两者拼 `--share/--expose`。

容器最终命令：`guix shell --container --emulate-fhs --network --manifest=$HERMES_MANIFEST --preserve="$HERMES_PRESERVE_RE" <share flags> --share=$HERMES_DESKTOP_RELEASE_DIR=/appimage-root -- bash -c "$EXEC_STRING" bash "$@"`。

**Remote gateway 探测**（容器只为 GUI 服务，agent 跑在宿主）：`curl -sf -m 2 http://127.0.0.1:9119/api/status` 探测宿主 backend，可达则从首页抓 `__HERMES_SESSION_TOKEN__` 并导出 `HERMES_DESKTOP_REMOTE_URL` / `HERMES_DESKTOP_REMOTE_TOKEN`（token 每次重启重生成，启动时动态抓取不写死）；不可达或抓不到 token 则告警并回退容器内残缺 serve。

## 容器内执行

`EXEC_STRING` 内先设 `APPDIR` 与 `LD_LIBRARY_PATH`，再 `exec /appimage-root/Hermes`。各旗标的存在理由：

| 旗标                                                          | 理由                                                                                                                                       |
| ------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| `--no-sandbox --disable-gpu-sandbox`                          | 嵌套在 guix shell 容器里，Chromium 沙箱起不来（渲染进程 crash loop），必需                                                                 |
| `--ozone-platform="${ELECTRON_OZONE_PLATFORM_HINT:-wayland}"` | 与宿主解析出的 Ozone 后端一致                                                                                                              |
| `--enable-wayland-ime`                                        | Wayland text-input 协议，fcitx5 的 `libwaylandim.so` 靠它与 Chromium 通信，Wayland 下必须显式开                                            |
| `--gtk-version=3`                                             | GTK3 初始化（原生文件对话框与主题集成）                                                                                                    |
| `--ignore-gpu-blocklist`                                      | 容器内 GPU 探测不全，Chromium 可能回退软件渲染；崩时可 `LIBGL_ALWAYS_SOFTWARE=1 hermes desktop` 临时回退（该变量已在 PRESERVE 正则里透传） |
| `--disable-dev-shm-usage`                                     | 容器内 `/dev/shm` 太小，Chromium 默认会因此崩                                                                                              |

d-Bus 优先复用宿主 session bus（`DBUS_SESSION_BUS_ADDRESS` 已 preserve + RT_DIR 已 expose），不可达才 `dbus-launch` 起新的——dconf/GSettings 暗色偏好与 fcitx5 D-Bus frontend 依赖它。

## --preserve 透传理由

白名单按语义分组在 `hermes-lib.sh` 的 `_HERMES_PRESERVE_VARS`，拼成正则 `^(...)$`；拼接顺序即 alternation 顺序，新增变量加在对应组末尾。

| 组                     | 变量                                                                                                     | 理由                                                                      |
| ---------------------- | -------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------- |
| 会话/显示基础          | `DISPLAY` `WAYLAND_DISPLAY` `XDG_RUNTIME_DIR` `XDG_SESSION_TYPE` `XAUTHORITY` `DBUS_SESSION_BUS_ADDRESS` | 容器内连得上显示服务与 session bus                                        |
| 平台后端选择           | `QT_QPA_PLATFORM` `ELECTRON_OZONE_PLATFORM_HINT`                                                         | 与宿主 GUI 环境解析结果一致                                               |
| PulseAudio             | `PULSE_SERVER` `PULSE_COOKIE`                                                                            | 音频经宿主 PulseAudio                                                     |
| 语言环境               | `LANG` `LC_[A-Z]+`                                                                                       | 正则前缀模式，一并透传全部 locale                                         |
| 动态库 / Node / 软渲染 | `LD_LIBRARY_PATH` `NODE_OPTIONS` `LIBGL_ALWAYS_SOFTWARE`                                                 | 软件渲染回退靠 `LIBGL_ALWAYS_SOFTWARE` 进容器                             |
| Agent 根               | `HERMES_HOME`                                                                                            | desktop 壳靠它推导 `ACTIVE_HERMES_ROOT`，不透传会 fallback 到 `~/.hermes` |
| Remote gateway         | `HERMES_DESKTOP_REMOTE_URL` `HERMES_DESKTOP_REMOTE_TOKEN`                                                | 连宿主 hermes-backend（9119）                                             |
| cua-driver             | `CUA_DRIVER_RS_ENABLE_WAYLAND`                                                                           | 原生 Wayland 抓屏开关，无它 Wayland 会话抓屏必炸                          |
| fontconfig             | `FONTCONFIG_FILE` `FONTCONFIG_PATH` `FONTCONFIG_CACHE_DIR`                                               | 容器复用宿主 fontconfig 配置                                              |
| 宿主搜索路径           | `XDG_DATA_DIRS` `XDG_CONFIG_HOME`                                                                        | 容器内 GTK 复用宿主主题/图标/光标搜索路径                                 |
| 输入法                 | `GTK_IM_MODULE` `QT_IM_MODULE` `XMODIFIERS`                                                              | fcitx5 透传                                                               |
| 光标                   | `XCURSOR_PATH` `XCURSOR_THEME`                                                                           | 光标主题搜索路径                                                          |
| GTK                    | `GTK_THEME` `GTK_IM_MODULE_DIR` `GDK_BACKEND`                                                            | 主题、immodules 目录、GDK 后端                                            |

## 容器边界

`hermes_build_share_flags` 生成的 `--share`/`--expose` 旗标按存在性条件追加，错了都是「窗口起不来 / 字体怪 / 软渲染」级别的坑。

| 旗标                                                    | 条件           | 理由                                                                  |
| ------------------------------------------------------- | -------------- | --------------------------------------------------------------------- |
| `--share=/tmp`、`--share=$HOME`                         | 无条件         | 临时目录与家目录                                                      |
| `--expose=$RT_DIR`、`--expose=$RT_DIR/$WAYLAND_DISPLAY` | 无条件         | Wayland 与 dbus socket 目录、真实 compositor socket                   |
| `--expose=$RT_DIR/pulse/native`                         | 该 socket 存在 | PulseAudio                                                            |
| `--expose=/run/current-system/profile/share/fonts`      | 存在           | 字体                                                                  |
| `--share=/dev/dri`                                      | 存在           | **必须读写**：GPU 进程要对 `renderD128` 发 ioctl，只读 bind 会 SIGILL |
| `--expose=/sys`                                         | 存在           | 只读：mesa `drmGetDevice` 要读 PCI 信息，缺了回退 llvmpipe 软渲染     |
| `--expose=/gnu/store`                                   | 存在           | 只读：venv python 软链指向 store，不挂则运行时解析失败                |
| `--expose=/etc/machine-id`                              | 存在           | FHS 容器内 `/etc` 只读，`dbus-uuidgen` 写不进，直接 expose 宿主的     |
| `--share=/tmp/.X11-unix`                                | `DISPLAY` 非空 | X11 fallback                                                          |
| `--expose=/run/current-system/profile/share`            | 存在           | XDG data 目录本体                                                     |

函数末尾显式 `return 0`：最后一条 `[[ -d ]]` 为假时函数会带 1 返回，`set -e` 下调用方误退。

## 实现与约束

- **uv symlink 预置必须先于一切官方调用**：官方 clone/venv 阶段就可能查 uv。
- **herd 顺序固定 backend → gateway**（gateway 依赖 backend），停服时同序。
- **不用 `exec` 委托官方 update**：成功后还要跑 herd 收尾，委托是普通调用并保留退出码。收尾判据是「checkout 的 HEAD 是否变了」而非官方退出码——updater 的收尾步骤自己可能因进程内 `sys.modules` 还是旧代码而 `ImportError` 崩，此时退出码非 0 但代码已更新，继续收尾；HEAD 未变才是真失败。`--check` 是只读探测，不重启服务。
- **`${HERMES_CLI_BIN} desktop --build-only` 必须直调 venv**：走 `bin/hermes` 会分发回 `hermes-desktop` 造成死循环。
- **`curl | grep | sed` 管道须 `|| true`**：`pipefail` 下 token 缺失（后端可达但页面无 token）会让整个命令替换返回非零、脚本中途退出，到不了 fallback 告警分支。

## 排障

| 现象                                 | 原因                                             | 处理                                                                      |
| ------------------------------------ | ------------------------------------------------ | ------------------------------------------------------------------------- |
| 容器内找不到安装（回退 `~/.hermes`） | `HERMES_HOME` 未 export 透传                     | 确认 lib 的 export 生效，不要手动覆盖                                     |
| ACP 宿主报 agent 找不到              | `hermes-acp` 软链被上游 update 真身覆盖          | restow 后核对软链（`stow -R agents/hermes`）                              |
| backend crash-loop、`EBADENGINE`     | managed node 未 provision，Guix npm 落进禁止区间 | 见「managed-node」，手动跑 node-bootstrap                                 |
| 更新后 MCP 全挂                      | 旧 gateway 进程持失效模块路径                    | `herd restart hermes-gateway`，或再跑一次 `hermes update` 触发收尾        |
| `$HERMES_HOME/bin/uv` 变成真二进制   | 预置 symlink 被官方替换                          | 重跑 `hermes update` 恢复 symlink                                         |
| 窗口起不来、渲染 crash               | 容器沙箱或 GPU 探测                              | 确认 `--no-sandbox` 等旗标在；试 `LIBGL_ALWAYS_SOFTWARE=1 hermes desktop` |
| 中文输入无效                         | 缺 `--enable-wayland-ime`                        | 检查 `EXEC_STRING`                                                        |
| 远程模式退回本地                     | token 提取失败                                   | 查 backend 是否可达、页面是否含 session token                             |
