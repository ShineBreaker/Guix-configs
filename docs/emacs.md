<!--
SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>

SPDX-License-Identifier: GPL-3.0
-->

# Emacs 配置说明

基于 Guix 的模块化 Emacs 配置，提供类似 JetBrains IDE 的开发体验。

## 快速开始

### 1. 重启 Emacs

```bash
emacs
```

### 2. 首次启动

- 按 `F5` 打开 VS Code 风格工作区布局
- 使用 `C-x C-f` 打开文件开始编辑

### 3. 核心快捷键

#### Leader 键系统（推荐）

在 Evil Normal 模式下使用 `SPC`（空格键）作为 Leader 键：

- `SPC f f` - 打开文件
- `SPC p f` - 项目内查找文件
- `SPC b b` - 切换缓冲区
- `SPC g s` - Git 管理（Magit）
- `SPC t t` - 文件树（Treemacs）
- `SPC a c` - AI 对话
- `SPC t l` - 重置工作区布局
- `SPC h ?` - 快捷键帮助

#### 传统快捷键（备选）

- `C-p` - 项目内查找文件
- `C-x g` - Git 管理（Magit）
- `C-c t` - 文件树（Treemacs）
- `C-c a c` - AI 对话
- `F5` - 重置工作区布局

## 文档

- **GUIDE.md** - 详细使用指南
- **changelog.md** - 变更记录

## 目录结构

```
.emacs.d/
├── init.el              # 主入口
├── early-init.el        # 启动优化
├── core/                # 核心模块
├── configs/             # 配置模块
│   ├── ui/             # 界面
│   ├── editor/         # 编辑器
│   ├── coding/         # 编程
│   ├── tools/          # 工具
│   ├── org/            # Org Mode
│   └── system/         # 系统
└── themes/             # 主题

旧配置保留在 lisp/ 目录（可删除）
```

## 清理旧配置

确认新配置正常后，可删除旧配置：

```bash
rm -rf ~/.emacs.d/lisp/
```

## 故障排查

启动时出错：

```bash
emacs --debug-init
```

查看启动时间：

```elisp
M-x emacs-init-time
```
