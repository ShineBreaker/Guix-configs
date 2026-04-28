;;; org-knowledge.el --- 人机协作知识库 -*- lexical-binding: t; -*-

;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; Commentary:
;; 构建人机协作知识库：任务完成后（AI 或人类）自动生成经验卡片，
;; 后续任务启动时可检索相关经验，实现"自我进化"路线。
;;
;; 设计思路：
;; - 经验卡片使用 Org PROPERTIES + TAGS 结构化存储元数据
;; - 利用已有的 org-roam 建立经验间的双向链接
;; - 检索层复用 consult-ripgrep，不引入额外依赖（org-ql 不可用）
;; - AI 可精确解析 Org 语法，按模板写入经验卡片
;;
;; 知识库目录结构（位于 custom:org-directory 下）：
;; - inbox.org          快速捕获入口
;; - experiences/       经验卡片（org-roam 节点）
;; - patterns.org       提炼出的通用模式/原则
;; - index.org          知识库导航
;;
;; 模板文件位于配置目录（版本控制）：
;; - configs/org/templates/experience-template.org
;;
;; 标签体系：
;; - 技术栈：emacs python rust go ...
;; - 任务类型：debug refactor research workflow
;; - 难度/价值：easy hard
;; - 状态标记：verified deprecated
;;
;; 快捷键：
;; - C-c o k c    快速捕获经验
;; - C-c o k s    检索经验
;; - C-c o k i    插入相关经验到当前 buffer（AI 上下文注入）
;; - C-c o k p    打开模式/原则文件
;; - C-c o k I    打开知识库索引
;;
;; 索引重建：
;; - M-x custom/knowledge-rebuild-index  或  kb reindex
;;   扫描 experiences/ 按 CATEGORY 分组重建 index.org
;;
;; 作为 org-mode.el 的扩展，延迟加载直到 org 包加载完成。

;;; Code:

(require 'cl-lib)

;; ═════════════════════════════════════════════════════════════════════════════
;; 目录确保
;; ═════════════════════════════════════════════════════════════════════════════

(defun custom--ensure-knowledge-directories ()
  "确保知识库相关目录和索引文件存在。"
  ;; 确保 experiences 目录存在
  (unless (file-exists-p (expand-file-name "experiences" custom:org-directory))
    (make-directory (expand-file-name "experiences" custom:org-directory) t))
  ;; 确保索引文件存在
  (dolist (file (list custom:org-inbox-file
                      (expand-file-name "index.org" custom:org-directory)
                      (expand-file-name "patterns.org" custom:org-directory)))
    (unless (file-exists-p file)
      (let ((base (file-name-base file)))
        (with-temp-buffer
          (cond
           ((equal base "index")
            (insert (format "#+title: 知识库导航\n#+date: [%s]\n\n"
                            (format-time-string "%Y-%m-%d %a"))
                    "* 概览\n知识库暂无经验卡片。使用 =kb add= 或 =C-c o k c= 添加。\n使用 =kb reindex= 重建本索引。\n\n"
                    "* 收件箱\n  快速捕获入口：[[file:inbox.org][inbox.org]]\n\n"
                    "* 模式与原则\n  提炼出的通用模式/原则记录在 [[file:patterns.org][patterns.org]]。\n\n"
                    "* 按类别浏览\n（运行 kb reindex 或 M-x custom/knowledge-rebuild-index 生成）\n\n"
                    "* 快速入口\n"
                    "  - C-c o k c :: 快速捕获经验\n"
                    "  - C-c o k s :: 检索经验\n"
                    "  - C-c o k p :: 打开模式/原则\n"
                    "  - C-c o k I :: 打开本索引\n"
                    "  - kb reindex :: 重建本索引\n"))
           ((equal base "patterns")
            (insert (format "#+title: 模式与原则\n#+date: [%s]\n\n"
                            (format-time-string "%Y-%m-%d %a"))
                    "* 编码模式\n\n* 工作流模式\n\n* 常见陷阱与对策\n"))
           (t
            (insert (format "#+title: %s\n#+date: [%s]\n\n* Inbox\n"
                            base (format-time-string "%Y-%m-%d %a")))))
          (write-region (point-min) (point-max) file))))))

;; 延迟到空闲时创建，避免阻塞启动
(run-with-idle-timer 3 nil #'custom--ensure-knowledge-directories)

;; ═════════════════════════════════════════════════════════════════════════════
;; Capture 模板
;; ═════════════════════════════════════════════════════════════════════════════

(defun custom/knowledge--template-file ()
  "返回经验卡片模板文件的路径。
模板文件位于 configs/org/templates/ 下，跟随配置版本控制。"
  (expand-file-name "configs/org/templates/experience-template.org" custom:emacs-dir))

(defun custom/knowledge--setup-capture-templates ()
  "注册知识库相关的 Org Capture 模板。"
  (add-to-list
   'org-capture-templates
   `("k" "经验记录" entry
     (file+headline ,custom:org-inbox-file "Inbox")
     (file ,(custom/knowledge--template-file))
     :prepend t
     :empty-lines 1)
   t))

;; ═════════════════════════════════════════════════════════════════════════════
;; 检索函数
;; ═════════════════════════════════════════════════════════════════════════════

(defun custom/knowledge-search (query)
  "在知识库中检索经验。
使用 consult-ripgrep 搜索 QUERY，限定 experiences/ 和 patterns.org。"
  (interactive "s检索关键词: ")
  (let ((dir (expand-file-name "experiences" custom:org-directory))
        (patterns-file (expand-file-name "patterns.org" custom:org-directory)))
    (cond
     ((fboundp 'consult-ripgrep)
      (consult-ripgrep (list dir patterns-file) query))
     ((fboundp 'rgrep)
      (rgrep query "*.org" (list dir)))
     (t
      (message "未找到可用的搜索工具")))))

(defun custom/knowledge-search-by-tag (tag)
  "按标签检索经验。
TAG 为 Org 标签字符串（不含冒号）。"
  (interactive "s标签: ")
  (custom/knowledge-search (format ":%s:" tag)))

(defun custom/knowledge-insert-relevant (query)
  "插入与 QUERY 相关的历史经验到当前 buffer（供 AI 上下文注入）。
使用 ripgrep 快速检索，返回匹配的段落摘要。"
  (interactive "s关键词: ")
  (let* ((experiences-dir (expand-file-name "experiences" custom:org-directory))
         (patterns-file (expand-file-name "patterns.org" custom:org-directory))
         (rg-available (executable-find "rg"))
         results)
    (if (not rg-available)
        (message "需要 ripgrep 才能检索经验")
      ;; 用 ripgrep 搜索标题行和匹配行
      (with-temp-buffer
        (call-process "rg" nil t nil
                      "-l" query experiences-dir patterns-file)
        (goto-char (point-min))
        (while (not (eobp))
          (push (buffer-substring-no-properties
                 (line-beginning-position) (line-end-position))
                results)
          (forward-line 1)))
      (if (not results)
          (message "未找到相关经验: %s" query)
        (insert "\n* 相关历史经验\n")
        (dolist (file (nreverse results))
          (insert (format "** [[file:%s][%s]]\n" file (file-name-base file))))
        (insert "\n")
        (message "已插入 %d 条相关经验" (length results))))))

;; ═════════════════════════════════════════════════════════════════════════════
;; 导航函数
;; ═════════════════════════════════════════════════════════════════════════════

(defun custom/knowledge-open-index ()
  "打开知识库索引文件。"
  (interactive)
  (find-file (expand-file-name "index.org" custom:org-directory)))

(defun custom/knowledge-open-patterns ()
  "打开模式/原则文件。"
  (interactive)
  (find-file (expand-file-name "patterns.org" custom:org-directory)))

(defun custom/knowledge-open-inbox ()
  "打开知识库收件箱。"
  (interactive)
  (find-file custom:org-inbox-file))

(defun custom/knowledge-capture ()
  "快速捕获经验记录。"
  (interactive)
  (org-capture nil "k"))

;; ═════════════════════════════════════════════════════════════════════════════
;; 索引重建
;; ═════════════════════════════════════════════════════════════════════════════

(defun custom/knowledge-rebuild-index ()
  "扫描 experiences/ 目录，按 CATEGORY 属性分组重建 index.org。
使 index.org 成为按类别组织的导航索引。"
  (interactive)
  (let* ((index-file (expand-file-name "index.org" custom:org-directory))
         (exp-dir (expand-file-name "experiences" custom:org-directory))
         (patterns-file (expand-file-name "patterns.org" custom:org-directory))
         (inbox-file custom:org-inbox-file)
         (files (directory-files exp-dir t "\\.org\\'" t))
         entries categories)

    ;; 收集所有卡片元数据
    (dolist (f files)
      (with-temp-buffer
        (insert-file-contents f)
        (goto-char (point-min))
        (let* ((title (when (re-search-forward "^\\* \\(TODO\\|DONE\\|CANCELLED\\) +\\(.+\\)" nil t)
                        (match-string 2)))
               (category (when (re-search-forward "^:CATEGORY:[ \t]+\\(.+\\)$" nil t)
                           (string-trim (match-string 1))))
               (created (when (re-search-forward "^:CREATED:[ \t]+\\[\\([^]]+\\)\\]" nil t)
                          (match-string 1))))
          (push (list :file f
                      :title (or title (file-name-base f))
                      :category (or category "general")
                      :created (or created ""))
                entries))))

    ;; 收集分类（保持插入顺序）
    (dolist (e entries)
      (let ((cat (plist-get e :category)))
        (unless (member cat categories)
          (push cat categories))))
    (setq categories (nreverse categories))

    ;; 生成 index.org
    (with-temp-buffer
      (insert (format "#+title: 知识库导航\n#+date: [%s]\n\n" (format-time-string "%Y-%m-%d %a")))

      ;; 概览
      (insert (format "* 概览\n共 %d 条经验卡片，%d 个类别。\n使用 =kb reindex= 或 =M-x custom/knowledge-rebuild-index= 重建本索引。\n\n"
                      (length entries) (length categories)))

      ;; 收件箱
      (insert (format "* 收件箱\n  快速捕获入口：[[file:%s][%s]]\n\n"
                      (file-name-nondirectory inbox-file)
                      (file-name-base inbox-file)))

      ;; 模式与原则
      (insert (format "* 模式与原则\n  提炼出的通用模式/原则记录在 [[file:%s][%s]]。\n\n"
                      (file-name-nondirectory patterns-file)
                      (file-name-base patterns-file)))

      ;; 按类别浏览
      (if (null entries)
          (insert "* 按类别浏览\n知识库暂无经验卡片。使用 =kb add= 或 =C-c o k c= 添加。\n\n")
        (insert "* 按类别浏览\n")
        (dolist (cat categories)
          (let ((cat-entries (cl-remove-if-not
                              (lambda (e) (equal (plist-get e :category) cat))
                              entries)))
          (insert (format "** %s (%d)\n" cat (length cat-entries)))
          (dolist (e cat-entries)
            (let* ((f (plist-get e :file))
                   (relpath (concat "experiences/" (file-name-nondirectory f)))
                   (title (plist-get e :title))
                   (created (plist-get e :created))
                   ;; 只取日期部分
                   (date-part (if (string-match "^\\[?\\([0-9-]+\\)" created)
                                  (match-string 1 created)
                                "")))
              (insert (format "  - [[file:%s][%s]] (%s)\n" relpath title date-part))))
          (insert "\n"))))

      ;; 快速入口
      (insert "* 快速入口\n"
              "  - C-c o k c :: 快速捕获经验\n"
              "  - C-c o k s :: 检索经验\n"
              "  - C-c o k p :: 打开模式/原则\n"
              "  - C-c o k I :: 打开本索引\n"
              "  - kb reindex :: 重建本索引\n")

      (write-region (point-min) (point-max) index-file))

    (message "索引已重建: %d 条卡片, %d 个类别" (length entries) (length categories))

    ;; 如果 index.org 已在某个 buffer 中打开，刷新它
    (let ((buf (get-file-buffer index-file)))
      (when buf
        (with-current-buffer buf
          (revert-buffer t t t))))))

;; ═════════════════════════════════════════════════════════════════════════════
;; Agenda 集成
;; ═════════════════════════════════════════════════════════════════════════════

(defun custom/knowledge--setup-agenda ()
  "将经验目录加入 agenda 自定义命令。"
  (add-to-list
   'org-agenda-custom-commands
   '("K" "知识库回顾"
     ((tags "difficulties|lessons"
            ((org-agenda-files (list (expand-file-name "experiences" custom:org-directory)))
             (org-agenda-sorting-strategy '(timestamp-down))))))
   t))

;; ═════════════════════════════════════════════════════════════════════════════
;; 初始化
;; ═════════════════════════════════════════════════════════════════════════════

(with-eval-after-load 'org-capture
  (custom/knowledge--setup-capture-templates))

(with-eval-after-load 'org-agenda
  (custom/knowledge--setup-agenda))

(provide 'org-knowledge)
;;; org-knowledge.el ends here
