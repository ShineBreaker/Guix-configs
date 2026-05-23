<!--
SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>

SPDX-License-Identifier: MIT
-->

# 终端工具链配置

通过 Guix Home 部署到 `~/.config/` 和 `~/.local/`。

## 结构

```
terminal/.config/
├── broot/               # broot 文件浏览器
│   ├── conf.hjson           # 主配置
│   └── verbs.hjson          # 自定义动词
├── btop/                # 系统监控
│   └── btop.conf
├── fastfetch/           # 系统信息展示
│   └── config.jsonc
├── fish/                # Fish Shell
│   ├── conf.d/              # 自动加载配置
│   │   ├── 00-load-functions.fish
│   │   ├── 01-guix.fish         # Guix 路径
│   │   ├── 05-java.fish         # Java 环境
│   │   ├── 05-path.fish         # PATH 设置
│   │   ├── 10-settings.fish     # 通用设置
│   │   ├── 20-greeting.fish     # 欢迎信息
│   │   ├── 99-command-not-found.fish
│   │   └── 99-tmux.fish         # tmux 集成
│   └── functions/           # 自定义函数
│       ├── denv.fish            # 开发环境切换
│       ├── fish_prompt.fish     # 提示符
│       ├── java_tools.fish
│       └── retry.fish           # 重试工具
├── foot/                # 终端模拟器
│   └── foot.ini
├── starship.toml        # 命令提示符主题
├── tmux/                # 终端复用器
│   ├── tmux.conf
│   └── scripts/             # 自定义脚本
│       ├── session-selector
│       ├── sidebar-render.scm
│       ├── sidebar-toggle
│       ├── tmux-helpers.scm
│       ├── which-key
│       └── window-jump
└── tmuxifier/           # tmux 会话管理
    └── layouts/termide.session.sh
```

## 关键约定

- fish 配置按编号顺序加载（00 → 99），数字越大优先级越高
- tmux 自定义脚本使用 Scheme（`.scm`）和 shell 混合
- `termide` 是自定义终端会话管理器，入口在 `.local/bin/termide`
- starship 使用 TOML 格式配置

## 修改约束

- fish 配置修改后新 shell 自动生效
- tmux 配置修改后需 `tmux source ~/.config/tmux/tmux.conf`
- 新增 fish 函数需放在 `functions/` 目录
