<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# nixgpu-update — 非 NixOS 主机 GPU 链接建立

- 源码：`dotfiles/immutable/utilities/.local/bin/nixgpu-update`
- 部署：`~/.local/bin/nixgpu-update`（immutable，改后需 `blue home`）
- 调用方：手动（需 root）

## 用法

```bash
sudo nixgpu-update    # 建 /var/lib/non-nixos-gpu → /nix/store/<hash>-non-nixos-gpu
```

调用时机：首次安装后跑一次；nix 重新部署后（store hash 变化）再跑一次刷新链接。

## 依赖

`non-nixos-gpu-setup`（nix profile 提供）、root 权限（写 `/etc` 与 `/var/lib`）。

## 工作原理

配合 shepherd service `non-nixos-gpu`：`/run/opengl-driver` 在 tmpfs 上重启即空，service 启动时建链 `/run/opengl-driver → /var/lib/non-nixos-gpu`，`/var/lib/non-nixos-gpu` 是持久化目标，本脚本负责把它建好。

流程：

1. `mkdir -p /etc/tmpfiles.d` 兜底（Guix 主机上该目录默认不存在——Guix 用 shepherd 而非 systemd，`non-nixos-gpu-setup` 第 2 步软链会因父目录缺失失败），然后 `non-nixos-gpu-setup || true`（新版 setup：删旧 `/etc/systemd/system/non-nixos-gpu.service`、软链 tmpfiles conf 到 store、尝试 `systemd-tmpfiles --create`——Guix 上无该命令，`|| true` 容错）。
2. 从 `/etc/tmpfiles.d/non-nixos-gpu.conf` 读 target（conf 格式 `L+ /run/opengl-driver - - - - /nix/store/<hash>-non-nixos-gpu`，取末字段）。
3. `ln -nsf $target /var/lib/non-nixos-gpu`。

## 设计决策与不变量

- **root 前置检查**：写 `/etc` 与 `/var/lib`，非 root 会在中途留半成品，先 `EUID` 检查直接退出。
- **target 前缀强校验**：`$target` 必须 `/nix/store/*`——防止异常 conf 把链接指到任意路径。
- setup 失败不致命（`|| true`）：真正必需的产物是 conf 文件，后续步骤自行校验它的存在与可解析性。

## 故障排查

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| `not found after non-nixos-gpu-setup` | setup 未产出 conf（nix profile 未装/旧版） | 确认 `non-nixos-gpu-setup` 存在且为新版本 |
| `failed to parse target` | conf 格式变了 | 人工查看 conf，调整 awk 匹配 |

## 变更记录

无破坏性改动（本次重构只压缩注释）。
