# 终端工具链配置

本目录部署到 `~/.config/` 与 `~/.local/`，覆盖 Fish、Foot、Kitty、Tmux（含 tmuxifier 会话布局）、Btop、Broot、Fastfetch、Atuin、Herdr 与 Starship。

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

- **Fish**：`conf.d/` 碎片按字母序加载，数字前缀只用于固定执行顺序（逐文件契约见 `docs/scripts/fish-conf-d.md`）；自定义函数放 `functions/<name>.fish`，已建函数的手册见 `docs/scripts/fish-functions.md`（run / retry / screen-off / git-resign / jdk / fish_prompt），`denv` 自成一篇见 `denv.md`。
- **Tmux 架构**：状态侧栏渲染由常驻 Guile 进程负责，Bash 只处理 Pane 生命周期与 FIFO 事件（设计见 `docs/scripts/tmux-sidebar.md`、`sidebar-toggle.md`；入口脚本见 `docs/scripts/tmux-scripts.md`）；`termide` 会话布局在 `tmuxifier/layouts/termide.session.sh`（见 `docs/scripts/termide-layout.md`）。
- **TERM**：Foot 保持 `TERM=foot`，Tmux Pane 保持 `TERM=tmux-256color`，切勿覆写成 `xterm-*`（会丢掉真彩色与键盘协议）。
- **Tab 补全是硬性联动**：在 `tools/`、`.local/bin/` 或 `functions/` 新增可执行脚本/函数时，必须同步写 `.config/fish/completions/<name>.fish`（`complete -c <name> ...`）。例外：`blue`（动态跟随仓库）、`denv`（独立维护）。

## 修改与生效

- **通用**：改源后须 `blue home` 重建（部署进 Store 只读副本）。
- **Fish**：新开终端窗口即刻读取最新配置。
- **Tmux**：`prefix + r` 或 `tmux source ~/.config/tmux/tmux.conf` 重载。
- **其余随启动读取**：配置由进程启动时载入，改动需重启对应程序。
