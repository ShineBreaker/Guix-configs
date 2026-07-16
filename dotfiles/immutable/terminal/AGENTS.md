# 终端工具链配置

通过 Guix Home 部署到 `~/.config/` 与 `~/.local/`。涵盖 shell、终端模拟器、终端复用器、监控、信息展示等。

## 目录结构

<!-- structor:begin depth=4 -->

<!-- 此树形目录由 structor 自动生成，请勿手动编辑。 -->

```
terminal/
├── .config/
│   ├── atuin/
│   │   └── config.toml
│   ├── broot/
│   │   ├── conf.hjson
│   │   └── verbs.hjson
│   ├── btop/
│   │   └── btop.conf
│   ├── fastfetch/
│   │   └── config.jsonc
│   ├── fish/
│   │   ├── conf.d/
│   │   │   ├── 00-load-functions.fish
│   │   │   ├── 01-guix.fish
│   │   │   ├── 05-java.fish
│   │   │   ├── 05-path.fish
│   │   │   ├── 10-settings.fish
│   │   │   ├── 20-greeting.fish
│   │   │   ├── 99-command-not-found.fish
│   │   │   └── 99-tmux.fish
│   │   └── functions/
│   │       ├── denv.fish
│   │       ├── fish_prompt.fish
│   │       ├── java_tools.fish
│   │       └── retry.fish
│   ├── foot/
│   │   └── foot.ini
│   ├── tmux/
│   │   ├── scripts/
│   │   │   ├── session-selector
│   │   │   ├── sidebar-render.scm
│   │   │   ├── sidebar-toggle
│   │   │   ├── which-key
│   │   │   └── window-jump
│   │   └── tmux.conf
│   ├── tmuxifier/
│   │   └── layouts/
│   │       └── termide.session.sh
│   └── starship.toml
└── .local/
    └── bin/
        └── termide
```

<!-- /structor -->

## 关键约定

- fish `conf.d/` 按文件名字母序加载；数字前缀仅排序提示，无优先级语义
- tmux 侧栏由长驻 Guile 渲染进程负责，Bash 只处理 pane 生命周期与 FIFO 事件
- `termide` 是 tmuxifier 衍生的会话管理器，入口 `~/.local/bin/termide`

## 修改约束

- 改源后 `blue home` 生效
- fish 新 shell 自动生效；tmux 内 `prefix+r` 或 `tmux source ~/.config/tmux/tmux.conf` 热加载
- 新增 fish 函数放 `functions/`；conf 块放 `conf.d/` 加数字前缀控制排序
- foot 保持 `TERM=foot`，tmux pane 保持 `TERM=tmux-256color`；不要手工覆写为 `xterm-*`
