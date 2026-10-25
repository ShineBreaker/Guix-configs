# dsh 架构地图与集成接缝（server/client 形态）

做 dsh 架构级调研或集成（server 常驻、多客户端接入、backend 扩展）前先读这份地图。
事实核对本机 0.2.1-rc 线安装；跨版本使用前先抽查包是否仍在。

## 1. 组件与路径

| 层 | 路径 |
| --- | --- |
| CLI 本体（pnpm 聚合根） | `~/.local/share/agents/dsh/node_modules/@deepseek-ai/dsh` |
| profiles | `$DSH_HOME/profiles/<name>`（web / dsh-tui / headless / …） |
| 会话存储（全 profile 共享） | `$DSH_HOME/sessions/--<workspace 路径转义>--/` |
| wrapper 与 libexec | Guix-configs `dotfiles/mutable/agents/dsh/.local/{bin,libexec}` |

包生态速查：`ls ~/.local/share/agents/dsh/node_modules/.pnpm/ | grep <关键词>`
命中后读该包 package.json 的 `description`——每包一句话自述，是画依赖图最快的方式。
TUI 官方文档在 profile 内
`node_modules/@deepseek-harness-tui/dsh-tui/guide/dsh-tui-guide/`（含 claude/codex
backend、插件准入、VS Code 集成各专页）。

## 2. web 侧已是 server/client 架构

- `dsh web` 起的就是常驻 server：cordis 应用 + HTTP/WS（默认 127.0.0.1:3080），
  浏览器只是客户端。`dsh-web` wrapper 已幂等（端口探测在跑就不重启）。
- 认证握手：`/?token=<launch-token>` → 303 + Set-Cookie（约 30 天）→ WS RPC。
  token 一次性，`dsh web --reauth` 换新。
- RPC 三层（包名即职责）：
  - `dsh-client-connection` — 认证 RPC 传输。`client.node.js` 导出
    `installConnection`，Node 侧 carrier 是官方预留的非浏览器客户端入口。
  - `dsh-api-gateway` — 传输无关：进程内 carrier 或共享 WebSocket，同一套分帧。
  - `dsh-api-remotes` — 有类型的 Host 能力 BFF。README 明文：Web 或未来的
    TUI 只要提供同一份不依赖 React 的 `ctx.remote` 约定，均可复用其 Client face。

## 3. TUI 侧是 in-process backend

- `dsh-tui` 经 host-dsh adapter 在自己进程里 boot 一份 DSH 运行时
  （followLauncher 扫启动器文本定位宿主包），关 TUI 回合即断——这是它与
  hermes（gateway 常驻 + 客户端接入）的形态差异根源。
- 多内核架构：`DSH_TUI_BACKEND`（dsh / claude / codex）。backend = registry +
  manifest，`registerBackend()` 对插件开放（manifest 的 KernelLabel 规则里
  明确写了插件注册分支）——给 TUI 加新内核走这条路。
- TUI 无任何「连远程 Host」模式：无配置键、无 CLI flag、无环境变量。

## 4. 会话库跨端共享

`$DSH_HOME/sessions/` 按 workspace 路径组织、跨 profile 共享：TUI 的 `/resume`
与 web 的会话列表看到同一个库。「换端接力」天然可用；缺的只是「关掉客户端
任务继续跑」——即 server 常驻 + 客户端重连，不是会话迁移。

## 5. 上游集成约束（做改动前核对）

- 无受支持的「本地 UI attach 远程 Host」方式：Desktop 壳的 backend URL 是
  main() 内局部变量，无配置缝。浏览器 + tunnel + token 握手是唯一官方远程模式。
- 浏览器信任栅栏按 Host/Origin 判定：loopback 形状的 Host 头在认证层放行，
  非 loopback 直接 403。「把本地渲染的 UI 重定向到远程 authority」被构造性
  排除，不是未实现。`--trusted-host <authority>` 可显式加白（dsh-web wrapper
  用它信任尾网主机名）。
- 落地顺序：server 常驻用 home-shepherd service 跑 `dsh web --no-open`
  （等价 hermes gateway 常驻；注意复用 wrapper 的 `_relink_profile` 防 stow
  断链）；「TUI 连 server」优先等上游兑现 api-remotes 的承诺——自写 remote
  backend 插件需把 AgentSession 接口全量映射到 session-controller RPC
  （流式、取消、审批问询），成本高且易随上游漂移。

## 6. 调研技法

- `.pnpm` store 里每个包的 `lib/types/*.d.ts` 头注释写明包职责与边界，比
  README 快。
- 判断「某能力是否存在」：先 grep 环境变量面（如 TUI 的 `DSH_TUI_*` 全集），
  再 grep dts 声明——`declare module` 的接口扩展（如 `interface Context`）
  即官方插件接缝。
- 引擎版本注意：web profile 的 bundle 在 `profiles/web/package.json` 的
  `dsh.profile.bundles`，不在依赖树里查。
