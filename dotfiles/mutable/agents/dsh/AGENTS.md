# agents/dsh — DeepSeek Harness 配置层

dsh（DeepSeek 的 everything-is-a-plugin agent harness，developer preview 迭代快）的 Guix 部署包。
包根映射到 `$HOME`，故本文件与 `.stow-local-ignore` 自身不进部署位。

## 布局

| 路径                                    | 说明                                                                                                              |
| --------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| `~/.local/share/dsh/`                   | `$DSH_HOME`，真实目录，配置逐文件 stow 链回本包（不用 folding，对齐 hermes 实证形态）                             |
| `_cli/`                                 | CLI 本体：源只托管 `package.json` + `pnpm-workspace.yaml`，`node_modules/` 与 `pnpm-lock.yaml` 是部署侧运行时产物 |
| `profiles/web/`                         | web profile：源托管 `cordis.yml`、`cordis.patch.yml`、`package.json`、`pnpm-workspace.yaml`                       |
| `.local/bin/dsh`                        | CLI wrapper：注入 `DSH_HOME`；CLI 缺失时询问后自动装，非交互场景走 `dsh --install`                                |
| `.local/bin/dsh-web`                    | desktop 入口：确保服务在跑，再用 chromium app 窗口打开                                                            |
| `.local/share/applications/dsh.desktop` | 桌面项，`StartupWMClass` 与窗口 app_id 成对绑定                                                                   |
| `.local/share/icons/dsh.png`            | 图标（Papirus 风格）；同目录 `dsh.svg` 是矢量母版，`.desktop` 的 `Icon=` 指绝对路径                               |

部署侧另留、由 `.stow-local-ignore` 防御性排除：`.credentials.yaml`（API key）、`sessions/`、`storages/`、`node_modules/`、`pnpm-lock.yaml`、`.anonymous-user-id`。

## 通道

本体 0.1.5-rc.1 经 pnpm 装在 `_cli/`。升级 = 改源 `package.json` 版本 → `_cli/` 里 `pnpm install`。
`_cli/pnpm-workspace.yaml` 声明 `minimumReleaseAge: 0`（preview 期逐包日更，默认 1440min 供应链冷却必拦自家闭包）与 `allowBuilds` 五件套（node-pty / koffi / dsh-subprocess-local / protobufjs / @google/genai）。

2026-09-10 自 uv tool 的 PyPI wheel 迁移：SEA 单文件闭包两度缺包（`session-title-llm` 崩启动、`client-modules` 报 "Failed to load plugins"）且 0.1.5-rc.1 未修，npm 通道依赖树完整、零 workaround。

## 插件层（web profile）

`dsh plugin --profile web add <pkg>@<ver>` 是 pnpm 薄转发器：在 profile 目录跑 pnpm，再把声明 `dsh.bundle` 的依赖自动并入 `dsh.profile.bundles`，profile 文件不用手改。依赖锁**精确版本**——插件迭代快，`^` 会在重装时静默升到与当前 DSH 不兼容的版本（实测 `dsh-context` 0.47 对 0.1.5-rc.1 会缺 UI）。

| 插件                 | 版本   | 说明                                                                                                                                |
| -------------------- | ------ | ----------------------------------------------------------------------------------------------------------------------------------- |
| `dsh-better-sidebar` | 0.19.0 | ★3479 / MIT。侧边栏工作台：文件编辑器、内嵌真实终端（xterm + node-pty）、Git 差异、子代理与后台任务、侧边对话。要求 DSH ≥0.1.5-rc.1 |
| `dsh-context`        | 0.49.0 | ★1314 / Apache-2.0。上下文面板（组合/趋势/事件/文件活动/agent 网络）。首个在 `dsh.compatibility` 声明兼容 0.1.5-rc.1 的版本         |
| `dsh-dream-skin`     | 8.30.1 | ★153 / MIT。走官方 `ctx.theme.register` / `overrideTokens` 的原生 token 换肤，不注入 CSS                                            |

装插件三坑：① pnpm 11 的 24h 供应链冷却会挡当日发布版本（pnpm 自动把 `minimumReleaseAgeExclude` 写进 profile workspace，本就该如此）；② native 依赖须 `pnpm approve-builds`（写的是 `allowBuilds`，不是旧文档的 `onlyBuiltDependencies`）；③ 装完须重启 `dsh web`，且首次页面可能因 host 扫描竞态漏插件条目（`__DSH_BOOT__.entries` 少 3 条），硬刷新即恢复。

主题包只收颜色且存浏览器 localStorage，无法随仓库声明式分发。

## 图标

`dsh.desktop` 的 `Icon=` 走**绝对路径**而非名字查找：用户级 `hicolor` 没有 `index.theme` 与 `icon-theme.cache`，按名查找不可靠（hermes 踩过）。

`dsh.png`（256×256 RGBA）是部署产物，已由 stow 链出，改源即生效、无需 `blue home`。`dsh.svg` 是它的矢量母版，**留在仓库侧、不必部署**——`Icon=` 指绝对路径的 `.png`，没有任何按名查找会用到它。重跑栅格化：

```bash
cd dotfiles/mutable/agents/dsh/.local/share/icons
rsvg-convert -w 256 -h 256 dsh.svg -o dsh.png
```

改完图标让 noctalia 重新读：`noctalia msg dock-reload`（dock 是 `smart_auto_hide`，不必重启面板）。

样式对齐 Papirus（实测：抽样彩色图标在 `Papirus` 与 `Papirus-Dark` 下逐字节相同，故透明底一套通吃亮/暗色；`128x128/apps` 8321 个图标里只有 38 个用渐变，故用平涂）：

- 64×64 网格，鲸鱼宽 56——即 Papirus 自己 56/64 圆形的占比——垂直居中。
- 投影 = 本体 `translate(0,1)` 的 `#000` `opacity=".2"`：硬偏移、无模糊，与 Papirus 一致。
- 顶缘高光 = 白 `opacity=".12"`，用 mask 取「本体 − 向下平移 1.2 的本体」，故只落在朝上的边缘。
- 主体 `#4d6bfe` 保持旧图标的 DeepSeek 品牌蓝——Papirus 不改品牌色（spotify 仍是 `#1ed760`）。
- **不做底缘暗带**：Papirus 的 glyph 型图标（vscode）只有投影 + 顶缘高光，加暗带会在光滑大色块上读成第二条描边。

鲸鱼路径逐字节取自上游 `dsh-web-frontend/dist/favicon.svg`（单一 `<path>`，腹部与眼睛是镂空）。重绘时不要手改 `d`，从那里重新取。旧的白底方块版本见 commit `73ed2466`。

## 窗口

`dsh-web` 用 chromium `--app=<url>` 开无浏览器 chrome 的窗口（无标签栏/地址栏/工具栏，继承 niri 全局圆角与阴影）。**不装 PWA**：dsh 前端自带 `manifest.webmanifest`，但 `display: fullscreen`，装出来是全屏而非窗口。

窗口 app_id 走 `--profile-directory=dsh` 定为 `chrome-127.0.0.1__-dsh`，与 `dsh.desktop` 的 `StartupWMClass` **成对绑定——改名须同时改两处**。该 profile 顺带把 dsh 的会话 cookie 与日常浏览的 Default profile 隔开。

app_id 机制实测：端口不入 app_id；`WAYLAND_DEBUG=1` 显示 app 窗口只发一次 `set_app_id`（值即 Chromium 算的 web-app id），`--class` 的值根本不出现——`--class` 只有普通窗口才读，`--wm-class` 该版二进制不存在。要任意名字只能 `--ozone-platform=x11` 退回 XWayland（已否决：为装饰性名字放弃原生 Wayland 不划算）。

## 认证

launch token 按进程随机（`PROCESS_LAUNCH_TOKENS` WeakMap）且一个 token 只换一次 cookie，所以**只有 wrapper 亲起的实例才拿得到它的 token URL**；已在监听的实例须 `dsh-web --reauth` 换新 token（终止前校验目标 cmdline 含 `@deepseek-ai/dsh`，不误杀同端口上的其它进程）。

换到的 cookie 由 `$DSH_HOME/.credentials.yaml` 里的持久化密钥 HMAC-SHA256 签名、`cookieMaxAgeDays` 默认 30 天、**跨重启有效**——别被「token 一次性消耗」的说法误导成每次重启都要重认证。cookie 名是 `dsh-auth-` + sha256(authority)，**authority 含端口**，故换端口要重新握手。

`/` 与 API 需认证（无 cookie 返回 68 字节单行 401 提示），静态资源与 `/manifest.webmanifest` 免认证。

## 排障

- 服务起不来先查 3080 占用。进程 comm 是 `MainThread`，`pkill -f` 模式易自杀，用 `ss -tlnp` 取 pid 精确处理。
- 服务 stdout 落在 `~/.local/state/dsh/web.log`（600），里面有一次性 token URL。
- `dsh-web` 在服务起不来时会打印日志末尾并发桌面通知——desktop 入口没有终端可看，不这样就是静默失败。
- 页面插件 UI 缺失先硬刷新；仍缺再查 `__DSH_BOOT__.entries` 条数。
- wrapper 的环境覆盖：`DSH_WEB_PORT`（端口；改了 cookie 的 authority 也变，需重新握手）、`DSH_WEB_LOG`、`DSH_BIN`（测试用）、`DSH_HOME`。
