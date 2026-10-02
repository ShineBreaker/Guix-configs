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

面板未运行就没有 socket，直接跳过不阻塞。**为什么要 load-config**：darkman hook 切主题时是以后代身份发的 RC 写，被 kitty 忽略，且面板处于 hidden 态时重载还会延迟，主题刷新只能靠呼出瞬间以会话身份手动刷一次。

## 系统与 GPU

### nixgpu-update

```bash
sudo nixgpu-update    # 建 /var/lib/non-nixos-gpu → /nix/store/<hash>-non-nixos-gpu
```

配合 shepherd service `non-nixos-gpu`：`/run/opengl-driver` 在 tmpfs 上、重启即空，service 启动时建链 `/run/opengl-driver → /var/lib/non-nixos-gpu`，`/var/lib/non-nixos-gpu` 才是持久化目标。

**调用时机：首次安装后跑一次，nix 重新部署（store hash 变化）后再跑一次。**

流程：

1. root 前置检查——写 `/etc` 与 `/var/lib`，非 root 会在中途留半成品，所以先查 `EUID` 直接退出。
2. `mkdir -p /etc/tmpfiles.d` 兜底（Guix 用 shepherd 而非 systemd，该目录默认不存在，setup 内部的软链会因父目录缺失失败），随后 `non-nixos-gpu-setup || true`（其末步 `systemd-tmpfiles --create` 在 Guix 上无此命令）。
3. 从 `/etc/tmpfiles.d/non-nixos-gpu.conf` 取 target：conf 格式为 `L+ /run/opengl-driver - - - - /nix/store/<hash>-non-nixos-gpu`，取末字段。
4. **强校验 `$target` 以 `/nix/store/` 开头**后 `ln -nsf "$target" /var/lib/non-nixos-gpu`——防止异常 conf 把链接指到任意路径。

三条错误文案可压成一行排障：`not found after non-nixos-gpu-setup` = setup 没产出 conf（nix profile 未装或版本旧）；`failed to parse target` = conf 格式变了，人工看 conf 调 awk 匹配；`target is not under /nix/store` = conf 内容异常，**不要**手工建链绕过。

### 40-force-unmute

WirePlumber 兜底脚本，加载 `~/.config/wireplumber/scripts/40-alsa/` 时自动注册。

监听 `node-state-changed` 事件，约束 `media.class=Audio/Sink` 且 `device.api=alsa`，只在 `new-state=running` 时处理：对 `direction=Output` 且 `route.device == card.profile.device` 的路由写 `mute=false` 再 `device:set_param("Route", …)`。

红线：

- **`save = false`**：只改运行时状态，不写回路由持久化，避免把兜底动作固化进用户配置。
- **目录名 `40-alsa`**：WirePlumber 按字典序加载脚本目录，`40-*` 先于上游 `50-alsa` 注册 hook，保证拦截时机。

## 凭据

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
