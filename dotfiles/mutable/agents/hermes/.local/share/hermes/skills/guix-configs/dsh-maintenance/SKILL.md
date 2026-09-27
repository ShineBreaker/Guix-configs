---
name: dsh-maintenance
description: Use when installing, updating, or removing dsh (DeepSeek Harness) plugins and profiles.
---

# dsh-maintenance — dsh 更新、验证与源同步

dsh 经 pnpm 装在 `$DSH_HOME/_cli`（本体）与 `$DSH_HOME/profiles/web`（插件），配置源在
Guix-configs 仓库 `dotfiles/mutable/agents/dsh/`，GNU Stow no-folding 逐文件软链。插件语义、
版本锁定、远程访问、排障细节以仓库内 `dotfiles/mutable/agents/dsh/AGENTS.md` 为权威，本
skill 不重复，只覆盖「更新 → 验证 → 源同步」工作流及其静默失败点。

## 0. 环境前置（每次都要）

- pnpm 只在 nix profile，非登录 shell 的 PATH 里没有。任何 dsh 更新命令前：
  ```bash
  export PATH="$HOME/.local/state/nix/profiles/profile/bin:$PATH"
  ```
  否则 `dsh update` 以 "找不到 pnpm" 127 退出。
- 被提升为 background 的 terminal 可能丢掉前台的 export：同一条命令里用
  `PATH="$HOME/.local/state/nix/profiles/profile/bin:$PATH" <绝对路径>/dsh ...` 前缀赋值 +
  绝对路径调用最稳，别只写 `dsh` 依赖 PATH 解析。

## 1. 更新流程

```bash
dsh update --check          # 只查差异；退出码 0=已最新，1=有更新
dsh update --yes --restart  # 执行 + 后台 dsh web --reauth 重启
```

- 本体与 web 插件两层强绑定一起升；差异列表即更新面（按通道稳定性 latest→next→
  beta→alpha 选版，24h 冷却内的版本由 pnpm 自动写 minimumReleaseAgeExclude 豁免）。
- `link:` 本地插件（dsh-agenote / dsh-agent-extensions）不参与自动更新，只在输出里
  列提示。
- `--restart` 换新 launch token；cookie 由 `.credentials.yaml` 持久化密钥签名（30 天），
  浏览器旧窗口重连即可，不需要用户重新认证。
- 跑完再执行一次 `dsh update --check`，应报已是最新——同时验证版本声明与 lockfile
  回源一致。

## 2. 升级后验证（三步全绿才算完成）

### 2.1 bundle 解析健康

```bash
grep -c "skipping profile bundle" ~/.local/state/dsh/web.log   # 必须为 0
```

核心升级后逐个核对 `profiles/web/package.json` 的 `dsh.profile.bundles`：上游会把
bundle 移出依赖树（实例：`@deepseek-ai/dsh-experimental-agent-team-web-profile` 曾随
`@deepseek-ai/dsh` 分发、后不再随核心分发），残留行启动时逐次 skipping——非致命但属
配置陈旧，从 bundles 删除、同步部署侧后重启。其余错误判轻重：上游插件自身的路由重复
注册（devin-cli 的 `/devin-cli`）只影响它自己的 fallback，非致命，等上游修。

### 2.2 页面 entry 清单

agent 会话没有 `WAYLAND_DISPLAY`，chromium 窗口必然起不来——服务本身已正常监听，
验证走 HTTP：

```bash
token=$(grep -oP 'token=\K\S+' ~/.local/state/dsh/web.log | tail -1)
curl -s -c /tmp/ck.txt "http://127.0.0.1:3080/?token=$token" -o /dev/null  # token 换 cookie
curl -s -b /tmp/ck.txt "http://127.0.0.1:3080/" -o /tmp/page.html          # 应 200
```

`__DSH_BOOT__` 的 entries 即加载的 client 插件清单（典型约 70 条）：从 `{"rev"}` 起按
花括号配平切出 JSON 再 `json.loads`。核对关注插件在列（dsh-agent-extensions、
dsh-context、dsh-opencode-go 等）；host 半边插件不出现在 entries 里属正常——
llm-pi-ai 是 dormant 挂载（settings 供 provider 前零路由），无 client entry。

### 2.3 源 / 部署一致性

```bash
for f in package.json pnpm-lock.yaml pnpm-workspace.yaml cordis.patch.yml; do
  cmp -s <仓库源>/profiles/web/$f ~/.local/share/dsh/profiles/web/$f || echo "DIFF $f"
done
# _cli 侧同理核对 package.json / pnpm-lock.yaml / pnpm-workspace.yaml
```

任一项 DIFF = 部署链路断了，见 §3。只查 lockfile 会漏掉配置分叉。

## 3. 源同步陷阱（本类任务最容易静默出错的地方）

- **pnpm 原地覆写 stow 软链**：`pnpm add/install` 把 `package.json`、
  `pnpm-workspace.yaml` 写成真实文件（lockfile 更是 pnpm Rust 端拒写软链），部署侧与
  仓库源从此分叉，且 git 看不到部署侧。
- **dsh web 运行期也覆写 `cordis.patch.yml`**：设置页改偏好、配模型 provider 都经
  config editor 的 `writeFileAtomic` 落盘，软链同样被替换——**用户在 UI 里做的模型
  配置可能只存在于部署侧**，仓库源是旧的。
- **回源路径不得从部署侧软链推导**：`readlink <dir>/pnpm-workspace.yaml` 在该文件已被
  覆写成真实文件时失败；若脚本在此处静默 return，后面全部回源一起被跳过。从 stow 包内
  脚本自身位置反推（`readlink -f "${BASH_SOURCE[0]}"` → 包根 → `share/dsh`），源布局与
  部署布局同构，不依赖任何软链存活。
- **wrapper 自愈面有限**：`bin/dsh` 的 `_relink_profile` 只在 `plugin` 子命令后自愈
  `package.json`，`cordis.patch.yml` 不在其列；全量回源只发生在 `dsh update`
  （lockfile / package.json / pnpm-workspace.yaml / cordis.patch.yml 四件套）。
- **发现分叉时以部署侧为基线拷回源**——用户在 UI 改过的配置是事实源；回源后按 §2
  重启验证，别反过来把旧源覆盖上去。
- **`_relink_profile` 自愈建的绝对软链会被 stow 拒绝接管**：它用 `ln -sfn <绝对路径>`
  重建链接，而 stow 只认相对链接——`--restow` 报 `Ignoring an absolute symlink` +
  `existing target is not owned by stow` 并**全量中止**（一条不清，整包不部署）。修法：
  `trash-put` 掉那条绝对软链再 restow，stow 会用相对路径重建。pnpm 把配置写成实体
  文件后的 `neither a link nor a directory` 冲突同理：内容已在源里，trash 部署侧实体
  文件即可，**不要** `--adopt`（那会把部署侧当基线反向覆盖源）。
- **`blue stow` 的包参数是 `agents/dsh`**（stow dir = `dotfiles/mutable/agents`）：写
  `dsh` 报「stow 包不存在: .../dotfiles/mutable/dsh」，别顺着报错去建同名目录。
- **提交前核对暂存清单恰好等于本次任务文件表**：上个会话遗留的 staged 文件不会
  被你的 `git add -- <路径>` 排除，会静默混进你的提交。先
  `git restore --staged <遗留路径>` 剔出，再 `git diff --cached --name-only` 核对。
  修正形态：`git reset --soft HEAD~N`（禁 `--hard`）后按正确清单重提。
- **`git commit` 只接受 `-m`**：gate 拒 `-F` 与 heredoc（`git commit 必须使用
  -m 指定提交信息`）。多段 body 用多个 `-m` 按序拼（header / why / trailer
  各一个）；不要为了凑一条完整消息去试 `-F /tmp/msg` 或 `commit -F -`。
- **署名必须是当前 agent 名 + 实际模型**：仓库配置（SOUL.md 的 commit 偏好、
  agent skill 的 commit 规范、wrapper 头注释）可能残留**别的 agent** 的
  attribution 规定，照抄会让作者信息张冠李戴。发现规定与实际 agent 不符时先改
  配置源头（那是根因，否则后续会话继续抄），再改已写错的提交。

## 4. 新插件装入新 profile（安装 → 验证 → 源同步）

自带 agent preset / 独立 launcher 的插件（TUI 类、终端类）**装独立 profile**，与
`_cli`、`web` 平级——并进 web profile 会把它的 preset 行注册进 web 的组合，两边的
预设、shell 方言、渲染方式都不同。完整操作配方见
`references/dsh-plugin-profile-install.md`，本节只列判据。

```bash
~/.local/bin/dsh plugin --profile <name> allow-version <pkg>@<ver> --dsh-version <core> --accept-risk
~/.local/bin/dsh plugin --profile <name> add -w <pkg>@<ver>
```

- **`compatibility.json` 是 boot 必需文件**：删掉它 compat 门直接静默跳过整条
  bundle（dump-config 条目数掉下去、零报错），症状是「插件装了却什么都不显示」。
  它记录 allow-version 授权，必须进仓库源（新机复现的一部分）。
- **验证三连**：`dsh --profile <name> --dump-config | grep -c '^- id:'` 对基线；
  `grep -c '^- id: <bundle-id>$'` 精确到条；插件自带 launcher 的再跑其
  `doctor` 子命令。缺 compat 授权时做一次「移走 compatibility.json → 条目下降 →
  放回」的删除测试，把基线数字钉住。
- **alt-screen CLI 的 boot 冒烟看 session 文件，不看 stdout**：ink 类 TUI 的
  alt-screen 会吞掉全部日志，`script -qfc` 抓到的 6 字节 `ESC[?25l` 就是已进入渲染
  阶段的证据；再核
  `~/.local/share/dsh/sessions/--<profile 路径转义>--/*/session.v4.jsonl.zstd`
  （`zstd -dc` 首行读 `agentPreset`）。被杀时未 flush 的只剩 `session.lock` +
  `.tmp`，找完整落盘那个。agent 伪终端里的 `setRawMode EIO` 是固有噪声，**不是**
  失败判据；真机 TTY 下没有。
- **profile 层 patch 打不到 preset 里的行**：preset 组合行要等 preset 挂载后才
  存在，提前写 `- id: <preset 内 id>` 每次 boot 都报
  `patch: entry "<id>" not found`。要改 preset 行（如 Guix 无 `/bin/bash` 的
  `shellPath`），照 web 侧 `preset-minimal-guix` 先例整块复制 + 换 id + 保留改动
  （registry 按 `config.id` 去重，同 id 覆盖直接抛 `Duplicate agent preset`）。
- **双态 launcher 挂 libexec，不新增 `~/.local/bin` 入口**：npm 包的 bin 常是
  「profile 内完整副本 + 全局瘦壳」双态，`version`/`doctor`/`safe`/`update` 等
  子命令只在完整副本层。新建 `.local/libexec/<name>` 直接 exec profile 内副本，
  在既有 wrapper 的 case 分发点加一行透传；上游原生已有同名子命令时属**遮蔽**，
  注释里写明原生行为只能经 `$_cli_bin` 直调。
- **新 profile / 新入口必须同步仓库 `agents/dsh/AGENTS.md`**（布局表加行 + 专节写
  安装命令、compat 门、版本线判据），否则文档与实现漂移，下次没人记得
  `compatibility.json` 不能删。编辑门禁可能拦下 AGENTS.md 的首次写入（提示
  超时未获同意）；重试一次，仍被拦则如实上报「待补文档」，不要静默跳过——
  用户说「再试试」就是明确的重试授权。

## 5. 收尾

- 改动全部落在仓库源（mutable stow 包，改源即时生效；包内新增文件才需要
  `blue stow --restow agents/dsh`；不需要 `blue home`，更不需要 sudo）。
- `git diff` 核对后按 Conventional Commits 提交，遵守逐文件精确 add 的 commit 边界；
  运行中的 dsh web 持有旧模块图，最终以 `dsh web --reauth` 重启后的 §2 验证为准。
