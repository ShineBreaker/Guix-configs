;;; lib.el --- 工具函数库 -*- lexical-binding: t; -*-

;;; Commentary:
;; 提供通用的工具函数，供其他模块使用。

;;; Code:

(defun my/load-config (category filename)
  "从 CATEGORY 目录加载 FILENAME 配置文件。"
  (let ((file (expand-file-name
               (concat category "/" filename)
               my/configs-dir)))
    (when (file-exists-p file)
      (load file nil t))))

(defun my/executable-find-required (command)
  "检查 COMMAND 是否存在，不存在时给出友好提示。"
  (or (executable-find command)
      (warn "未找到可执行文件: %s，请通过 Guix 安装" command)))

(provide 'lib)
;;; lib.el ends here
