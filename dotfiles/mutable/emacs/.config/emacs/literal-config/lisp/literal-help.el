;;; help.el --- 快捷键帮助系统 -*- lexical-binding: t; -*-

;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: MIT

;;; Commentary:
;; 快捷键帮助系统。
;;
;; 由于交互层已从单一总前缀改为 Emacs 风格的多前缀分组,
;; 本文件不再尝试从源码动态解析键位,而是直接维护一份中文分组总览。
;; which-key 的中文菜单文本则集中维护在 `configs/i18n/which-key-descriptions.el`。
;;
;; 帮助入口:
;; - `F1 ?` - 快捷键参考
;; - `F1 i/b/k/f/v/m/r` - Emacs 内建 help-map(Info / describe-* / manual)
;; - `C-c h f/v/k/m` - helpful 增强版(函数/变量/按键/模式)
;; - `C-c h ?` - 快捷键参考(同 F1 ?)
;;
;; 设计目标:
;; - 用中文分组描述前缀键的职责
;; - 把 Emacs 原生前缀和自定义前缀放在同一页里
;; - 让 dashboard 也能复用一份精简版概览

;;; Code:

(defface literal-help-section-title
  '((t :weight bold :height 1.2))
  "帮助缓冲区分类标题样式。前景色由 color-scheme hook 统一设置。"
  :group 'help)

(defconst literal/help--dashboard-bindings
  '(("C-x" . "文件 / 缓冲区 / 窗口 / 标签")
    ("C-x p" . "项目")
    ("M-s" . "搜索")
    ("M-g" . "跳转 / 错误")
    ("C-c l" . "代码 / LSP")
    ("C-c d" . "调试")
    ("C-c g" . "Git")
    ("C-c w" . "窗口创建:文件查找、缓冲区、终端、Agent、目录、小地图")
    ("C-c a" . "应用:Agent、日历、邮件、Telegram、Matrix、游戏")
    ("C-c o" . "Org:议程、Babel、任务、笔记、知识库"))
  "Dashboard 展示用的精简前缀总览。")

(defconst literal/help--sections
  '(("基础移动与直达键"
     ("C-h / C-j / C-k / C-l" . "左移 / 下移 / 上移 / 右移")
     ("方向键" . "保留原生光标移动")
     ("C-z / C-S-z" . "撤销 / 重做")
     ("C-a" . "全选")
     ("C-/ / C-_" . "注释 / 取消注释")
     ("C-S-c" . "智能复制(ghostel 内:进入 copy-mode)")
     ("C-S-v" . "粘贴(ghostel 内:粘贴到终端)")
     ("C-s" . "保存")
     ("C-f" . "当前缓冲区搜索")
     ("C-p" . "项目内查找文件")
     ("C-S-f" . "项目全文搜索")
     ("C-S-b" . "切换缓冲区")
     ("C-S-o" . "当前文件符号大纲")
     ("C-S-j" . "屏幕内快速跳转")
     ("C-S-p" . "命令面板")
     ("F2" . "重命名符号 / 文件")
      ("C-= / C-- / C-0" . "放大 / 缩小 / 重置缩放")
      ("M-方向键" . "切换窗口")
      ("C-S-x" . "智能剪切(行/选区)")
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
     ("C-x s ..." . "选择前缀:多光标、整行、代码块、扩缩选区")
     ("C-Tab / C-S-Tab" . "下一个 / 上一个标签")
     ("C-x t n / p" . "下一个 / 上一个标签")
     ("C-x t g" . "按项目分组标签")
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
     ("M-g j / C-S-j" . "屏幕内快速跳转")
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
       ("C-c l x ..." . "LSP 扩展(声明/实现/类型定义)"))
     ("LSP 扩展(eglot-x)"
      ("C-c l x d" . "跳转到声明")
      ("C-c l x i" . "跳转到实现")
      ("C-c l x t" . "跳转到类型定义"))
    ("格式化"
     ("C-c f f" . "智能格式化")
     ("C-c f b" . "格式化整个缓冲区")
     ("C-c f r" . "格式化选区")
     ("C-c f i / I" . "增加 / 减少缩进"))
    ("编辑变换"
     ("C-c e l ..." . "行操作:复制、移动、空行、清理")
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
     ("<backtab>" . "切换当前折叠")
     ("C-c z a" . "切换当前折叠")
     ("C-c z c / o" . "关闭 / 打开当前折叠")
     ("C-c z m / r" . "全部折叠 / 全部展开"))
     ("Git"
      ("C-x g" . "Magit 状态页")
      ("C-c g s" . "版本控制状态")
      ("C-c g b / l / d / t" . "追责 / 日志 / 差异 / 时光机")
      ("C-c g S / D" . "暂存 / 丢弃当前文件")
      ("C-c g F / P" . "拉取 / 推送")
      ("C-c g # / @" . "暂存修改 / 恢复暂存")
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
     ("窗口创建"
     ("C-c w t" . "切换工作区布局")
     ("C-c w r" . "按项目分组缓冲区")
     ("C-c w d" . "目录浏览")
     ("C-c w v" . "打开终端")
     ("C-c w a" . "切换 Agent 面板")
     ("C-c w u / U" . "撤销 / 重做窗口布局"))
    ("应用"
     ("C-c a a" . "Agent Shell 子菜单(按 a 展开后可选 a/r/d/n/k/s/b)")
     ("C-c a a a" . "切换 Agent 面板显示/隐藏")
     ("C-c a a r" . "重载 Agent")
     ("C-c a a d" . "Agent 切换目录")
     ("C-c a a n" . "新建 Agent Shell")
     ("C-c a a k" . "关闭 Agent Shell")
     ("C-c a a s" . "选择 Agent Shell")
     ("C-c a a b" . "选择 Agent 后端(agent-shell / ghostel)")
     ("C-c a g ..." . "游戏")
     ("C-c a c" . "日历")
     ("C-c a m" . "邮件")
     ("C-c a t t / b / c" . "Telegram:打开 / 切换 buffer / 选择聊天")
     ("C-c a t u / i / s / k" . "Telegram:未读 / 重要 / Saved Messages / 关闭")
     ("C-c a e e" . "Matrix 房间列表(主入口)")
     ("C-c a e c / l / r" . "Matrix:连接 / 房间列表 / 打开房间")
     ("C-c a e f / n / j" . "Matrix:公开目录 / 新建房间 / 加入房间")
     ("C-c a e d / D" . "Matrix:断开当前 / 断开所有"))
     ("Org 扩展"
      ("C-c o a" . "议程视图")
      ("C-c o f" . "打开待办文件")
      ("C-c o b ..." . "Babel:执行、跳转、Tangle、编辑")
      ("C-c o i / I" . "插入代码块 / 内联代码块")
      ("C-c o r ..." . "任务:标记完成/TODO、归档、窄化、添加标题")
      ("C-c o n f" . "查找或新建笔记(org-roam)")
      ("C-c o n i" . "在当前笔记中插入链接")
      ("C-c o n l" . "切换笔记反向链接面板")
      ("C-c c n" . "新建笔记(问题排查/决策/学习/通用)")
      ("C-c o k c" . "新建经验卡片")
      ("C-c o k r" . "重命名为 <标题>-<时间戳>")
      ("C-c o k R" . "批量重命名所有卡片")
      ("C-c o k s" . "全文检索经验")
      ("C-c o k t" . "按标签检索经验")
      ("C-c o k a" . "归档 inbox 条目到 experiences/")
      ("C-c o k I" . "打开收件箱")
      ("C-c o k S" . "知识库统计")
      ("C-c o k v" . "可视化知识库(类别树/时间线)")
      ("C-c o k V" . "在浏览器打开知识库可视化")
      ("C-c c i / o / g" . "开始计时 / 停止计时 / 跳到当前计时"))
    ("模式局部"
     ("Markdown: C-c p" . "预览 Markdown"))
    ("帮助"
     ("F1 ?" . "完整快捷键帮助")
     ("F1 i" . "Info 浏览器(Emacs/elisp manual)")
     ("F1 b" . "列出所有键位")
     ("F1 k" . "查按键绑定")
     ("F1 f" . "查函数")
     ("F1 v" . "查变量")
     ("F1 m" . "查模式")
     ("F1 r" . "Emacs Manual")
     ("C-c h f / v / k / m" . "helpful 增强:函数 / 变量 / 按键 / 模式")
     ("C-c h ?" . "打开这份帮助"))
    ("终端(ghostel 内专用)"
     ("C-S-c" . "进入 / 退出 copy-mode(冻结输出、选择复制)")
     ("C-S-v" . "从 kill-ring 粘贴到终端")
     ("C-h" . "发送原始 Ctrl+H 给终端(C-j/k/l 默认已发)")
     ("C-c C-c" . "发送中断信号")
     ("C-c C-t / C-y / M-l" . "复制模式 / 粘贴 / 清屏"))
    ("Agent Shell 终端(viewport 内专用)"
     ("C-c C-c" . "发送(edit 模式)/ 中断(view 模式)")
     ("C-c C-p / C-c C-k / C-c C-h" . "预览上次 / 取消 / 帮助菜单(edit 模式)")
     ("C-c C-m / C-c C-v" . "设置会话模式 / 模型")
     ("C-c C-o" . "其他缓冲区")
     ("C-<tab>" . "切换会话模式")
     ("M-p / M-n / M-r" . "上一条 / 下一条 / 搜索历史(edit 模式)")
     ("TAB / <backtab>" . "下一项 / 上一项")
     ("n / p" . "下一项 / 上一项")
     ("f / b" . "下一页 / 上一页(view 模式)")
     ("r / y" . "回复 / 回复 Yes(view 模式)")
     ("1-9" . "回复选项 1-9(view 模式)")
     ("q" . "关闭缓冲区(view 模式)")
     ("v / s" . "设置会话模型 / 模式(view 模式)")
     ("m / a / c" . "更多 / 再次 / 继续回复(view 模式)")
     ("o" . "其他缓冲区(view 模式)")
     ("?" . "帮助菜单(view 模式)"))
    ("鼠标增强"
     ("右键" . "代码 / Git 上下文菜单")
     ("C-<mouse-1>" . "跳转到定义")
     ("M-<mouse-1>" . "添加多光标")
     ("S-<mouse-1>" . "扩展选区")
     ("<mouse-8> / <mouse-9>" . "后退 / 前进")))
  "完整快捷键帮助分组。")

(defun literal/help--extract-dashboard-bindings ()
  "返回 dashboard 需要展示的关键前缀绑定。"
  literal/help--dashboard-bindings)

(defun literal/help--insert-section (title bindings)
  "向当前 buffer 插入一个分类段落。
TITLE 为分类标题,BINDINGS 为 ((key . desc) ...) 列表。"
  (insert (propertize (format "═══ %s ═══" title)
                      'face 'literal-help-section-title))
  (insert "\n\n")
  (dolist (binding bindings)
    (insert (format "  %-24s %s\n"
                    (propertize (car binding) 'face 'font-lock-keyword-face)
                    (cdr binding))))
  (insert "\n"))

(defun literal/show-help ()
  "显示完整的快捷键帮助。"
  (interactive)
  (let ((buf (get-buffer-create "*Shortcuts Help*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (special-mode)
        (insert "\n")
        (insert (propertize "快捷键参考(Emacs 前缀分组版)\n\n"
                            'face '(:height 1.5 :weight bold)))
        (insert "本配置不再使用单一总前缀。命令按"文件 / 项目 / 搜索 / 跳转 / 代码 / Git / 切换 / Org / 帮助"分布在多个前缀里。\n")
        (insert "由于 ")
        (insert (propertize "C-h" 'face 'font-lock-keyword-face))
        (insert " 保留给左移，帮助入口改为 ")
        (insert (propertize "F1" 'face 'font-lock-keyword-face))
        (insert " 前缀（F1 i = Info, F1 f = 查函数, ...）；增强版帮助用 ")
        (insert (propertize "C-c h" 'face 'font-lock-keyword-face))
        (insert " 前缀。\n")
        (insert "按 ")
        (insert (propertize "F1 ?" 'face 'font-lock-keyword-face))
        (insert " 或 ")
        (insert (propertize "C-c h ?" 'face 'font-lock-keyword-face))
        (insert " 打开这份完整参考。\n\n")
        (dolist (section literal/help--sections)
          (literal/help--insert-section (car section) (cdr section)))
        (insert (propertize "提示:" 'face '(:weight bold)))
        (insert " 按 ")
        (insert (propertize "q" 'face 'font-lock-keyword-face))
        (insert " 关闭此帮助窗口\n"))
      (goto-char (point-min)))
    (pop-to-buffer buf)))

(global-set-key (kbd "<f1> ?") #'literal/show-help)
(global-set-key (kbd "C-c h ?") #'literal/show-help)

(provide 'literal-help)
;;; help.el ends here
