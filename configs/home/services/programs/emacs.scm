(define %emacs-packages-list
  (cons* (specs->pkgs+out
          ;; --- Emacs 核心与 Lisp ---
          "emacs-pgtk"                    ; 纯 GTK 版 Emacs（原生 Wayland 支持）
          "sbcl"                          ; Steel Bank Common Lisp（SLY 所需）
          "emacs-use-package"             ; 包配置宏

          ;; --- 补全与迷你缓冲区 ---
          "emacs-vertico"                 ; 垂直补全界面
          "emacs-marginalia"              ; 迷你缓冲区注释信息
          "emacs-orderless"               ; 无序补全风格
          "emacs-consult"                 ; Consult 命令（搜索、导航）
          "emacs-embark"                  ; 目标对象的上下文操作
          "emacs-corfu"                   ; 区域补全（覆盖层显示）

          ;; --- Evil 模式（Vim 模拟）---
          "emacs-evil"                    ; Vim 模拟层
          "emacs-evil-collection"         ; 各类模式的 Evil 键绑定

          ;; --- 界面与外观 ---
          "emacs-dashboard"               ; 启动仪表盘
          "emacs-doom-modeline"           ; 现代模式行
          "emacs-ef-themes"               ; Ef-themes 配色主题
          "emacs-kind-icon"               ; 补全图标
          "emacs-nerd-icons"              ; Nerd Font 图标
          "emacs-which-key"               ; 键绑定弹出帮助
          "emacs-minimap"                 ; 迷你地图侧边栏
          "emacs-rainbow-delimiters"      ; 彩色括号
          "emacs-treemacs"                ; 树形文件浏览器
          "emacs-treemacs-nerd-icons"     ; Treemacs 的 Nerd 图标
          "emacs-diff-hl"                 ; 边距差异高亮
          "emacs-stickyfunc-enhance"      ; 粘性函数头
          "emacs-ws-butler"               ; 自动清理行尾空格

          ;; --- 开发工具 ---
          "emacs-vterm"                   ; 终端模拟器（vterm）
          "emacs-yasnippet"               ; 代码片段扩展
          "emacs-yasnippet-snippets"      ; 代码片段集合
          "emacs-rg"                      ; Ripgrep 集成

          ;; --- 编程语言支持 ---
          "emacs-kotlin-mode"             ; Kotlin 语言支持
          "emacs-rust-mode"               ; Rust 语言支持
          "emacs-zig-mode"                ; Zig 语言支持
          "emacs-typescript-mode"         ; TypeScript 支持
          "emacs-web-mode"                ; 前端模板编辑
          "emacs-json-mode"               ; JSON 编辑
          "emacs-markdown-mode"           ; Markdown 编辑
          "emacs-sly"                     ; Superior Lisp 交互（Common Lisp）
          "emacs-geiser"                  ; Scheme REPL 集成
          "emacs-geiser-guile"            ; Geiser 的 Guile Scheme 支持

          ;; --- Git 集成 ---
          "emacs-magit"                   ; Git 界面
          "emacs-magit-todos"             ; Magit 中显示 TODO
          "emacs-git-messenger"           ; 显示当前行的提交信息

          ;; --- 项目管理 ---
          "emacs-projectile"              ; 项目管理增强

          ;; --- Org Mode 生态 ---
          "emacs-org-modern"              ; 现代化 Org 样式
          "emacs-org-roam"                ; 笔记管理系统
          "emacs-org-appear"              ; 自动显示隐藏元素

          ;; --- 帮助与文档 ---
          "emacs-helpful"                 ; 更友好的帮助缓冲区

          ;; --- 邮件与日历 ---
          "emacs-notmuch"                 ; 邮件客户端
          "emacs-calfw"                   ; 日历框架

          ;; --- 文件管理增强 ---
          "emacs-dired-sidebar"           ; Dired 侧边栏

          ;; --- 环境与工具 ---
          "emacs-no-littering"            ; 保持 Emacs 目录整洁

          ;; --- LLM / AI 集成 ---
          "emacs-ellama"                  ; Emacs LLM 客户端
          "emacs-llm"                     ; LLM 库
          "emacs-llm-tool-collection"     ; LLM 工具集合
          "emacs-spinner"                 ; 加载动画
          "emacs-yaml"                    ; YAML 支持

          ;; --- Tree-sitter（语法解析）---
          "tree-sitter"                   ; Tree-sitter 核心
          "tree-sitter-bash"
          "tree-sitter-c"
          "tree-sitter-cpp"
          "tree-sitter-css"
          "tree-sitter-dockerfile"
          "tree-sitter-go"
          "tree-sitter-html"
          "tree-sitter-javascript"
          "tree-sitter-json"
          "tree-sitter-python"
          "tree-sitter-rust"
          "tree-sitter-typescript")))
