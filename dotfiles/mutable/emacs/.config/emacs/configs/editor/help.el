;;; help.el --- 快捷键帮助系统 -*- lexical-binding: t; -*-

;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; Commentary:
;; 快捷键帮助系统。
;;
;; 由于交互层已从单一总前缀改为 Emacs 风格的多前缀分组，
;; 本文件不再尝试从源码动态解析键位，而是直接维护一份中文分组总览。
;; which-key 的中文菜单文本则集中维护在 `configs/i18n/which-key-descriptions.el`。
;;
;; 帮助入口：
;; - `F1 ?`
;; - `C-c h ?`
;;
;; 设计目标：
;; - 用中文分组描述前缀键的职责
;; - 把 Emacs 原生前缀和自定义前缀放在同一页里
;; - 让 dashboard 也能复用一份精简版概览

;;; Code:

(defconst custom/help--dashboard-bindings
  '(("C-x" . "文件 / 缓冲区 / 窗口 / 标签")
    ("C-x p" . "项目")
    ("M-s" . "搜索")
    ("M-g" . "跳转 / 错误")
    ("C-c l" . "代码 / LSP")
    ("C-c d" . "调试")
    ("C-c g" . "Git")
    ("C-c t" . "切换 / 工作区")
    ("C-c o" . "Org 扩展"))
  "Dashboard 展示用的精简前缀总览。")

(defconst custom/help--sections
  '(("基础移动与直达键"
     ("C-h / C-j / C-k / C-l" . "左移 / 下移 / 上移 / 右移")
     ("方向键" . "保留原生光标移动")
     ("C-z / C-S-z" . "撤销 / 重做")
     ("C-a" . "全选")
     ("C-/" . "注释 / 取消注释")
     ("C-S-c" . "智能复制")
     ("C-v / C-S-v" . "粘贴")
     ("C-s" . "保存")
     ("C-f" . "当前缓冲区搜索")
     ("C-p" . "项目内查找文件")
     ("C-S-f" . "项目全文搜索")
     ("C-S-b" . "切换缓冲区")
     ("C-S-p" . "命令面板")
     ("F2" . "重命名符号 / 文件")
      ("C-= / C-- / C-0" . "放大 / 缩小 / 重置缩放")
      ("M-方向键" . "切换窗口")
      ("C-S-x" . "智能剪切（行/选区）")
      ("C-S-w" . "关闭当前缓冲区")
      ("C-S-t" . "重新打开最近文件")
      ("C-S-d" . "复制当前行")
      ("C-S-<up/down>" . "上移/下移当前行")
      ("C-<f12>" . "跳转到定义")
      ("C-S-<f12>" . "查找引用")
      ("C-S-i" . "智能格式化")
      ("C-`" . "打开终端")
      ("C-S-/" . "块注释")
      ("C-S-s" . "另存为")
      ("C-S-a" . "项目文件搜索"))
    ("文件 / 缓冲区 / 窗口 / 标签"
     ("C-x C-f / C-x C-s / C-x C-w" . "打开 / 保存 / 另存为")
     ("C-x C-r" . "最近文件")
     ("C-x P" . "打开 PDF")
     ("C-x b / C-x B" . "切换缓冲区 / 缓冲区列表")
     ("C-x k / C-x K" . "关闭当前 / 指定缓冲区")
     ("C-x 2 / 3 / 0 / 1 / o" . "分割 / 关闭 / 保留 / 切窗")
     ("C-x s ..." . "选择前缀：多光标、整行、代码块、扩缩选区")
     ("C-x t n / p" . "下一个 / 上一个标签")
     ("C-x t g" . "刷新当前 frame 的标签栏")
     ("C-x t k" . "关闭当前标签")
     ("C-x t 1..5" . "跳到可见标签 1 到 5"))
    ("项目"
     ("C-x p p" . "切换项目")
     ("C-x p f" . "项目内查找文件")
     ("C-x p s" . "项目全文搜索")
     ("C-x p o / O" . "打开项目目录 / 目录浏览")
     ("C-x p k" . "关闭项目缓冲区"))
     ("搜索与替换"
      ("M-s l" . "搜索当前缓冲区")
      ("M-s p" . "搜索项目")
      ("M-s b" . "搜索缓冲区")
      ("M-s r" . "项目范围替换")
      ("M-s e" . "Eglot 符号搜索")
      ("M-s f" . "Flycheck 错误浏览"))
    ("跳转与错误"
     ("M-." . "跳转到定义")
     ("M-," . "返回上一个位置")
     ("M-g n / p" . "下一个 / 上一个错误")
     ("M-g l" . "错误列表")
     ("M-g r" . "查找引用")
     ("M-g h" . "显示悬停信息")
     ("M-g b / f" . "后退 / 前进")
     ("C-c ] e / C-c [ e" . "错误导航别名"))
     ("代码 / LSP"
      ("C-c l d" . "跳转到定义")
      ("C-c l r" . "查找引用")
      ("C-c l h" . "显示悬停信息")
      ("C-c l a" . "代码操作")
      ("C-c l q" . "快速修复")
      ("C-c l n" . "重命名符号")
      ("C-c l c" . "触发补全")
      ("C-c l s" . "显示签名")
      ("C-c l e" . "错误列表")
      ("C-c l t" . "切换 Flycheck")
       ("C-c l g ..." . "Godot 相关操作")
       ("C-c l x ..." . "LSP 扩展（声明/实现/类型定义）"))
     ("LSP 扩展（eglot-x）"
      ("C-c l x d" . "跳转到声明")
      ("C-c l x i" . "跳转到实现")
      ("C-c l x t" . "跳转到类型定义")
      ("C-c f b" . "格式化缓冲区（eglot-format-buffer）"))
    ("格式化"
     ("C-c f f" . "智能格式化")
     ("C-c f b" . "格式化整个缓冲区")
     ("C-c f r" . "格式化选区")
     ("C-c f i / I" . "增加 / 减少缩进"))
    ("编辑变换"
     ("C-c e l ..." . "行操作：复制、移动、空行、清理")
     ("C-c e c ..." . "注释操作")
     ("C-c e t ..." . "文本变换")
     ("C-c e s ..." . "包围 / 去包围")
     ("C-c e b ..." . "书签"))
    ("多光标与选区"
     ("C-x s n / p / a" . "标记下一个 / 上一个 / 全部")
     ("C-x s s / S" . "跳过并标记下一个 / 上一个")
     ("C-x s l / f" . "选中整行 / 代码块")
     ("C-x s e / E" . "扩大 / 缩小选区"))
    ("折叠"
     ("C-c z a" . "切换当前折叠")
     ("C-c z c / o" . "关闭 / 打开当前折叠")
     ("C-c z m / r" . "全部折叠 / 全部展开"))
     ("Git"
      ("C-x g" . "Magit 状态页")
      ("C-c g s" . "Git 状态")
      ("C-c g b / l / d / t" . "Blame / 日志 / 差异 / 时光机")
      ("C-c g S / D" . "Stage / 丢弃当前文件")
      ("C-c g F / P" . "Pull / Push")
      ("C-c g # / @" . "Stash Push / Pop")
      ("C-c g f i/p/n/c" . "Forge: Issue / PR / 列表 / 拉取"))
     ("调试"
      ("C-c d b" . "切换断点")
      ("C-c d B" . "清除所有断点")
      ("C-c d d" . "开始调试")
      ("C-c d n" . "单步跳过")
      ("C-c d s" . "单步进入")
      ("C-c d o" . "单步跳出")
      ("C-c d c" . "继续运行")
      ("C-c d q" . "停止调试")
      ("C-c d r" . "重启调试")
      ("C-c d l" . "查看日志"))
     ("撤销可视化"
      ("C-c u v" . "打开撤销树"))
     ("切换与工作区"
     ("F5" . "切换工作区布局")
     ("C-c t t" . "文件树")
     ("C-c t r" . "在文件树中定位当前文件")
     ("C-c t d" . "目录浏览")
     ("C-c t v" . "打开终端")
     ("C-c t l" . "工作区布局")
     ("C-c t p / P" . "PDF 护眼模式 / 适配宽度")
     ("C-c t F" . "切换保存时格式化")
     ("C-c t c" . "同步颜色方案")
     ("C-c t h" . "文档弹窗开关")
     ("C-c t m" . "代码小地图"))
    ("应用"
     ("C-c a g ..." . "游戏")
     ("C-c a c" . "日历")
     ("C-c a m" . "邮件"))
     ("Org 扩展"
      ("C-c o a" . "议程")
      ("C-c o b ..." . "Babel 执行、跳转、Tangle")
      ("C-c o i / I" . "插入代码块 / 内联代码块")
      ("C-c o r ..." . "TODO、归档、窄化、标题")
      ("C-c o n ..." . "Org-roam 笔记")
      ("C-c o k ..." . "知识库（捕获、检索、AI 上下文）"))
    ("模式局部"
     ("Markdown: C-c p" . "预览 Markdown"))
    ("帮助"
     ("F1 ?" . "完整快捷键帮助")
     ("C-c h f / v / k / m" . "函数 / 变量 / 按键 / 模式帮助")
     ("C-c h B" . "查看当前上下文绑定")
     ("C-c h ?" . "打开这份帮助"))
    ("鼠标增强"
     ("右键" . "代码 / Git 上下文菜单")
     ("C-<mouse-1>" . "跳转到定义")
     ("M-<mouse-1>" . "添加多光标")
     ("S-<mouse-1>" . "扩展选区")
     ("<mouse-8> / <mouse-9>" . "后退 / 前进")))
  "完整快捷键帮助分组。")

(defun custom/help--extract-dashboard-bindings ()
  "返回 dashboard 需要展示的关键前缀绑定。"
  custom/help--dashboard-bindings)

(defun custom/help--insert-section (title bindings)
  "向当前 buffer 插入一个分类段落。
TITLE 为分类标题，BINDINGS 为 ((key . desc) ...) 列表。"
  (insert (propertize (format "═══ %s ═══" title)
                      'face '(:weight bold :foreground "#7aa2f7" :height 1.2)))
  (insert "\n\n")
  (dolist (binding bindings)
    (insert (format "  %-24s %s\n"
                    (propertize (car binding) 'face 'font-lock-keyword-face)
                    (cdr binding))))
  (insert "\n"))

(defun custom/show-help ()
  "显示完整的快捷键帮助。"
  (interactive)
  (let ((buf (get-buffer-create "*Shortcuts Help*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (special-mode)
        (insert "\n")
        (insert (propertize "快捷键参考（Emacs 前缀分组版）\n\n"
                            'face '(:height 1.5 :weight bold)))
        (insert "本配置不再使用单一总前缀。命令按“文件 / 项目 / 搜索 / 跳转 / 代码 / Git / 切换 / Org / 帮助”分布在多个前缀里。\n")
        (insert "由于 ")
        (insert (propertize "C-h" 'face 'font-lock-keyword-face))
        (insert " 保留给左移，帮助入口改为 ")
        (insert (propertize "F1 ?" 'face 'font-lock-keyword-face))
        (insert " 或 ")
        (insert (propertize "C-c h ?" 'face 'font-lock-keyword-face))
        (insert "。\n\n")
        (dolist (section custom/help--sections)
          (custom/help--insert-section (car section) (cdr section)))
        (insert (propertize "提示：" 'face '(:weight bold)))
        (insert " 按 ")
        (insert (propertize "q" 'face 'font-lock-keyword-face))
        (insert " 关闭此帮助窗口\n"))
      (goto-char (point-min)))
    (pop-to-buffer buf)))

(global-set-key (kbd "<f1> ?") #'custom/show-help)
(global-set-key (kbd "C-c h ?") #'custom/show-help)

(provide 'help)
;;; help.el ends here
