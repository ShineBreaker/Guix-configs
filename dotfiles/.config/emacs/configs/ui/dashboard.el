;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; dashboard.el --- 启动仪表盘配置 -*- lexical-binding: t; -*-

;;; Commentary:
;; 配置启动仪表盘，集成文件管理器和常用功能入口。

;;; Code:

;; 快捷键帮助内容
(defun my/dashboard-insert-shortcuts (list-size)
  "在 dashboard 中插入快捷键帮助。"
  (dashboard-insert-heading "快捷键参考" "?" "按 F1 ? 查看完整帮助")
  (insert "\n")
  (let ((shortcuts '(("Leader 键 (SPC)"
                      ("SPC f f" "打开文件")
                      ("SPC p f" "项目查找文件")
                      ("SPC p s" "项目搜索")
                      ("SPC b b" "切换缓冲区"))
                     ("常用操作"
                      ("SPC g s" "Git 状态")
                      ("SPC t t" "文件树")
                      ("SPC t l" "工作区布局")
                      ("SPC a a" "AI 终端"))
                     ("帮助"
                      ("SPC h ?" "完整快捷键帮助")
                      ("SPC SPC" "执行命令 (M-x)")
                      ("C-c v v" "切换到 Vim 模式")))))
    (dolist (section shortcuts)
      (insert (propertize (car section) 'face 'dashboard-heading) "\n")
      (dolist (item (cdr section))
        (insert (format "  %-12s %s\n"
                       (propertize (car item) 'face 'font-lock-keyword-face)
                       (cadr item))))
      (insert "\n"))))

(use-package dashboard
  :custom
  (dashboard-startup-banner 'official)
  (dashboard-set-navigator t)
  (dashboard-items '((recents . 10)
                     (projects . 8)
                     (bookmarks . 8)
                     (shortcuts . 1)))
  (dashboard-set-heading-icons t)
  (dashboard-set-file-icons t)
  :config
  (add-to-list 'dashboard-item-generators '(shortcuts . my/dashboard-insert-shortcuts))
  (dashboard-setup-startup-hook))

(provide 'dashboard)
;;; dashboard.el ends here
