# AGENTS.md — lem 配置工作规范

本文件是本目录内 AI Agent 的唯一操作手册。配置复刻 VSCode Dark Modern，经 GNU Stow 直链 `~/.config/lem/`：**改仓库源即改部署源**，禁止编辑 `~/.config/lem/` 下任何部署路径。**新增文件后必须 `blue stow --restow lem`**（no-folding 单文件软链，新文件不会自动出现）；修改既有文件即时生效。

## 1. 架构契约

| 文件 / 目录         | 角色                             | 修改规则                                                        |
| ------------------- | -------------------------------- | --------------------------------------------------------------- |
| `init.lisp`         | 薄引导                           | 不改：配置目录定位 + read+eval 加载器 + 模块遍历，已稳定        |
| `modules/00-*`      | utils：vs$ 解析族、注册表、trace | 被全部模块依赖，必须最先加载                                    |
| `modules/NN-*.lisp` | 功能模块（NN 数字前缀定序）      | 字典序即加载序，间隔 10 留插入位；新模块建文件即可，init 零登记 |
| `modules/90-*`      | startup：钩子登记                | 必须最后加载                                                    |

加载序（数字前缀即依赖序）：`00-utils → 10-extensions → 20-icons → 25-fonts → 30-themes → 40-explorer → 45-keyhelp → 50-terminal → 55-completion → 60-editor-config → 70-keybindings → 80-modes-base → 81-modes-<lang> → 90-startup`。跨模块依赖写进各模块头注释；同层 81-* 互不依赖。

硬约束（违反即加载失败或运行期炸死）：

- 每个模块必须以 `(in-package :lem-user)` 开头，否则编译期触发包锁崩溃。
- **配置里静态书写「包前缀 + 不存在的符号」会在编译期炸死进程**，handler-case 无效。非 `:lem`/`:lem-user` 核心符号一律 `vs$` 动态解析，缺失只告警跳过。
- **keymap 绑定的符号必须是 `define-command` 产物**：执行靠同名命令类分发，普通 `defun` 符号绑键后按键即炸。
- Guix 打包的 lem 镜像内 `asdf:load-system` 不可用（output-translations 指向只读 store）；加载 store 扩展源码走 `vs-load-lem-source`（相对 `*lem-source-tree*`，升级换 hash 自动跟随），serial 顺序依赖的扩展逐文件按序加载（见 10-extensions 的 terminal/legit 先例）。

## 2. 符号速查（home 包陷阱）

动态解析时 `vs$` 第一个参数是 **定义包**，不是使用处包。踩过的坑：

| 符号                      | 定义包                        | 说明                                                            |
| ------------------------- | ----------------------------- | --------------------------------------------------------------- |
| `*FIND-FILE-HOOK*`        | `:lem/buffer/file`            | **未 reexport 进 :lem**，`vs$ :lem` 解析必空                    |
| `RUN-COMPLETION` 等补全族 | `:lem/completion-mode`        | 同上；弹窗补全公开 API 即 `run-completion`                      |
| `*TERMINAL-MODE-KEYMAP*`  | `:lem-terminal/terminal-mode` | 终端面板局部键                                                  |
| `LEGIT-STATUS`            | `:lem/legit`                  | `PROJECT-GREP` 在 `:lem/grep`                                   |
| `LSP-RENAME`              | `:lem-lsp-mode`               | language 泛型命令（find-definitions 等）在 `:lem/language-mode` |

其他语义坑：

- `buffer-filename` 返回 **namestring**（字符串），不是 pathname。
- 文件路径转目录用 `(make-pathname :directory (pathname-directory file))`；**不能**用 `uiop:pathname-parent-directory-pathname`——它只看 directory 组件再剥尾段，对文件路径返回的是祖父目录（explorer root 错位一层的根因）。
- `frame-multiplexer` 的 `C-z` 是前缀 keymap：任何绑定到 `C-z` 的命令都会整体覆盖数字快切。

## 3. 键位与帮助体系

- 全局键一律 `vs-bind`（keyspec 包名 命令名 分组 中文描述），落键同时登记 `*vs-binding-registry*`——45-keyhelp 的 F1 菜单与 C-c h 静态帮助页的数据源，**不经 vs-bind 的绑定不进帮助页**（局部 keymap / 默认键用 `vs-help-note` 收编，`vs-declare-group` 声明分组顺序）。
- `Shift` 必须写全拼 `"Shift-C-x"`（`S-` 是 super）。
- 已占用键：`C-p/C-f/C-s/C-b/C-j/C-\`/C-Tab/F2 等 VSCode 高频键覆盖 lem 同位键，被覆盖的移动退 Meta 系；`C-z`=undo、`C-/`=注释、`C-a`=全选（行首退 Home）为 Emacs 对齐键；`F1`=键位菜单、`C-c h`=静态帮助页、`M-/`=dabbrev。
- 弹窗补全站在 `lem/completion-mode:run-completion` 上（LSP 补全同管线）；候选必须是 `make-completion-item :label ...` 对象，字符串列表会在插入时炸。

## 4. 上游缺陷与规避（勿踩二遍）

- **`with-pop-up-typeout-window` 的 floating window 存活期间按移动键必炸**（MOVE-TO-VIRTUAL-LINE-COLUMN 收到 NIL column）——帮助类内容一律渲染进只读 buffer 再 `switch-to-buffer`。
- **属性渲染的只读 buffer（explorer）上放行 next-line/previous-line 必炸**（virtual-column 为 NIL）：mode keymap 必须显式拦 `Up`/`Down`（40-explorer 尾部的纯点操作命令），任何新「渲染型 buffer」照抄该模式。
- `M-` 系与 `F1` 等键序在本机 tmux 的 send-keys 下不可靠（Escape 前缀被拆），**自动化验证不走键注入**（见第 5 节）。
- lem 的 `with-editor-stream` 吞 `*error-output*`（ncurses/SDL2 双无声）：诊断一律 `vs-trace` 直写 `/tmp/vs-trace.log`。

## 5. 验证管线

1. **语法验证（每次修改后必跑）**：SBCL stub 包 read-only parse 全部 .lisp。stub 只需满足 reader 解析：`:lem-user`/`:uiop`（directory-pathname-p/getcwd/getenv 等）/`:lem`（config/icon-value）/`:asdf`/`:lem-core` 存在即可；运行用 `sbcl --noinform --load`（`--script` 静默丢输出）。
2. **行为自检（LEM_HOME 沙箱）**：临时目录 `init.lisp` 里先 `(load "~/.config/lem/init.lisp")` 再挂验证代码；**`LEM_HOME` 值必须带尾斜杠**（`merge-pathnames` 把无斜杠当文件名，init 会静默不加载）。延迟执行用 `make-timer` + `start-timer`（`lem-core` 导出，回调进主循环，界面就绪后安全跑），断言写 /tmp log，**零按键、零焦点纠缠**——逐键推进的 post-command 自检会与 startup/popup 焦点互噬产生假炸点。
3. **真 UI 驱动**：`lem --eval '(load "/tmp/xxx.lisp")'`——**eval 表达式在启动 parse 期就被 read 进 cl-user**（先写的 in-package 救不了，符号包已固化），所以必须经 load 文件、文件内 in-package 才生效。
4. **tmux 观测**：capture-pane 看画面；字符注入只用 `set-buffer` + `paste-buffer`（`send-keys -l` 首字符后必丢）；启动后必须先发一键才触发 post-command 启动钩子（无按键只见 dashboard，不是加载失败）。
5. **渲染类改动（侧栏/主题/字体）必须真机 capture 验证**，静态检查不算数；SDL2 字体 config 只持久化到 config.lisp、**下一次启动才生效**。

禁令沿用仓库根 AGENTS.md：不运行 `blue rebuild` / `guix system reconfigure`（提醒用户手动），不编辑 `channel.lock` 与 `tmp/`，不持久安装包。本目录为 mutable Stow 源，普通修改无需 `blue home`。
