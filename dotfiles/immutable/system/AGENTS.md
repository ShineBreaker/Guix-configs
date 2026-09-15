# 系统级用户态配置

本目录通过 Guix Home 部署到 `~/.config/`，专注系统底层相关的用户态配置（容器策略、PipeWire 音频服务、XDG 用户目录等），与桌面视觉主题解耦。

## 目录结构

<!-- structor:begin depth=2 -->

<!-- 此树形目录由 structor 自动生成，请勿手动编辑。 -->

```
system/
└── .config/
    ├── containers/
    ├── mihomo/
    ├── pipewire/
    ├── wireplumber/
    ├── user-dirs.dirs
    └── user-dirs.locale
```

<!-- /structor -->

## 关键约定与机制

- **PipeWire / WirePlumber**：配置碎片分别放置于 `pipewire.conf.d/` 与 `wireplumber.conf.d/`（Lua 脚本在 `wireplumber/scripts/`），按字母字典序加载。
- **Containers**：`containers/policy.json` 声明镜像拉取时的签名验证策略与安全规则。
- **XDG 用户目录**：`user-dirs.dirs` 与 `user-dirs.locale` 声明用户标准目录（下载、文档、音乐等），由 `xdg-user-dirs` 读取。
- **mihomo**：`config.yaml` 是模板而非生效配置。`mihomo-run` 启动包装（见 `config.org`）先解密 `mihomo-subscriptions.age`，再把 `$MIHOMO_SUB_ONE/TWO` 占位符经 envsubst 渲染到 `/var/lib/mihomo/config.yaml`。改模板：`blue home` + `sudo herd restart mihomo-daemon`；换订阅：`secrets set mihomo-subscriptions MIHOMO_SUB_ONE "<url>"`（或 `secrets edit`）+ 重启服务。

## 修改与生效流程

1. 修改仓库源码后，运行 `blue home` 完成部署。
2. **音频服务重启**：修改 PipeWire/WirePlumber 配置后，运行 `herd restart pipewire` 重启服务。
3. **用户目录更新**：修改 `user-dirs` 变更后，运行 `xdg-user-dirs-update` 或重新登录会话。
4. **mihomo 生效**：模板改动在 `herd restart mihomo-daemon`（重新渲染）后才生效。
