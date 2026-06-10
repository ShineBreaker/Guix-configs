# C. Emacs 与外部工具集成的最佳范式

> 研究范围: doomemacs (doom3) + spacemacs
> 重点: 集成模式, 不是工具本身的文档
> 所有代码引用: `<绝对路径>:<行号>`

---

## 0. 摘要

Emacs 之所以"长青"是因为它把自己定位为"协调外部世界工具的中枢神经"——当内置实现变慢、变难、变脆时, 用合适的外部程序替换 elisp 实现, 几乎总是更优解。

本研究从两个最成熟发行版 (doomemacs + spacemacs) 的代码库中提取了**可复用的集成模式**, 涵盖:

- 检测缺失依赖并优雅降级
- 跨平台 PATH/exec-path 处理 (macOS, WSL, Flatpak, tty)
- 用 ripgrep/fd/jq/tree-sitter/LSP server/magit/vterm 加速 Emacs 内部操作
- AI 客户端 (gptel) 集成
- "按需开关全局变量" 的 minor-mode 范式
- 异步 vs 同步 trade-off

核心结论:

1. **doom 用 `executable-find` 硬错误 + `doctor.el` 软警告的双层防御**, spacemacs 用 `dotspacemacs-search-tools` 列表做软降级
2. **`+lsp-optimization-mode` 模式** (打开时调高 `read-process-output-max`, 关闭时还原) 是跨领域可复用的
3. doom 用 `doom env` 文件代替 `exec-path-from-shell`, 启动期**零进程** — 这是"批量外部状态注入"的更优解
4. **tree-sitter 集成 doom 选择"内置优先 + 旁路外部包"** 是 Emacs 29+ 时代最干净的选择
5. **异步 grep 必须用 consult/counsel 模式** (`--null --line-buffered`), 同步 grep 用 rgrep + find-name-dired 已经过时

---

## 1. 子问题 1: 检测外部依赖的模式

### 1.1 doom 的双层防御: 运行时硬错误 + 启动期 doctor

**运行时硬错误** (调用时直接 `user-error`, 不降级):

```elisp
;;; modules/completion/helm/autoload/helm.el:42-50
(defun +helm-file-search (&key query in all-files (recursive t) _prompt args)
  (declare (indent defun))
  (unless (executable-find "rg")
    (user-error "Couldn't find ripgrep in your PATH"))
  (require 'helm-rg)
  ...)
```

特征:

- 错误信息包含工具名 ("ripgrep")
- 不给降级路径 — 因为 helm 内部已经基于 helm-rg 设计, 退到内置 grep 反而更糟
- 用户**主动调用**时立即抛错, 比静默失败好

**启动期 doctor** (`doctor.el` 在 `bin/doom doctor` 时执行, 不阻塞启动):

```elisp
;;; modules/completion/vertico/doctor.el:9-21
(when (require 'consult nil t)
  (if (executable-find "rg")
      ;; TODO: Move this to core in v3.0
      (unless (consult--grep-lookahead-p "rg" "-P")
        (warn! "The installed ripgrep binary was not built with support for PCRE lookaheads.")
        (explain! "Some advanced consult filtering features will not work as a result, see the module readme."))
    (if (executable-find "grep")
        (unless (consult--grep-lookahead-p "grep" "-P")
          (warn! "The installed grep binary was not built with support for PCRE lookaheads")
          (explain! "Some advanced consult filtering features will not work as a result, see the module readme."))
      (error! "Neither grep nor ripgrep are available on this system")
      (explain! "Various file and project search features won't be available"))))
```

特征:

- 软警告 (`warn!`) vs 硬错误 (`error!`) 分级
- 降级链: `rg → grep → (error!)`
- 解释文本 (`explain!`) 给出具体补救指南
- 用 `consult--grep-lookahead-p` 做**深度健康检查**: 不仅是 "rg 装没装", 而是 "rg 是不是 PCRE lookahead 编译版"

**Emacs 构建能力检查**:

```elisp
;;; modules/tools/tree-sitter/doctor.el
(unless (bound-and-true-p module-file-suffix)  ; requires dynamic-modules support
  (error! "Emacs not built with dynamic modules support"))

(if (version< emacs-version "29.1")
    (error! "Emacs 29.1 or newer is required for tree-sitter support")
  (unless (treesit-available-p)
    (error! "Emacs not built with tree-sitter support!")))
```

- `(bound-and-true-p module-file-suffix)` 是检测 Emacs 是否支持动态模块的标准 idiom
- 三层检查: 模块支持 → 版本 → 实际可用

**核心模块冲突检测**:

```elisp
;;; modules/completion/ivy/doctor.el
(dolist (module '(helm ido vertico))
  (when (doom-module-active-p :completion module)
    (error! "This module is incompatible with :completion %s; disable one or the other"
            module)))
```

- 在配置层做不变量检查, 比运行时随机行为好

### 1.2 spacemacs 的"软降级列表"模式

spacemacs 用 `dotspacemacs-search-tools` 让用户声明**优先级列表**, 而不是写死选择:

```elisp
;;; core/core-dotspacemacs.el:701
(spacemacs|defc dotspacemacs-search-tools '("rg" "ag" "ack" "grep")
  ...)
```

然后在 helm 层动态构建 cond:

```elisp
;;; layers/+completion/helm/funcs.el:115-128
(defun spacemacs//helm-do-search-find-tool (base tools default-inputp)
  "Create a cond form given a TOOLS string list and evaluate it."
  (eval
   `(cond
     ,@(mapcar
        (lambda (x)
          `((executable-find ,x t)
            ',(let ((func
                     (intern
                      (format (if default-inputp
                                  "spacemacs/%s-%s-region-or-symbol"
                                "spacemacs/%s-%s")
                              base x))))
                (if (fboundp func)
                    func
                  (intern (format "%s-%s"  base x))))))
        tools)
     (t 'helm-do-grep))))
```

特征:

- `executable-find ,x t` 用 `t` 参数也搜远程文件
- 找不到任何工具时退回 `helm-do-grep` (内置)
- 通过 `intern` 动态拼接函数名, 同一个框架支持 `helm-files-do-rg`, `helm-files-do-ag`, `helm-files-do-ack`

**ripgrep 特定配置** (版本感知):

```elisp
;;; layers/+completion/helm/funcs.el:168-177
(defun spacemacs/helm-files-do-rg (&optional dir)
  "Search in files with `rg'."
  (interactive)
  (let* ((root-helm-ag-base-command "rg --smart-case --no-heading --color=never --line-number")
         (helm-ag-base-command (if spacemacs-helm-rg-max-column-number
                                   (concat root-helm-ag-base-command " --max-columns=" (number-to-string spacemacs-helm-rg-max-column-number))
                                 root-helm-ag-base-command)))
    (helm-do-ag dir)))
```

### 1.3 缺 eglot → 退到 lsp-mode 的"分发"模式

doom 的 `lsp!` 宏做客户端分发, 模块选择不影响调用:

```elisp
;;; modules/tools/lsp/autoload/common.el
;;;###autodef (fset 'lsp! #'ignore)
(defun lsp! ()
  "Dispatch to call the currently used lsp client entrypoint"
  (if (modulep! +eglot)
      (when (require 'eglot nil t)
        (if (eglot--lookup-mode major-mode)
            (eglot-ensure)
          (eglot--message "No client defined for %s" major-mode)))
    (unless (bound-and-true-p lsp-mode)
      (lsp-deferred))))
```

特征:

- 用户写 `M-x lsp!` 就能用, 不需要知道当前是 eglot 还是 lsp-mode
- `modulep!` 是 doom 的编译期宏, 零开销分发

### 1.4 缺 vterm-module → 退到 term 的模块加载守卫

```elisp
;;; modules/term/vterm/config.el
(use-package! vterm
  :when (bound-and-true-p module-file-suffix)  ; requires dynamic-modules support
  ...)
```

- 模块根本不被声明, 用户写 `M-x vterm` 时会得到 `command not defined`
- 配合 `doctor.el` 的 `(unless (fboundp 'module-load) (warn! ...))`, 用户知道为什么缺

### 1.5 范式总结表

| 范式                                                 | 触发点            | 缺工具时行为   | 适用                                  |
| ---------------------------------------------------- | ----------------- | -------------- | ------------------------------------- |
| 运行时硬错误 (`user-error`)                          | 用户主动调用      | 立即抛错       | 工具是核心依赖 (rg, fd)               |
| 启动期 doctor (`warn!`/`error!`)                     | `bin/doom doctor` | 仅打印诊断     | 所有外部工具                          |
| 软降级列表 (spacemacs)                               | 用户配置          | 按列表首个可用 | 多个等价工具 (rg/ag/ack/grep)         |
| 模块宏分发 (`modulep!`)                              | 编译期            | 编译期决定     | 完整后端替换 (eglot vs lsp-mode)      |
| 模块加载守卫 (`bound-and-true-p module-file-suffix`) | 加载期            | 模块不声明     | 需要动态模块的包 (vterm, tree-sitter) |

**反模式**:

- ❌ 静默降级 (用 `if-let*` 包裹, 不告诉用户为什么没 rg)
- ❌ 在所有调用点重复 `(executable-find "rg")` — 应该一次检测, 缓存结果

---

## 2. 子问题 2: exec-path 与 GUI 启动问题

### 2.1 问题根源

macOS / WSL / Flatpak 下, Emacs GUI 是从 Finder / 文件管理器 / .desktop 文件启动的, **不继承用户 shell rc**. 结果:

- `(executable-find "rg")` → nil (因为 Homebrew 的 bin 不在默认 PATH)
- LSP 启动 → "command not found"
- Tree-sitter 找不到 cc, c++

### 2.2 doom 的方案: `doom env` 文件 (替代 exec-path-from-shell)

**doom 官方明确反对 `exec-path-from-shell`**:

```elisp
;;; lisp/cli/env.el:73-92 (in `defcli! env')
  Why this over exec-path-from-shell?

  1. `exec-path-from-shell' spawns (at least) one process at startup to scrape
     your shell environment. This can be arbitrarily slow depending on the
     user's shell configuration. A single program (like pyenv or nvm) or config
     framework (like oh-my-zsh) could undo all of Doom's startup optimizations
     in one fell swoop.

  2. `exec-path-from-shell' only scrapes some state from your shell. You have to
     be proactive in order to get it to capture all the envvars relevant to your
     development environment.

     I'd rather it inherit your shell environment /correctly/ (and /completely/)
     or not at all.
```

**实现**:

- 用户在终端运行 `doom env`, doom 调用 `$SHELL -ic env` 抓取环境
- 写入 `doom-env-file` (默认 `<profile-dir>/env`)
- 启动时 `doom-load-envvars-file` 读这个文件, 设置 `process-environment`, `exec-path`, `shell-file-name`:

```elisp
;;; lisp/doom-lib.el:225-244
;;; DEPRECATED: Remove in v3 (where the envvar file will be an elisp file)
(defun doom-load-envvars-file (file &optional noerror)
  "Read and set envvars from FILE..."
  (if (null (file-exists-p file))
      (unless noerror
        (signal 'file-error (list "No envvar file exists" file)))
    (with-temp-buffer
      (insert-file-contents file)
      (when-let* ((env (read (current-buffer))))
        (let ((tz (getenv-internal "TZ")))
          (setq-default
           process-environment
           (append env (default-value 'process-environment))
           exec-path
           (append (split-string (getenv "PATH") path-separator t)
                   (list exec-directory))
           shell-file-name
           (or (getenv "SHELL")
               (default-value 'shell-file-name)))
          ...))))
```

**优势**:

- 启动时**零进程** (不调用 shell)
- 用户可以预览生成的文件
- `doom env -a 'PYENV_*' -d 'XDG_*'` 允许/拒绝特定变量
- 配合 `doom sync` 自动重新生成

### 2.3 平台特定 exec-path 处理

**doom 平台检测** (用 `:system` pseudo-feature):

```elisp
;;; lisp/doom.el:120-130
(defconst doom-system
  (pcase system-type
    ('darwin                           '(macos bsd))
    ((or 'cygwin 'windows-nt 'ms-dos)  '(windows))
    ((or 'gnu 'gnu/linux)              '(linux))
    ((or 'gnu/kfreebsd 'berkeley-unix) '(linux bsd))
    ('android                          '(android)))
  "A list of symbols denoting available features in the active Doom profile.")

(defconst doom--system-macos-p   (eq 'macos   (car doom-system)))
(defconst doom--system-windows-p (eq 'windows (car doom-system)))
(defconst doom--system-linux-p   (eq 'linux   (car doom-system)))
```

**WSL 检测**:

```elisp
;;; lisp/doom.el:132-138
(when (and doom--system-linux-p
           (if (boundp 'operating-system-release) ; is deprecated since 28.x
               (string-match-p "-[Mm]icrosoft" operating-system-release)
             (getenv-internal "WSLENV")))
  (add-to-list 'doom-system 'wsl 'append))
```

- `WSLENV` 是 WSL 注入的环境变量
- 之后用 `(featurep :system 'wsl)` 判断

**平台特定条件** (模块内使用):

```elisp
;;; modules/os/macos/config.el:5
(setq locate-command "mdfind")  ; macOS Spotlight as M-x locate
```

**doom-bind-fd-executable 跨平台**:

```elisp
;;; lisp/doom-projects.el:12-15
(defvar doom-fd-executable (cl-find-if #'executable-find (list "fdfind" "fd"))
  "On some distros it's fdfind (ubuntu, debian, and derivatives). On most it's fd.
Is nil if no executable is found in your PATH during startup.")
```

- `cl-find-if` + 列表 = "第一个能找到的可执行文件名"
- 关键: 这是**启动期一次性绑定**的 defvar, 不是每次调用都查

```elisp
(defvar doom-ripgrep-executable (executable-find "rg")
  "Is nil if no executable is found in your PATH during startup.")
```

### 2.4 spacemacs 的等价处理 (Pyenv 版)

```elisp
;;; layers/+lang/python/funcs.el:130-150
(defun spacemacs/pyenv-executable-find (commands)
  "Find executable taking pyenv shims into account.
COMMANDS may also be a single string, for backwards compatibility."
  (unless (listp commands)
    (setq commands (list commands)))
  (if (or (bound-and-true-p pyvenv-virtual-env) ; in virtualenv
          (not (executable-find "pyenv")))      ; or no pyenv
      (cl-some (lambda (dir)
                 (let ((exec-path (list dir)))
                   (cl-find-if 'executable-find commands)))
               exec-path)
    (let ((pyenv-vers (split-string (string-trim (shell-command-to-string "pyenv version-name")) ":")))
      (cl-some
       (lambda (cmd)
         (when-let* ((pyenv-cmd (string-trim (shell-command-to-string (concat "pyenv which " cmd))))
                     ((not (string-match "not found" pyenv-cmd))))
           (cl-some
            (lambda (ver)
              (cond ((string-match ver pyenv-cmd) pyenv-cmd)
                    ((string-match ver "system") (and (executable-find cmd) cmd))))
            pyenv-vers)))
       commands))))
```

**关键技巧**:

- `pyenv which <cmd>` 给当前激活版本的实际路径
- 在 venv 内直接走 `executable-find`
- 多个候选命令 (e.g. `("ipython3" "ipython" "python3" "python")`)

### 2.5 范式总结

| 场景                              | 推荐方案                                            | 反例                                       |
| --------------------------------- | --------------------------------------------------- | ------------------------------------------ |
| macOS/Linux GUI 启动缺 PATH       | doom `doom env` (启动期零进程)                      | `exec-path-from-shell-initialize` (启动慢) |
| WSL                               | 检测 `WSLENV` + `operating-system-release`          | 假设 `$PATH` 正确                          |
| 跨发行版命令名差异 (fd vs fdfind) | `cl-find-if #'executable-find (list "fdfind" "fd")` | 写死 "fd"                                  |
| pyenv 多版本                      | `pyenv which` + `let exec-path` 局部                | 直接 `executable-find` (只看到 shim)       |
| 平台特定默认值                    | `(when (featurep :system 'macos) ...)`              | `(when (eq system-type 'darwin) ...)`      |

**反模式**:

- ❌ 在每个命令里调 `doom-call-process "which rg"` — 启动期已绑定 `doom-ripgrep-executable`
- ❌ 假设 `$PATH` 在 GUI Emacs 中正确 — 几乎在所有 OS 都不成立

---

## 3. 子问题 3: 用 ripgrep/fd 加速 Emacs 内部搜索

### 3.1 doom helm 的 ripgrep 集成 (硬错误 + 完整参数集)

```elisp
;;; modules/completion/helm/autoload/helm.el:42-73
(defun +helm-file-search (&key query in all-files (recursive t) _prompt args)
  (declare (indent defun))
  (unless (executable-find "rg")
    (user-error "Couldn't find ripgrep in your PATH"))
  (require 'helm-rg)
  (let ((this-command 'helm-rg)
        (helm-rg-default-directory (or in (doom-project-root) default-directory))
        (helm-rg-default-extra-args
         (delq nil (append (list (when all-files "-z -uu")
                                 (unless recursive "--maxdepth 1")
                                 "--hidden" "-g" "!.git")
                           args))))
    (setq deactivate-mark t)
    (helm-rg (or query ... ""))))
```

**关键参数**:

- `-z -uu` (universal-arg 时): 搜压缩文件 + 全部隐藏文件
- `--maxdepth 1`: 非递归
- `--hidden`: 包括隐藏文件
- `-g "!.git"`: 用 gitignore 模式排除

### 3.2 doom ivy 的咨询-项目-ripgrep 集成 (advices 包装)

doom 在 counsel-rg 上加了多个**外科手术式** advice:

**(a) 抑制 ripgrep exit code 2** (权限错误时不让 counsel 丢弃结果):

```elisp
;;; modules/completion/ivy/config.el:170-183
;; REVIEW: See abo-abo/swiper#2339.
(defadvice! +counsel-rg-suppress-error-code-a (fn &rest args)
  "Ripgrep returns a non-zero exit code if it encounters any trouble (e.g. you
don't have the needed permissions for a couple files/directories in a project).
Even if rg continues to produce workable results, that non-zero exit code causes
counsel-rg to discard the rest of the output to display an error.

This advice suppresses the error code, so you can still operate on whatever
workable results ripgrep produces, despite the error."
  :around #'counsel-rg
  (letf! (defun process-exit-status (proc)
           (let ((code (funcall process-exit-status proc)))
             (if (= code 2) 0 code)))
    (apply fn args)))
```

**妙处**: 用 `letf!` 临时重新定义 `process-exit-status`, 仅在 `counsel-rg` 范围内生效。

**(b) counsel-file-jump 用 fd 替代 find-file**:

```elisp
;;; modules/completion/ivy/config.el:186-217
(defadvice! +ivy--counsel-file-jump-use-fd-rg-a (args)
  "Change `counsel-file-jump' to use fd or ripgrep, if they are available."
  :override #'counsel--find-return-list
  (cl-destructuring-bind (find-program . args)
      (cond ((when-let* ((fd (executable-find (or doom-fd-executable "fd") t)))
               (append (list fd "--hidden" "--type" "file" "--type" "symlink" "--follow" "--color=never")
                       (cl-loop for dir in projectile-globally-ignored-directories
                                collect "--exclude"
                                collect dir)
                       (if (featurep :system 'windows) '("--path-separator=/")))))
            ((executable-find "rg" t)
             (append (list "rg" "--hidden" "--files" "--follow" "--color=never" "--no-messages")
                     ...))
            ((cons find-program args)))
    ...))
```

**降级链**: `fd → rg → find`

### 3.3 doom vertico/consult 的 ripgrep 集成 (异步)

```elisp
;;; modules/completion/vertico/autoload/vertico.el:1-70
(cl-defun +vertico-file-search (&key query in all-files (recursive t) prompt args)
  (declare (indent defun))
  (unless (executable-find "rg" t)
    (user-error "Couldn't find ripgrep in your PATH"))
  (require 'consult)
  (setq deactivate-mark t)
  (let* ((project-root (or (doom-project-root) default-directory))
         (directory (or in project-root))
         (consult-ripgrep-args
          (concat "rg "
                  (if all-files "-uu ")
                  (unless recursive "--maxdepth 1 ")
                  "--null --line-buffered --color=never --max-columns=1000 "
                  "--path-separator /   --smart-case --no-heading "
                  "--with-filename --line-number --search-zip "
                  "--hidden -g !.git -g !.svn -g !.hg "
                  (mapconcat #'identity args " ")))
         ...)
    (consult--grep prompt #'consult--ripgrep-make-builder directory query)))
```

**异步 ripgrep 的关键参数** (与同步 `helm-rg` 不同):

- `--null`: NUL 分隔 (consult 解析需要)
- `--line-buffered`: 边输出边处理, 不用等 rg 跑完
- `--no-heading`: 不分组, 一行一结果
- `--max-columns=1000`: 防止单行超长卡 Emacs
- `--path-separator /`: 跨平台路径一致 (Windows 也用 /)
- `--search-zip`: 包括 zip 内文件

**复杂逻辑: 异步分隔符处理** (用户输入 `#` 切换 perl-style 分隔符):

```elisp
;; Change the split style if the initial query contains the separator.
(when query
  (cl-destructuring-bind (&key separator initial function)
      (alist-get consult-async-split-style consult-async-split-styles-alist)
    ;; Perl async split style starts with an #. If the query contains #,
    ;; then use oneof the alternative delimiters instead.
    (if (eq consult-async-split-style 'perl)
        (when (string-match-p (char-to-string initial) query)
          (setf (alist-get 'perlalt consult-async-split-styles-alist)
                `(:initial ,(or (cl-loop for char in (list "%" "@" "!" "&" "/" ";")
                                         unless (string-match-p char query)
                                         return char)
                                "%")
                  :separator ,separator
                  :function ,function)
                consult-async-split-style 'perlalt))
      ...)))
```

### 3.4 consult-fd vs consult-find 的版本感知降级

```elisp
;;; modules/completion/vertico/autoload/vertico.el:174-194
;;;###autoload
(defun +vertico/consult-fd-or-find (&optional dir initial)
  "Runs consult-fd if fd version > 8.6.0 exists, consult-find otherwise.
See minad/consult#770."
  (interactive "P")
  ;; REVIEW: This condition was adapted from a similar one in
  ;;   lisp/doom-projects.el, to be replaced with a more robust check post v3
  (if (when-let*
          ((bin (if (ignore-errors (file-remote-p default-directory nil t))
                    (cl-find-if (doom-rpartial #'executable-find t)
                                (list "fdfind" "fd"))
                  doom-fd-executable))
           (version (with-memoization (get 'doom-fd-executable 'version)
                      (cadr (split-string (cdr (doom-call-process bin "--version"))
                                          " " t))))
           ((ignore-errors (version-to-list version))))
        ;; REVIEW: Remove once fd 8.6.0 is widespread enough.
        (version< "8.6.0" version))
      (consult-fd dir initial)
    (consult-find dir initial)))
```

**技巧**:

- `with-memoization` 缓存 fd 版本, 避免每次调用都 `doom-call-process fd --version`
- 远程文件用 `cl-find-if` 查 fdfind 或 fd
- 本地用 `doom-fd-executable` (启动期已绑定)

### 3.5 同步 vs 异步 trade-off

| 场景                      | 推荐                      | 原因                          |
| ------------------------- | ------------------------- | ----------------------------- |
| 交互式搜索 (用户等结果)   | 异步 (consult-ripgrep)    | `--line-buffered`, 边查边显示 |
| 后台批量索引 (projectile) | 同步 (process-file)       | 简单, 不需要 SGR 解析         |
| 大仓库 M-x grep           | ripgrep 走 `process-file` | 退到 `lgrep`/`rgrep` 慢 100x  |
| git grep 后端             | 用 `git-grep` (内置)      | ripgrep 不索引 .git/          |

**`M-x grep` 用 ripgrep 的范式** (doom):

```elisp
;; 推荐在 user-config.el:
(setq grep-program "rg")
(setq grep-template "rg -nH --no-heading --color=never <C> -e <R> <F>")
;; 或更彻底:
(setq counsel-grep-base-command
      "rg -i --casing=smart --no-heading --line-number --color=never")
```

### 3.6 反模式

- ❌ **大仓库用 `rgrep`** (elisp 实现 find + grep): 100x 慢, 且阻塞 UI
- ❌ **异步 ripgrep 用 `--no-line-buffered`**: 用户看到结果延迟 5s+
- ❌ **重复检测 rg 是否存在** (每次调用都 `executable-find`): 启动期已绑定 `doom-ripgrep-executable`
- ❌ **忽略 ripgrep exit code 1 vs 2**: 1=无匹配 (正常), 2=错误 (rg 部分输出)
- ❌ **拼错 `--line-buffered`**: 默认 rg 用 4KB 块缓冲, 实时性差

---

## 4. 子问题 4: tree-sitter 集成

### 4.1 为什么 doom 把 tree-sitter 放在 `tools/` 而非 `lang/`

doom 的模块分层逻辑:

- `lang/<lang>`: 该语言的所有功能 (LSP, REPL, snippets, formatter)
- `tools/<tool>`: 跨语言工具, 可被任何 lang 模块启用

tree-sitter 是**所有 lang 共享的语法/结构引擎**, 所以在 `tools/`。这样 `:lang python` 模块 `use-package!` 它时, 用户**只需启用 `:tools tree-sitter` 一次**, 多个 lang 都受益。

### 4.2 Emacs 29+ 内置 vs 外部包

doom 明确选择**内置优先**:

```elisp
;;; modules/tools/tree-sitter/packages.el
(package! treesit :built-in t)
(when (> emacs-major-version 28)
  ;; (package! combobulate
  ;;   ;; HACK: This package has terrible autoload ettiquette, eagerly
  ;;   ;;   loading a number of expensive packages at startup, so
  ;;   ;;   autoloads are handled manually in config.el
  ;;   :build (:not autoloads)
  ;;   :pin "59b64d66d66eb84da6a2cedd152b1692378af674")
  ;; (when (modulep! :editor evil +everywhere)
  ;;   (package! evil-textobj-tree-sitter
  ;;     :pin "bce236e5d2cc2fa4eae7d284ffd19ad18d46349a"))
  )
```

注意:

- `combobulate` 和 `evil-textobj-tree-sitter` 被注释掉 — 内置 `treesit` 已够用
- `:built-in t` 告诉 doom 不要从 ELPA 安装

**treesit-auto / tree-sitter-langs / 手工 mode-hook 三种范式对比**:

| 范式                                             | 优点                    | 缺点                 | doom 选择 |
| ------------------------------------------------ | ----------------------- | -------------------- | --------- |
| 内置 `treesit` + `treesit-language-source-alist` | 零额外依赖, Emacs 维护  | 需要手写 grammar URL | ✅        |
| `treesit-auto`                                   | 自动检测 + 安装 grammar | 启动慢, 自动安装争议 | ❌        |
| `tree-sitter-langs`                              | 预编译 binary           | 第三方包, 已停止维护 | ❌        |
| 手工 mode-hook                                   | 完全控制                | 大量样板代码         | ❌        |

### 4.3 doom 的"动态 remap + 自动安装 grammar" 实现

`set-tree-sitter!` 宏是 doom 模式的关键:

```elisp
;;; modules/tools/tree-sitter/autoload/tree-sitter.el:12-49
;;;###autodef (fset 'set-tree-sitter! #'ignore)
(defun set-tree-sitter! (modes ts-mode &optional recipes)
  "Remap major MODES to TS-MODE.
MODES and TS-MODE are major mode symbols. MODES can be a list thereof. If
RECIPES is provided, fall back to MODES if RECIPES don't pass `treesit-ready-p'
when activating TS-MODE. Use this for ts modes that error out instead of failing
gracefully.

RECIPES is a symbol (a grammar language name), list thereof, or alist of plists
with the format (LANG &key URL REV SOURCE-DIR CC CPP COMMIT). If an alist of
plists, it will be transformed into entries for `treesit-language-source-alist'..."
  (declare (indent 2))
  (cl-check-type modes (or list symbol))
  (cl-check-type ts-mode symbol)
  (let ((recipes (mapcar #'ensure-list (ensure-list recipes)))
        (modes (ensure-list modes)))
    (when modes
      (put ts-mode 'derived-mode-extra-parents modes))   ; ts 模式继承原模式
    (dolist (m (or modes (list nil)))
      (when m
        (setf (alist-get m major-mode-remap-defaults) ts-mode)))  ; remap
    (put ts-mode '+tree-sitter (cons m (mapcar #'car recipes)))   ; 记录 grammar 依赖
    (when-let* ((fn (intern-soft (format "%s-maybe" ts-mode))))   ; 删 ts-maybe 防双注册
      (cl-callf2 rassq-delete-all fn auto-mode-alist)
      (cl-callf2 rassq-delete-all fn interpreter-mode-alist))
    (when-let* ((recipes (cl-delete-if-not #'cdr recipes)))
      (with-eval-after-load 'treesit
        (dolist (recipe recipes)
          (cl-destructuring-bind (name &key url rev source-dir cc cpp commit) (ensure-list recipe)
            (setf (alist-get name treesit-language-source-alist)
                  (append (list url rev source-dir cc cpp)
                          ;; COMPAT: 31.1 introduced a COMMIT recipe argument. On
                          ;;   <=30.x, extra arguments will trigger an arity error
                          ;;   when installing grammars.
                          (if (eq (cdr (func-arity
                                        (advice--cd*r
                                         (advice--symbol-function 'treesit--install-language-grammar-1))))
                                  'many)
                              (list commit))))))))))
```

**用法示例** (从 doom 的 lang/python 推断):

```elisp
(set-tree-sitter! 'python-mode 'python-ts-mode '(:url "https://github.com/tree-sitter/tree-sitter-python"))
```

**核心运行时拦截**:

```elisp
;;; modules/tools/tree-sitter/config.el:42-90
(defadvice! +tree-sitter--maybe-remap-major-mode-a (fn mode)
  :around #'major-mode-remap
  (let ((mode (funcall fn mode)))
    (if-let* ((ts (get mode '+tree-sitter))
              (fallback-mode (car ts)))
        (cond ((not (treesit-available-p))
               (message "Treesit unavailable, falling back to `%S'" fallback-mode)
               fallback-mode)
              ((not (fboundp mode))
               (message "Couldn't find `%S', falling back to `%S'" mode fallback-mode)
               fallback-mode)
              ((and (or (eq treesit-enabled-modes t)
                        (memq fallback-mode treesit-enabled-modes))
                    ;; ... grammar 检查 + 安装
                    )
               (put mode '+tree-sitter-ensured t)
               mode)
              (fallback-mode))
      mode)))
```

**降级链**:

1. `treesit-available-p` → nil → 退到原 mode
2. `fboundp` → nil (没装 ts 包) → 退到原 mode
3. `treesit-enabled-modes` 用户禁用 → 退到原 mode
4. grammar 未安装 → `(if (eq treesit-auto-install-grammar 'always) install (y-or-n-p))` → 用户拒绝 → 退到原 mode

### 4.4 安装路径本地化

```elisp
;;; modules/tools/tree-sitter/config.el:104-110
;; HACK: Keep $EMACSDIR clean by installing grammars to central location (the
;;   active profile).
(let ((data-dir (file-name-concat doom-profile-data-dir "tree-sitter")))
  (add-to-list 'treesit-extra-load-path data-dir)
  ;; Treesit's API saw major changes in 30.x.
  (if (< emacs-major-version 30)
      (defadvice! +tree-sitter--install-grammar-to-local-dir-a (fn out-dir &rest args)
        :around #'treesit--install-language-grammar-1
        (apply fn (or out-dir data-dir) args))
    (defadvice! +tree-sitter--install-grammar-to-local-dir-a (fn lang &optional out-dir &rest args)
        :around #'treesit-install-language-grammar
        :around #'treesit--build-grammar
        (apply fn lang (or out-dir data-dir) args))))
```

- 通过 `defadvice! :around` 重新路由安装路径
- 兼容 Emacs 30.x 和 31.x 的 API 差异 (用 `func-arity` 检测)

### 4.5 ts-mode 的副作用抑制

很多 ts-mode 会偷偷修改 `auto-mode-alist`, doom 拦截:

```elisp
;;; modules/tools/tree-sitter/config.el:25-34
;; HACK: The *-ts-mode major modes are inconsistent about how they treat
;;   missing language grammars (some error out, some respect
;;   `treesit-auto-install-grammar', some fall back to `fundamental-mode').
;;   I'd like to address this poor UX using `major-mode-remap-alist' entries
;;   created by `set-tree-sitter!' (which will fall back to the non-ts-modes),
;;   but most *-ts-mode's clobber `auto-mode-alist' and/or
;;   `interpreter-mode-alist' each time the major mode is activated, so those
;;   must be undone too so they don't overwrite user config.
(save-match-data
  (dolist (sym '(auto-mode-alist interpreter-mode-alist))
    (set
     sym (cl-loop for (src . fn) in (symbol-value sym)
                  unless (and (functionp fn)
                              (string-match "-ts-mode\\(?:-maybe\\)?$" (symbol-name fn)))
                  collect (cons src fn)))))
```

- 启动时清理掉所有 `-ts-mode` 相关的 auto-mode-alist 条目
- 用 `defadvice!` 拦截后续修改:

```elisp
;;; modules/tools/tree-sitter/autoload/tree-sitter.el:88-93
;;;###autoload
(defun +tree-sitter-ts-mode-inhibit-side-effects-a (fn &rest args)
  "Suppress changes to `auto-mode-alist' and `interpreter-mode-alist'."
  (let (auto-mode-alist interpreter-mode-alist)
    (apply fn args)))
```

### 4.6 范式总结

| 决策                          | 推荐                                                 |
| ----------------------------- | ---------------------------------------------------- |
| 内置 vs 外部包                | Emacs 29+: **内置 `treesit`**                        |
| 安装 grammar 路径             | 集中到 `<profile>/tree-sitter/`, 不污染 `~/.emacs.d` |
| 缺失 grammar 处理             | `treesit-auto-install-grammar` + `y-or-n-p` 询问     |
| ts-mode 副作用                | 用 advice 抑制 `auto-mode-alist` 修改                |
| combobulate / evil-textobj-ts | 谨慎用, autoload 不规范                              |

**反模式**:

- ❌ `tree-sitter-langs` (已停止维护)
- ❌ 写死 `treesit-language-source-alist` 不带 URL/REV (无法从源头安装)
- ❌ 启用 ts-mode 但不确保 grammar 已安装 (用户会看到 `fundamental-mode` 一样)

---

## 5. 子问题 5: LSP 集成的"性能优化点"

### 5.1 `+lsp-optimization-mode` 范式

这是**整个研究最值得复用的模式**:

```elisp
;;; modules/tools/lsp/config.el:7-39
(defvar +lsp--default-read-process-output-max nil)
(defvar +lsp--default-gcmh-high-cons-threshold nil)
(defvar +lsp--optimization-init-p nil)

(define-minor-mode +lsp-optimization-mode
  "Deploys universal GC and IPC optimizations for `lsp-mode' and `eglot'."
  :group '+lsp
  :global t
  :init-value nil
  (if (not +lsp-optimization-mode)
      ;; Only apply these settings once! A minor mode's body is triggered each
      ;; time it is called, even if it's already in the desired state.
      (when +lsp--optimization-init-p
        (setq-default read-process-output-max +lsp--default-read-process-output-max
                      +lsp--optimization-init-p nil)
        (unless (fboundp 'igc-info)
          (setq-default gcmh-high-cons-threshold +lsp--default-gcmh-high-cons-threshold)))
    ;; See above.
    (unless +lsp--optimization-init-p
      (setq +lsp--default-read-process-output-max (default-value 'read-process-output-max))
      (setq-default read-process-output-max (* 1024 1024))
      ;; REVIEW: LSP causes a lot of allocations, with or without the native
      ;;   JSON library, so we up the GC threshold to stave off GC-induced
      ;;   slowdowns/freezes. Doom uses `gcmh' to enforce its GC strategy, so we
      ;;   modify its variables rather than `gc-cons-threshold' directly.
      (unless (fboundp 'igc-info)
        (setq-default +lsp--default-gcmh-high-cons-threshold (default-value 'gcmh-high-cons-threshold)
                      gcmh-high-cons-threshold (* 2 +lsp--default-gcmh-high-cons-threshold))
        (when (bound-and-true-p gcmh-mode)
          (gcmh-set-high-threshold)))
      (setq +lsp--optimization-init-p t))))
```

**5 个关键设计点**:

1. **缓存原值** (`+lsp--default-read-process-output-max`): 关闭时还原
2. **`+lsp--optimization-init-p` 守卫**: 避免重复缓存
3. **`init-value nil`**: 默认关闭, 不影响正常用户
4. **`:global t`**: 全局 minor-mode
5. **条件升级** (Emacs 31+ 用 `igc`): `(unless (fboundp 'igc-info) ...)`

**触发**:

```elisp
;;; modules/tools/lsp/+lsp.el:75
(add-hook 'lsp-before-initialize-hook #'+lsp-optimization-mode)

;; eglot 等价:
;;; modules/tools/lsp/+eglot.el:5
:hook (eglot-managed-mode . +lsp-optimization-mode)
```

**关闭** (最后一个 workspace buffer 关闭时):

```elisp
;;; modules/tools/lsp/+lsp.el:78-83
(add-hook! 'lsp-after-uninitialized-functions
  (defun +lsp--disable-optimization-mode-if-no-workspaces-h (_workspace)
    (unless (lsp--session-workspaces lsp--session)
      (+lsp-optimization-mode -1))))
```

### 5.2 eglot 的对等实现

```elisp
;;; modules/tools/lsp/+eglot.el:5-10
(use-package! eglot
  :commands eglot eglot-ensure
  :hook (eglot-managed-mode . +lsp-optimization-mode)
  ...)
```

- eglot 用 `eglot-managed-mode` 钩子 (而非 `eglot-mode`), 更精确
- 用 eglot 时, eglot 自带 `eglot-events-buffer`, 关闭它:

```elisp
;; PERF: Disable the eglot-events-buffer, so Emacs doesn't churn GC and CPU
;;   cycles on pretty-printing the events buffer in the background (once it
;;   reaches max size). Enable debug mode to restore the events buffer.
(cl-callf plist-put eglot-events-buffer-config :size 0)
```

### 5.3 server shutdown 延迟

```elisp
;;; modules/tools/lsp/+lsp.el:103-126
(defvar +lsp-defer-shutdown 3
  "If non-nil, defer shutdown of LSP servers for this many seconds after last
workspace buffer is closed.")

(defadvice! +lsp-defer-server-shutdown-a (fn &optional restart)
  :around #'lsp--shutdown-workspace
  (if (or lsp-keep-workspace-alive
          restart
          (null +lsp-defer-shutdown)
          (= +lsp-defer-shutdown 0))
      (funcall fn restart)
    (when (timerp +lsp--deferred-shutdown-timer)
      (cancel-timer +lsp--deferred-shutdown-timer))
    (setq +lsp--deferred-shutdown-timer
          (run-at-time
           (if (numberp +lsp-defer-shutdown) +lsp-defer-shutdown 3)
           nil (lambda (workspaces)
                 (dolist (ws workspaces)
                   (or (cl-some #'lsp-buffer-live-p
                                (lsp--workspace-buffers ws))
                       (with-lsp-workspace ws
                         (let ((lsp-restart 'ignore))
                           (funcall fn))))))
           lsp--buffer-workspaces))))
```

**问题场景**: 用户 `C-x k` 关闭最后一个 LSP buffer, 然后立即 `C-x C-f` 打开同一项目另一个文件。默认行为会关闭 server, 再启动新实例 — 浪费 2-3s。

**方案**: 3s 延迟, 期间任何 buffer 复活都取消 shutdown。

### 5.4 eglot 版本的等效

```elisp
;;; modules/tools/lsp/+eglot.el:43-65
(defadvice! +lsp--defer-server-shutdown-a (fn &optional server)
  :around #'eglot--managed-mode
  (letf! (defun eglot-shutdown (server)
           (if (or (null +lsp-defer-shutdown)
                   (eq +lsp-defer-shutdown 0))
               (prog1 (funcall eglot-shutdown server)
                 (+lsp-optimization-mode -1))
             (run-at-time
              (if (numberp +lsp-defer-shutdown) +lsp-defer-shutdown 3)
              nil (lambda (server)
                    (unless (eglot--managed-buffers server)
                      (prog1 (funcall eglot-shutdown server)
                        (+lsp-optimization-mode -1))))
              server)))
    (funcall fn server)))
```

- eglot 用 `letf!` 临时替换 `eglot-shutdown` 函数, 范围仅限 `eglot--managed-mode`
- 关闭时也关 `+lsp-optimization-mode`

### 5.5 eglot-booster (IO 加速)

```elisp
;;; modules/tools/lsp/+eglot.el:73-87
(use-package! eglot-booster
  :when (modulep! +booster)
  :after eglot
  :init
  (setq eglot-booster-io-only
        ;; JSON parser on 30+ is faster, so we only exploit eglot-booster's IO
        ;; buffering (benefits more talkative LSP servers).
        (and (> emacs-major-version 29)
             (not (functionp 'json-rpc-connection))))
  :config
  (eglot-booster-mode +1))
```

- `eglot-booster` 是单独的二进制, 用 Rust 写, 加速 LSP JSON-RPC 帧解析
- 关闭 bytecode 模式 (`--disable-bytecode`) 减少转换开销

### 5.6 状态保存路径

```elisp
;;; modules/tools/lsp/+lsp.el:18-19
(setq lsp-session-file (file-name-concat doom-profile-cache-dir "lsp-session")
      lsp-server-install-dir (file-name-concat doom-profile-data-dir "lsp/"))
```

- 不污染 `~/.emacs.d`
- 用户可手动清理

### 5.7 反模式

- ❌ **永远不还原** 默认值: 关闭 LSP 后 `read-process-output-max` 还是 1MB, 浪费内存
- ❌ **不缓存原值** 上来就 `setq-default read-process-output-max (1MB)`: 用户自己改的值被覆盖
- ❌ **同步关 server** (无 `defer-shutdown`): 用户切项目卡 2-3s
- ❌ **`-Q` 启动** 测 LSP: 没加载 doom, 测的是 baseline, 不是真实场景

---

## 6. 子问题 6: magit 范式

### 6.1 doom 的窗口方向控制

```elisp
;;; modules/tools/magit/config.el:5-7
(defvar +magit-open-windows-in-direction 'right
  "What direction to open new windows from the status buffer.
For example, diffs and log buffers. Accepts `left', `right', `up', and `down'.")
```

**实现** (`+magit-display-buffer-fn` + `+magit--display-buffer-in-direction`):

```elisp
;;; modules/tools/magit/autoload.el:24-67
(defun +magit-display-buffer-fn (buffer)
  "Same as `magit-display-buffer-traditional', except..."
  (let ((buffer-mode (buffer-local-value 'major-mode buffer)))
    (display-buffer
     buffer (cond
             ((and (eq buffer-mode 'magit-status-mode)
                   (get-buffer-window buffer))
              '(display-buffer-reuse-window))
             ((or (bound-and-true-p git-commit-mode)
                  (eq buffer-mode 'magit-process-mode)
                  (eq major-mode 'magit-log-select-mode))
              (let ((size (if (eq buffer-mode 'magit-process-mode) 0.35 0.7)))
                `(display-buffer-below-selected
                  . ((window-height . ,(truncate (* (window-height) size)))))))
             ((or (not (derived-mode-p 'magit-mode))
                  (and (eq major-mode 'magit-status-mode)
                       (memq buffer-mode '(magit-diff-mode magit-stash-mode)))
                  (not (memq buffer-mode '(magit-process-mode
                                           magit-revision-mode
                                           magit-stash-mode
                                           magit-status-mode))))
              '(display-buffer-same-window))
             ('(+magit--display-buffer-in-direction))))))

(defun +magit--display-buffer-in-direction (buffer alist)
  "`display-buffer-alist' handler that opens BUFFER in a direction.
This differs from `display-buffer-in-direction' in one way: it will try to use a
window that already exists in that direction. It will split otherwise."
  (let ((direction (or (alist-get 'direction alist) +magit-open-windows-in-direction))
        (origin-window (selected-window)))
    (if-let* ((window (window-in-direction direction)))
        (unless magit-display-buffer-noselect (select-window window))
      (if-let* ((window ...))  ; 找反向窗口
        ...
        (let ((window (split-window nil nil direction)))
          ...)))))
```

**关键技巧**: `window-in-direction` 复用现有窗口, 避免"切个 magit 屏幕就裂成 4 块"

### 6.2 自动 revert 优化

doom 不依赖 `magit-auto-revert-mode`, 自己实现"可见立即 revert, 不可见标记 stale, 切换时再 revert":

```elisp
;;; modules/tools/magit/autoload.el:119-140
(defvar +magit--stale-p nil)

(defun +magit--revertable-buffer-p (buffer)
  (when (buffer-live-p buffer)
    (pcase +magit-auto-revert
      (`t t)
      (`local
       (not (file-remote-p ...)))
      ((pred functionp) (funcall +magit-auto-revert buffer)))))

(defun +magit--revert-buffer (buffer) ...)

;;;###autoload
(defun +magit-mark-stale-buffers-h ()
  "Revert all visible buffers and mark buried buffers as stale."
  (when +magit-auto-revert
    (let ((visible-buffers (doom-visible-buffers nil t)))
      (dolist (buffer (buffer-list))
        (when (+magit--revertable-buffer-p buffer)
          (if (memq buffer visible-buffers)
              (progn (+magit--revert-buffer buffer) ...)
            (with-current-buffer buffer
              (setq-local +magit--stale-p t))))))))
```

**挂钩点**:

```elisp
;;; modules/tools/magit/config.el:67-69
(add-hook 'magit-post-refresh-hook #'+magit-mark-stale-buffers-h)
(add-hook 'doom-switch-buffer-hook #'+magit-revert-buffer-maybe-h)
(add-hook 'doom-switch-frame-hook #'+magit-mark-stale-buffers-h)
```

### 6.3 projectile 缓存同步失效

magit 之后让 projectile 重新扫文件 (因为可能 stage 了新文件):

```elisp
;;; modules/tools/magit/config.el:54-66
(defvar +magit--last-hash nil)
(add-hook! 'magit-refresh-buffer-hook
  (defun +magit-invalidate-projectile-cache-h ()
    (when (bound-and-true-p projectile-mode)
      (let ((hash (buffer-hash))
            projectile-require-project-root
            projectile-enable-caching
            projectile-verbose)
        (unless (equal +magit--last-hash hash)
          (letf! ((#'recentf-cleanup #'ignore))
            (projectile-invalidate-cache nil))
          (setq-local +magit--last-hash hash))))))
```

- `buffer-hash` 防止重复失效
- `letf!` 临时禁用 `recentf-cleanup` (避免 expensive I/O)

### 6.4 magit-todos 懒加载

```elisp
;;; modules/tools/magit/packages.el:55-58
(package! orgit
  :requires org)  ; 强制 org 先加载

(when (modulep! +forge)
  (package! orgit-forge
    :requires (org forge)))
```

- `:requires` 确保依赖先就绪
- `+forge` 模块才装 orgit-forge (减少默认包数量)

spacemacs 用 `:toggle` 控制 magit-todos:

```elisp
;;; layers/+source-control/git/packages.el
(magit-todos :toggle git-enable-magit-todos-plugin)
...
(defun git/init-magit-todos ()
  (use-package magit-todos
    :after magit-status
    :config
    (spacemacs|diminish magit-todos-mode "TODOS")
    (magit-todos-mode 1)))
```

### 6.5 transient 文件本地化

```elisp
;;; modules/tools/magit/config.el:21-23
;; Must be set early to prevent ~/.config/emacs/transient from being created
(setq transient-levels-file  (file-name-concat doom-profile-data-dir "transient" "levels")
      transient-values-file  (file-name-concat doom-profile-data-dir "transient" "values")
      transient-history-file (file-name-concat doom-profile-data-dir "transient" "history"))
```

- 不污染 `~/.config/emacs`
- 用户卸载 doom 后 transient 状态不残留

### 6.6 spacemacs magit 范式对比

spacemacs 走的是**heavy keybindings**路线:

```elisp
;;; layers/+source-control/git/packages.el (init-magit)
(spacemacs|define-transient-state git-blame
  :title "Git Blame Transient State"
  :doc "..."
  :on-enter (let (golden-ratio-mode)
              (unless (bound-and-true-p magit-blame-mode)
                (call-interactively 'magit-blame-addition)))
  :bindings
  ("?" spacemacs//git-blame-ts-toggle-hint)
  ("p" magit-blame-previous-chunk)
  ("P" magit-blame-previous-chunk-same-commit)
  ("n" magit-blame-next-chunk)
  ("N" magit-blame-next-chunk-same-commit)
  ("RET" magit-show-commit)
  ...)
```

**对比**:

| 范式         | doom                                        | spacemacs                                  |
| ------------ | ------------------------------------------- | ------------------------------------------ |
| 窗口方向     | `+magit-open-windows-in-direction` (声明式) | `magit-display-buffer-function` 整函数替换 |
| 快捷键       | evil-collection 接管                        | 自定义 transient-state (heavy keybindings) |
| auto-revert  | 自己实现 (`+magit-mark-stale-buffers-h`)    | 依赖 `magit-auto-revert-mode`              |
| 临时文件位置 | `<profile>/transient/*`                     | `~/.config/emacs/transient/*` (污染!)      |

### 6.7 反模式

- ❌ **用 `magit-auto-revert-mode` 全局开**: 性能差 (一次 revert 全部 buffer)
- ❌ **不显式设置 transient 路径**: 污染 `~/.config/emacs/`
- ❌ **不区分 `magit-status-mode` 和 `magit-diff-mode` 的窗口行为**: 一律弹新窗

---

## 7. 子问题 7: vterm / eat / term 范式

### 7.1 编译时 dynamic-module 检测

```elisp
;;; modules/term/vterm/config.el:4
(use-package! vterm
  :when (bound-and-true-p module-file-suffix)  ; requires dynamic-modules support
  ...)
```

- Emacs 编译期决定: 没模块支持 → 不引入包
- 用户 `M-x vterm` 会得到 "no match", 不会崩

**doctor 检查**:

```elisp
;;; modules/term/vterm/doctor.el
(unless (executable-find "make") (warn! "Couldn't find make command. Vterm module won't compile"))
(unless (executable-find "cmake") (warn! "Couldn't find cmake command. Vterm module won't compile"))
(unless (fboundp 'module-load) (warn! "Your emacs wasn't built with dynamic modules support. The vterm module won't build"))
```

### 7.2 vterm 字节编译时的副作用抑制

vterm 在 load 时强制编译 module, doom 在 byte-compile 时拦截:

```elisp
;;; modules/term/vterm/config.el:8-11
;; HACK: Because vterm clusmily forces vterm-module.so's compilation on us
;;   when the package is loaded, this is necessary to prevent it when
;;   byte-compiling this file (`use-package' blocks eagerly loads packages
;;   when compiled).
(when noninteractive
  (advice-add #'vterm-module-compile :override #'ignore)
  (provide 'vterm-module))
```

- `noninteractive` = `emacs -Q --batch` 编译期
- `provide 'vterm-module` 让 `require 'vterm` 不再尝试编译

### 7.3 缓冲复用策略

**vterm** (doom):

```elisp
;;; modules/term/vterm/config.el:18
(setq vterm-kill-buffer-on-exit t)  ; 进程退出 = 缓冲也死
```

- vterm 进程死亡后, 缓冲没用了, 立即回收
- 跨项目用不同 vterm 缓冲 (通过 `*doom:vterm-popup:<workspace>*` 命名)

**vterm toggle** (doom):

```elisp
;;; modules/term/vterm/autoload.el:7-43
;;;###autoload
(defun +vterm/toggle (arg)
  "Toggles a terminal popup window at project root."
  (interactive "P")
  (+vterm--configure-project-root-and-display
   arg
   (lambda ()
     (let ((buffer-name
            (format "*doom:vterm-popup:%s*"
                    (if (bound-and-true-p persp-mode)
                        (safe-persp-name (get-current-persp))
                      "main")))
           ...)
       (when arg
         (let ((buffer (get-buffer buffer-name))
               (window (get-buffer-window buffer-name)))
           (when (buffer-live-p buffer) (kill-buffer buffer))  ; prefix arg = 重建
           ...))
       (if-let* ((win (get-buffer-window buffer-name)))
           (delete-window win)  ; 二次调用 = 关闭
         (let ((buffer (or (cl-loop for buf in (doom-buffers-in-mode 'vterm-mode)
                                    if (equal (buffer-local-value '+vterm--id buf) buffer-name)
                                    return buf)
                           (get-buffer-create buffer-name))))  ; 找已有或新建
           ...))))))
```

**term** (doom) 用 multi-term:

```elisp
;;; modules/term/term/autoload.el:21-48
;;;###autoload
(defun +term/toggle (arg)
  "Toggle a persistent terminal popup window."
  (interactive "P")
  (require 'multi-term)
  (let ((multi-term-dedicated-select-after-open-p t)
        (multi-term-buffer-name
         (format "doom:term-popup:%s"
                 (if (bound-and-true-p persp-mode)
                     (safe-persp-name (get-current-persp))
                   "main"))))
    (let* ((buffer (multi-term-get-buffer nil t))
           (window (get-buffer-window buffer)))
      (when arg
        (+term--kill-dedicated window buffer)
        (setq buffer (multi-term-get-buffer nil t)))
      (if (and (window-live-p window) (buffer-live-p buffer))
          (delete-window window)
        (setenv "PROOT" (or (doom-project-root) default-directory))
        (with-current-buffer buffer
          (doom-mark-buffer-as-real-h)
          (multi-term-internal))
        ...))))
```

**对比**:

| 范式                                | 进程退出 | 缓冲退出                          | 适用             |
| ----------------------------------- | -------- | --------------------------------- | ---------------- |
| vterm `vterm-kill-buffer-on-exit t` | 自动     | 自动                              | 短任务, 临时命令 |
| term (multi-term)                   | 保留     | 保留                              | 长任务, REPL     |
| eshell                              | 由用户   | `eshell-kill-processes-on-exit t` | 纯 elisp shell   |

### 7.4 shell init 注入

vterm 通过环境变量 `PROOT` 注入项目根:

```elisp
;;; modules/term/vterm/autoload.el:73-85
(defun +vterm--configure-project-root-and-display (arg display-fn)
  (let* ((project-root (or (doom-project-root) default-directory))
         (default-directory (if arg default-directory project-root)))
    (setenv "PROOT" project-root)
    (funcall display-fn)))
```

shell rc 里读 `$PROOT` 自动 cd。

### 7.5 vterm 弹窗配置

```elisp
;;; modules/term/vterm/config.el:14
(set-popup-rule! "^\\*vterm" :size 0.25 :vslot -4 :select t :quit nil :ttl 0)
```

- `:size 0.25` = 占 25% 高度
- `:vslot -4` = 底部 4 槽 (popup window 系统)
- `:ttl 0` = 永远不自动关闭
- `:select t` = 打开时切到该窗

### 7.6 vterm 键位适配 evil

```elisp
;;; modules/term/vterm/config.el:15-18
(map! :map vterm-mode-map
      "C-q"   #'vterm-send-next-key
      :n "0"  #'+vterm/beginning-of-line  ; evil 的 0 改为发 C-a
      :n "dd" #'+vterm/delete-line)
```

- evil normal 模式下 `0` 是行首, 但 shell 里 `0` 不对, 转发成 C-a
- `dd` 是 evil 的删除行, 转发成 C-e C-u

### 7.7 term 视觉模式保护

evil visual 模式下编辑 term 输出会导致**执行垃圾字符**:

```elisp
;;; modules/term/term/config.el:14-29
(defadvice! +term--protect-process-output-in-visual-modes-a (&rest _)
  :before #'term-line-mode
  (when (term-in-char-mode)
    (let* ((prompt?)
           (prompt-end
            (save-excursion
              (goto-char (process-mark (get-buffer-process (current-buffer))))
              (or (and (not (equal term-prompt-regexp "^"))
                       (setq prompt? (re-search-backward term-prompt-regexp (line-beginning-position) t))
                       (match-end 0))
                  (line-beginning-position)))))
      (with-silent-modifications
        (when prompt? (put-text-property (1- prompt-end) prompt-end 'read-only 'fence))
        (add-text-properties (point-min) prompt-end '(read-only t))))))
```

- 进入 `term-line-mode` 前, 把 process mark 之前的内容标记 `read-only`
- 防止用户在 visual mode "看到" 输出, 然后改字然后按回车

### 7.8 eshell 别名 + pcomplete

```elisp
;;; modules/term/eshell/config.el:24-39
(defvar +eshell-aliases
  '(("q"  "exit")
    ("f"  "find-file $1")
    ("ff" "find-file-other-window $1")
    ("d"  "dired $1")
    ("bd" "eshell-up $1")
    ("rg" "rg --color=always $*")
    ("l"  "ls -lh $*")
    ("ll" "ls -lah $*")
    ("git" "git --no-pager $*")
    ("gg" "magit-status")
    ("cdp" "cd-to-project")
    ("clear" "clear-scrollback"))
  "An alist of default eshell aliases, meant to emulate useful shell utilities,
like fasd and bd. Note that you may overwrite these in your
`eshell-aliases-file'. This is here to provide an alternative, elisp-centric way
to define your aliases.

You should use `set-eshell-alias!' to change this.")
```

- 用户用 `set-eshell-alias!` 而不是写 alias 文件
- 卸载 eshell 不留垃圾

**pcomplete 集成 fd/rg**:

```elisp
;;; modules/term/eshell/config.el:240-244
(use-package! pcmpl-args
  :after eshell
  :config
  (dolist (cmd '("doom" "nix-shell"))
    (defalias (intern (concat "pcomplete/" cmd))
      #'pcmpl-args-pcomplete-on-help))
  (dolist (cmd '("fd" "rg" "exa" "emacsclient"))
    (defalias (intern (concat "pcomplete/" cmd))
      #'pcmpl-args-pcomplete-on-man)))
```

- `pcomplete/fd` 用 man 补全
- 第三方 CLI 即时补全

### 7.9 范式总结

| 工具       | 适用                     | 性能     | 特性                            |
| ---------- | ------------------------ | -------- | ------------------------------- |
| vterm      | 高 I/O (cat 大文件, vim) | GPU 渲染 | 需要 libvterm                   |
| eat        | 纯 elisp, 无 native 依赖 | 较慢     | Emacs 28+ 内置候选              |
| term       | 兼容老 Emacs             | 慢       | 标配, char-mode + line-mode     |
| multi-term | 多个持久 shell           | 慢       | 复杂 buffer 管理                |
| eshell     | 纯 elisp, 无 PTY         | 非常快   | 无外部进程, 但不 100% 兼容 bash |

**反模式**:

- ❌ **无条件 `(require 'vterm)`** (没模块支持会崩): 用 `:when (bound-and-true-p module-file-suffix)`
- ❌ **byte-compile 时编译 vterm-module**: 慢且失败
- ❌ **保留 vterm 缓冲**: 进程死了缓冲没用
- ❌ **不保护 term 输出在 visual mode**: 用户能编辑就可能误执行

---

## 8. 子问题 8: JSON / jq / sqlite-cli / html-xml 解析

### 8.1 doom 的 `doom-call-process` 基础设施

```elisp
;;; lisp/lib/process.el:6-15
;;;###autoload
(defun doom-call-process (command &rest args)
  "Execute COMMAND with ARGS synchronously.

Returns (STATUS . OUTPUT) when it is done, where STATUS is the returned error
code of the process and OUTPUT is its stdout output."
  (with-temp-buffer
    (cons (or (apply #'call-process command nil t nil (remq nil args))
              -1)
          (string-trim (buffer-string)))))
```

**优势**:

- 返回 `(STATUS . OUTPUT)` cons cell, 一次调用同时拿错误码和输出
- `(remq nil args)` 自动剔除 nil
- `string-trim` 去掉尾部 newline

**doom-cli 的 sh! 别名**:

```elisp
;;; lisp/doom-cli.el:1948
(defalias 'sh! #'doom-call-process)
```

### 8.2 jq 替代 `json-parse-buffer`

```elisp
;; 推荐用法:
(let* ((result (cdr (doom-call-process "jq" "-r" ".field" "/tmp/data.json"))))
  (unless (string= result "null")
    result))
```

**vs elisp `json-parse-buffer`**:

- 优点: jq 更快 (C 实现), 表达式灵活 (`.field.subfield | length`)
- 缺点: 需要 jq 安装, 启动 jq 进程 ~10ms

**反模式**:

- ❌ **小 JSON 用 jq**: `<1KB` 用 elisp `json-parse-string` 更快
- ❌ **大 JSON 反复调用 jq**: 一次调用, 一次解析

### 8.3 sqlite3 替代内置 sqlite-mode

```elisp
;; 推荐用法 (forge 的数据库查询):
(let ((rows (cdr (doom-call-process "sqlite3" "-separator" "\t" "-noheader"
                                     db-file "SELECT * FROM issues WHERE closed=0"))))
  (mapcar (lambda (line) (split-string line "\t"))
          (split-string rows "\n")))
```

**doom 的 forge 用法**:

```elisp
;;; modules/tools/magit/config.el (forge block)
(setq forge-database-file (file-name-concat doom-profile-data-dir "forge" "forge-database.sqlite"))
```

- 用户数据库在 `<profile>/forge/`, 不污染 `~/.emacs.d`
- `emacsql` 是 elisp 客户端, 但底层还是 sqlite3

### 8.4 反模式

- ❌ **不缓存 jq/sqlite3 输出**: 每次调用起新进程
- ❌ **JSON 拼字符串**: 用 elisp `json-serialize` 更快
- ❌ **解析 HTML 用 `libxml-parse-html-region`**: 慢, 用 `pandoc -f html -t json` 然后 jq

---

## 9. 子问题 9: deer / finder / external launcher

### 9.1 macOS 的 `+macos-open-with`

```elisp
;;; modules/os/macos/autoload.el:5-11
;;;###autoload
(defun +macos-open-with (&optional app-name path)
  "Send PATH to APP-NAME on OSX."
  (interactive)
  (let* ((path (expand-file-name
                (replace-regexp-in-string
                 "'" "\\'"
                 (or path (if (derived-mode-p 'dired-mode)
                              (dired-get-file-for-visit)
                            (buffer-file-name)))
                 nil t)))
         (args (cons "open"
                     (append (if app-name (list "-a" app-name))
                             (list path)))))
    (message "Running: %S" args)
    (apply #'doom-call-process args)))
```

**宏生成 9 个命令**:

```elisp
;;; modules/os/macos/autoload.el:23-31
(defmacro +macos--open-with (id &optional app dir)
  `(defun ,(intern (format "+macos/%s" id)) ()
     (interactive)
     (+macos-open-with ,app ,dir)))

;;;###autoload (autoload '+macos/open-in-default-program "os/macos/autoload" nil t)
(+macos--open-with open-in-default-program)
(+macos--open-with reveal-in-finder "Finder" default-directory)
(+macos--open-with reveal-project-in-finder "Finder"
                   (or (doom-project-root) default-directory))
(+macos--open-with send-to-transmit "Transmit")
(+macos--open-with send-cwd-to-transmit "Transmit" default-directory)
(+macos--open-with send-to-launchbar "LaunchBar")
(+macos--open-with send-project-to-launchbar "LaunchBar"
                   (or (doom-project-root) default-directory))
```

**iTerm 特殊处理** (临时改 default):

```elisp
;;; modules/os/macos/autoload.el:33-49
(defmacro +macos--open-with-iterm (id &optional dir newwindow?)
  `(defun ,(intern (format "+macos/%s" id)) ()
     (interactive)
     (letf! ((defun read-newwindows ()
               (cdr (+macos-defaults
                     "read" "com.googlecode.iterm2" "OpenFileInNewWindows")))
             (defun write-newwindows (bool)
               (+macos-defaults
                "write" "com.googlecode.iterm2" "OpenFileInNewWindows"
                "-bool" (if bool "true" "false"))))
       (let ((newwindow?
              (if ,newwindow? (not (equal (read-newwindows) "1")))))
         (when newwindow? (write-newwindows t))
         (unwind-protect (+macos-open-with "iTerm" ,dir)
           (when newwindow? (write-newwindows nil)))))))
```

- `letf!` 临时重定义 `read-newwindows`/`write-newwindows` 函数
- `unwind-protect` 保证恢复

### 9.2 跨平台的 browse-url

Emacs 内置 `browse-url` 已经处理平台差异:

- macOS: `browse-url-default-macosx-browser`
- Windows: `browse-url-default-windows-browser`
- Linux: `browse-url-default-xdg-open`

doom 的 lookup 模块直接用:

```elisp
;;; modules/tools/lookup/config.el:39-40
(defvar +lookup-open-url-fn #'browse-url
  "Function to use to open search urls.")
```

### 9.3 doom 平台特定配置

```elisp
;;; modules/os/macos/config.el
(setq locate-command "mdfind")  ; 不用 locate, 用 Spotlight
```

### 9.4 反模式

- ❌ **写死 `xdg-open`**: macOS 没有
- ❌ **写死 `open`**: Linux 没有
- ❌ **不传 `default-directory`**: 打开 Finder 时用户期望在当前项目

---

## 10. 子问题 10: chatgpt-shell / gptel / llm 客户端

### 10.1 doom 的 gptel 集成 (轻量)

```elisp
;;; modules/tools/llm/config.el
(use-package! gptel
  :defer t
  :config
  (set-debug-var! 'gptel-log-level 'debug)

  (setq gptel-display-buffer-action nil   ; if changed, popup manager will bow out
        gptel-default-mode 'org-mode)

  (set-popup-rule!
    (lambda (bname _action)
      (and (null gptel-display-buffer-action)
           (buffer-local-value 'gptel-mode (get-buffer bname))))
    :select t
    :size 0.3
    :quit nil
    :ttl nil))
```

**popup 规则用 lambda 判定**:

- `gptel-display-buffer-action` 是 nil (用户没改) 时才用 popup 规则
- 检查 buffer 是否 `gptel-mode` 激活

**magit 集成** (commit message 生成):

```elisp
;;; modules/tools/llm/config.el
(use-package! gptel-magit
  :when (modulep! :tools magit)
  :hook (magit-mode . gptel-magit-install))
```

**org babel 集成**:

```elisp
(use-package! ob-gptel
  :when (modulep! :lang org)
  :hook (org-mode . +llm-ob-gptel-install-completions-h)
  :config
  (defun +llm-ob-gptel-install-completions-h ()
    (add-hook 'completion-at-point-functions 'ob-gptel-capf nil t)))
```

### 10.2 范式: 外部 API + elisp wrapper

doom 的 gptel 集成展示了一个**可复用模式**:

1. `:defer t` — 启动期不加载
2. `:config` 调 API key / 端点 (用户自己 `gptel-api-key` set)
3. `set-popup-rule!` 用 lambda 动态判定
4. **多 module 协同** (`+magit`, `+org`)
5. **completion 集成** (ob-gptel-capf)

### 10.3 反模式

- ❌ **同步调 API**: `gptel-request` 是同步的, 但 doom 用 popup-rules 避免阻塞
- ❌ **写死 endpoint URL**: 用户应该能切到 OpenAI / Anthropic / Ollama

---

## 11. 工具/场景对应表

| 外部工具                            | 主要场景        | doom 集成点                                                         | 关键配置                                                              |
| ----------------------------------- | --------------- | ------------------------------------------------------------------- | --------------------------------------------------------------------- |
| **ripgrep**                         | 文件内容搜索    | `+helm-file-search`, `+vertico-file-search`, `consult-ripgrep-args` | `--null --line-buffered --smart-case --no-heading --max-columns=1000` |
| **fd / fdfind**                     | 文件名搜索      | `doom-fd-executable`, `projectile-generic-command`                  | `--hidden --type file --type symlink --follow`                        |
| **git**                             | 版本控制        | magit, projectile-git                                               | `magit-git-executable` (强制 absolute path)                           |
| **tree-sitter**                     | 语法/结构       | `:tools tree-sitter`                                                | `set-tree-sitter!`, `treesit-language-source-alist`                   |
| **LSP server** (pylsp, gopls, etc.) | IDE 能力        | `:tools lsp +eglot/+lsp-mode/+booster`                              | `+lsp-optimization-mode`, server root 检测                            |
| **magit** (elisp)                   | git UI          | `:tools magit +forge`                                               | `+magit-open-windows-in-direction`, `+magit-mark-stale-buffers-h`     |
| **vterm**                           | 终端 (libvterm) | `:term vterm`                                                       | `vterm-kill-buffer-on-exit t`                                         |
| **term / ansi-term**                | 终端 (内置)     | `:term term`                                                        | `term-prompt-regexp` 本地化                                           |
| **eshell**                          | elisp shell     | `:term eshell`                                                      | `+eshell-aliases`, `pcmpl-args`                                       |
| **jq**                              | JSON 处理       | `doom-call-process`                                                 | 不在 doom 内置, 用户自己写                                            |
| **sqlite3**                         | SQL 查询        | forge (magit)                                                       | `forge-database-file` 在 profile                                      |
| **mdfind** (mac)                    | locate 替代     | `(setq locate-command "mdfind")`                                    | macOS 专用                                                            |
| **fc-list**                         | 字体检测        | doom doctor                                                         | `fontconfig`                                                          |
| **emacs-lsp-booster**               | LSP 加速        | `:tools lsp +eglot +booster`                                        | `eglot-booster-mode`                                                  |
| **make, cmake**                     | 编译 vterm      | doom doctor                                                         | vterm 模块编译                                                        |
| **gptel / API**                     | AI 集成         | `:tools llm`                                                        | `gptel-api-key`                                                       |
| **xdg-open / open / start**         | URL/file 打开   | 内置 `browse-url`                                                   | 平台自动检测                                                          |
| **xclip / wl-copy / pbcopy**        | 剪贴板 (tty)    | `:os tty`                                                           | `xclip-mode`, `clipetty-mode`                                         |
| **fontconfig**                      | 字体            | doom doctor                                                         | `fc-list`                                                             |
| **git config**                      | git 全局配置    | doom doctor                                                         | 不允许 `url.git://` 重写                                              |
| **npm**                             | LSP server 安装 | lsp doctor                                                          | lsp-mode 需要                                                         |

---

## 12. 外部依赖缺失时的降级策略 (具体代码)

### 12.1 统一降级框架

doom 用**三档错误** + 三个**检查时机**:

| 错误级别     | 时机              | 例子                                                |
| ------------ | ----------------- | --------------------------------------------------- |
| `user-error` | 用户主动调用      | `(user-error "Couldn't find ripgrep in your PATH")` |
| `error!`     | `bin/doom doctor` | `(error! "+booster does nothing without +eglot")`   |
| `warn!`      | `bin/doom doctor` | `(warn! "Couldn't find npm...")`                    |

### 12.2 完整降级代码示例

**`+helm-file-search` (硬错误) → 退到 `helm-do-grep`**:

```elisp
(defun +helm-file-search (&key query in all-files (recursive t) _prompt args)
  (declare (indent defun))
  (unless (executable-find "rg")
    (user-error "Couldn't find ripgrep in your PATH"))
  (require 'helm-rg)
  ...)
```

**没有 ripgrep 时, 用户调用得到清晰错误**。但 doom 假设 ripgrep 必有, 不在代码里给内置降级 (因为 helm-rg 和 helm-do-grep 是不同代码路径)。

**`+ivy/projectile-find-file` (软降级) → 大项目用 ripgrep, 小项目用 find-file**:

```elisp
;; modules/completion/ivy/config.el (counsel-projectile section)
(setf (alist-get 'projectile-find-file counsel-projectile-key-bindings)
      #'+ivy/projectile-find-file)
```

`+ivy/projectile-find-file` 是 doom 自己的 wrapper, 根据项目大小决定。

**`+vertico/consult-fd-or-find` (版本感知降级)**:

```elisp
(defun +vertico/consult-fd-or-find (&optional dir initial)
  (if (when-let* ((bin ...) (version (with-memoization (get 'doom-fd-executable 'version)
                                       (cadr (split-string (cdr (doom-call-process bin "--version")) " " t))))
                ((ignore-errors (version-to-list version))))
        (version< "8.6.0" version))
      (consult-fd dir initial)    ; fd >= 8.6
    (consult-find dir initial)))  ; 否则退到 find.el
```

**`+tree-sitter--maybe-remap-major-mode-a` (四档降级)**:

```elisp
(cond ((not (treesit-available-p)) fallback-mode)        ; 1. Emacs 不支持
      ((not (fboundp mode))        fallback-mode)        ; 2. ts 包没装
      ((not (or treesit-enabled-modes ...)) fallback)    ; 3. 用户禁用 ts
      ((not (treesit-ready-p ...))                       ; 4. grammar 未装
       (if (or auto-install (y-or-n-p)) install t)
       (or t fallback-mode)))
```

### 12.3 反模式清单

❌ **静默失败**: `if-let*` 包裹 `(executable-find "rg")` 后什么都不做
❌ **重复检测**: 在每个调用点 `(executable-find "rg")`, 应启动期绑定
❌ **"全自动"** 检测: `treesit-auto-install-grammar 'always` 静默下载
❌ **panic 优先于 warning**: 多错误时**先看 panic**, 再看 warning (F012 已踩坑)
❌ **降级到更差方案**: ripgrep → grep 是合理的, rg → fundamental-mode 不合理

---

## 13. 整体反模式 (跨范式)

1. **同步调用长任务** (而非异步) — `doom-call-process` 应该换成 `make-process`
2. **重复检测依赖** (而非启动期缓存) — `doom-ripgrep-executable` 应在 `defvar` 一次
3. **污染 `~/.emacs.d`** (而非 profile 目录) — `lsp-server-install-dir`, `forge-database-file` 都应在 `<profile>/`
4. **写死平台** (而非 `(featurep :system 'macos)`) — doom 全面使用 `featurep`
5. **不保护进程输出** (term 在 visual mode) — 防止用户误执行
6. **不缓存 `:version`** (每次调 `binary --version`) — `with-memoization` + 列表绑定
7. **不守护 byte-compile 期副作用** (vterm module 编译) — `advice-add :override`
8. **不抑制 ts-mode 副作用** (auto-mode-alist 覆盖) — 用 defadvice 拦截
9. **不区分 fast/slow 模式** (异步 vs 同步) — `consult--ripgrep` 用 `--line-buffered`
10. **不在 doctor 里给修复指南** (`explain!`) — 只报错不说怎么修

---

## 14. 检查清单 (Checklist)

### 14.1 启动期

- [ ] 所有外部工具路径在 `defvar` 启动期绑定 (doom-ripgrep-executable, doom-fd-executable)
- [ ] macOS/WSL 下用 `doom env` 文件, 不用 `exec-path-from-shell`
- [ ] platform 检测用 `(featurep :system 'macos/linux/windows/wsl)`, 不用 `eq system-type`
- [ ] 平台特定包用 `:toggle (spacemacs/system-is-macos)` 或 `(modulep! :os macos)`
- [ ] vterm/eat/tree-sitter 用 `:when (bound-and-true-p module-file-suffix)` 守卫
- [ ] lsp-server-install-dir, forge-database-file 等放 `<profile>/`, 不放 `~/.emacs.d`

### 14.2 配置期

- [ ] `use-package! :defer t` 延迟加载重型包
- [ ] `use-package! :defer-incrementally` 分阶段加载 (magit 模式)
- [ ] `use-package! :hook (...)` 模式激活时挂钩
- [ ] `set-popup-rule!` 弹窗用正则, 不用 `*vterm*` 字面量
- [ ] `doctor.el` 包含 `error!/warn!/explain!` 完整三段
- [ ] doctor 检查 `executable-find`, 还检查**深度健康** (rg 是否 PCRE 编译)
- [ ] 不在每个调用点重复 `(executable-find ...)`, 用 `defvar` 缓存

### 14.3 运行时

- [ ] 用户调用前用 `(unless (executable-find "rg") (user-error ...))` 硬错误
- [ ] 软降级用 `cl-find-if` + 列表 (fd/fdfind 兼容)
- [ ] 异步 ripgrep 必带 `--null --line-buffered --no-heading`
- [ ] 同步 grep 用 `process-file` (不阻塞 UI)
- [ ] `+lsp-optimization-mode` 模式: 打开时调高全局, 关闭时还原
- [ ] LSP server shutdown 延迟 3s (防反复开关)
- [ ] magit auto-revert 区分可见/不可见
- [ ] vterm 进程退出 = 缓冲退出 (`vterm-kill-buffer-on-exit t`)
- [ ] term/eshell 视觉模式保护 process mark

### 14.4 平台特定

- [ ] macOS: `locate-command = "mdfind"`, `ns-auto-titlebar-mode`
- [ ] WSL: 检测 `WSLENV` 或 `operating-system-release`
- [ ] tty: `xclip-mode` 或 `clipetty-mode` (按 OSC 切换)
- [ ] Windows: `(if (featurep :system 'windows) "--path-separator=/")`

### 14.5 AI / LLM 集成

- [ ] `:defer t`, 不在启动期拉模型列表
- [ ] `gptel-api-key` 用户自己设, 不硬编码
- [ ] popup 规则用 lambda 动态判定
- [ ] 多 module 协同 (magit 集成, org-babel 集成)

### 14.6 测试 / 验证

- [ ] `bin/doom doctor` 通过
- [ ] `(doom-call-process "rg" "--version")` 实际跑过
- [ ] 大仓库 (10k+ 文件) M-x grep 流畅
- [ ] 关闭 LSP 后 `read-process-output-max` 已还原 (M-x describe-variable)
- [ ] 进程退出后 vterm 缓冲已死 (M-x buffer-list 确认)

---

## 15. 关键发现总结 (执行摘要)

### 15.1 最有价值的 5 个范式

1. **`+lsp-optimization-mode` 模式** (打开/关闭时改全局变量, 配 `+lsp--optimization-init-p` 守卫)
   - 适用任何 "需要调优全局资源的后台服务"
   - 可应用到: eglot, magit, vterm, eglot-booster

2. **启动期 defvar 缓存外部工具路径** (doom-ripgrep-executable, doom-fd-executable)
   - 适用任何 "在 runtime 频繁调用"的外部工具
   - 防止 N 次 `executable-find` 调用

3. **`doom env` 文件代替 `exec-path-from-shell`**
   - 启动期零进程 (不调 shell)
   - 完整环境变量注入, 不只是 PATH
   - 用户可预览/手动编辑

4. **`spacemacs//helm-do-search-find-tool` 动态 cond + dotspacemacs-search-tools**
   - 用户声明优先级列表
   - 用 `cl-find-if` 找第一个可用
   - 失败时回退到内置 (helm-do-grep)

5. **`set-tree-sitter!` + `+tree-sitter--maybe-remap-major-mode-a`**
   - 内置 treesit 优先 (无外部包)
   - 四档降级 (Emacs 不支持 / 包没装 / 用户禁用 / grammar 缺失)
   - 拦截 ts-mode 副作用 (auto-mode-alist 覆盖)

### 15.2 三个最常见踩坑

1. **不抑制 byte-compile 副作用** → vterm 编译失败
2. **不保护 term 输出在 visual mode** → 用户误执行垃圾
3. **panic 错误优先于 warning** (F012) → 诊断方向错误

### 15.3 不应该复用的部分

- ❌ 整个 doom 的 `transient` 配置路径污染 `~/.config/emacs/`
- ❌ spacemacs 的 heavy keybindings (transient-state) — 过于复杂
- ❌ lsp-mode 的 `lsp-ui-mode` 自动启用 — doom 改成 hook 控制

### 15.4 未来方向

- Emacs 30+ 的 `igc` 让 `+lsp-optimization-mode` 的 GC 部分过时
- `eglot-booster` 可能在 Emacs 31+ 内置
- tree-sitter 31+ 的 `COMMIT` 字段让 `set-tree-sitter!` 简化
- `treesit-auto-install-grammar` 默认值争议可能推动 doom 默认设 `nil`

---

## 16. 引用代码位置索引

| 模式                               | 文件:行                                                             |
| ---------------------------------- | ------------------------------------------------------------------- |
| 硬错误 user-error                  | `doomemacs/modules/completion/helm/autoload/helm.el:42-50`          |
| doctor DSL (error!/warn!/explain!) | `doomemacs/lisp/cli/doctor.el:18-32`                                |
| consult vertico ripgrep 集成       | `doomemacs/modules/completion/vertico/autoload/vertico.el:1-70`     |
| ivy counsel-rg 改造 (advice)       | `doomemacs/modules/completion/ivy/config.el:170-217`                |
| lsp 性能优化 minor-mode            | `doomemacs/modules/tools/lsp/config.el:7-39`                        |
| lsp-mode shutdown 延迟             | `doomemacs/modules/tools/lsp/+lsp.el:103-126`                       |
| eglot shutdown 延迟                | `doomemacs/modules/tools/lsp/+eglot.el:43-65`                       |
| doom env (替代 exec-path)          | `doomemacs/lisp/cli/env.el:73-92`                                   |
| doom env file loader               | `doomemacs/lisp/doom-lib.el:225-244`                                |
| platform detection                 | `doomemacs/lisp/doom.el:120-138`                                    |
| doom-fd-executable 跨平台          | `doomemacs/lisp/doom-projects.el:12-15`                             |
| doom-call-process                  | `doomemacs/lisp/lib/process.el:6-15`                                |
| tree-sitter set-tree-sitter!       | `doomemacs/modules/tools/tree-sitter/autoload/tree-sitter.el:12-49` |
| tree-sitter remap advice           | `doomemacs/modules/tools/tree-sitter/config.el:42-90`               |
| tree-sitter doctor                 | `doomemacs/modules/tools/tree-sitter/doctor.el:1-9`                 |
| magit +magit-display-buffer-fn     | `doomemacs/modules/tools/magit/autoload.el:24-67`                   |
| magit +magit-mark-stale-buffers    | `doomemacs/modules/tools/magit/autoload.el:119-140`                 |
| vterm module 守卫                  | `doomemacs/modules/term/vterm/config.el:4-25`                       |
| vterm toggle                       | `doomemacs/modules/term/vterm/autoload.el:7-43`                     |
| term visual mode 保护              | `doomemacs/modules/term/term/config.el:14-29`                       |
| eshell aliases                     | `doomemacs/modules/term/eshell/config.el:24-39`                     |
| macOS open with                    | `doomemacs/modules/os/macos/autoload.el:5-49`                       |
| macOS mdfind                       | `doomemacs/modules/os/macos/config.el:5-6`                          |
| gptel 集成                         | `doomemacs/modules/tools/llm/config.el:9-37`                        |
| 软降级列表 (spacemacs)             | `spacemacs/layers/+completion/helm/funcs.el:115-128`                |
| ripgrep 列宽 (spacemacs)           | `spacemacs/layers/+completion/helm/funcs.el:168-177`                |
| pyenv executable-find (spacemacs)  | `spacemacs/layers/+lang/python/funcs.el:130-150`                    |
| shell default (spacemacs)          | `spacemacs/layers/+tools/shell/config.el:23-29`                     |
