;;; undo.el --- 撤销可视化 -*- lexical-binding: t; -*-

;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; Commentary:
;; 配置 vundo — 可视化撤销树。
;;
;; 功能：
;; - 将 Emacs 的 undo 历史以树状结构可视化展示
;; - 分支查看：可以回到任何历史节点
;; - 紧凑显示模式，节省空间
;;
;; 快捷键：
;; - `C-c u v` — 打开 vundo 可视化界面
;;
;; vundo buffer 内导航：
;; - `j` / `k` — 上下移动
;; - `l` / `h` — 展开/折叠分支
;; - `RET` — 恢复到选中状态
;; - `q` — 退出

;;; Code:

;; ═════════════════════════════════════════════════════════════════════════════
;; Vundo - 可视化撤销树
;; ═════════════════════════════════════════════════════════════════════════════

(use-package vundo
  :defer t
  :commands (vundo)
  :bind (("C-c u v" . vundo))
  :custom
  (vundo-compact-display t)          ; 紧凑显示模式
  :config
  ;; vundo buffer 内的导航键
  (define-key vundo-mode-map (kbd "j") #'vundo-next)
  (define-key vundo-mode-map (kbd "k") #'vundo-previous)
  (define-key vundo-mode-map (kbd "l") #'vundo-forward)
  (define-key vundo-mode-map (kbd "h") #'vundo-backward)
  (define-key vundo-mode-map (kbd "q") #'vundo-quit)
  (define-key vundo-mode-map (kbd "RET") #'vundo-confirm))

(provide 'undo)
;;; undo.el ends here
