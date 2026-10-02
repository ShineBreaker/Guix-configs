<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# dsh — DeepSeek Harness CLI wrapper 与 update / web / tui 增强子命令

源码 `dotfiles/mutable/agents/dsh/.local/bin/dsh` 与 `.local/libexec/{dsh-web,dsh-update,dsh-tui}` · 部署 `~/.local/bin/dsh`（mutable，改源即时生效） · 调用方：终端直接调用；桌面入口经 `dsh web` 拉起；`update|web|tui` 由 wrapper 首参分发进 libexec

wrapper 只做三件事：注入 `DSH_HOME`/`AGENTS_ROOT`、按首参分发三个增强子命令、跑完 CLI 后做断链自愈。真正的服务启动、升级与 TUI 启动都在同包 `libexec/` 里，全族共用一套断链自愈与 lockfile 回源。

## 布局

| 路径 | 说明 |
| --- | --- |
| `$AGENTS_ROOT/dsh`（默认 `~/.local/share/agents/dsh`） | CLI 本体安装树，源托管 `package.json`、`pnpm-workspace.yaml` 与 lockfile 副本，`node_modules` 是部署侧运行时产物 |
| `$DSH_HOME`（默认 `~/.local/share/dsh`） | 配置与运行时状态：`profiles/`（web、dsh-tui）、`sessions/`、`.credentials.yaml` |
| `libexec/dsh-web`、`dsh-update`、`dsh-tui` | 三个增强子命令实体，`exec` 分发不残留在进程树上 |

`DSH_HOME` 与 `AGENTS_ROOT` 由 wrapper 注入——niri 会话不经 fish `conf.d`，桌面入口拿不到 export。安装根与配置根分层：`DSH_HOME` 不放 CLI 本体。

## dsh（wrapper）

```bash
dsh [args...]        # CLI 透传（含 dsh plugin 等原生子命令）
dsh --install        # 无人值守安装 CLI（在 $AGENTS_ROOT/dsh 里 pnpm install）
dsh update|web|tui   # Guix 增强子命令 → libexec/{dsh-update,dsh-web,dsh-tui}
```

- **拦截即覆写**：上游原生也有 `dsh update` 与 `dsh web`，首参分发把这两个名字遮蔽为 Guix 增强版。原生行为经直调 CLI 本体触达：`$AGENTS_ROOT/dsh/node_modules/.bin/dsh update|web`（libexec 内部本就直调 CLI 本体，无递归）。`tui` 是本包新增子命令，上游无同名命令，不涉及覆写。
- **分发必须排在 CLI 缺失检查之前**：`dsh-update` 自身能装 CLI，`dsh-web` 的缺 CLI 报错也更友好，先检查会拦掉这两条自举路径。
- **CLI 缺失行为分叉**：交互终端问一句再装（`[y/N]`，拒绝则退出码 130）；非交互只提示 `dsh --install` 并以 127 退出，不静默联网。
- **`dsh plugin` 提前单独放行**：直调 CLI 本体取回退出码，末尾统一跑一次断链自愈（该子命令正是 `package.json` 原子写的触发源）。
- **断链自愈 `_relink_profile`**（全族唯一一份定义）：dsh 的原子写（临时文件 + rename）会把 stow 软链换成实体文件——plugin bundles 写入、UI 设置编辑 `cordis.patch.yml`、pnpm 覆写 manifest 都在这条路上。自愈覆盖**两处 pnpm 项目**：CLI 安装树（`$AGENTS_ROOT/dsh`）与 web profile（`$DSH_HOME/profiles/web`），各按 `package.json`、`pnpm-workspace.yaml`、`cordis.patch.yml` 三个文件检测非 symlink → 内容写回仓库源再 `ln -sfn` 重建软链；`pnpm-lock.yaml` 只回拷内容（pnpm 的 Rust 端拒写软链 lockfile，部署侧必须真实文件）。源目录从 `$0` 反推而非从部署侧软链推导——pnpm 覆写后链接随时不在。时机：每次 CLI 调用结束、`dsh web` 起服务前、`dsh update` 每次 pnpm 操作后。
- **安装树的 lockfile 回源**：`install_cli` 成功后单独拷回 `pnpm-lock.yaml`。安装树是手动升级路径（改 `package.json` 后裸跑 `pnpm install`）的回源盲区，不过 `dsh update` 的 sync，靠自愈兜底。

## dsh web

```bash
dsh web                # 起服务（默认带远程信任）并开本机 chromium --app 窗口
dsh web --reauth       # 强制重启服务换新 token（cookie 失效时用）
dsh web --remote-url   # 只打印手机首次握手的 https://<尾网主机名>/?token=... URL
dsh web --lan-off      # 本次不带 --trusted-host（`DSH_TS_HOST=` 的显式等价）
```

| 环境变量 | 默认 | 说明 |
| --- | --- | --- |
| `DSH_WEB_PORT` | `3080` | 监听端口，cookie 的 authority 随之变 |
| `DSH_WEB_LOG` | `$XDG_STATE_HOME/dsh/web.log` | 服务 stdout，含一次性 token URL 与 launch token 行 |
| `DSH_BIN` | `$AGENTS_ROOT/dsh/node_modules/.bin/dsh` | 起服务的 CLI 本体，**必须指本体** |
| `DSH_TS_HOST` | 尾网主机名 | 空串关闭远程信任 |
| `DSH_HOME` | `~/.local/share/dsh` | 同 wrapper |

- **`DSH_BIN` 默认必须指 CLI 本体**：公共入口会把 `web` 分发回本脚本，指公共入口即递归；测试覆盖时同理。
- **实例永远带 `--trusted-host` 启动**：远程流量经 tailscale serve 反代进 loopback，Host 头是尾网主机名，非 loopback 请求必须命中该白名单；`DSH_TS_HOST=` 空串即关闭。已在监听但不带该参数的实例会被自动重启（判据是 `/proc/<pid>/cmdline` 里含 `--trusted-host <host>`）。
- **launch token 按进程随机，一个 token 只换一次 cookie**：token 从日志的 `dsh web: http://127.0.0.1:<port>/?token=...` 行解析，只对本脚本亲自起的实例有效；cookie 由 `$DSH_HOME/.credentials.yaml` 里的持久化密钥签名，跨服务重启有效，之后直接开干净 URL。`--reauth` 终止旧实例换新。
- **窗口 app_id 与 `dsh.desktop` 的 `StartupWMClass` 严格成对绑定**：Wayland 下窗口 ID 只由 profile 目录名决定，脚本定死 `--profile-directory=dsh`，改名须两处同改。该 profile 顺带隔离 dsh 的 cookie 与日常浏览。不装 PWA——只传 `--app`/`--no-first-run`/`--no-default-browser-check`，装出来是全屏而非窗口。
- **服务脱离会话**：以 `setsid -w` 起，日志 `umask 077` 重建，同时留有同寿命 pid 供 `kill -0` 早判失败；起不来时 `notify-send` critical 通知让桌面场景可见。`stop_server` 只终止 `/proc/<pid>/cmdline` 含 `@deepseek-ai/dsh` 的监听进程，拒绝杀第三方占端口的进程，最多等 10s。
- **`usage()` 是独立 heredoc**，不得回读自身注释——历史实现用 `sed` 从头注释提取帮助，精简注释即自毁帮助。
- **断链自愈**：起服务前跑同一套 `_relink_profile`（定义见上），dsh web 是长驻服务，UI 改完设置重启时才经过这里。

## dsh update

```bash
dsh update            # 交互确认后更新本体 + web profile 插件
dsh update --check    # 只查差异（退出码 0=已最新，1=有更新），可作 CI 判断
dsh update -y|--yes   # 跳过确认
dsh update --restart  # 完成后后台 `dsh web --reauth`
```

- **插件清单从 `profiles/web/package.json` 的 dependencies 动态读取**（全量保序），本体固定为 `$AGENTS_ROOT/dsh/package.json` 的 `@deepseek-ai/dsh`。依赖分三类处理。
- **npm 包选版不跟 `latest` tag**：dsh 全是 preview 版本，发布者把 latest 停在保守位。按通道稳定性 `latest → next → beta → alpha` 取第一个高于当前的版本，输出里标出来源通道与距冷却期的小时数。
- **`github:<owner>/<repo>#<sha>` 跟上游 HEAD**：用 `git ls-remote` 查 HEAD，commit 变了才列为更新项。**`allowBuilds` key 迁移必须在换 commit 之前**——key 形如 `<pkg>@https://codeload.github.com/<repo>/tar.gz/<commit>`，绑定 commit，不迁则 prepare 不放行。
- **`git+` / `git@` / `file:` / `link:` 只列提醒**：锁定源码没有可比较的上游位标，人工确认后改 spec 并 `pnpm install`。
- **用 `pnpm add` 更新，不手改 `package.json`**：版本号只来自 pnpm 的 registry 解析；命令行 `-E` 加两侧 `pnpm-workspace.yaml` 的 `saveExact: true` 双保险写精确值（pnpm 默认写 `^`）。冷却期内的版本由 pnpm 自动写进 `minimumReleaseAgeExclude`，豁免不用手写。
- **`ERR_PNPM_IGNORED_BUILDS` 在此降级为非致命**：包已装好、只是 build script 未审批时只提示去跑 `pnpm approve-builds`（与 pi 族的「批准后重试」不同）。
- **lockfile 回源**：每次 `pnpm add` 后把部署侧 lockfile 拷回仓库源副本，收尾再对两棵目录树各拉平一次（`package.json`、`pnpm-workspace.yaml`、`cordis.patch.yml` 同步内容并重建软链）。
- **兼容性提醒**：读插件的 `dsh.compatibility.dshReleases`，只在「声明了白名单却不含目标本体版本」时提醒；没有该字段不代表不兼容。
- **更新后须重启 `dsh web`**（host 半边不热载），`--restart` 后台调 `dsh web --reauth`。

## dsh tui

```bash
dsh tui [args...]   # 直 exec profile 内的完整 launcher
```

上游 dsh-tui 的 bin 是双态设计：`$DSH_HOME/profiles/dsh-tui/node_modules/@deepseek-harness-tui/dsh-tui/bin/dsh-tui.js` 那份承载完整逻辑，全局安装的那份只是找到 profile 副本后委托的瘦壳。本脚本跳过瘦壳直 exec 完整副本（`DSH_TUI_BIN` 可覆盖）。launcher 独有子命令只有这一层触达得到（`version` / `doctor` / `safe` / `update` / `--resume`），一包一入口规则下挂靠 `dsh tui` 是唯一合规形态。交互要求真实 TTY。

## 实现与约束

- **分发与兜底统一用 `exec`**：wrapper 不残留在进程树上；`plugin` 分支需取回退出码故用普通调用并在末尾自愈。
- **`dsh update` 的回源映射显式给出**：CLI 安装树与 web profile 分居两棵目录树，部署根与仓库源根须成对传入，否则搬出 `$DSH_HOME` 后会静默跳不回源。
- **回源源目录一律从 `$0` 的 stow 软链反推**，不从部署侧软链推导。
- **`grep | head` 管道必须 `|| true`**：`set -euo pipefail` 下无匹配时 grep 返回 1，曾让 `migrate_allow_builds` 在「无需迁移」的正常场景中途退出，连带 `--restart` 到不了重启路径。

## 排障

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| 窗口打开要求重新登录 | token 已被消耗或换了设备 | `dsh web --reauth` |
| 手机连上但 API 报 403 | 实例没带 `--trusted-host` | 跑一次 `dsh web` 自动重启修复；查 `DSH_TS_HOST` |
| 窗口 app_id 与桌面图标不匹配 | profile 目录名与 `StartupWMClass` 不成对 | 保持 `--profile-directory=dsh` 与 desktop 文件两处同步 |
| 改完 `package.json` 部署侧不生效 | stow 软链被原子写断 | 下次 `dsh` 调用自动归源重建；或 `ls -la ~/.local/share/dsh/profiles/web/` 抽查 |
| `dsh tui` 报 127 | profile 内 launcher 副本缺失 | `dsh plugin --profile dsh-tui add @deepseek-harness-tui/dsh-tui@<版本>` |
| TUI 整条消失（dump-config 条目骤减） | `compatibility.json` 被删 | 恢复该文件（见 `agents/dsh/AGENTS.md`） |

## 变更

- CLI 本体安装树从 `$DSH_HOME/_cli` 迁至 `$AGENTS_ROOT/dsh`，配置与运行时状态留 `$DSH_HOME` 不动；`dsh-update` 的 lockfile 回源映射随之参数化（部署根 + 仓库源根显式传入）；断链自愈从「仅 web profile」扩展为「安装树 + web profile」双目录，补上手动升级路径的回源盲区。