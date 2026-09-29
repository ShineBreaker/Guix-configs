;;; help-zh.el --- Localized Emacs data -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT
;; This file contains non-binding help copy only.  Binding rows are generated
;; from custom:binding-spec in emacs.org.

(setq custom:help-introduction
      '("本配置按 Emacs 原生前缀组织命令；下表由实际键位声明实时生成。"
        "C-h 保留为左移，F1 是原生帮助前缀，C-c h 提供内置 describe-* 入口。"))

;; Magit 状态页速查卡。键位核对自 Magit 4.7.1 的 magit-status-mode-map：
;; 状态页内单键不经过 custom/bind 声明，故以静态数据直接供帮助页渲染。
;; 改动键位或升级 Magit 后请同步本表，实时行为可在状态页按 C-h k 核对。
(setq custom:help-magit-notes
      '("状态页是一份分组清单：改动按「未跟踪/未暂存/已暂存」分组列出，改动集中"
        "的目录折叠为单条目。C-c g s 打开状态页。"
        "TAB 只折叠/展开分组，不是暂存；s 弹出的补全候选只列单个文件——整目录"
        "暂存请用 C-c g a（目录感知）或 Dired 面板内的 C-c s。"))

(setq custom:help-magit-keys
      '(("s" . "暂存光标处文件（弹补全，可多选）")
        ("S" . "暂存全部已修改文件")
        ("u" . "取消暂存光标处文件")
        ("U" . "取消全部暂存")
        ("c" . "提交：再按 c 写信息，C-c C-c 确认")
        ("P" . "推送：再按 u 推到上游")
        ("z" . "贮藏：再按 z 保存当前修改")
        ("k" . "丢弃光标条目的改动（带确认）")
        ("g" . "刷新状态页")
        ("?" . "弹出全部命令面板")
        ("TAB" . "折叠/展开分组")
        ("RET" . "打开光标处文件（进主编辑窗口）")))
