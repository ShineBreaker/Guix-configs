<!--
SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>

SPDX-License-Identifier: GPL-3.0
-->

# AGENTS.md

本文件只保留仓库入口和硬约束。

**请尽量把功能说明、快捷键、troubleshooting、设计理由写回对应代码文件的 `;;; Commentary:`，非必要不要继续把细节堆进 `AGENTS.md`。**

## 核心原则

- 了解功能先读代码注释，尤其是各文件的 `;;; Commentary:`
- 修改前先读相关文件，确认无同名函数、重复状态、冲突键绑定
- 修改完成后必须反复测试，直到运行无报错

## 概览

这是基于 Guix 的模块化 Emacs 配置，默认按 daemon/client 工作流使用：

- Shepherd 服务 `emacs-daemon` 通过 `emacs --fg-daemon` 启动服务端
- 日常编辑优先使用 `emacsclient` 连接已有会话
- 不使用 `package.el`，所有包都由 Guix 管理

## 架构入口

加载顺序：

1. `early-init.el`
2. `init.el`
3. `core/`
4. `diagnose/`
5. `configs/`

目录职责：

- `core/`：路径常量、基础工具函数
- `diagnose/`：`--debug-init` 诊断框架与 ERT 测试
- `configs/`：系统、UI、编辑、编程、工具、Org 模块

模块职责和具体行为不要重复写在这里，直接看对应文件 `Commentary`。

## 包管理

- 禁止使用 `package.el`
- 禁止写 `:ensure t`
- 新包流程：`guix search <pkg>` → 创建 `emacs.scm` 并写入 → 提醒用户安装

## 命名规范

- `custom:*`：常量
- `custom/*`：公开函数/变量
- `custom--*`：内部私有实现

## 修改约束

- 新增键绑定前检查 `configs/editor/prefix-keymaps.el` 和 `configs/editor/keybindings.el`
- 依赖其他包的配置优先使用 `:after`，不要滥用 `:demand`
- 修改快捷键时，同步 `configs/editor/help.el` 与 `configs/ui/dashboard.el`
- Dashboard 只展示前缀分组的表层入口，不展开子命令
- 新增或重构重要行为时，优先更新对应文件 `Commentary`，而不是扩写本文件

## Daemon / Client 约束

涉及启动、主题、补全、dashboard、workspace、窗口生命周期时，默认按 daemon/client 语义思考：

- daemon 侧 server 由 `emacs --fg-daemon` 自身管理，不要在 daemon 中重复启用 `server-mode`
- `desktop` 默认不在 daemon 中恢复；仅在 `custom/desktop-enable-in-daemon` 非 nil 时启用
- `emacsclient FILE` 打开的 frame 可能已经带目标 buffer，不能假设新 frame 一定应该显示 dashboard
- 所有 display-dependent 设置都应放在 per-frame 入口里处理
- 主题是 Emacs 全局状态，不要在每个新 frame 上重复 `load-theme`
- Treemacs / workspace / completion / dashboard 这类依赖窗口状态的逻辑，要按 frame 记录状态，并用 idle timer 避免阻塞首帧
- 终端内 `EDITOR` / `VISUAL` 指向 `emacsclient`，修改 server buffer 退出行为时要兼容 `server-edit`

涉及这部分逻辑时，优先阅读：

- `configs/ui/appearance.el`
- `configs/ui/color-scheme.el`
- `configs/ui/dashboard.el`
- `configs/ui/workspace.el`
- `configs/editor/completion.el`

## 终端适配

- `(display-graphic-p)` 为 nil 时表示终端模式
- 终端配色和降级策略见 `configs/ui/appearance.el` 的 `Commentary`

## 测试

修改完成后至少执行这些检查，并在失败时继续修复直到通过：

```bash
# 推荐工作流验证
herd restart emacs-daemon
emacsclient -c

# 启动时间
emacs --batch --eval "(message \"%s\" (emacs-init-time))"

# 初始化诊断
emacs --debug-init

# ERT 测试
emacs --batch -L . -L core -L diagnose -L configs -l diagnose/run-tests.el
```

## 知识库

AI Agent 完成任务后应将经验写入知识库。详见 `INSTRUCT.md`。

- 工具：`../../local/bin/kb`（add / get / list / search / tags / patterns）
- 经验卡片：`~/Documents/Org/experiences/`
- 模式文件：`~/Documents/Org/patterns.org`

## 编码

- 所有文件使用 UTF-8
- 注释与文档保持中文
