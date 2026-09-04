# 终端工具链配置

通过 Guix Home 部署到 `~/.config/` 与 `~/.local/`。涵盖 shell、终端模拟器、终端复用器、监控、信息展示等。

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

- fish `conf.d/` 按字母序加载，数字前缀仅排序提示，无优先级语义
- tmux 侧栏：渲染归长驻 Guile 进程，Bash 只管 pane 生命周期与 FIFO 事件；`termide` 为 tmuxifier 会话布局（`tmuxifier/layouts/termide.session.sh`）

## 修改约束

- 改源后 `blue home` 生效；fish 新 shell 自动生效，tmux `prefix+r` 或 `tmux source ~/.config/tmux/tmux.conf` 热加载；新增 fish 函数放 `functions/`，conf 块放 `conf.d/` 加数字前缀排序
- foot 保持 `TERM=foot`，tmux pane 保持 `TERM=tmux-256color`，不要覆写为 `xterm-*`
- **新增脚本/可执行必须同步补全**：新增 `functions/<name>.fish` 或 `tools/`/`.local/bin/` 下可执行时，须同步在 `dotfiles/immutable/terminal/.config/fish/completions/<name>.fish` 新增鱼壳 Tab 补全（`complete -c <name>`），否则视为未完成。例外：`blue`/`blueprint.scm`（按仓库动态不钉死）、`denv`（负责人另行维护）
