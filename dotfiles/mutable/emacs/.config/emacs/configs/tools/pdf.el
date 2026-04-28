;;; pdf.el --- PDF 文档阅读 -*- lexical-binding: t; -*-

;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; Commentary:
;; 配置 PDF 文档阅读体验。
;;
;; 选型：
;; - pdf-tools: 专用 PDF 阅读器，支持更流畅的渲染、目录、搜索与注释
;; - doc-view: 缺少 pdf-tools 时的内置回退方案
;;
;; 快捷键：
;; - `C-x P`    打开 PDF 文件
;; - `C-c t p`  切换 PDF 护眼模式（pdf-view themed mode）
;; - `C-c t P`  PDF 适配窗口宽度
;;
;; 适配说明：
;; - 若 `pdf-tools' 可用，则优先注册 `pdf-view-mode'
;; - 若初始化失败，则自动回退到内置 `doc-view-mode'
;; - PDF 缓冲区默认关闭行号与 auto-revert，避免渲染/刷新冲突

;;; Code:

(defgroup custom/pdf nil
  "PDF 阅读相关设置。"
  :group 'tools)

(defcustom custom/pdf-doc-view-resolution 144
  "回退到 `doc-view-mode' 时使用的默认分辨率。"
  :type 'integer
  :group 'custom/pdf)

(defvar custom/pdf--pdf-tools-enabled nil
  "非 nil 表示当前会话已成功启用 pdf-tools。")

(autoload 'pdf-loader-install "pdf-loader" nil t)
(autoload 'pdf-view-mode "pdf-view" nil t)
(autoload 'pdf-view-fit-width-to-window "pdf-view" nil t)
(autoload 'pdf-view-themed-minor-mode "pdf-view" nil t)

(defun custom/pdf-open (file)
  "打开 PDF 文件 FILE。"
  (interactive
   (list
    (read-file-name "打开 PDF: " nil nil t nil
                    (lambda (candidate)
                      (or (file-directory-p candidate)
                          (string-match-p "\\.pdf\\'" candidate))))))
  (find-file file))

(defun custom/pdf-mode-common-setup ()
  "为 PDF 阅读缓冲区应用通用显示设置。"
  (display-line-numbers-mode -1)
  (auto-revert-mode -1))

(defun custom/pdf-view-mode-setup ()
  "为 `pdf-view-mode' 应用阅读优化。"
  (custom/pdf-mode-common-setup)
  (when (fboundp 'pdf-view-fit-width-to-window)
    (pdf-view-fit-width-to-window))
  (when (and (fboundp 'pdf-view-themed-minor-mode)
             (eq (frame-parameter nil 'background-mode) 'dark))
    (pdf-view-themed-minor-mode 1)))

(defun custom/doc-view-mode-setup ()
  "为 `doc-view-mode' 应用阅读优化。"
  (custom/pdf-mode-common-setup))

(defun custom/pdf-enable-fallback ()
  "回退到内置 `doc-view-mode'。"
  (setq custom/pdf--pdf-tools-enabled nil)
  (add-to-list 'auto-mode-alist '("\\.pdf\\'" . doc-view-mode))
  (setq doc-view-resolution custom/pdf-doc-view-resolution
        doc-view-continuous t))

(defun custom/pdf-setup-viewer ()
  "初始化 PDF 阅读后端。优先使用 `pdf-tools'，失败时回退到 `doc-view'。"
  (if (locate-library "pdf-loader")
      (condition-case err
          (progn
            (pdf-loader-install)
            (setq custom/pdf--pdf-tools-enabled t))
        (error
         (message "[pdf] pdf-tools 初始化失败，回退到 doc-view: %s"
                  (error-message-string err))
         (custom/pdf-enable-fallback)))
    (custom/pdf-enable-fallback)))

(defun custom/pdf-toggle-themed-view ()
  "切换当前 PDF 缓冲区的护眼模式。"
  (interactive)
  (if (derived-mode-p 'pdf-view-mode)
      (if (bound-and-true-p pdf-view-themed-minor-mode)
          (pdf-view-themed-minor-mode -1)
        (pdf-view-themed-minor-mode 1))
    (message "当前缓冲区不是 pdf-view-mode")))

(defun custom/pdf-fit-width ()
  "让当前 PDF 缓冲区按窗口宽度适配。"
  (interactive)
  (if (derived-mode-p 'pdf-view-mode)
      (pdf-view-fit-width-to-window)
    (message "当前缓冲区不是 pdf-view-mode")))

(use-package pdf-tools
  :defer t
  :commands (pdf-loader-install
             pdf-view-mode
             pdf-view-fit-width-to-window
             pdf-view-themed-minor-mode)
  :init
  (custom/pdf-setup-viewer)
  :config
  (setq-default pdf-view-display-size 'fit-width))

(add-hook 'pdf-view-mode-hook #'custom/pdf-view-mode-setup)
(add-hook 'doc-view-mode-hook #'custom/doc-view-mode-setup)

(provide 'pdf)
;;; pdf.el ends here
