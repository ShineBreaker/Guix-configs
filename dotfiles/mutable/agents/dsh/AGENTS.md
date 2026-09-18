# agents/dsh — DeepSeek Harness 配置与部署

本目录为 DeepSeek Harness（DSH，一切皆插件的 Agent Harness 框架）的 Guix 部署包。
本包映射到 `$HOME`，通过 GNU Stow 逐文件软链到系统。

## 目录与文件布局

| 路径                                    | 说明                                                                                                 |
| --------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| `~/.local/share/dsh/`                   | `$DSH_HOME`，为真实目录，配置文件逐个软链回本包（采用 no-folding 模式）                              |
| `.local/share/dsh/cordis.patch.yml`     | `$DSH_HOME` 顶层的 cordis 补丁配置                                                                   |
| `.local/share/dsh/_cli/`                | CLI 本体源：仅托管 `package.json` 与 `pnpm-workspace.yaml`；`node_modules/` 与 Lockfile 为运行时产物 |
| `.local/share/dsh/profiles/web/`        | Web Profile：托管 `cordis.yml`、`cordis.patch.yml`、`package.json`、`pnpm-workspace.yaml` 等配置     |
| `.local/bin/dsh`                        | CLI 启动包装器：注入 `DSH_HOME`；CLI 缺失时可交互式自动安装，或通过 `dsh --install` 无人值守安装     |
| `.local/bin/dsh-web`                    | Desktop 启动入口：启动后台服务并在独立的 Chromium App 窗口中打开                                     |
| `.local/bin/dsh-update`                 | 一键更新本体与三个插件（见「一键更新」）                                                             |
| `.local/share/applications/dsh.desktop` | 桌面快捷方式，其 `StartupWMClass` 与窗口 `app_id` 成对绑定                                           |
| `.local/share/icons/hicolor/`           | 图标：`48x48/apps/dsh.png` 为栅格图标，`scalable/apps/dsh.svg` 为矢量母版                            |

> **忽略规则**：`.credentials.yaml`（API 密钥）、`sessions/`、`storages/`、`node_modules/`、`pnpm-lock.yaml` 等运行时产物已被 `.stow-local-ignore` 防御性排除。

## 安装通道与升级

- **安装机制**：DSH CLI 本体（当前为 0.1.5-rc.1）通过 pnpm 安装在 `_cli/` 目录中。
- **升级步骤**：修改源码中 `.local/share/dsh/_cli/package.json` 的版本号 → 在 `_cli/` 目录中执行 `pnpm install`。插件同理改 `profiles/web/package.json`。日常更新直接跑 `dsh-update`（见「一键更新」），它会同时处理本体与插件，并在插件的兼容声明不含目标本体版本时给出提醒。
- **Workspace 配置**：`_cli/pnpm-workspace.yaml` 设置了 `minimumReleaseAge: 0`（适配预览期的日更版本，避免 24h 供应链冷却拦截）以及 `allowBuilds`（批准 node-pty、koffi、protobufjs 等原生编译依赖）。插件侧 `profiles/web/pnpm-workspace.yaml` 同理。

## 插件管理（Web Profile）

添加插件推荐使用 `dsh plugin --profile web add <pkg>@<ver>` 命令。它会在 profile 目录运行 pnpm，并将依赖自动写入 `dsh.profile.bundles`。

> **重要规则**：必须锁定**精确版本**，避免依赖漂移导致插件与 DSH 核心版本不兼容。

| 插件                                 | 当前版本       | 说明                                                                               |
| ------------------------------------ | -------------- | ---------------------------------------------------------------------------------- |
| `dsh-better-sidebar`                 | 0.19.1         | 侧边栏工作台：集成文件编辑、内置终端（xterm + node-pty）、Git 差异与后台任务管理   |
| `dsh-context`                        | 0.53.3         | 上下文监控面板：展示 Agent 组合、趋势分析、文件活动与 Agent 通信网络               |
| `dsh-dream-skin`                     | 9.16.0         | 原生主题换肤：通过官方 `ctx.theme.register` / `overrideTokens` 实现原生 Token 换肤 |
| `@opencode2dsh/dsh-plugin`           | 0.3.2          | OpenCode Zen 免费通道：原生 LLM adapter，无凭据零配置                              |
| `dsh-opencode-go`                    | 0.1.4          | OpenCode Go 订阅接入：网关模型目录 + 订阅额度显示                                  |
| `@mars-sea/dsh-commandcode-provider` | 0.11.5         | Command Code 接入：全套餐、浏览器内 OAuth 登录、多账户轮换                         |
| `dsh-devin-cli`                      | 0.4.2 @06a9c61 | 本地 Devin CLI 经 stdio ACP 接入（git 锁 commit，不参与自动更新）                  |

### 插件常见问题与注意点

1. **供应链冷却**：pnpm 会自动将 `minimumReleaseAgeExclude` 写入 profile workspace，确保新发插件正常拉取。
2. **原生模块编译**：涉及 native 依赖时需执行 `pnpm approve-builds`（配置项为 `allowBuilds`）。
3. **服务重启**：安装新插件后须重启 `dsh web`。若首次加载时页面漏掉插件条目，对浏览器进行一次硬刷新（Ctrl+F5）即可恢复。
4. **软链断链**：`dsh plugin add/remove` 写 `dsh.profile.bundles` 走原子替换（临时文件 + rename），会把 `profiles/web/package.json` 的 stow 软链换成独立文件——dependencies 更新进仓库源、bundles 却只落在部署侧。跑完 `ls -la` 验证；断了就把部署侧内容写回源文件，再 `ln -sfn` 重建软链（pnpm 自身的写入不会断链，只有 dsh 的 bundles 写入会）。

## 一键更新（dsh-update）

`dsh-update` 把本体与 web profile 的全部插件一起升到上游最新（插件清单从 `package.json` 的 dependencies 动态读取）。两层强绑定，故不提供只升一层的开关。

```bash
dsh-update --check           # 只查差异；退出码 0=已最新，1=有更新
dsh-update                   # 列出差异，确认后执行
dsh-update --yes --restart   # 一键：跳过确认，并在更新后重启 dsh web
```

- **选版不跟 npm 的 `latest` tag**：DSH 全是 preview 版本，发布者把 `latest` 停在保守位（`0.1.5-rc.2` 发布时 `latest` 仍是 rc.1）。脚本按通道稳定性 `latest → next → beta → alpha` 取第一个高于当前的版本，来源通道在输出里标出。
- **版本锁精确**：用 `pnpm add -E`（`--save-exact`）。pnpm 默认写 `^`，那正是依赖静默升到不兼容版本的成因。
- **不手写 YAML**：显式 `pnpm add <pkg>@<ver>` 时，pnpm 会自动把仍在 24h 供应链冷却期内的版本写进 workspace 的 `minimumReleaseAgeExclude`。脚本只提示、不自己改这两个配置文件。
- **兼容性提醒**：读插件的 `dsh.compatibility.dshReleases`（发布方自列的已验证版本白名单）。多数插件没有这个字段，那不代表不兼容，故只在「声明了白名单却不含目标版本」时才提醒。
- **源码锁定的依赖不自动更新**：`github:` / `git+` / `file:` / `link:` 这类依赖没有可比较的 registry 版本，脚本只列出提示。升级要手动换 commit——注意 git 插件的 `allowBuilds` 放行 key 绑定在 commit 上，换 commit 须同步替换（pnpm 报 `ERR_PNPM_GIT_DEP_PREPARE_NOT_ALLOWED` 时会打印新 key）。
- **生效**：更新后须重启 `dsh web`（host 半边不热载）。`--restart` 会调 `dsh-web --reauth`。

> **改的是仓库源文件**：`package.json` 与 `pnpm-workspace.yaml` 由 pnpm 原地写入（两者都是回本包的软链），跑完 `git diff` 后提交。

## 图标与桌面集成

- **图标查找**：`dsh.desktop` 使用 `Icon=dsh` 主题名，图标按 hicolor 布局存放（`hicolor/48x48/apps/dsh.png` + `hicolor/scalable/apps/dsh.svg`）。
- **SVG 母版与栅格化**：`scalable/apps/dsh.svg` 为矢量母版。若需重新生成 PNG 图标，执行以下命令：
  ```bash
  cd dotfiles/mutable/agents/dsh/.local/share/icons/hicolor
  rsvg-convert -w 48 -h 48 scalable/apps/dsh.svg -o 48x48/apps/dsh.png
  ```
- **刷新 Dock 缓存**：修改图标后通知 Noctalia 刷新：`noctalia msg dock-reload`。

## 窗口管理与 Wayland 适配

- `dsh-web` 使用 Chromium `--app=<url>` 模式拉起无浏览器边框的独立窗口，自动继承 Niri 的全局圆角与阴影特效。
- **窗口 App ID**：通过 `--profile-directory=dsh` 将窗口 ID 固定为 `chrome-127.0.0.1__-dsh`，与 `dsh.desktop` 中的 `StartupWMClass` **严格成对绑定**。修改时两处须同时修改。
- 独立 Profile 同时将 DSH 的会话 Cookie 与日常浏览器的默认配置隔离开。

## 认证与会话机制

- **启动 Token**：进程启动时生成随机 Launch Token，仅供包装器脚本一次性换取 Session Cookie。
- **持久化 Cookie**：换取的 Cookie 由 `$DSH_HOME/.credentials.yaml` 中的持久化密钥进行 HMAC-SHA256 签名，默认有效期为 30 天，**跨服务重启依然有效**。
- **重新认证**：若需强制重置凭据，执行 `dsh-web --reauth` 即可安全终止旧实例并重新握手。

## 排障指南

1. **端口冲突**：服务启动失败时优先检查 3080 端口占用。使用 `ss -tlnp` 精确查找对应 PID 并处理。
2. **日志排查**：服务标准输出记录在 `~/.local/state/dsh/web.log`（权限 600），包含详细启动与 Token 信息。
3. **UI 缺失**：页面插件未渲染时先进行浏览器硬刷新；若仍缺失，检查 `__DSH_BOOT__.entries` 加载条数。
4. **环境变量覆盖**：
   - `DSH_WEB_PORT`：自定义 Web 监听端口（更换端口会使 Cookie 重新握手）。
   - `DSH_WEB_LOG`：自定义日志输出路径。
   - `DSH_HOME`：覆盖默认 DSH 数据主目录。
