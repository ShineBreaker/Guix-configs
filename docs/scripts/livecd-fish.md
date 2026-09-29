<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# livecd fish — Live ISO 的 fish greeting 与 prompt

- 源码：`source/files/livecd/.config/fish/functions/{fish_greeting,fish_prompt}.fish`
- 部署：Live ISO 内 `~/.config/fish/functions/`（经 `source/config.org` 的 `local-file` 引用，**文件名与路径不可改**）
- 调用方：Live ISO 内 fish 启动

## fish_greeting

打印救援/安装速查：live/live 凭据、`nmtui` 联网、`sudo rescue-chroot.sh status|mount|chroot|umount` 救援、`tools/emergency-blue.sh init /mnt` 安装入口、`info guix` 与桌面 README 指引。

## fish_prompt

`set_color` 渲染的两段提示符：`$status` 非零时 `brgreen` 显示状态码、cwd 用 `fish_color_cwd`（root 时换 `fish_color_cwd_root`）、VCS 用 `brpurple`、后缀 `❯`（root 为 `#`）。`fish_prompt_pwd_dir_length 0` 让目录名不截断。

## 设计决策与不变量

- 与主配置的 `functions/fish_prompt.fish` 是**两套独立实现**：livecd 版面向救援场景（状态码醒目、目录不截断），主配置版面向日常（Informative 风格两行式）。
- 两文件经 `local-file` 进 store——改内容需 `blue build-iso` 重出镜像，运行中改源码不影响旧 ISO。

## 变更记录

- 2026-09-29：仅补 doc 指针头注（行为不变）。
