# 系统级用户态配置

本目录部署到 `~/.config/`，覆盖容器策略、mihomo 代理、PipeWire/WirePlumber 音频与 XDG 用户目录。

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

## 关键约定

- **碎片按文件名排序加载**：PipeWire 与 WirePlumber 分别用 `pipewire.conf.d/`、`wireplumber.conf.d/`（Lua 脚本在 `wireplumber/scripts/`），文件名即加载顺序。
- **Containers**：`containers/policy.json` 决定镜像拉取的签名验证策略。
- **mihomo 模板链**：`config.yaml` 是模板不是生效配置。`mihomo-run`（`source/config.org` 内嵌脚本）被 shepherd 的 `mihomo-daemon` 调用，先解密 `mihomo-subscriptions.age`，再把 `$MIHOMO_SUB_ONE` / `$MIHOMO_SUB_TWO` 经 envsubst 渲染到 `/var/lib/mihomo/config.yaml` 才 exec mihomo（解密失败降级为空订阅直连，不会反复 respawn）。因此直接改 `/var/lib/mihomo/config.yaml` 会被下次渲染覆盖，换订阅只走 `secrets set mihomo-subscriptions MIHOMO_SUB_ONE "<url>"`（或 `secrets edit`）。
- **XDG 用户目录**：`user-dirs.dirs` 与 `user-dirs.locale` 由 `xdg-user-dirs` 读取。

## 修改与生效

- **通用**：改源后须 `blue home` 重建（部署进 Store 只读副本）。
- **音频**：改 `pipewire.conf.d/` 或 `wireplumber.conf.d/` 后 `herd restart pipewire`。
- **mihomo**：模板改动须 `blue home` 部署后 `sudo herd restart mihomo-daemon` 才会重新渲染；只换订阅则重启 daemon 即可。
- **用户目录**：改 `user-dirs.dirs` 后跑 `xdg-user-dirs-update` 或重新登录会话。
- **containers**：`policy.json` 只作用于后续镜像拉取，随部署生效，不必重启容器。
