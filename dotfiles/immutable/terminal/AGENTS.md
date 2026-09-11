# 终端工具链配置

本目录通过 Guix Home 部署到 `~/.config/` 与 `~/.local/`，涵盖 Shell（Fish）、终端模拟器（Foot、Kitty）、终端复用器（Tmux）、系统监控（Btop）、历史搜索（Atuin）与提示符（Starship）等。

## 目录结构

<!-- structor:begin depth=2 -->

<!-- 此树形目录由 structor 自动生成，请勿手动编辑。 -->

```
terminal/
└── .config/
    ├── atuin/
    ├── broot/
    ├── btop/
    ├── fastfetch/
    ├── fish/
    ├── foot/
    ├── herdr/
    ├── kitty/
    ├── tmux/
    ├── tmuxifier/
    └── starship.toml
```

<!-- /structor -->

## 关键约定

- **Fish Shell**：
  - `conf.d/` 碎片按字母顺序加载，数字前缀仅用于控制执行顺序。
  - 自定义函数放置于 `functions/<name>.fish`。
- **Tmux 架构**：
  - Tmux 状态侧栏渲染由常驻 Guile 进程负责，Bash 仅处理 Pane 生命周期与 FIFO 事件。
  - `termide` 会话布局维护在 `tmuxifier/layouts/termide.session.sh`。
- **终端类型（TERM）**：Foot 保持 `TERM=foot`，Tmux Pane 保持 `TERM=tmux-256color`，切勿强制覆写为 `xterm-*`。

## 修改与生效流程

1. **改源后生效**：修改后执行 `blue home` 部署。
2. **热加载**：
   - Fish：新开终端窗口即刻读取最新配置。
   - Tmux：按快捷键 `prefix + r` 或执行 `tmux source ~/.config/tmux/tmux.conf` 重新加载。
3. **命令补全规范**：
   - 当在 `tools/`、`.local/bin/` 或 `functions/` 新增可执行脚本/函数时，**必须同步在 `.config/fish/completions/<name>.fish` 编写 Tab 补全规则**（`complete -c <name> ...`）。
   - 例外：`blue`（动态跟随仓库）、`denv`（独立维护）。
