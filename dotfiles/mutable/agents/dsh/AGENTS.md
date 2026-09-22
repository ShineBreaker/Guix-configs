# agents/dsh — DeepSeek Harness 配置与部署

本目录为 DeepSeek Harness（DSH，一切皆插件的 Agent Harness 框架）的 Guix 部署包。
本包映射到 `$HOME`，通过 GNU Stow 逐文件软链到系统。

## 目录与文件布局

| 路径                                    | 说明                                                                                                 |
| --------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| `~/.local/share/dsh/`                   | `$DSH_HOME`，为真实目录，配置文件逐个软链回本包（采用 no-folding 模式）                              |
| `.local/share/dsh/cordis.patch.yml`     | `$DSH_HOME` 顶层的 cordis 补丁配置                                                                   |
| `.local/share/dsh/.agent-presets/`      | 用户自有 agent preset 根：`minimal-guix`（极简模式）、`simple-mode`（简单模式）、`liangshen`（梁神模式），部署侧逐文件软链回本包 |
| `.local/share/dsh/_cli/`                | CLI 本体源：托管 `package.json`、`pnpm-workspace.yaml` 与 `pnpm-lock.yaml` 副本；`node_modules/` 为运行时产物。部署侧 lockfile 是真实文件（pnpm 拒写软链 lockfile），由 `dsh --install` 自动拷回源 |
| `.local/share/dsh/profiles/web/`        | Web Profile：托管 `cordis.yml`、`cordis.patch.yml`、`package.json`、`pnpm-workspace.yaml` 等配置     |
| `.local/share/dsh/profiles/agent-extensions/` | 自建插件包（pi/omp 共享扩展的 DSH 移植，见「自建插件」）；profile 以 `link:../agent-extensions` 引用 |
| `.local/bin/dsh`                        | CLI 启动包装器：注入 `DSH_HOME`；CLI 缺失时可交互式自动安装，或通过 `dsh --install` 无人值守安装；`update`/`web` 子命令分发到同包 `.local/libexec/` 实体（一包一入口，上游原生的同名子命令被遮蔽为 Guix 增强版） |
| `.local/libexec/dsh-web`                | Web UI 启动实体（`dsh web`）：启动后台服务并开 Chromium App 窗口；默认带远程信任（`--remote-url`/`--reauth`/`--lan-off`，见「远程访问」） |
| `.local/libexec/dsh-update`             | 一键更新本体与三个插件（`dsh update`，见「一键更新」）                                                             |
| `.local/share/applications/dsh.desktop` | 桌面快捷方式，其 `StartupWMClass` 与窗口 `app_id` 成对绑定                                           |
| `.local/share/icons/hicolor/`           | 图标：`48x48/apps/dsh.png` 为栅格图标，`scalable/apps/dsh.svg` 为矢量母版                            |

> **忽略规则**：`.credentials.yaml`（API 密钥）、`sessions/`、`storages/`、`node_modules/` 等运行时产物已被 `.stow-local-ignore` 防御性排除。`pnpm-lock.yaml` 也在 stow 忽略之列（pnpm 的 Rust 端拒绝写软链 lockfile，部署侧必须是真实文件），但**仓库源里有其副本**（进 git 保证部署可复现），由 `dsh`/`dsh update` 在 pnpm 跑完后自动拷回同步。

## 安装通道与升级

- **安装机制**：DSH CLI 本体（当前为 0.1.6-alpha.2）通过 pnpm 安装在 `_cli/` 目录中。
- **升级步骤**：修改源码中 `.local/share/dsh/_cli/package.json` 的版本号 → 在 `_cli/` 目录中执行 `pnpm install`。插件同理改 `profiles/web/package.json`。日常更新直接跑 `dsh update`（见「一键更新」），它会同时处理本体与插件，并在插件的兼容声明不含目标本体版本时给出提醒。
- **Workspace 配置**：`_cli/pnpm-workspace.yaml` 设置了 `minimumReleaseAge: 0`（适配预览期的日更版本，避免 24h 供应链冷却拦截）、`saveExact: true`（一切 pnpm add 通道——含 `dsh plugin add`——都写精确版本，根治 `^` 范围漂移）以及 `allowBuilds`（批准 node-pty、koffi、protobufjs 等原生编译依赖）。插件侧 `profiles/web/pnpm-workspace.yaml` 同理。

## 插件管理（Web Profile）

添加插件推荐使用 `dsh plugin --profile web add <pkg>@<ver>` 命令。它会在 profile 目录运行 pnpm，并将依赖自动写入 `dsh.profile.bundles`。

> **重要规则**：必须锁定**精确版本**，避免依赖漂移导致插件与 DSH 核心版本不兼容。

| 插件                                 | 当前版本       | 说明                                                                               |
| ------------------------------------ | -------------- | ---------------------------------------------------------------------------------- |
| `dsh-context`                        | 0.53.3         | 上下文监控面板：展示 Agent 组合、趋势分析、文件活动与 Agent 通信网络               |
| `dsh-dream-skin`                     | 9.16.0         | 原生主题换肤：通过官方 `ctx.theme.register` / `overrideTokens` 实现原生 Token 换肤 |
| `@opencode2dsh/dsh-plugin`           | 0.3.2          | OpenCode Zen 免费通道：原生 LLM adapter，无凭据零配置                              |
| `dsh-opencode-go`                    | 0.1.4          | OpenCode Go 订阅接入：网关模型目录 + 订阅额度显示                                  |
| `@mars-sea/dsh-commandcode-provider` | 0.11.5         | Command Code 接入：全套餐、浏览器内 OAuth 登录、多账户轮换                         |
| `dsh-devin-cli`                      | 0.4.2 @06a9c61 | 本地 Devin CLI 经 stdio ACP 接入（github 锁 commit，dsh update 自动跟 HEAD）        |
| `dsh-agent-extensions`               | `link:` 本地  | 自建插件：pi/omp 共享扩展的 DSH 移植，见「自建插件」                                |
| `dsh-agenote`                        | `link:` 本地  | 自建插件：agenote 知识库集成（会话注入 / turn 转交 / 斜杠命令），源在 `~/Projects/agenote/dsh-agenote` |

> **已移除：`dsh-better-sidebar`（0.19.1，2026-09-19）**——侧边栏工作台（文件编辑、内置终端、Git 差异）。其 peer 锁 `@deepseek-ai/dsh-agent: ^0.1.5-rc.1`，semver 预发布区间够不到核心 `0.1.6-alpha.2`：`conversation.chat.turnTail` 槽位在 0.1.6 由 `chain` 改为 `list`（注册要求 `options.id`），旧插件按 chain API 注册 → 整页 `web boot` 失败。上游发布适配 0.1.6 的版本后可 `dsh plugin --profile web add dsh-better-sidebar@<ver>` 装回。

### 插件常见问题与注意点

1. **供应链冷却**：pnpm 会自动将 `minimumReleaseAgeExclude` 写入 profile workspace，确保新发插件正常拉取。
2. **原生模块编译**：涉及 native 依赖时需执行 `pnpm approve-builds`（配置项为 `allowBuilds`）。
3. **服务重启**：安装新插件后须重启 `dsh web`。若首次加载时页面漏掉插件条目，对浏览器进行一次硬刷新（Ctrl+F5）即可恢复。
4. **软链断链**：`dsh plugin add/remove` 写 `dsh.profile.bundles` 走原子替换（临时文件 + rename），会把 `profiles/web/package.json` 的 stow 软链换成独立文件——dependencies 更新进仓库源、bundles 却只落在部署侧。**wrapper 已自动自愈**：`dsh` 包装器在每次 `plugin` 子命令结束后检测断链，从同目录幸存的 `pnpm-workspace.yaml` 软链推导仓库源目录（无硬编码路径），把内容写回源并重建软链，同时把部署侧 lockfile 拷回源。仍建议跑完 `ls -la` 抽查（pnpm 自身的写入不会断链，只有 dsh 的 bundles 写入会）。
5. **插件不得把核心包写成 dependency**：`@deepseek-ai/dsh-*` 在插件里应声明为 **peer**，运行时由 dsh 统一解析到 `_cli` 的核心版本（profile 顶层解析不到时才回退）。若某插件把它们写成 dependency 且版本范围够不到当前核心（如 `^0.1.0-rc.6`——semver 下预发布区间只匹配同 `0.1.0` 元组，永远升不到 `0.1.6-alpha.2`），pnpm 会解析出一份**旧核心**，又因 `nodeLinker: hoisted` 把它平铺到 profile 顶层，**劫持所有插件的解析** → 启动时成批报 `does not provide an export named <符号>`（各插件缺的符号不同，看着像一批插件同时损坏，实为同一个旧副本）。
   - **判定**：`ls profiles/web/node_modules/@deepseek-ai/`，正常只应有 `cordis`、`cosmokit`、`schemastery`、`dsh-brand`；出现 `dsh-llm` / `dsh-session` 等即中招。
   - **修法**：移除该插件（`dependencies`、`bundles`、workspace 的 `minimumReleaseAgeExclude` 三处同清）后 `pnpm install`，顶层旧副本随之消失。
   - **`dsh plugin rm` 会静默失败**：它的 pnpm 子进程报错时（如依赖树重算撞上 supply-chain 校验 / Git 依赖 prepare 未放行），终端可能只闪一下 exit code，`package.json` 分毫未动。日志在 `.plugin-manager/logs/operation-*/pnpm.log`，但**只记一行摘要不记 stderr**。删除后必须验证（`git diff` 那两处 + `ls node_modules/@deepseek-ai/`），别信命令"跑过了"。
   - **实例**：`dsh-session-import@0.1.1`（上游 2026-08 后停更，依赖 `^0.1.0-rc.6` 并使用已被移除的 `createUserMessage` 等 API，与 0.1.6 核心无法共存）。2026-09-19 17:05 的 `dsh plugin rm` 失败未被察觉，插件滞留至当晚定位。

## 自建插件（agent-extensions）

把 pi/omp 共享扩展（`dotfiles/mutable/agents/extensions/`）移植到 DSH，源码放在
`profiles/agent-extensions/`，经 `link:../agent-extensions` 挂进 web profile 的
`dependencies` 与 `dsh.profile.bundles`。四个特性：

| 源扩展（pi/omp） | DSH 行 | 作用面                                                                     |
| ---------------- | ------ | -------------------------------------------------------------------------- |
| `pi-gate`        | gate   | `tools/pre-execute` 拦截 bash/write/edit，判定仍由 `~/.config/agents/gate-core.sh` 出 |
| `global-context` | global-context | `systemPrompt.section`（order 10300）注入 + `/global-context`、`/fetchcontext` 命令 |
| `custom-shortcuts` | （客户端半边） | Shift+Tab 切 plan 模式，见 `client.js`                              |
| （DSH 原生，无 pi 对应） | lifecycle | `/dsh-services` / `/dsh-kill-others` / `/dsh-restart` 命令 + 会话头「清残留 / 重启」按钮 |

**lifecycle 半边**（`lifecycle.js`，2026-09-20 新增）：`link:` 部署的本地插件源码改动
不热载，运行中 host 持有旧模块图，必须重启进程——把「查残留 / 清残留 / 重启」收进
命令与按钮：

- **判据**：`/proc` 扫描 argv 指向 dsh `bin.js` 且（`ss -tlnp` 有监听或首参是
  `web`/`serve`）——一次性 CLI 子命令（`dsh plugin` 等）不监听端口，天然排除。
- **`/dsh-restart` 的 respawn 语义**：detached watcher 轮询本 PID 死亡（SIGTERM 优雅
  停机最长 ~5s，端口释放时刻不定，轮询而非裸 sleep）后按原 argv `exec` 重拉。cookie
  由 `.credentials.yaml` 密钥签名（30 天），浏览器旧窗口断开重连即可，无需重新握手。
- **客户端按钮**（`client.js` 的 `ServiceControls`，挂 `conversation.session.header.actions`
  list 槽）：重启前先 `history.replaceState` 剥掉 `?token=`（旧 launch token 已失效，
  带死 token 重载会 401），再轮询 `HEAD /` 等新 host 复活后 `location.reload()`。
- **坑：本插件自己的改动也需要重启才生效**——首次部署 lifecycle 后若按钮/命令不在，
  用 `kill <host-pid>` + `dsh web` 手动拉起一次，之后就有按钮了（鸡生蛋问题）。
- **坑：host 半边 import 断链会让整个 bundle 静默消失**——新增 `lifecycle.js` 后没
  restow，部署侧缺文件 → `index.js` 的 `import "./lifecycle.js"` 失败 → gate、
  global-context、lifecycle **三个特性一起没挂载**，且启动日志无显式报错。改完必须
  核对部署侧软链齐全（`ls ~/.local/share/dsh/profiles/agent-extensions/`）。

- **`default-timeout` 未移植**：pi 版给 bash 补 120s。DSH 内建 `@deepseek-ai/dsh-tool-call-timeout-policy`（`dsh-base` 组合的 `timeout-policy` 行），bash 执行器自身已带 `timeoutMs: 60000`，无需再挂。原移植版只针对 `ctx_*` 系列 MCP 工具，本机未接该 MCP，属死配置，已移除。
- **`lib.js` 的由来**：本包经 `link:` 部署，模块 realpath 落在仓库源目录，Node 的
  `node_modules` 父级检索够不到 `$DSH_HOME/profiles/node_modules` 的共享 fallback，
  因此 `@deepseek-ai/*` 一律不导入，用到的纯函数（`createUserMessage`、
  `assembleContextFor`、`renderPrompt`、`deadline`/`timeoutOf`/`TOOL_TIMEOUT`）在此复刻。
  **上游改语义需手动同步**。
- **新增文件必须 `--restow`**：`lib.js` 曾因新增后未跑 `blue stow --restow dsh` 而
  只存在于源目录，部署侧缺链 → `gate.js`/`global-context.js` 的 `import "./lib.js"`
  直接解析失败。改完本包务必核对部署侧软链齐全。
- **客户端半边不得注册 single 型槽位**：`conversation.input.plan` 等 `kind: single` 槽位只允许一个注册者，且激活顺序由服务可用性驱动（与 row 顺序无关）。自建 client 若与核心插件争同一个 single 槽（如 ui-plan 的 PlanChip），**后激活者抛 `already has a registration` 并被记为 `did not activate`，整页 boot 失败**——报错指向的 entry 往往是核心插件而非肇事的自建插件，极易误导。挂载体一律选 list 型槽（`conversation.input.left/right`、`conversation.session.header.actions` 等，注册带 `options.id` 即可并存）；`sessionId`/`useProjection` 属 session 作用域标准 kit，任何 session 槽照常注入。槽位清单及类型见 `dsh-client-ui-conversation` 的 `lib/types/client/contract/slots.d.ts`。
  - **判定**：页面报 `web boot: N entries did not activate`，点名的是核心 entry（如 `@deepseek-ai/dsh-client-ui-plan: failed`）；用 CDP 监听 console 可见根因异常（`single slot "..." already has a registration`）。
  - **二分定位**：临时把 `dsh.profile.bundles` 砍到 `[dsh-base, dsh-web-app]` 重启验证纯净组合，再逐半加回。
- **`cordis.patch.yml` 的 row 必须用裸包名**：客户端半边只有在 loader row 是**精确包说明符**
  时才被扫描到 —— `dsh-client-modules` 的 `exactPackageSpecifier` 会拒绝任何含 `/` 的非 scoped
  名（`dsh-agent-extensions/gate` → `undefined`），`locatePkgJson` 随即放弃，`dsh.client`
  声明被**静默跳过**：host 半边照常加载，浏览器半边永远不出现，且无任何报错。
  故本包只挂一行 `name: 'dsh-agent-extensions'`（`index.js` 内部再分派 gate 与
  global-context），**不要拆成子路径行**。
  - **判定**：页面 `__DSH_BOOT__.entries` 里没有该插件条目，或
    `/plugins/??dsh-agent-extensions/client.js` 返回 404。
- **验证方式**：host 半边可用桩 `ctx` 直接驱动模块（`node --input-type=module` 导入
  `gate.js`，喂假 exec 走 `tools/pre-execute`），无需启动服务即可确认拦截/注入语义。

## 一键更新（dsh update）

`dsh update` 把本体与 web profile 的全部插件一起升到上游最新（插件清单从 `package.json` 的 dependencies 动态读取）。两层强绑定，故不提供只升一层的开关。

```bash
dsh update --check           # 只查差异；退出码 0=已最新，1=有更新
dsh update                   # 列出差异，确认后执行
dsh update --yes --restart   # 一键：跳过确认，并在更新后重启 dsh web
```

- **选版不跟 npm 的 `latest` tag**：DSH 全是 preview 版本，发布者把 `latest` 停在保守位（`0.1.5-rc.2 发布时 latest` 仍是 rc.1）。脚本按通道稳定性 `latest → next → beta → alpha` 取第一个高于当前的版本，来源通道在输出里标出。
- **版本锁精确**：workspace 的 `saveExact: true` 兜底 + 命令行 `-E` 双保险。pnpm 默认写 `^`，那正是依赖静默升到不兼容版本的成因。
- **github 插件自动跟 HEAD**：`github:<owner>/<repo>#<sha>` 形态的依赖用 `git ls-remote` 查上游 HEAD，commit 变化即列为更新项；执行前自动把 `allowBuilds` 的放行 key 迁到新 commit（key 绑定 tarball URL，pnpm 报 `ERR_PNPM_GIT_DEP_PREPARE_NOT_ALLOWED` 时也会打印新 key）。其余锁定源码（`git+`/`git@`/`file:`/`link:`）没有可查的上游位标，只列出提示。
- **不手写冷却豁免**：显式 `pnpm add <pkg>@<ver>` 时，pnpm 会自动把仍在 24h 供应链冷却期内的版本写进 workspace 的 `minimumReleaseAgeExclude`。
- **兼容性提醒**：读插件的 `dsh.compatibility.dshReleases`（发布方自列的已验证版本白名单）。多数插件没有这个字段，那不代表不兼容，故只在「声明了白名单却不含目标版本」时才提醒。
- **lockfile 自动回源**：每次 pnpm 跑完后，脚本把部署侧 lockfile 拷回仓库源副本（见「忽略规则」），git 里始终是可复现的锁。
- **生效**：更新后须重启 `dsh web`（host 半边不热载）。`--restart` 会调 `dsh web --reauth`。

> **改的是仓库源文件**：`package.json` 与 `pnpm-workspace.yaml` 由 pnpm 原地写入（两者都是回本包的软链），`pnpm-lock.yaml` 由脚本拷回源副本，跑完 `git diff` 后提交。

## 图标与桌面集成

- **图标查找**：`dsh.desktop` 使用 `Icon=dsh` 主题名，图标按 hicolor 布局存放（`hicolor/48x48/apps/dsh.png` + `hicolor/scalable/apps/dsh.svg`）。
- **SVG 母版与栅格化**：`scalable/apps/dsh.svg` 为矢量母版。若需重新生成 PNG 图标，执行以下命令：
  ```bash
  cd dotfiles/mutable/agents/dsh/.local/share/icons/hicolor
  rsvg-convert -w 48 -h 48 scalable/apps/dsh.svg -o 48x48/apps/dsh.png
  ```
- **刷新 Dock 缓存**：修改图标后通知 Noctalia 刷新：`noctalia msg dock-reload`。

## 窗口管理与 Wayland 适配

- `dsh web` 使用 Chromium `--app=<url>` 模式拉起无浏览器边框的独立窗口，自动继承 Niri 的全局圆角与阴影特效。
- **窗口 App ID**：通过 `--profile-directory=dsh` 将窗口 ID 固定为 `chrome-127.0.0.1__-dsh`，与 `dsh.desktop` 中的 `StartupWMClass` **严格成对绑定**。修改时两处须同时修改。
- 独立 Profile 同时将 DSH 的会话 Cookie 与日常浏览器的默认配置隔离开。

## 认证与会话机制

- **启动 Token**：进程启动时生成随机 Launch Token，仅供包装器脚本一次性换取 Session Cookie。
- **持久化 Cookie**：换取的 Cookie 由 `$DSH_HOME/.credentials.yaml` 中的持久化密钥进行 HMAC-SHA256 签名，默认有效期为 30 天，**跨服务重启依然有效**。
- **重新认证**：若需强制重置凭据，执行 `dsh web --reauth` 即可安全终止旧实例并重新握手。
- **`.credentials.yaml` 被重写 → 全部 Cookie 作废**：密钥一换，所有已签发 Cookie 验签失败，`dsh web` 走「端口已监听 + 干净 URL」路径时页面停在 `dsh web authentication required`（401），服务日志却一切正常。判定：`stat ~/.local/share/dsh/.credentials.yaml` 的 mtime 晚于上次握手；或查 chromium `dsh` profile 的 Cookies 库里 `127.0.0.1` cookie 的签发时间。修法就是 `dsh web --reauth`。

## 远程访问（tailscale serve → 手机/平板操控）

**架构**：dsh 永远绑 `127.0.0.1`（CLI 故意拦 `--host 0.0.0.0`，提示 RCE 风险），远程流量经 `tailscale serve` 反代进入：`手机浏览器 → https://<尾网主机名> → tailscaled(443, WireGuard) → 127.0.0.1:3080`。只在尾网内可达，不暴露公网。

**两道门**（0.1.6 核心实码验证，2026-09-20）：

1. **fence（`isTrustedApiRequest`）**：校验每个 `/api` 请求的 Host 头——loopback 恒放行；非 loopback 须命中 `--trusted-host` 白名单（serve 反代注入的 Host 是尾网主机名，所以必须带上它启动）。同时拦 `sec-fetch-site: cross-site` 与跨站 Origin（实测 403）。
2. **认证 cookie**：名字与 payload 都按 authority（`sha256(host)`）绑定——手机 cookie 绑尾网主机名，本机 chromium cookie 绑 `127.0.0.1`，**两套共存互不干扰**；无 `Secure` 标志故经 serve 的 https 也能发；HttpOnly SameSite=Strict，30 天。

**一次性开通**（需手动）：

```bash
# 1. tailscale 后台启用 serve（打开提示的 login.tailscale.com 链接）
# 2. root 权限配置反代（sudo 被 gate 冻结，agent 不能跑）
sudo tailscale serve --bg --https=443 http://127.0.0.1:3080
```

**日常使用**：远程默认开启——`dsh web` 无参数启动即带 `--trusted-host`（菜单打开电脑即支持远程，无需手动步骤）。手机首次握手跑 `dsh web --remote-url` 拿 token URL，之后直接开 `https://<尾网主机名>/`。

| 用法 | 作用 |
| --- | --- |
| `dsh web` | 常规启动：实例未带 `--trusted-host` 时**自动重启**为 trusted（检测 `/proc/<pid>/cmdline`），再开本机窗口 |
| `dsh web --remote-url` | 不弹窗：确保实例 trusted，打印手机首次握手 token URL |
| `dsh web --reauth` | 强制重启换新 token（cookie 失效时用） |
| `dsh web --lan-off` | 本次不带远程信任启动（`DSH_TS_HOST=` 空串等价；主机名默认 `brokenshine-laptop.tail3889e8.ts.net`，环境变量可覆盖） |

- **token 一次性**：token 只能换一次 cookie。`--remote-url` 拿到旧 token（已消耗）时手机端 401——`--reauth` 重启换新。
- **本机窗口照旧**：`dsh web` 检测到端口已监听且 trusted 就直接开 `127.0.0.1` 干净 URL，不重启不弹第二窗。
- **fence 拦截判定**：远程开页 401 = cookie 问题（重新握手）；403 = 实例没带 `--trusted-host`（跑 `dsh web` 一次自动修）。症状实例：手机页面能开但会话列表空 + `directoryPicker/list HTTP 403`——都是 `/api` 被 fence 拦，页面壳（静态文件）不受影响所致，**不是开了新 profile**（服务端会话只有一份）。
- **目录选择器**：本机无 zenity/kdialog 时 boot 即解析为 `browse` 后端（应用内逐级浏览，天生支持远程）；`native` 后端（OS 弹窗）只在 loopback+本机显示会话+选择器齐备时挂载，远程浏览器够不到 OS 对话框是其设计边界（`resolveDirectoryPickerBackend` 注释明言）。装 `zenity` 后下次重启实例会自动切 native，本机窗口体验更好，远程仍走 browse。

## 排障指南

1. **端口冲突**：服务启动失败时优先检查 3080 端口占用。使用 `ss -tlnp` 精确查找对应 PID 并处理。
2. **日志排查**：服务标准输出记录在 `~/.local/state/dsh/web.log`（权限 600），包含详细启动与 Token 信息。
3. **UI 缺失**：页面插件未渲染时先进行浏览器硬刷新；若仍缺失，检查 `__DSH_BOOT__.entries` 加载条数。
4. **环境变量覆盖**：
   - `DSH_WEB_PORT`：自定义 Web 监听端口（更换端口会使 Cookie 重新握手）。
   - `DSH_WEB_LOG`：自定义日志输出路径。
   - `DSH_HOME`：覆盖默认 DSH 数据主目录。
5. **极简模式报 `PTY shell exited during startup`**：Guix 没有 `/bin/bash`（`/bin` 下只有 `sh`），而 `@deepseek-ai/dsh-terminal-bash` 把 bash 方言的默认 shell 硬编码成这个路径 → spawn `ENOENT` → PTY 子进程当场退出 → 报出这条**误导性**错误（真正失败在 exec 阶段，不是就绪超时；姐妹分支是 `PTY shell did not reach readiness before startup timeout`）。只有极简模式中招，因为四档 preset 里只有它挂持久 shell。
   - **修法**：用户根 `$DSH_HOME/.agent-presets/minimal-guix/` 是内置 `minimal` 的副本 + `shellPath: /run/current-system/profile/bin/bash`。该目录已纳管本包（源在 `dotfiles/mutable/agents/dsh/.local/share/dsh/.agent-presets/`，部署侧逐文件软链回源、进 Git），改源即时生效；`dsh update` 只管 `_cli` 与 profile bundles，不会碰它。
   - **为什么不能覆盖内置 `minimal`**：preset 根顺序是「shipped → 自定义 roots → user root」，且同 id **靠前者胜**，shipped 根永远排第一 → 同名 user preset 会被静默遮蔽。只能换个 id。
   - **为什么改仓库的 `cordis.patch.yml` 也不行**：`shellPath` 是 preset 组合文件里的**行配置**，不在 `agent-presets` 这一行的 config 里；顶层 patch 够不到它。
   - **升级后要重同步**：上游若改了 `minimal` 组合，副本会陈旧。diff 内置 `<dsh-agent-presets>/presets/minimal/agent.cordis.yml` 后重新套用 `shellPath`。
   - **连带坑**：`shellPath` 是**单个字符串**（schemastery `z.string()`），loader 不按空格切分，`confine()` 直接把它当 `argv[0]`。写 `/usr/bin/env bash` 会被当成一个文件名 → 同样 `ENOENT`。要 env 语义只能 `shellPath: /usr/bin/env` + `shellArgs: [bash, --noprofile, --norc, -i]`。
6. **第三方插件报 `cannot get property "webServer" without inject`（boot 崩溃）**：`ctx.connection.rpc.handle()` 内部在 **connection 插件自己的 scope** 解析 `webServer`（cordis shadow 语义，`this.ctx` 经 `createShadow` 指向服务方 context），而 bundle 的 `connection` 行只 inject 了 `webRuntime` → 任何调 `rpc.handle` 的插件（如 `dsh-remote-web-gateway`）都会炸掉整个 boot；`rpc.intercept`/`fetch.register` 不受影响。修法：profile `cordis.patch.yml` 给 `connection` 行补 `inject: [webRuntime, webServer]`（inject 是整表替换，原值须复述）。
7. **plugin-manager 装包会覆写 stow 软链**：UI/`dsh plugin` 安装插件时 pnpm 原地写 `profiles/web/package.json`，把回本仓库的软链替换成实体文件 → 源与部署侧静默分叉。**`dsh` wrapper 的 plugin 拦截已自动修复**（内容归源 + 重建软链 + lockfile 回源，见插件注意点 4）；若绕过 wrapper 直接跑了内部 CLI，手动把部署侧内容写回仓库源后 `ln -sfn` 恢复软链。
