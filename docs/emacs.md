<!--
SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>

SPDX-License-Identifier: GPL-3.0
-->

# Emacs 配置说明

基于 Guix 的模块化 Emacs 配置，提供类似 JetBrains IDE 的开发体验。

## 快速开始

### 1. 安装依赖

使用 Guix 安装所有依赖：

```bash
# 方法一：使用清单文件
guix install -m emacs.scm

# 方法二：手动安装核心包
guix install emacs emacs-use-package emacs-evil emacs-general \
  emacs-vertico emacs-consult emacs-corfu emacs-magit \
  emacs-treemacs emacs-org emacs-org-roam
```

### 2. 启动 Emacs

```bash
emacs
```

### 3. 首次启动

- 按 `F5` 打开 VS Code 风格工作区布局
- 使用 `SPC f f` 打开文件开始编辑
- 按 `F1 ?` 或 `SPC h ?` 查看快捷键帮助

## 核心快捷键

### Leader 键系统（推荐）

在 Evil Normal 模式下使用 `SPC`（空格键）作为 Leader 键：

| 类别       | 快捷键     | 说明           |
| ---------- | ---------- | -------------- |
| **文件**   | `SPC f f`  | 打开文件       |
|            | `SPC f s`  | 保存文件       |
|            | `SPC f r`  | 最近文件       |
| **缓冲区** | `SPC b b`  | 切换缓冲区     |
|            | `SPC b d`  | 关闭缓冲区     |
| **窗口**   | `SPC w s`  | 水平分割       |
|            | `SPC w v`  | 垂直分割       |
| **项目**   | `SPC p f`  | 项目查找文件   |
|            | `SPC p p`  | 切换项目       |
| **搜索**   | `SPC s s`  | 搜索当前文件   |
|            | `SPC s p`  | 搜索项目       |
| **代码**   | `SPC c g d`| 跳转到定义     |
|            | `SPC c f f`| 格式化代码     |
| **Git**    | `SPC g s`  | Git 管理       |
| **切换**   | `SPC t t`  | 文件树         |
|            | `SPC t v`  | 终端           |
|            | `SPC t l`  | 工作区布局     |
| **Org**    | `SPC o a`  | Org 议程       |
|            | `SPC o n f`| 查找笔记       |
| **帮助**   | `SPC h ?`  | 快捷键帮助     |
| **快速**   | `SPC SPC`  | M-x 命令       |

### 功能键

| 快捷键 | 说明               |
| ------ | ------------------ |
| `F5`   | VS Code 风格布局   |
| `F1 ?` | 显示快捷键帮助     |

## 文档

- **CLAUDE.md** - 开发者指南（AI 助手参考）
- **OPTIMIZATION.md** - 优化报告
- **emacs.scm** - Guix 包安装清单

## 目录结构

```
.emacs.d/
├── early-init.el       # 启动优化
├── init.el             # 主入口
├── core/               # 核心模块
│   ├── bootstrap.el    # 路径常量
│   └── lib.el          # 工具函数
├── configs/            # 配置模块
│   ├── system/         # 系统配置
│   ├── ui/             # 界面配置
│   ├── editor/         # 编辑器配置
│   ├── coding/         # 编程配置
│   ├── tools/          # 工具配置
│   └── org/            # Org Mode 配置
├── emacs.scm           # Guix 包清单
└── OPTIMIZATION.md     # 优化报告
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

## 特性

- **Leader 键系统**：参考 Spacemacs/Doom，减少对 Ctrl 键依赖
- **Guix 包管理**：所有包由 Guix 管理，不使用 package.el
- **详细中文注释**：配置文件包含详细的中文说明
- **VS Code 布局**：一键切换到 IDE 风格布局
- **LSP 支持**：通过 Eglot 提供智能代码补全
- **Org Mode**：完整的笔记和任务管理系统
