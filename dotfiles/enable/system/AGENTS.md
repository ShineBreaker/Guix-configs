# 系统级配置

通过 Guix Home 部署到 `~/.config/`。本目录聚焦系统级用户态配置（容器、音频服务、XDG 用户目录），与桌面/主题无关。

## 目录结构

<!-- structor:begin -->

<!-- 此结构图由 maak structor 自动维护，请勿手改 -->

```
system/
└── .config/
    ├── containers/
    │   ├── containers.conf
    │   └── policy.json
    ├── pipewire/
    │   └── pipewire.conf.d/
    │       └── 10-latency-fix.conf
    ├── user-dirs.dirs
    └── user-dirs.locale
```

<!-- /structor -->
## 关键约定

- pipewire 配置使用 `pipewire.conf.d/` 目录，按字母顺序加载
- containers `policy.json` 定义镜像拉取签名验证规则
- `user-dirs.dirs` / `user-dirs.locale` 由 `xdg-user-dirs` 工具读取，定义 `Desktop`、`Documents`、`Downloads` 等

## 修改约束

- 修改后必须 `maak rebuild` 才会生效
- pipewire 配置修改后建议重启用户服务：`systemctl --user restart pipewire pipewire-pulse wireplumber`
- user-dirs 变更后重新登录或 `xdg-user-dirs-update` 让 XDG 感知