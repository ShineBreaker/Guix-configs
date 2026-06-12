# 终端工具链配置

通过 Guix Home 部署到 `~/.config/` 与 `~/.local/`。涵盖 shell、终端模拟器、终端复用器、监控、信息展示等。

## 目录结构

```
terminal/.config/
├── broot/
│   ├── conf.hjson                       # broot 文件浏览器
│   └── verbs.hjson
├── btop/
│   └── btop.conf                        # 系统监控
├── fastfetch/
│   └── config.jsonc                     # 系统信息展示
├── fish/
│   ├── conf.d/                          # 自动加载配置（按文件名字母序）
│   │   ├── 00-load-functions.fish
│   │   ├── 01-guix.fish                 # Guix PATH 集成
│   │   ├── 05-java.fish
│   │   ├── 05-path.fish
│   │   ├── 10-settings.fish
│   │   ├── 20-greeting.fish
│   │   ├── 99-command-not-found.fish
│   │   └── 99-tmux.fish
│   └── functions/
│       ├── denv.fish
│       ├── fish_prompt.fish
│       ├── java_tools.fish
│       └── retry.fish
├── foot/
│   └── foot.ini                         # Wayland 终端模拟器
├── starship.toml                        # 命令提示符主题（TOML）
├── tmux/
│   ├── tmux.conf
│   └── scripts/                         # 自定义脚本
│       ├── session-selector             # 会话选择器（fzf）
│       ├── sidebar-render.scm           # 侧边栏渲染（Guile）
│       ├── sidebar-toggle               # 侧边栏生命周期（Bash）
│       ├── tmux-helpers.scm             # 共享工具模块
│       ├── which-key                    # 快捷键帮助弹窗
│       └── window-jump                  # 窗口跳转（fzf）
└── tmuxifier/
    └── layouts/
        └── termide.session.sh           # termide 会话布局

terminal/.local/
└── bin/
    └── termide                          # 自定义终端会话管理器入口
```

## 关键约定

- fish `conf.d/` 按文件名字母序加载；数字前缀只是排序提示，非优先级语义
- tmux 自定义脚本混合 Scheme（`.scm`，Guile 驱动）+ Bash（胶水）
- `termide` 是 tmuxifier 衍生的自定义会话管理器，入口在 `~/.local/bin/termide`
- starship 使用 TOML；`terminal/` 下唯一顶级文件
- foot 主题片段在 `desktop-suite/.config/foot/themes/`，主配置在本目录

## 修改约束

- 修改后必须 `maak rebuild` 才会生效
- fish 配置：新 shell 自动生效，无需 reload
- tmux 配置：tmux 内 `prefix + r` 或 `tmux source ~/.config/tmux/tmux.conf` 即可热加载
- 新增 fish 函数放 `functions/`；新增 conf 块放 `conf.d/` 并加数字前缀控制顺序
- tmux 侧栏依赖 foot 终端行为；在其他终端下可能需要调整 `default-terminal` 和 `terminal-overrides`