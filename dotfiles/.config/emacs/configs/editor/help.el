;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; help.el --- 快捷键帮助系统 -*- lexical-binding: t; -*-

;;; Commentary:
;; 提供完整的快捷键参考文档（仅 Leader 键系统）。

;;; Code:

(require 'cl-lib)

(defun my/show-shortcuts-help ()
  "显示完整的快捷键帮助。"
  (interactive)
  (let ((buf (get-buffer-create "*Shortcuts Help*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (special-mode)
        (insert "\n")
        (insert (propertize "快捷键参考（Leader 键系统）\n\n" 'face '(:height 1.5 :weight bold)))
        (insert "在 Evil Normal/Visual 模式下，按 ")
        (insert (propertize "SPC" 'face 'font-lock-keyword-face))
        (insert " 触发 Leader 键\n\n")

        (cl-labels
            ((section (title)
               (insert (propertize title 'face '(:weight bold :foreground "#7aa2f7" :height 1.2)))
               (insert "\n\n"))
             (row (key desc)
               (insert (format "  %-15s %s\n"
                              (propertize key 'face 'font-lock-keyword-face)
                              desc))))

          (section "═══ 文件操作 (SPC f) ═══")
          (row "SPC f f" "打开文件")
          (row "SPC f s" "保存文件")
          (row "SPC f S" "另存为")
          (row "SPC f r" "最近文件")
          (insert "\n")

          (section "═══ 缓冲区 (SPC b) ═══")
          (row "SPC b b" "切换缓冲区")
          (row "SPC b d" "关闭缓冲区")
          (row "SPC b k" "关闭指定缓冲区")
          (row "SPC b l" "列出缓冲区")
          (row "SPC b n" "下一个缓冲区")
          (row "SPC b p" "上一个缓冲区")
          (insert "\n")

          (section "═══ 窗口 (SPC w) ═══")
          (row "SPC w d" "关闭窗口")
          (row "SPC w D" "只保留当前窗口")
          (row "SPC w s" "水平分割")
          (row "SPC w v" "垂直分割")
          (row "SPC w h/j/k/l" "切换到左/下/上/右窗口")
          (row "SPC w o" "下一个窗口")
          (row "M-方向键" "切换窗口")
          (insert "\n")

          (section "═══ 项目 (SPC p) ═══")
          (row "SPC p f" "项目查找文件")
          (row "SPC p p" "切换项目")
          (row "SPC p s" "搜索项目")
          (row "SPC p d" "项目目录")
          (row "SPC p k" "关闭项目缓冲区")
          (insert "\n")

          (section "═══ 搜索 (SPC s) ═══")
          (row "SPC s s" "搜索当前文件")
          (row "SPC s p" "搜索项目")
          (row "SPC s b" "搜索缓冲区")
          (insert "\n")

          (section "═══ Git (SPC g) ═══")
          (row "SPC g s" "Git 状态")
          (row "SPC g b" "Git blame")
          (row "SPC g l" "Git 日志")
          (row "SPC g d" "Git 差异")
          (insert "\n")

          (section "═══ 切换 (SPC t) ═══")
          (row "SPC t t" "文件树")
          (row "SPC t v" "终端")
          (row "SPC t l" "工作区布局")
          (row "SPC t s" "功能栏")
          (insert "\n")

          (section "═══ Org (SPC o) ═══")
          (row "SPC o a" "议程")
          (row "SPC o c" "日历")
          (row "SPC o n f" "查找笔记")
          (row "SPC o n i" "插入笔记")
          (row "SPC o n l" "反向链接")
          (insert "\n")

          (section "═══ Markdown (Local Leader ,) ═══")
          (row ", p" "预览 Markdown")
          (insert "\n")

          (section "═══ 帮助 (SPC h) ═══")
          (row "SPC h f" "查看函数")
          (row "SPC h v" "查看变量")
          (row "SPC h k" "查看按键")
          (row "SPC h m" "查看模式")
          (row "SPC h ?" "快捷键帮助")
          (insert "\n")

          (section "═══ 快速操作 ═══")
          (row "SPC SPC" "执行命令 (M-x)")
          (row "SPC :" "执行表达式")
          (row "SPC q" "退出 Emacs")
          (insert "\n")

          (section "═══ Evil 模式 ═══")
          (row "i" "插入模式")
          (row "ESC" "返回普通模式")
          (row "h/j/k/l" "左/下/上/右移动")
          (row "w/b" "下一个/上一个单词")
          (row "0/$" "行首/行尾")
          (row "gg/G" "文件开头/结尾")
          (row "dd" "删除当前行")
          (row "yy" "复制当前行")
          (row "p/P" "粘贴到后面/前面")
          (row "u" "撤销")
          (row "C-r" "重做")
          (row "v/V/C-v" "可视/行/块模式")
          (insert "\n")

          (section "═══ 类 VS Code 快捷键 ═══")
          (row "C-s" "保存文件")
          (row "C-f" "查找当前文件")
          (row "C-p" "项目内查找文件")
          (row "C-S-f" "全文搜索")
          (row "C-S-b" "切换缓冲区")
          (row "C-S-c" "智能复制")
          (row "C-S-v" "粘贴")
          (insert "\n")

          (section "═══ 其他常用 ═══")
          (row "F5" "重建工作区布局")
          (row "F1 ?" "显示此帮助")
          (insert "\n\n")

          (insert (propertize "提示：" 'face '(:weight bold)))
          (insert " 按 ")
          (insert (propertize "q" 'face 'font-lock-keyword-face))
          (insert " 关闭此帮助窗口\n"))
        (goto-char (point-min))))
    (pop-to-buffer buf)))

;; 快捷键绑定
(global-set-key (kbd "<f1> ?") #'my/show-shortcuts-help)

(provide 'help)
;;; help.el ends here
