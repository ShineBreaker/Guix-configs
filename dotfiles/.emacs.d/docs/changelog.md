# Emacs 配置重构 - 变更日志

## 2026-03-10 - 第一阶段：包依赖更新

### 变更摘要

根据用户需求（后端开发、Python/Java学习、未来学习C/Rust/Kotlin/Zig、前端入门、邮件/日历管理、Org Mode），更新了Guix包依赖清单。

### 新增包列表

#### 1. Git管理（2个包）

- `emacs-magit` (v4.5.0) - 强大的Git界面，必备工具
- `emacs-magit-todos` (v1.8.1) - 在Magit中显示代码中的TODO/FIXME

**用途**：替代命令行Git操作，提供类似JetBrains的Git集成体验

#### 2. 项目管理（1个包）

- `emacs-projectile` (v2.9.1) - 项目管理增强

**用途**：增强项目文件导航、搜索和管理功能

#### 3. Org Mode生态（3个包）

- `emacs-org-modern` (v1.12) - 现代化Org样式
- `emacs-org-roam` (v2.3.1) - 笔记管理系统（类似Obsidian）
- `emacs-org-appear` (v0.3.1) - 自动显示/隐藏Org元素

**用途**：实现"All in Emacs"愿景，使用Org Mode管理笔记、任务和知识库

#### 4. 编程语言支持（6个包）

- `emacs-rust-mode` (v1.0.6) - Rust语言支持
- `emacs-typescript-mode` (v0.4) - TypeScript支持
- `emacs-web-mode` (v17.3.20) - 前端模板编辑（HTML/CSS/JS）
- `emacs-zig-mode` (v0.0.8) - Zig语言支持
- `emacs-json-mode` (v1.9.2) - JSON编辑
- `emacs-markdown-mode` (v2.7) - Markdown编辑

**用途**：支持用户未来学习的现代化编程语言和前端开发

#### 5. 代码片段（1个包）

- `emacs-yasnippet-snippets` (v1.1) - 代码片段集合

**用途**：提供各种语言的代码模板，提升编码效率

#### 6. 邮件与日历（2个包）

- `emacs-notmuch` (v0.39) - 邮件客户端
- `emacs-calfw` (v2.0) - 日历框架

**用途**：实现"All in Emacs"愿景，在Emacs中管理邮件和日历

#### 7. 文件管理增强（1个包）

- `emacs-dired-sidebar` (v0.3.0) - Dired侧边栏

**用途**：提供类似IDE的文件浏览器侧边栏

#### 8. 系统依赖（1个包）

- `notmuch` (v0.39) - 邮件索引系统（添加到package.scm）

**用途**：emacs-notmuch的后端依赖

### 总计

- **新增Emacs包**：16个
- **新增系统包**：1个

### 风险评估

**[风险: 低]** - 所有包均为Guix官方仓库提供，版本稳定，不会影响现有配置。

### 下一步操作

用户需要执行以下命令安装新增的包：

```bash
# 方法1：如果使用Guix Home
guix home reconfigure ~/.config/guix/home-configuration.scm

# 方法2：如果直接使用包定义文件
guix package -m ~/.emacs.d/emacs.scm
guix package -m ~/.emacs.d/package.scm
```

安装完成后，请回复"已安装完成"或"允许下一步"，我将继续进行配置重构工作。

---

## 2026-03-10 - 第二阶段：架构重构完成

### 变更摘要

将配置重构为模块化、分层的目录结构，提升可维护性和可扩展性。

### 新目录结构

```
.emacs.d/
├── init.el                 # 主入口（已重写）
├── early-init.el           # 启动优化（保持不变）
├── core/                   # 核心模块（新增）
│   ├── bootstrap.el        # 核心常量、路径、Guix检测
│   ├── lib.el              # 工具函数库
│   └── autoloads.el        # 自动加载定义
├── configs/                # 配置模块（新增）
│   ├── ui/                 # 界面配置
│   │   ├── appearance.el   # 外观、主题、字体
│   │   ├── dashboard.el    # 启动仪表盘
│   │   └── workspace.el    # 工作区布局、Treemacs
│   ├── editor/             # 编辑器配置
│   │   ├── keybindings.el  # Evil、键位绑定
│   │   ├── completion.el   # Vertico、Consult、Corfu
│   │   └── editing.el      # 编辑行为、括号、Git差异
│   ├── coding/             # 编程配置
│   │   ├── lsp.el          # Eglot LSP、格式化
│   │   └── languages.el    # 各语言模式
│   ├── tools/              # 工具集成
│   │   ├── git.el          # Magit（新增）
│   │   ├── project.el      # Projectile（新增）
│   │   ├── terminal.el     # Vterm
│   │   ├── ai.el           # Ellama AI
│   │   ├── mail.el         # Notmuch（新增）
│   │   └── calendar.el     # Calfw（新增）
│   ├── org/                # Org Mode
│   │   └── org-mode.el     # Org、Org-roam（新增）
│   └── system/             # 系统配置
│       ├── startup.el      # 启动、持久化
│       └── guix.el         # Guix集成
└── lisp/                   # 旧配置（待清理）
```

### 主要改进

1. **模块化架构**：按功能分类，每个模块独立可维护
2. **清晰的加载顺序**：core → system → ui → editor → coding → tools → org
3. **Guix集成**：专门的guix.el处理环境检测
4. **新功能集成**：
   - Git管理（Magit + Magit-todos）
   - 项目管理（Projectile）
   - Org Mode生态（org-modern、org-roam、org-appear）
   - 邮件客户端（Notmuch）
   - 日历管理（Calfw）

### 代码简化

- 移除冗余代码，保持最小化实现
- 统一使用use-package管理配置
- 优化启动性能（延迟加载）
