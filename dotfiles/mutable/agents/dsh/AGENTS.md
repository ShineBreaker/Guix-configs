# agents/dsh — DeepSeek Harness 配置与部署

本包是 DeepSeek Harness（DSH，一切皆插件的 Agent Harness 框架）的 Guix 部署包：映射到 `$HOME`，经 GNU Stow 逐文件软链（`--no-folding`），改源即时生效。

本篇只讲**包内布局与配置层机制**（profile 结构、preset 声明、插件兼容门、自建插件不变量）。入口脚本的命令、旗标与实现契约见 [docs/scripts/dsh.md](../../../../docs/scripts/dsh.md)：wrapper 见 §dsh（wrapper），增强子命令见 §dsh web / §dsh update / §dsh tui。

## 目录与文件布局

| 路径                                            | 说明                                                                                                                                          |
| ----------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| `~/.local/share/dsh/`                           | `$DSH_HOME`，真实目录，配置文件逐个软链回本包（no-folding）。含 `cordis.patch.yml`、`.credentials.yaml`、`sessions/`、`storages/`             |
| `.local/share/dsh/profiles/web/`                | Web Profile：`cordis.yml`（loader 配置）+ `cordis.patch.yml`（用户 patch 层）+ `package.json`、`pnpm-workspace.yaml`                          |
| `.local/share/dsh/profiles/dsh-tui/`            | dsh-TUI Profile：`package.json`、`cordis.yml`、`cordis.patch.yml`、`pnpm-workspace.yaml`、**`compatibility.json`**、`pnpm-lock.yaml` 副本     |
| `.local/share/dsh/profiles/agent-extensions/`   | 自建插件包（pi/omp 共享扩展的 DSH 移植）；web profile 以 `link:../agent-extensions` 引用                                                      |
| `.local/share/dsh/profiles/web/preset-plugins/` | 自定义 preset 专用 `.mjs`（梁神模式的 tool-bootstrap 等 6 个），组合行以 `./preset-plugins/xxx.mjs` 相对 profile 目录引用                     |
| `.local/share/agents/dsh/`                      | CLI 本体安装树（`$AGENTS_ROOT` 下）：源托管 `package.json`、`pnpm-workspace.yaml`、`pnpm-lock.yaml` 副本；`node_modules/` 是部署侧运行时产物  |
| `.local/bin/dsh`                                | 唯一入口：注入 `DSH_HOME`/`AGENTS_ROOT`，`update`/`web`/`tui` 分发到同包 libexec（上游同名子命令被遮蔽为 Guix 增强版，原生行为直调 CLI 本体） |
| `.local/libexec/dsh-{web,update,tui}`           | 三个增强子命令实体（一包一入口，实现放 libexec）                                                                                              |
| `.local/share/applications/dsh.desktop`         | 桌面入口，其 `StartupWMClass` 与窗口 `app_id` 成对绑定                                                                                        |
| `.local/share/icons/hicolor/`                   | `48x48/apps/dsh.png` 栅格图标 + `scalable/apps/dsh.svg` 矢量母版                                                                              |

> **stow 忽略规则**：`.credentials.yaml`（API 密钥）、`sessions/`、`storages/`、`node_modules/`、`.mimosa/` 被 `.stow-local-ignore` 排除。`pnpm-lock.yaml` 也在忽略之列（pnpm 的 Rust 端拒绝写软链 lockfile，部署侧必须是真实文件），但**仓库源里留有副本**（进 git 保证部署可复现），由每次 `dsh` 调用的断链自愈（安装树 + web profile 双目录）拷回同步——手动升级路径（改 `package.json` 后裸跑 `pnpm install`）不过 `dsh update`，靠前者兜底。

## 安装通道与 workspace 策略

- **安装机制**：CLI 本体经 pnpm 装在 `$AGENTS_ROOT/dsh/`，配置与状态留 `$DSH_HOME` 不动。手动升级路径是改源 `package.json` 版本 → 在安装树跑 `pnpm install` → 跑任意 `dsh` 命令触发 lockfile 回源；日常更新走 `dsh update`（见 [docs/scripts/dsh.md §dsh update](../../../../docs/scripts/dsh.md)）。
- **`pnpm-workspace.yaml` 三项策略**（本体与 web profile 各一份）：`minimumReleaseAge: 0` 适配预览期的日更版本（避开 24h 供应链冷却拦截）；`saveExact: true` 让一切 pnpm add 通道（含 `dsh plugin add`）都写精确版本，根治 `^` 范围漂移；`allowBuilds` 批准 node-pty、koffi、protobufjs 等原生编译依赖。显式 `pnpm add <pkg>@<ver>` 时 pnpm 会自行把冷却期内的版本写进 `minimumReleaseAgeExclude`，豁免不用手写。

## 插件管理（Web Profile）

加插件用 `dsh plugin --profile web add <pkg>@<ver>`：在 profile 目录跑 pnpm 并自动写入 `dsh.profile.bundles`。**必须锁精确版本**，否则依赖漂移会让插件与核心版本不兼容。

| 插件                     | 当前版本       | 说明                                                                                         |
| ------------------------ | -------------- | -------------------------------------------------------------------------------------------- |
| `dsh-context`            | 0.61.0         | 上下文监控面板：Agent 组合、趋势、文件活动与 Agent 通信网络                                  |
| `dsh-dream-skin`         | 9.29.0         | 原生主题换肤（官方 `ctx.theme.register` / `overrideTokens`）                                 |
| `dsh-opencode-go`        | 0.1.16         | OpenCode Go 订阅接入：网关模型目录 + 订阅额度显示                                            |
| `dshmarket`              | 1.66.4         | 插件市场：浏览、安装与更新社区插件                                                           |
| `dsh-devin-cli`          | 0.4.2 @06a9c61 | 本地 Devin CLI 经 stdio ACP 接入（github 锁 commit，`dsh update` 自动跟 HEAD）               |
| `dsh-find-plugin`        | 0.4.0          | 文件/内容查找；peer 止步 0.1.7 线，0.2.0 下被 compat 门 skip（见下）                         |
| `dsh-remote-web-gateway` | 0.2.2          | 远程网关；2026-08-28 后停更，0.2.0 下被 compat 门 skip（见下）                               |
| `dsh-agent-extensions`   | `link:` 本地   | 自建插件，见「自建插件」                                                                     |
| `dsh-agenote`            | `link:` 本地   | 知识库集成（会话注入 / turn 转交 / 斜杠命令），源在外部仓库 `~/Projects/agenote/dsh-agenote` |

### 兼容门（compat gate）

0.1.7-rc.1 起 `dsh-app-boot` 的 `evaluatePluginCompatibility` 在启动时按插件 manifest 的 `@deepseek-ai/dsh*` peer 范围做强制校验（`includePrerelease: true`，不读 `peerDependenciesMeta.optional`），不满足即**整 bundle skip**，只在 `web.log` 记 `skipping profile bundle`——boot 本身不受影响，页面表现为该插件功能整体缺失。`dsh-find-plugin@0.4.0`（peer 止步 `^0.1.7-alpha.1`）与 `dsh-remote-web-gateway@0.2.2`（peer 全 0.1.x）当前就在这个状态，保留观望；上游发适配版后用 `dsh plugin --profile web add <pkg>@<ver>` 升回，确认不再需要则 `dsh plugin rm` 并验证 `package.json` 的 dependencies、`dsh.profile.bundles`、workspace 的 `minimumReleaseAgeExclude` 三处同清。

> **semver 预发布区间的陷阱**：peer 范围写 `^0.1.0-rc.6` 时只匹配同 `0.1.0` 元组，永远够不到 `0.1.6-alpha.2`。降级判断先看这条。

### 插件不得把核心包写成 dependency

`@deepseek-ai/dsh-*` 在插件里必须声明为 **peer**，运行时由 dsh 统一解析到核心版本。写成 dependency 且范围够不到当前核心时，pnpm 会解析出一份**旧核心**，又因 `nodeLinker: hoisted` 把它平铺到 profile 顶层，**劫持所有插件的解析**，启动时成批报 `does not provide an export named <符号>`——各插件缺的符号不同，看着像一批插件同时损坏，实为同一个旧副本。

- **判定**：`ls profiles/web/node_modules/@deepseek-ai/`，正常只应有 `cordis`、`cosmokit`、`schemastery`、`dsh-brand`；出现 `dsh-llm` / `dsh-session` 等即中招。
- **修法**：移除该插件（dependencies、`bundles`、workspace 的 `minimumReleaseAgeExclude` 三处同清）后 `pnpm install`，顶层旧副本随之消失。
- **`dsh plugin rm` 会静默失败**：pnpm 子进程报错时终端可能只闪一下退出码，`package.json` 分毫未动；日志在 `.plugin-manager/logs/operation-*/pnpm.log` 但只记摘要不记 stderr。删除后必须用 `git diff` 那两处 + `ls node_modules/@deepseek-ai/` 验证，别信命令"跑过了"。

## 自建插件（agent-extensions）

把 pi/omp 共享扩展（`dotfiles/mutable/agents/extensions/`）移植到 DSH，源码放 `profiles/agent-extensions/`，经 `link:../agent-extensions` 挂进 web profile 的 `dependencies` 与 `dsh.profile.bundles`。四个特性：

| 源扩展（pi/omp）         | DSH 行         | 作用面                                                                                   |
| ------------------------ | -------------- | ---------------------------------------------------------------------------------------- |
| `pi-gate`                | gate           | `tools/pre-execute` 拦截 bash/write/edit，判定仍由 `~/.config/agents/gate-core.sh` 出    |
| `global-context`         | global-context | `systemPrompt.section`（order 10300）注入 + `/global-context`、`/fetchcontext` 命令      |
| `custom-shortcuts`       | （客户端半边） | Shift+Tab 切 plan 模式，见 `client.js`                                                   |
| （DSH 原生，无 pi 对应） | lifecycle      | `/dsh-services` / `/dsh-kill-others` / `/dsh-restart` 命令 + 会话头「清残留 / 重启」按钮 |

`link:` 部署的本地插件源码**改动不热载**（运行中 host 持有旧模块图），必须重启进程才生效；首次部署 lifecycle 后若按钮/命令不在，用 `kill <host-pid>` + `dsh web` 手动拉一次（鸡生蛋）。

### 六条不变量

1. **客户端半边不得注册 single 型槽位**。`kind: single` 槽位只允许一个注册者，激活顺序由服务可用性驱动（与 row 顺序无关）。自建 client 若与核心插件争同一个 single 槽（如 ui-plan 的 PlanChip），**后激活者抛 `already has a registration` 并被记为 `did not activate`，整页 boot 失败**——报错点名的 entry 往往是核心插件而非肇事的自建插件，极易误导。挂载体一律选 list 型槽（`conversation.input.left/right`、`conversation.session.header.actions` 等，注册带 `options.id` 即可并存）；`sessionId`/`useProjection` 属 session 作用域标准 kit，任何 session 槽照常注入。槽位清单与类型见 `dsh-client-ui-conversation` 的 `lib/types/client/contract/slots.d.ts`。判定：页面报 `web boot: N entries did not activate`（点名的常是核心 entry，如 `dsh-client-ui-plan: failed`），用 CDP 监听 console 可见 `single slot "..." already has a registration`；二分定位靠把 `dsh.profile.bundles` 临时砍到 `[dsh-base, dsh-web-app]` 再逐半加回。
2. **`cordis.patch.yml` 的 row 必须用裸包名**。客户端半边只有在 loader row 是精确包说明符时才被扫描到——`dsh-client-modules` 的 `exactPackageSpecifier` 拒绝任何含 `/` 的非 scoped 名（`dsh-agent-extensions/gate` → `undefined`），`locatePkgJson` 随即放弃，`dsh.client` 声明被**静默跳过**：host 半边照常加载，浏览器半边永远不出现，且无任何报错。故本包只挂一行 `name: 'dsh-agent-extensions'`（`index.js` 内部再分派 gate 与 global-context），**不要拆成子路径行**。判定：页面 `__DSH_BOOT__.entries` 里没有该条目，或 `/plugins/??dsh-agent-extensions/client.js` 返回 404。
3. **新增文件必须 `--restow`**。新增 `.js` 后没跑 `blue stow --restow dsh`，部署侧缺链 → `index.js` 的 `import "./xxx.js"` 失败 → **整个 bundle 静默消失**（gate、global-context、lifecycle 一起没挂载），启动日志无显式报错。改完核对 `ls ~/.local/share/dsh/profiles/agent-extensions/`。
4. **`lib.js` 的由来**：本包经 `link:` 部署，模块 realpath 落在仓库源目录，Node 的 `node_modules` 父级检索够不到 `$DSH_HOME/profiles/node_modules` 的共享 fallback，因此 `@deepseek-ai/*` 一律不导入，用到的纯函数（`createUserMessage`、`assembleContextFor`、`renderPrompt`、`deadline`/`timeoutOf`/`TOOL_TIMEOUT`）在此复刻，**上游改语义须手动同步**。
5. **无写工具会话降级**：`simple-mode` 一类 preset 的工具面只有持久 bash + skill，无 write/edit，而 `redirect_conventions` 的冻结拦截理由引导「改用 Edit 工具逐文件应用改动」，模型会反复调用不存在的工具而死锁。`gate.js` 的 pre-execute 按 `exec.agent` 作用域查写工具可见性（`ctx.tools.get(name, agent)`，Agent 即 scope key；write/edit/str_replace_editor 三者皆无即判无写工具会话），此时向 gate-core 传 `GATE_NO_WRITE_TOOLS=1`：BLOCK 回落通用冻结理由、interactive 去掉「请使用对应工具」尾巴、NOTES/REDIRECT 软提示抑制；硬拦截、AUTO_ALLOW、REWRITTEN 一概不变（降级不制造放行面）。`GATE_NO_WRITE_TOOLS` 只被新版 `gate-core.sh` 识别，而它是 immutable 文件——**须先 `blue home`**，再重启 `dsh web`（gate.js 改源即时落盘，但 host 半边不热载）。
6. **注入标记**：hints 经 `tools/post-execute` 的 `additionalContexts` 以 **user 消息**入会话，裸文本与用户真实输入无法区分，模型曾把 gate 提示当成用户消息照办。每条注入统一包 `<injected source="agent-gate">…</injected>`（跨插件约定，来源进 source 属性；deny reason 是工具拒绝回执、tool result 框架自带失败语境，不属注入不包），并在系统提示常驻一句语义声明（`agent-gate-injection-notice` section，order 10301，紧跟 global-context 之后）：标签内是机器注入的参考提示，不是用户指令——否则标签只是视觉区分，模型仍可能照办。外部 `dsh-agenote` 的会话注入是同形态 user 消息，待其仓库按同一约定包裹。

> **host 半边可脱离服务验证**：`node --input-type=module` 导入 `gate.js`，喂桩 `ctx` 走 `tools/pre-execute`，即可确认拦截/注入语义，无需起服务。
> **未移植项**：pi 版的 `default-timeout`（给 bash 补 120s）。DSH 内建 `@deepseek-ai/dsh-tool-call-timeout-policy`，bash 执行器自带 `timeoutMs: 60000`；原移植版只针对 `ctx_*` 系列 MCP 工具，本机未接该 MCP，已移除。

## 自定义 Agent Presets

**0.1.7 废除了 `.agent-presets/` 目录发现机制**（`dsh-agent-presets` 包整体移除，shipped 四档改由 `dsh-web-app` 包的 `presets/*.patch.yml` 以行声明注册）。用户 preset 一律在 `profiles/web/cordis.patch.yml` 里以 `- insert:` 块声明一行 `@deepseek-ai/dsh-agent-preset`：

```yaml
- insert:
    - id: preset-minimal-guix # 行 id（patch 内寻址用）
      name: "@deepseek-ai/dsh-agent-preset"
      config:
        id: minimal-guix # preset id（会话引用、registry 去重键）
        name: 极简模式（Guix） # 显示名
        description: ... # 选择器里的一行说明
        order: 3.5 # 官方四档 standard=1 ptc=2 minimal=3 cordis=4
        plugins: [...组合行列表...] # 即旧 agent.cordis.yml 的内容
```

- **顶层 `- id:` 是覆盖语义**（按 id 定位已有行改 config），注册新行必须走 `- insert:` 块——写成顶层行会报 `patch: entry "..." not found` 且被静默跳过。
- **registry 按 `config.id` 去重**（重复即抛 `Duplicate agent preset`），官方四档先注册，同 id 的自定义块会直接报错——想改内置 `minimal` 只能换 id 另立副本（`minimal-guix` 即由此而来）。
- **相对路径行按 profile 目录解析**：`preset-plugins/xxx.mjs` 的行名写 `./preset-plugins/xxx.mjs`（Loader 的 baseUrl 锚定在 profile 目录）。组合内的 `!!js` 表达式照常可用。
- **验证**：`dsh --profile web --dump-config 2>&1 | grep '^- id: preset-'` 应列出七行（官方四档 + 自定义三档）。`--dump-config` 不 mount，实际挂载错误（如 .mjs 解析失败）在 boot 时以 `agent preset <id>: <原因>` warn 进 `~/.local/state/dsh/web.log`，选择器里该档带 `broken` 标注。
- **升级重同步**：diff 官方 `<dsh-web-app>/presets/*.patch.yml`，把差异套回 patch 里的 preset 块，重点保住 `terminal-bash` 行的 `shellPath`（Guix 无 `/bin/bash`，见排障 5）。
- 默认 preset 的选择持久化在 settings（`agent-presets` 命名空间，UI 的 General 设置页写入）；`$DSH_HOME/settings.yaml.imported` 是 0.1.7 首启从旧全局 settings.yaml 导入后的改名备份，仅作参考，不参与运行。

当前三档：

| preset id      | order | 说明                                                                                                               |
| -------------- | ----- | ------------------------------------------------------------------------------------------------------------------ |
| `minimal-guix` | 3.5   | 内置 minimal 副本 + `shellPath` 适配 Guix（无 `/bin/bash`）                                                        |
| `simple-mode`  | 3.6   | minimal-guix 工具面 + 完整上下文注入（AGENTS.md / 技能目录 / 系统提示词 / agenote）                                |
| `liangshen`    | 5     | 首轮 Minimal 双工具锚定，首工具调用后开放完整目录，压缩后重新锚定（V4 轨迹评估用，6 个 .mjs 在 `preset-plugins/`） |

## dsh-TUI Profile

dsh-TUI（上游 `ccch1mneyyy/dsh-TUI`，npm `@deepseek-harness-tui/dsh-tui`）是官方收录的 TUI 补位插件：鲸鱼顶栏 / 实时状态 / 流式思考 / 双击 Esc 回滚 / 上下文进度 + TPS。它与 web profile **平级但独立**——插件自带 agent preset，与 web 的三套自定义 preset、chrome App 窗口那条链路互不干扰。不并进 web profile 是刻意的：并进去会把 TUI 的 preset 行注册进 web 的组合，而两边预设、shell 方言与渲染方式都不同。

- **形态**：独立 profile `profiles/dsh-tui/`，随上游一键脚本 `install.sh`（`dsh plugin --profile dsh-tui add`）的建法，故沿用官方形态。入口 `dsh tui` 直 exec profile 内的完整 launcher 副本，不引上游 `dsh-tui`/`dst` 两个 bin 到 `~/.local/bin`。
- **compat 门同样生效，授权落在 `profiles/dsh-tui/compatibility.json`**：boot 时 loader 比对 bundle 声明的 peer 范围与本体版本，不匹配就静默跳过整个 bundle。**删掉该文件 TUI 就整条消失**（dump-config 条目数骤减且不报错）。判定：`dsh --profile dsh-tui --dump-config | grep -c '^- id:'`，或 `dsh tui doctor` 输出的 `config: .../cordis.patch.yml` 行。
- **版本线**：TUI 0.12.0 的 peer 逐项列出 `0.2.0-rc.1 || 0.2.0-rc.2`，是首个适配 0.2.0 的版本；0.11.0 的主验证线是 0.1.7-rc.2。
- **profile 层 patch 无法给 preset 行打补丁**：目标 id 要等 preset 挂载后才存在，提前写只会每次 boot 报 `patch: entry "terminal-bash" not found`。`shellPath` 坑只在切到 `minimal`/`liangshen` 时需要按 web 侧手法补；默认 `standard` preset 挂 `tool-bash`（subprocess 非 PTY），不吃这个坑。

## 图标与桌面集成

- **图标查找**：`dsh.desktop` 用 `Icon=dsh` 主题名，图标按 hicolor 布局存放（`48x48/apps/dsh.png` + `scalable/apps/dsh.svg`）。SVG 是矢量母版，重新栅格化：

  ```bash
  cd dotfiles/mutable/agents/dsh/.local/share/icons/hicolor
  rsvg-convert -w 48 -h 48 scalable/apps/dsh.svg -o 48x48/apps/dsh.png
  ```

  改完通知 Noctalia 刷新 Dock：`noctalia msg dock-reload`。

- **窗口 App ID 成对绑定**：`dsh web` 用 Chromium `--app=<url>` 拉无边框窗口（自动继承 Niri 圆角与阴影），并以 `--profile-directory=dsh` 把窗口 ID 固定为 `chrome-127.0.0.1__-dsh`，与 `dsh.desktop` 的 `StartupWMClass` **严格成对**——Wayland 下窗口 ID 只由 profile 目录名决定，改名须两处同改。该 profile 顺带隔离 dsh 的会话 cookie 与日常浏览器配置。

## 认证与会话机制

- **启动 Token**：进程启动时生成随机 Launch Token，仅供包装器脚本一次性换取 Session Cookie。
- **持久化 Cookie**：换取的 Cookie 由 `$DSH_HOME/.credentials.yaml` 中的持久化密钥 HMAC-SHA256 签名，默认 30 天，**跨服务重启依然有效**。
- **凭据或核心版本一变，旧 Cookie 全部作废**：`.credentials.yaml` 被重写（密钥轮换）或核心大版本升级换新密钥树，已签发 Cookie 一律验签失败。此时 `dsh web` 走「端口已监听 + 干净 URL」路径，页面停在 `dsh web authentication required`（401），而服务日志一切正常——**这是握手问题，不是服务挂了**。判定：`stat ~/.local/share/dsh/.credentials.yaml` 的 mtime 晚于上次握手，或查 chromium `dsh` profile 的 Cookies 库里 `127.0.0.1` cookie 的签发时间。修法就是 `dsh web --reauth`（旗标细节见 [docs/scripts/dsh.md §dsh web](../../../../docs/scripts/dsh.md)）。

## 远程访问（tailscale serve → 手机/平板操控）

**架构**：dsh 永远绑 `127.0.0.1`（CLI 故意拦 `--host 0.0.0.0`，提示 RCE 风险），远程流量经 `tailscale serve` 反代进入：`手机浏览器 → https://<尾网主机名> → tailscaled(443, WireGuard) → 127.0.0.1:3080`。只在尾网内可达，不暴露公网。

**两道门**：

1. **fence（`isTrustedApiRequest`）**：校验每个 `/api` 请求的 Host 头——loopback 恒放行；非 loopback 须命中 `--trusted-host` 白名单（serve 反代注入的 Host 是尾网主机名，所以必须带上它启动）。同时拦 `sec-fetch-site: cross-site` 与跨站 Origin（实测 403）。
2. **认证 cookie 按 authority 绑定**：名字与 payload 都按 `sha256(host)` 算——手机 cookie 绑尾网主机名，本机 chromium cookie 绑 `127.0.0.1`，**两套共存互不干扰**；无 `Secure` 标志故经 serve 的 https 也能发；HttpOnly SameSite=Strict，30 天。

**一次性开通**（需手动，sudo 被 gate 冻结，agent 不能跑）：在 tailscale 后台启用 serve（打开提示的 `login.tailscale.com` 链接），再以 root 权限配反代。

```bash
sudo tailscale serve --bg --https=443 http://127.0.0.1:3080
```

**日常默认已开**：`dsh web` 无参数启动即带 `--trusted-host`（菜单打开电脑即支持远程）。主机名默认 `brokenshine-laptop.tail3889e8.ts.net`，由 `DSH_TS_HOST` 覆盖，空串等价 `--lan-off`。

- **fence 拦截判定**：远程开页 401 = cookie 问题（重新握手）；403 = 实例没带 `--trusted-host`（跑一次 `dsh web` 自动重启修复）。典型症状是手机页面能开但会话列表空 + `directoryPicker/list HTTP 403`——页面壳（静态文件）不受 fence 约束，**不是开了新 profile**（服务端会话只有一份）。
- **目录选择器后端**：本机无 zenity/kdialog 时 boot 即解析为 `browse`（应用内逐级浏览，天生支持远程）；`native`（OS 弹窗）只在 loopback + 本机显示会话 + 选择器齐备时挂载，远程浏览器够不到 OS 对话框是其设计边界。装 `zenity` 后下次重启实例自动切 native，本机窗口体验更好，远程仍走 browse。

## 排障（配置层）

1. **端口冲突**：服务启动失败时先用 `ss -tlnp` 查 3080 占用者。服务 stdout 在 `~/.local/state/dsh/web.log`（权限 600），含一次性 token URL 与 launch token 行；UI 缺失先浏览器硬刷新，仍缺则看 `__DSH_BOOT__.entries` 的加载条数。`DSH_WEB_PORT` / `DSH_WEB_LOG` 可覆盖端口与日志路径（换端口会使 cookie 的 authority 变，须重新握手）。
2. **极简模式报 `PTY shell exited during startup`**：Guix 没有 `/bin/bash`（`/bin` 下只有 `sh`），而 `@deepseek-ai/dsh-terminal-bash` 把 bash 方言的默认 shell 硬编码成该路径 → spawn `ENOENT` → PTY 子进程当场退出，报出这条**误导性**错误（真正失败在 exec 阶段，不是就绪超时；姐妹分支是 `PTY shell did not reach readiness before startup timeout`）。只有极简模式中招，四档 preset 里只有它挂持久 shell。修法见「自定义 Agent Presets」的 `preset-minimal-guix`。
   - **连带坑**：`shellPath` 是**单个字符串**（schemastery `z.string()`），loader 不按空格切分，`confine()` 直接把它当 `argv[0]`。写 `/usr/bin/env bash` 会被当成一个文件名 → 同样 `ENOENT`。要 env 语义只能 `shellPath: /usr/bin/env` + `shellArgs: [bash, --noprofile, --norc, -i]`。
3. **第三方插件报 `cannot get property "webServer" without inject`（boot 崩溃）**：`ctx.connection.rpc.handle()` 内部在 **connection 插件自己的 scope** 解析 `webServer`（cordis shadow 语义，`this.ctx` 经 `createShadow` 指向服务方 context），而 bundle 的 `connection` 行只 inject 了 `webRuntime` → 任何调 `rpc.handle` 的插件（如 `dsh-remote-web-gateway`）都会炸掉整个 boot；`rpc.intercept` / `fetch.register` 不受影响。修法：profile `cordis.patch.yml` 给 `connection` 行补 `inject: [webRuntime, webServer]`（inject 是整表替换，原值须复述）。
4. **源与部署侧静默分叉**：UI / `dsh plugin` 装插件时 pnpm 原地写 `profiles/web/package.json`，把回本仓库的软链换成实体文件。断链自愈已双层覆盖（详见 [docs/scripts/dsh.md §dsh（wrapper）](../../../../docs/scripts/dsh.md)），但触发窗口（UI 编辑后、下次 dsh 命令前）内源是旧的，建议跑完 `ls -la ~/.local/share/dsh/profiles/web/` 抽查链接形态。
5. **会话报 `本轮运行失败 format v4 message requires a producer-owned source kind`**：0.1.7 会话格式 v4 拒绝旧式消息源 `{kind: "plugin", plugin: "<名>"}`（`kind: "plugin"` 包装已退役）。**插件创建 user/developer 消息必须直接写 producer-owned kind**：按 v3→v4 迁移器规则写 `{kind: "plugin:<名>"}`（如 `plugin:agent-gate`），与旧日志重放的迁移结果保持一致；读取侧识别自注入消息要同时兼容 v3（`kind === "plugin"` + `plugin` 字段）与 v4（`kind` 以 `plugin:` 开头）两种形态。本包 `gate.js` 与外部 `dsh-agenote` 已按此规范写，新增注入消息的插件照此办理。
