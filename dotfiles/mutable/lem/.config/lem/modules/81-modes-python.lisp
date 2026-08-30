;;; modules/modes/python.lisp — Python
;;;
;;; python-mode 镜像内建（缩进 tab-width 4 / 禁 tab 字符自带，
;;; run-python REPL 可用）。LSP 走 python-lsp-server（配置了 black 插件）。

(in-package :lem-user)

(vs-lsp-wire (vs$ :lem-python-mode "PYTHON-MODE")
             "python"
             '("pyproject.toml" "setup.py" "setup.cfg" "requirements.txt" ".git")
             '("pylsp"))
