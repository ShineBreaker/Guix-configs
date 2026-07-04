# chemacs2 引导层

本目录（`stow/emacs/.config/emacs/`）顶层是 **chemacs2 引导层**，部署后占据 `~/.config/emacs/`，是 Emacs 启动的真正入口。

## 文件

| 文件            | 作用                                                   |
| --------------- | ------------------------------------------------------ |
| `init.el`       | 引导层入口，调用 `chemacs-load-user-init`              |
| `early-init.el` | 引导层 early-init，调用 `chemacs-load-user-early-init` |
| `chemacs.el`    | chemacs2 核心：读 profiles.el 选 profile，设 UED，加载 |

来源：https://github.com/plexus/chemacs2 （commit `c2d700b`，GPL-3.0-or-later）

## 两个 profile 配置树

- `general-config/` —— 旧配置（git submodule，上游 codeberg.org/BrokenShine/.emacs.d）。
- `literal-config/` —— 新配置（org literate，后续由 `source/config.org` tangle 生成）。**当前默认 profile**。

## profile 选择配置

profile 表与默认选择器在 `../chemacs/`（部署到 `~/.config/chemacs/`）：

- `profiles.el` —— profile → user-emacs-directory 映射
- `profile` —— 默认 profile 名（当前 `general`）

## 常用操作

```bash
# 试新配置（前台实例，独立于 daemon，不影响日常使用）
emacs --with-profile literal

# 切默认到新配置（稳定后）
echo literal > stow/emacs/.config/chemacs/profile
blue stow --restow emacs
herd restart emacs-daemon

# 改旧配置源（submodule，改源即生效，无需 stow）
# 直接编辑 stow/emacs/.config/emacs/general-config/ 下的文件
```

## daemon 行为

rosenthal `home-emacs-service-type` 跑 `emacs --fg-daemon`（不传 `--with-profile`），
自动走默认 profile = general。socket 名为默认 "server"，所有现有 emacsclient
调用（niri Mod+E、skill 脚本、.desktop、with-editor）零改动。
