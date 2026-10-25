---
name: podman-non-systemd
description: Use when the user runs rootless Podman or podman-compose on a non-systemd Linux distribution (Guix, Artix, Devuan, etc.), encounters cgroup-related container start failures, or asks about container runtime configuration without systemd. Covers cgroup manager mismatch, cgroup_parent fix, crun vs runc, and keep-groups for device access.
---

# podman-non-systemd — Rootless Podman/Compose 在非 systemd 系统上的配置

> 非 systemd Linux 发行版（Guix、Artix、Devuan 等）跑 rootless Podman 时的常见问题与修复。

## 核心问题：cgroup 管理器不匹配

### 错误特征

```
Error: unable to start container <id>: systemd slice received as cgroup parent when using cgroupfs: invalid argument
```

### 触发条件

- 系统无 systemd（Guix 用 shepherd + elogind）
- `podman info` 显示 `cgroupManager: cgroupfs`
- `/proc/self/cgroup` 显示 `name=elogind:/` 而非 `name=systemd:/user.slice/...`

### 根因

Podman 默认用 `cgroupfs` 模式管理 cgroup，但容器元数据里记录的父节点是 systemd slice。在无 systemd 的系统里，这个父节点不存在或不兼容，导致启动失败。

### 修复

在 compose.yaml 的 service 块里加 `cgroup_parent: "/"`：

```yaml
services:
  mycontainer:
    image: ...
    container_name: MyContainer
    # ... 其他配置 ...
    group_add:
      - keep-groups
    cgroup_parent: "/"
```

`cgroup_parent: "/"` 告诉 Podman 把容器放到 cgroup 根节点，不尝试用 systemd slice 作为父节点。

### 完整修复流程

```bash
# 1) 删除残留容器（带错误元数据的）
podman rm <container_name>

# 2) 改 compose.yaml 加 cgroup_parent: "/"

# 3) 重新启动
podman-compose --file <path>/compose.yaml up
```

## 关联配置

### containers.conf

`~/.config/containers/containers.conf` 里确保 runtime 是 crun：

```toml
[engine]
runtime = "crun"
```

`runc` 在 rootless + keep-groups 场景下不工作，`crun` 才支持。

### group_add + keep-groups

rootless Podman 访问 `/dev/kvm` 等设备需要 `keep-groups`：

```yaml
group_add:
  - keep-groups
```

同时确保 crun runtime 已配置（见上）。

## 验证

```bash
# 确认 cgroup_manager 是 cgroupfs
podman info | grep cgroupManager
# → cgroupManager: cgroupfs

# 确认容器能正常启动
podman ps

# 确认 /dev/kvm 在容器内可用（如果挂了设备）
podman exec <container> ls -la /dev/kvm
```

## 适用范围

这是 **所有非 systemd 系统** 的通用问题，不限于特定应用：
- Guix System（shepherd + elogind）
- Artix Linux（OpenRC/s6/runit + elogind）
- Devuan（sysvinit/OpenRC + elogind）
- 任何 rootless Podman + cgroupfs 组合

## 注意事项

- `cgroup_parent: "/"` 是 compose.yaml / podman run 的**通用选项**，不限于 podman-compose
- 如果用了 `podman compose`（podman 4+ 内置子命令），行为相同
- 此修复不影响容器的资源限制（CPU/内存限制仍通过 cgroupfs 生效）
