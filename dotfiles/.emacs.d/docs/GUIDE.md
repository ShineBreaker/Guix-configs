# Emacs 配置使用指南

本文档介绍新增工具的使用方法。

## 1. Git 管理 - Magit

**启动方式**：`C-x g` 或 `M-x magit-status`

**核心操作**：

- `s` - 暂存文件（stage）
- `u` - 取消暂存（unstage）
- `c c` - 创建提交
- `P p` - 推送到远程
- `F p` - 拉取远程更新
- `b b` - 切换分支
- `b c` - 创建新分支
- `l l` - 查看日志
- `d d` - 查看差异
- `q` - 退出

**Magit Todos**：
在 Magit 状态页面自动显示代码中的 TODO/FIXME 注释。

## 2. 项目管理 - Projectile

**快捷键前缀**：`C-c p`

**常用命令**：

- `C-c p f` - 项目内查找文件
- `C-c p s g` - 项目内搜索（grep）
- `C-c p p` - 切换项目
- `C-c p k` - 关闭项目所有缓冲区
- `C-c p d` - 打开项目根目录

**项目识别**：
Projectile 自动识别包含 `.git`、`.projectile` 等标记的目录为项目。

## 3. Org Mode 生态

### 3.1 Org Mode 基础

**文件位置**：`~/org/`

**基本语法**：

- `* 标题` - 一级标题
- `** 子标题` - 二级标题
- `TODO` - 待办事项
- `DONE` - 已完成事项
- `[2026-03-10]` - 日期

**快捷键**：

- `C-c C-t` - 切换 TODO 状态
- `C-c C-s` - 设置计划时间
- `C-c C-d` - 设置截止时间
- `C-c a` - 打开议程视图

### 3.2 Org Roam（笔记管理）

**笔记目录**：`~/org/roam/`

**核心命令**：

- `C-c n f` - 查找或创建笔记
- `C-c n i` - 插入笔记链接
- `C-c n l` - 显示反向链接

**使用流程**：

1. `C-c n f` 创建新笔记
2. 在笔记中使用 `C-c n i` 链接其他笔记
3. `C-c n l` 查看哪些笔记链接到当前笔记

## 4. 邮件客户端 - Notmuch

**启动方式**：`C-c m` 或 `M-x notmuch`

**前置配置**：
需要先配置 notmuch 邮件索引：

```bash
notmuch setup
notmuch new
```

**基本操作**：

- `s` - 搜索邮件
- `RET` - 打开邮件
- `r` - 回复
- `c` - 撰写新邮件
- `+` / `-` - 添加/删除标签
- `a` - 归档邮件

## 5. 日历 - Calfw

**启动方式**：`C-c c` 或 `M-x cfw:open-calendar-buffer`

**导航**：

- `n` / `p` - 下一天/上一天
- `f` / `b` - 下一周/上一周
- `N` / `P` - 下一月/上一月
- `t` - 跳转到今天
- `g` - 跳转到指定日期

**集成 Org**：
Calfw 可以显示 Org Mode 中的日程安排。

## 6. 文件树 - Treemacs

**启动方式**：`C-c t` 或 `M-x treemacs`

**基本操作**：

- `RET` - 打开文件/展开目录
- `TAB` - 展开/折叠目录
- `r` - 刷新
- `d` - 删除文件
- `c` - 复制文件
- `m` - 移动/重命名文件
- `cf` - 创建文件
- `cd` - 创建目录
- `q` - 关闭

## 7. AI 工具 - Ellama

**前置配置**：
设置环境变量 `DASHSCOPE_API_KEY` 或使用 GNOME Keyring：

```bash
secret-tool store --label="DashScope API Key" service emacs-ai provider dashscope
```

**快捷键**：

- `C-c a c` - 开始 AI 对话
- `C-c a q` - 询问选中的代码
- `C-c a e` - 让 AI 编辑代码
- `C-c a i` - 让 AI 补充代码

**使用流程**：

1. 选中代码
2. `C-c a q` 询问问题
3. 根据回答使用 `C-c a e` 修改代码

## 8. 工作区布局

**快捷键**：`F9`

**布局说明**：

- 左侧：Treemacs 文件树
- 中间：代码编辑区
- 底部：终端（vterm）

## 9. Evil 模式（Vim 键位）

**状态切换**：

- `C-c v v` - 切换到 Vim 普通模式
- `C-c v e` - 切换到 Emacs 模式

**学习建议**：
保留 Emacs 原生快捷键的学习价值，可以在两种模式间自由切换。

## 10. 常用快捷键总结

| 功能         | 快捷键    | 说明         |
| ------------ | --------- | ------------ |
| 项目查找文件 | `C-p`     | 类似 VS Code |
| 全文搜索     | `C-S-f`   | Ripgrep 搜索 |
| 切换缓冲区   | `C-S-b`   | 快速切换     |
| Git 状态     | `C-x g`   | Magit        |
| 文件树       | `C-c t`   | Treemacs     |
| 工作区布局   | `F5`      | VS Code 风格 |
| 终端         | `C-c v t` | Vterm        |
| AI 对话      | `C-c a c` | Ellama       |
| 邮件         | `C-c m`   | Notmuch      |
| 日历         | `C-c c`   | Calfw        |
| Org 笔记     | `C-c n f` | Org-roam     |

## 11. 故障排查

### Notmuch 无法启动

确保已安装并配置 notmuch：

```bash
guix install notmuch
notmuch setup
```

### Org-roam 数据库错误

初始化数据库：

```elisp
M-x org-roam-db-sync
```

### AI 工具无法使用

检查 API Key 配置：

```elisp
M-: (my/ai-read-api-key)
```

### LSP 无法启动

确保已安装对应的 LSP 服务器（通过 Guix）：

- Python: `python-lsp-server`
- C/C++: `ccls`
- Rust: `rust-analyzer`

## 12. 进一步学习

- Magit: https://magit.vc/manual/
- Org Mode: https://orgmode.org/manual/
- Org Roam: https://www.orgroam.com/manual.html
- Projectile: https://docs.projectile.mx/
