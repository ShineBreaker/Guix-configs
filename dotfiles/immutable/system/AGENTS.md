# 系统级配置

通过 Guix Home 部署到 `~/.config/`。本目录聚焦系统级用户态配置（容器、音频服务、XDG 用户目录），与桌面/主题无关。

## 目录结构

<!-- structor:begin depth=4 -->

<!-- 此树形目录由 structor 自动生成，请勿手动编辑。 -->

```
system/
└── .config/
    ├── containers/
    │   ├── containers.conf
    │   └── policy.json
    ├── pipewire/
    │   └── pipewire.conf.d/
    │       └── 10-latency-fix.conf
    ├── wireplumber/
    │   ├── scripts/
    │   │   └── 40-alsa/
    │   └── wireplumber.conf.d/
    │       └── 50-disable-automute.conf
    ├── user-dirs.dirs
    └── user-dirs.locale
```

<!-- /structor -->

## 关键约定

- pipewire 使用 `pipewire.conf.d/` 按字母顺序加载
- containers `policy.json` 定义镜像拉取签名验证规则
- `user-dirs.dirs` / `user-dirs.locale` 由 `xdg-user-dirs` 读取

## 修改约束

- 改源后 `blue home` 生效
- pipewire 改后 `herd restart pipewire`（shepherd 是 Guix 的 init 系统）
- user-dirs 变更后重新登录或 `xdg-user-dirs-update`
