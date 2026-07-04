;;; literal-keys.el --- 键位 + which-key 描述同源辅助 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai004@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; 替代旧配置的 `custom/bind!' 宏。
;;
;; 在 use-package 原生写法下，全局键位通常用 `keymap-global-set'（Emacs 29+）
;; 或 `global-set-key'。但 which-key 的中文描述需要单独调
;; `which-key-add-key-based-replacements'，导致「绑定」与「描述」分离。
;;
;; 本模块提供 `literal/set-key'：一行完成绑定 + which-key 描述注册。
;;
;;   (literal/set-key "C-s" #'save-buffer "保存")
;;   (literal/set-key "C-h" #'backward-char "左移")
;;
;; 比 use-package :bind 更适合本配置「全局直达键集中维护」的风格。
;; use-package :bind 仍用于包内键位（如 embark / consult / corfu-map）。

;;; Code:

(defun literal/set-key (key command &optional desc)
  "全局绑定 KEY 到 COMMAND，可选用 DESC 注册 which-key 中文描述。
KEY 与 DESC 均为字符串。DESC 为 nil 时只做绑定。
此函数替代旧配置的 `custom/bind!' 宏。

Emacs 31 的 `keymap-global-set' 走严格 `key-valid-p'：
修饰键必须写在 <> 外部（\"C-<tab>\" 而非 \"<C-tab>\"）。
本函数对包含 `<' 的 KEY 自动转换格式，兼容旧式写法。"
  (keymap-global-set key command)
  (when (and desc (stringp desc))
    (with-eval-after-load 'which-key
      (which-key-add-key-based-replacements key desc))
    (push (cons key desc) literal--pending-wk-descs)))

(defvar literal--pending-wk-descs nil
  "literal/set-key 收集的键位描述，which-key 加载后批量注册。")

(defun literal/register-pending-wk-descs ()
  "把 `literal--pending-wk-descs' 注册到 which-key（一次性）。"
  (dolist (entry (nreverse literal--pending-wk-descs))
    (which-key-add-key-based-replacements (car entry) (cdr entry)))
  (setq literal--pending-wk-descs nil))

(provide 'literal-keys)
;;; literal-keys.el ends here
