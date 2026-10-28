<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# 零散脚本速查 — niri 桌面、系统与 GPU、凭据与 Live ISO

`dotfiles/immutable/{desktop,utilities,system}/` 与 `source/files/livecd/` · 前三者 immutable → `~/.local/bin/` / WirePlumber scripts（改后须 `blue home`），livecd 经 `local-file` 进 ISO · niri 键位绑定、手动调用或服务加载

本篇收纳互不相关但都很小的脚本：niri 桌面的两个入口、非 NixOS 主机的 GPU 链接、git 凭据配置管理、WirePlumber 兜底脚本与 Live ISO 的 fish 函数。

## niri 桌面

### niri-app-switcher

统一窗口切换器：`niri msg --json windows` 取运行中窗口 → 按规范应用名归组 → rofi 菜单按历史排序 → 聚焦该应用最近聚焦的窗口。调用方是 `dotfiles/immutable/desktop/.config/niri/settings/key-bindings.kdl`。

```bash
niri-app-switcher    # 呼出 rofi 菜单，选中后聚焦该应用最近聚焦的窗口
```

三个环境变量（默认值即正常使用路径）：

| 环境变量                        | 默认值                                    |
| ------------------------------- | ----------------------------------------- |
| `NIRI_APP_SWITCHER_CONFIG`      | `~/.config/niri/app-switcher.json`        |
| `NIRI_APP_SWITCHER_HISTORY`     | `~/.cache/niri-app-switcher-history.json` |
| `NIRI_APP_SWITCHER_ROFI_CONFIG` | `~/.config/rofi/config.rasi`              |

归组规则：`app_id` 命中配置里某个应用的 `match_app_ids` → 用该配置的键名；否则取 `app_id` 末段小写（`org.mozilla.firefox` → `firefox`）。`match_app_ids` 缺省或为空数组时回退为 `[key]`；**同一个 `app_id` 被多个 key 认领时只写 stderr 告警、不中止**。

窗口先按 `exclude_titles` 过滤，再归组；菜单按历史时间倒序，rofi 用 `-matching prefix -no-custom`。

红线：

- **`focus_timestamp` 是 `{secs, nanos}` 对象**，jq 直接 `max_by(.focus_timestamp)` 会先比 `nanos` 的**字段序**而非数值，必须拆成 `[.secs, .nanos]` 数组比较。
- **历史原子更新**：`mktemp` + `mv -f`；旧版历史把时间戳存成字符串，排序处用 `tonumber?` 兼容。
- **`--help` 不是纯帮助路径**：脚本不解析任何参数，传 `--help` 会照常启动切换器。`toolbox` 的 `tools.yaml` 不得为它登记 `help_cmd`。
- rofi 非零退出即取消（`|| exit 0`），Esc 不算错误；过滤后没有窗口时静默退出。
- 配置与历史文件缺失、损坏或为空一律回落 `{}`。

排障：菜单空 = 全部窗口被 `exclude_titles` 过滤（属预期）；应用名字不对 = `app_id` 与 `match_app_ids` 不匹配，用 `niri msg windows` 看实际 app_id 后补配置。

### niri-quake-toggle

Mod+grave 的薄壳入口，呼出 / 收起 kitty 的 quick-access 下拉面板：

```bash
niri-quake-toggle    # exec kitten quick-access-terminal "$@"
```

socket 发现用 `awk` 扫 `/proc/net/unix` 找 `quick-access-` 后缀的 kitty 控制 socket；找到且 `kitten` 可用时先 `kitten @ --to unix:$sock load-config`（静默容错），最后 `exec kitten quick-access-terminal "$@"` 收尾——**进程替换**，信号与退出码直透。

面板未运行就没有 socket，直接跳过不阻塞。**为什么要 load-config**：主题切换链（mode.d hook → nosd-helpers apply）发起的 RC 写会因后代身份被 kitty 忽略，且面板处于 hidden 态时重载还会延迟，主题刷新只能靠呼出瞬间以会话身份手动刷一次。

## 系统与 GPU

### 40-force-unmute

WirePlumber 兜底脚本，加载 `~/.config/wireplumber/scripts/40-alsa/` 时自动注册。

监听 `node-state-changed` 事件，约束 `media.class=Audio/Sink` 且 `device.api=alsa`，只在 `new-state=running` 时处理：对 `direction=Output` 且 `route.device == card.profile.device` 的路由写 `mute=false` 再 `device:set_param("Route", …)`。

红线：

- **`save = false`**：只改运行时状态，不写回路由持久化，避免把兜底动作固化进用户配置。
- **目录名 `40-alsa`**：WirePlumber 按字典序加载脚本目录，`40-*` 先于上游 `50-alsa` 注册 hook，保证拦截时机。

## 凭据

github.com 的 git 凭据**不走 keepassxc**：`~/.config/git/config`（本仓库 `dotfiles/immutable/utilities/.config/git/config`）为 `https://github.com` 与 `https://gist.github.com` 配了 URL 级 credential helper，直接调 `gh auth git-credential`——单一事实源是 `gh auth login`（`~/.config/gh/hosts.yml`），token 轮换只需重跑 `gh auth login`，无需动 keepassxc。URL 级 `helper = ""` 先清空全局 helper 列表，防止 keepassxc 抢先弹窗；keepassxc 只服务 codeberg 等其余 host。

`~/.config/nix/gh-token.conf`（nix access-tokens）与 fish 的 `GITHUB_TOKEN`/`GH_TOKEN` 导出同源 gh，token 过期后用 `gh auth token` 重新同步。

### keepassxc-credential-setup

管理 `~/.config/git-credential-keepassxc`（JSON，分 `databases` 与 `callers` 两段）。`callers` 登记「谁被允许向 KeePassXC 要凭据」，git 凭据 helper 实际由 `libexec/git-core/git` 触发。

```bash
keepassxc-credential-setup status    # 检查配置健康状态（发现问题返回非零）
keepassxc-credential-setup init      # 初始化完整配置（databases + callers）
keepassxc-credential-setup update    # 检测并更新过期的 callers 路径
keepassxc-credential-setup callers   # 仅重新注册 callers（不影响 databases）
```

四个子命令的语义差异：**`init` 连带初始化 databases**（走 `git-credential-keepassxc configure`）；**`update` 与 `callers` 只重写 callers 段**，不碰用户已配的 databases（`update` 发现 databases 为空时会先补一次 configure）。

`init` 在配置文件已存在时直接拒绝并提示先备份删除，不会覆盖既有配置。`status` 发现问题时返回非零。

红线：

- **`expected_callers` 是当前系统预期路径的单一事实来源**：新增调用方（如新的 git 前端）只改这一个函数，`status` 与 `update` 自动跟随。它 `readlink -f` 解 fish 与 git，**git 优先取 `<prefix>/libexec/git-core/git`**（helper 的真实调用者），不存在才回落 git 本体。
- **`callers` 数组必须用 jq 重写**，不能用 `caller clear` / `caller add`——clear 之后 bash 自身也会被拦截。写入走 `mktemp` + `mv` 原子替换。
- **包升级后 store hash 变化会让已登记路径过期**，这是 `status` / `update` 存在的理由。

典型症状：git 拉取时 KeePassXC 不弹授权——先 `status` 确认，再 `update` 刷新路径。

## 家目录体检

### home-health

只读体检 `$HOME`，一页输出五段：磁盘占用、HOME 顶层 top 15、会长胖的目录、仓库同步债、可回收空间与包管理器缓存。**不删任何东西**，所有"可回收"项只是报告，真清走 `trash-put` 保持可逆。

```bash
home-health
```

设计取向：**报告而非治理**。它不判定任何目录"该不该清"——哪些该留只有用户知道（Steam 沙箱数据、某个还在用的 agent 家目录），脚本越权判定就会重演"看起来很对的误判"。它只保证两件事：**让人一眼看清全部**（可见性），以及**让持续增长变得可观测**（包管理器缓存单列一节，因为那是唯一一类清了绝对安全、且会立刻再长回来的空间）。

仓库同步债一节扫 `~/Projects` 下所有 git 仓库，只列 dirty / unpushed / behind 非零的。它的优先级高于一切空间清理——本地未推送的 commit 等于没有备份。

## Live ISO

### livecd fish 函数

`source/files/livecd/.config/fish/functions/{fish_greeting,fish_prompt}.fish`，经 `source/config.org` 的 `local-file` 进 store，**文件名与路径不可改**；改内容需 `blue build-iso` 重出镜像，运行中改源码不影响已出的 ISO。

`fish_greeting` 是救援速查表，输出契约固定：

```
Guix Rescue/Install Live — live/live · root/live
network : nmtui          rescue : sudo rescue-chroot.sh status|mount|chroot|umount
install : cp -r ~/Guix-configs ~/cfg && ~/cfg/tools/emergency-blue.sh init /mnt
manual  : info guix      README : ~/Desktop/README.txt
```

`fish_prompt` 用 `set_color` 渲染两段：提示符独占一行且 `fish_prompt_pwd_dir_length 0` 让目录名不截断，后缀 `❯`（root 为 `#`）默认 `brgreen`，`$status` 非零时状态码 `[N]` 换成 `$fish_color_error` 并插在 cwd 与 VCS 之后。

与主配置的 `functions/fish_prompt.fish` 是**两套独立实现**：livecd 版面向救援（状态码醒目、目录不截断），主配置版面向日常（Informative 风格两行式），互不同步。
