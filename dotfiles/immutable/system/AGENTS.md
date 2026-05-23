<!--
SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>

SPDX-License-Identifier: MIT
-->

# 系统级配置

通过 Guix Home 部署到 `~/.config/`。

## 结构

```
system/.config/
├── containers/          # Podman/容器配置
│   ├── containers.conf
│   └── policy.json          # 镜像签名策略
├── pipewire/            # 音频服务
│   └── pipewire.conf.d/
│       └── 10-latency-fix.conf  # 延迟优化
├── user-dirs.dirs       # XDG 用户目录
└── user-dirs.locale     # 用户目录语言
```

## 关键约定

- pipewire 配置使用 `conf.d/` 目录，按字母顺序加载
- containers policy.json 定义镜像拉取签名验证规则

## 修改约束

- pipewire 配置修改后需 `systemctl --user restart pipewire`
- user-dirs 修改后需重新登录或运行 `xdg-user-dirs-update`
