#!/usr/bin/env guile
!#

;; workspace.scm - 工作区快照管理
;; 用法：workspace.scm save <name>
;;       workspace.scm load <name> [--dry-run]
;;       workspace.scm list
;;       workspace.scm remove <name>

(load (string-append (getenv "HOME") "/.config/tmux/scripts/tmux-helpers.scm"))

(use-modules (json)
             (ice-9 match)
             (srfi srfi-1))

(define workspace-dir
  (string-append (or (getenv "XDG_DATA_HOME")
                     (string-append (getenv "HOME") "/.local/share"))
                 "/tmux/workspaces"))

(define (mkdir-p dir)
  "递归创建目录，类似 mkdir -p。"
  (unless (file-exists? dir)
    (mkdir-p (dirname dir))
    (mkdir dir)))

(define (ensure-workspace-dir)
  (unless (file-exists? workspace-dir)
    (mkdir-p workspace-dir)))

(define (workspace-path name)
  (string-append workspace-dir "/" name ".json"))

;; === 保存 ===

(define (save-workspace name)
  (ensure-workspace-dir)
  (let* ((current-session (tmux-display "#{session_name}"))
         (windows-raw (cdr (tmux-cmd "list-windows" "-t" current-session "-F"
                                      "#{window_index}\\t#{window_name}\\t#{window_layout}\\t#{pane_current_path}")))
         (window-lines (filter (lambda (l) (not (string=? l "")))
                               (string-split windows-raw #\newline)))
         (windows (map parse-window window-lines)))
    (let ((data `(("name" . ,name)
                  ("created" . ,(strftime "%Y-%m-%dT%H:%M:%S" (localtime (current-time))))
                  ("tmux_version" . ,(string-trim-both (cdr (tmux-cmd "-V"))))
                  ("windows" . ,windows))))
      (call-with-output-file (workspace-path name)
        (lambda (port) (scm->json data port)))
      (format #t "已保存工作区: ~a~%" name))))

(define (parse-window line)
  (match (string-split line #\tab)
    ((idx name layout path)
     `(("index" . ,(string->number idx))
       ("name" . ,name)
       ("layout" . ,layout)
       ("cwd" . ,path)))
    (_ `(("raw" . ,line)))))

;; === 加载 ===

(define (load-workspace name dry-run?)
  (let ((path (workspace-path name)))
    (unless (file-exists? path)
      (format (current-error-port) "工作区 '~a' 不存在~%" name)
      (exit 1))
    (let ((data (call-with-input-file path json->scm)))
      (if dry-run?
          (display-dry-run data)
          (restore-workspace data)))))

(define (display-dry-run data)
  (format #t "工作区: ~a~%" (assoc-ref data "name"))
  (format #t "创建时间: ~a~%" (assoc-ref data "created"))
  (format #t "tmux 版本: ~a~%" (assoc-ref data "tmux_version"))
  (format #t "~%注意：快照不恢复进程内部状态~%~%")
  (for-each
   (lambda (w)
     (format #t "  窗口 ~a: ~a (~a)~%"
             (assoc-ref w "index")
             (assoc-ref w "name")
             (assoc-ref w "cwd")))
   (assoc-ref data "windows")))

(define (restore-workspace data)
  (let ((session-name (format #f "ws-~a" (assoc-ref data "name"))))
    ;; 创建新 session
    (tmux-cmd "new-session" "-d" "-s" session-name)
    ;; 恢复窗口
    (for-each
     (lambda (w)
       (let ((cwd (assoc-ref w "cwd"))
             (wname (assoc-ref w "name")))
         (tmux-cmd "new-window" "-t" session-name "-n" wname "-c" cwd)))
     (assoc-ref data "windows"))
    ;; 关闭默认的第一个窗口
    (tmux-cmd "kill-window" "-t" (string-append session-name ":1"))
    ;; Attach
    (tmux-cmd "switch-client" "-t" session-name)
    (format #t "已恢复工作区: ~a~%" (assoc-ref data "name"))))

;; === 列表 ===

(define (list-workspaces)
  (ensure-workspace-dir)
  (let ((files (scandir workspace-dir
                         (lambda (f) (string-suffix? ".json" f)))))
    (if (null? files)
        (display "没有已保存的工作区\n")
        (for-each
         (lambda (f)
           (let* ((path (string-append workspace-dir "/" f))
                  (data (call-with-input-file path json->scm)))
             (format #t "~a  (~a)  ~a~%"
                     (assoc-ref data "name")
                     (assoc-ref data "tmux_version")
                     (assoc-ref data "created"))))
         files))))

;; === 删除 ===

(define (remove-workspace name)
  (let ((path (workspace-path name)))
    (if (file-exists? path)
        (begin (delete-file path)
               (format #t "已删除工作区: ~a~%" name))
        (begin (format (current-error-port) "工作区 '~a' 不存在~%" name)
               (exit 1)))))

;; === 主入口 ===

(let ((args (command-line)))
  (match args
    ((_ "save" name) (save-workspace name))
    ((_ "load" name "--dry-run") (load-workspace name #t))
    ((_ "load" name) (load-workspace name #f))
    ((_ "list") (list-workspaces))
    ((_ "remove" name) (remove-workspace name))
    (_ (format (current-error-port)
               "用法: workspace.scm <save|load|list|remove> [name] [--dry-run]~%")
       (exit 1))))
