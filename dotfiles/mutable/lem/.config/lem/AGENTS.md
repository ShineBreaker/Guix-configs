# AGENTS.md — lem 配置工作规范

本文件是本目录内 AI Agent 的唯一操作手册。配置复刻 VSCode Dark Modern，经 GNU Stow 直链 `~/.config/lem/`：**改仓库源即改部署源**，禁止编辑 `~/.config/lem/` 下任何部署路径。**新增文件后必须 `blue stow --restow lem`**（no-folding 单文件软链，新文件不会自动出现）；修改既有文件即时生效。

## 1. 架构契约

| 文件 / 目录         | 角色                             | 修改规则                                                        |
| ------------------- | -------------------------------- | --------------------------------------------------------------- |
| `init.lisp`         | 薄引导                           | 不改：配置目录定位 + read+eval 加载器 + 模块遍历，已稳定        |
| `modules/00-*`      | utils：vs$ 解析族、注册表、trace | 被全部模块依赖，必须最先加载                                    |
| `modules/NN-*.lisp` | 功能模块（NN 数字前缀定序）      | 字典序即加载序，间隔 10 留插入位；新模块建文件即可，init 零登记 |
| `modules/modes/*.lisp` | 各语言 mode（LSP / paredit 接线） | 字典序，同层互不依赖；由 init 插在 80 之后、90 之前加载 |
| `modules/90-*`      | startup：钩子登记                | 必须最后加载                                                    |

加载序（数字前缀即依赖序）：`00-utils → 10-performance → 20-icons → 25-fonts → 30-themes → 40-explorer → 45-keyhelp → 50-terminal → 55-completion → 60-editor-config → 70-keybindings → 75-context-menu → 76-whichkey → 80-modes-base → modes/<lang> → 90-startup`。跨模块依赖写进各模块头注释；同层 modes/ 互不依赖。

硬约束（违反即加载失败或运行期炸死）：

- 每个模块必须以 `(in-package :lem-user)` 开头，否则编译期触发包锁崩溃。
- **配置里静态书写「包前缀 + 不存在的符号」会在编译期炸死进程**，handler-case 无效。非 `:lem`/`:lem-user` 核心符号一律 `vs$` 动态解析，缺失只告警跳过。
- **keymap 绑定的符号必须是 `define-command` 产物**：执行靠同名命令类分发，普通 `defun` 符号绑键后按键即炸。
- nightly AppImage（lem-next-bin，用户自打包官方 `Lem-x86_64-nightly.AppImage`）**扩展全部内置编译进 core**（terminal/legit/process/shell-mode/patch-mode/dashboard/lsp-mode/completion-mode 等），且镜像**无源码树**（`asdf:system-source-directory` 返回构建容器路径，本机不存在）——此两条仅适用 AppImage 构建；当前 git 源码构建（lem-next-2.3.0-0.68e85e0）在 store 内**带完整上游源码树**（`/gnu/store/vqbd1hhl5yvyjhc3p1phgjwv5iiy61qr-lem-next-2.3.0-0.68e85e0/share/common-lisp/sbcl/lem-next/`），API 疑问可直接读源码验证。原 store 扩展补载机制（10-extensions / `vs-load-lem-source`）已废除，运行时只允许 `vs-load-source` 加载配置目录内文件。

## 2. 符号速查（home 包陷阱）

动态解析时 `vs$` 第一个参数是 **定义包**，不是使用处包。踩过的坑：

| 符号                      | 定义包                        | 说明                                                            |
| ------------------------- | ----------------------------- | --------------------------------------------------------------- |
| `*FIND-FILE-HOOK*`        | `:lem/buffer/file`            | **未 reexport 进 :lem**，`vs$ :lem` 解析必空                    |
| `RUN-COMPLETION` 等补全族 | `:lem/completion-mode`        | 同上；弹窗补全公开 API 即 `run-completion`                      |
| `ISEARCH-FORWARD`         | `:lem/isearch`                | nightly 起不再从 :lem reexport；`UNMATCH-ISEARCH-ATTRIBUTE` 已删 |
| `*TERMINAL-MODE-KEYMAP*`  | `:lem-terminal/terminal-mode` | 终端面板局部键                                                  |
| `LEGIT-STATUS`            | `:lem/legit`                  | `PROJECT-GREP` 在 `:lem/grep`                                   |
| `LSP-RENAME`              | `:lem-lsp-mode`               | language 泛型命令（find-definitions 等）在 `:lem/language-mode` |

其他语义坑：

- `buffer-filename` 返回 **namestring**（字符串），不是 pathname。
- 文件路径转目录用 `(make-pathname :directory (pathname-directory file))`；**不能**用 `uiop:pathname-parent-directory-pathname`——它只看 directory 组件再剥尾段，对文件路径返回的是祖父目录（explorer root 错位一层的根因）。
- `frame-multiplexer` 的 `C-z` 是前缀 keymap：任何绑定到 `C-z` 的命令都会整体覆盖数字快切。
- **`vs-setvar` 与 `vs-setglobal` 二分**：`vs-setvar` 走 lem 的 `variable-value` plist 机制；但上游大量变量是**直接引用的 special variable**（grep 的 `*grep-command*`/`*last-query*`、format 的 `*auto-format*`、line-numbers 的 `*relative-line*` 等），plist 改了运行时读到的仍是镜像默认值——这类必须 `vs-setglobal`（setf symbol-value）。判断法：上游源码里 `(when *auto-format* ...)` 这种裸引用就是 vs-setglobal。
- **keymap 有两代模型，探针写法不同**：20260531 构建起是 PR #2100 的**前缀树**（`KEYMAP*` 类，槽 `PREFIXES/CHILDREN/PARENTS/FUNCTION-TABLE`，无 TABLE）——检查绑定走 `(lem-core:keymap-prefixes km)` 遍历 PREFIX 对象、比较 `(format nil "~A" (lem-core:prefix-key p))`，多键序列沿 suffix（子 keymap）逐层下钻；`define-key` 仍收字符串 keyspec + 命令符号，配置侧零改动。20250810 旧构建是哈希表模型（键为 key 结构体，`gethash` 新串必 NIL，须 maphash + 打印表示比较）。

## 3. 键位与帮助体系

- 全局键一律 `vs-bind`（keyspec 包名 命令名 分组 中文描述），落键同时登记 `*vs-binding-registry*`——45-keyhelp 的 F1 菜单与 C-c h 静态帮助页的数据源，**不经 vs-bind 的绑定不进帮助页**（局部 keymap / 默认键用 `vs-help-note` 收编，`vs-declare-group` 声明分组顺序）。
- `Shift` 必须写全拼 `"Shift-C-x"`（`S-` 是 super）。
- 已占用键：`C-p/C-f/C-s/C-b/C-j/C-\`/C-Tab/F2 等 VSCode 高频键覆盖 lem 同位键，被覆盖的移动退 Meta 系；`C-z`=undo、`C-/`=注释、`C-a`=全选（行首退 Home）、`C-=`/`C--`=字号为 Emacs/通用对齐键；`C-.`=Code Action（LSP）、`C-d`=多光标加光标（isearch 活动时逐个命中加光标，非搜索态 no-op）；`F1`=键位菜单、`C-c h`=静态帮助页、`M-/`=dabbrev。**`C-c h` 双语义**：全局是帮助页，但 lsp-mode 局部 keymap 把 `C-c h` 绑成了 hover（上游默认，未覆盖），LSP buffer 内会被遮蔽。lisp-mode 局部 `C-c C-d h`=CL Hyperspec。上游默认键（C-u 数字参数、C-x (/)/e 键盘宏、C-x SPC 矩形模式、Shift+方向选区、F3/Shift-F3 查找导航、isearch 内 C-M-n/p 多光标）不经 vs-bind，已用 vs-help-note 收编进帮助页。
- 弹窗补全站在 `lem/completion-mode:run-completion` 上（LSP 补全同管线）；候选必须是 `make-completion-item :label ...` 对象，字符串列表会在插入时炸。

## 4. 上游缺陷与规避（勿踩二遍）

- **nightly 图形前端是 webview（WebKitGTK + Canvas/JS），不是 SDL2**：`:sdl2-*` 系列 config 键已无读者；字体走运行时 API `set-font-name`（fontconfig 家族名，非 ttf 路径）+ `set-font-size`（**CSS 逻辑像素**，物理尺寸 = N×DPR；2x 屏 13 ≈ 旧 SDL2 26 物理像素观感）。webview **不持久化字号**，每次启动由 25-fonts 设置；ncurses 下这些调用报错，故包 ignore-errors。部署 config.lisp 里遗留 `:SDL2-*` 键属无害残留。
- **lem-core 的 make-timer/start-timer 在 webview 前端不 fire**（缺 timer tick 调度点）：沙箱验证需要延迟执行时，用 `sb-thread:make-thread` + sleep 做只读探测，不要依赖 timer。
- **`with-pop-up-typeout-window` 的 floating window 存活期间按移动键必炸**（MOVE-TO-VIRTUAL-LINE-COLUMN 收到 NIL column）——帮助类内容一律渲染进只读 buffer 再 `switch-to-buffer`。
- **属性渲染的只读 buffer（explorer）上放行 next-line/previous-line 必炸**（virtual-column 为 NIL）：mode keymap 必须显式拦 `Up`/`Down`（40-explorer 尾部的纯点操作命令），任何新「渲染型 buffer」照抄该模式。
- `M-` 系与 `F1` 等键序在本机 tmux 的 send-keys 下不可靠（Escape 前缀被拆），**自动化验证不走键注入**（见第 5 节）。
- lem 的 `with-editor-stream` 吞 `*error-output*`（webview/ncurses 双无声）：诊断一律 `vs-trace` 直写 `/tmp/vs-trace.log`。
- **20260531 构建「闪退」签名**：UI 起来后偶发 SBCL fatal `cannot suspend thread 0x…: 3 (ESRCH)`（webview/GTK 外部线程 vs GC 竞态，上游运行时 bug，间歇性——同构建有连跑数小时先例）。fatal 进 LDB 后：CLI 启动时 LDB 文本会落进 *Terminal* 面板（进程半死）；desktop 启动 stdin=EOF → LDB 退出带崩全进程 = 用户视角的「闪退」。处置：直接重启即可（勿当配置回归排查——2026-08-31 实测一轮：裸配置/沙箱全配置/真实配置交替「复现」，最终确认与配置无关）。**timeout 杀 wrapper 会留下 lem.real 孤儿**，多实例并存会加剧竞态，排查前先 `pgrep -af lem.real` 清场（注意 pgrep -f 会匹配到自己的命令行，过滤之）；`~/.config/lem/debug.log` 只记启动不记崩溃。
- **插件通道三坑**（lem-extension-manager + 内置 Quicklisp）：① `*PACKAGES-DIRECTORY*` 在镜像构建期被固化成 `/root/.config/lem/packages/`（构建容器 HOME 残留），不可写，60-editor-config 已 `vs-setglobal` 重设到 `~/.config/lem/packages/`；② 镜像里 quicklisp **客户端在但 dist 为空**（`ql-systems=0`），首次装包前须 `(ql-dist:install-dist "https://beta.quicklisp.org/dist/quicklisp.txt" :replace nil :prompt nil)`（官方 dist 里**没有任何 lem 系统**——第三方 lem 扩展走 `lem-use-package :source '(:type :git ...)` 从 GitHub 直装，ql 通道只用于通用 CL 库）；③ `LEM-USE-PACKAGE` 是**宏**不是函数，程序化调用要 eval/macroexpand，不能 funcall。
- **webview 前端下 `--eval` 探针不可用**（与多实例无关）：webview 前端初始化与 apply-args 的求值序不兼容，`--eval` 的 load 经常整段不执行（探针文件连 marker 都不落地）或直接挂起；剥离 display 跑则崩在 webview 初始化（fatal ERROR，stderr 被吞只留 `compilation unit aborted` 摘要）。**探针一律走 ncurses 通道**（见第 5 节第 2 条）。
- **tabbar（webview 顶栏 buffer 列表条）双坑**：① 上游 `*enable-tabbar-on-startup*` 默认 t，显示**全部 buffer**（含 *terminal*/*dashboard* 等临时 buffer，无过滤点）；60-editor-config 已 wrap `lem/tabbar::get-tabbar-buffers` 过滤为只显示文件 buffer，tab 的点击切换/关闭/dirty 圆点为 webview 原生。② **ncurses 前端下 tabbar 渲染走 lem-server 的 HTML 管线、view 类型不匹配必崩**（redraw 即 fatal），60-editor-config 按前端分派：webview 开、其余关（探针通道能跑正是依赖此关闭）。
- **`set-clickable` 回调签名前端不一致（2026-09-02 explorer 点击实测）**：`SET-CLICKABLE` 在 `:lem-core`（internal）。上游 main 源码与 ncurses 实测都是 `(window point)` 两参 funcall，但 **webview 前端实际分发收 0 参**——固定形参 lambda 点一下就 `Invalid number of arguments: 0` 炸进 SBCL debugger。配置侧 clickable 回调**一律 `(lambda (&rest args) ...)` + 渲染期闭包捕获条目数据**（40-explorer 的 vs-make-icon-click / vs-insert-tree-line 模式），不依赖回调参数、不在回调里读属性。
- **终端双通道与 vterm 构建门槛（2026-09-03 git 构建实测收口）**：50-terminal 为双通道——vterm（`lem-terminal`，libvterm 真终端）+ fish（`sb-posix:setenv "SHELL"` 注入，上游 terminal-new 只读 `$SHELL`，无 Lisp 覆盖点），退化通道为 shell-mode + bash + `script(1)`。**20260531 AppImage 构建的 vterm 通道带上游 I/O 线程数据竞争（#2209/#2211 于 2026-06-03/05 修复）**：terminal 包与 terminal.so 均正常加载、fish 能 spawn，但 spawn 后主进程随机 SIGSEGV fatal（ncurses 实测复现）——旧结论「配置层不可修、弃用」在修复版构建上不再成立。构建自识别读 `sb-impl::*runtime-pathname*`（`uiop:argv0` / `sb-ext:runtime-pathname` / `*lem-version*` 均被镜像剥离为 NIL，/proc/self/exe 指向 ld-linux 拿不到）：AppImage 包名（`lem-next-bin-YYYYMMDD`）按 ≥20260605 门槛；**git 源码构建（`lem-next-<版本>-<hash>`，当前 lem-next-2.3.0-0.68e85e0 = 2026-08-31）默认信任**。**shell-mode 退化通道不能用 fish**：哑管道下 fish 0.13s 发出能力查询包（kitty `?u` / XTVERSION / OSC 11 / DECRQM）后阻塞等应答，~30s 才出提示符（pty 实测），bash 无查询即时出（0.02s）。vterm+fish 在 webview 下已终验（fastfetch 全彩 + starship 提示符 + 项目根 cwd + toggle 管线）。另：90-startup 的 workspace 钩子在面板已显示时跳过 split（用户启动即按 C-j 场景，否则叠加双终端窗）；webview 前端下 startup 同样需要首键触发。

## 5. 验证管线

1. **语法验证（每次修改后必跑）**：SBCL stub 包 read-only parse modules/ 下全部 .lisp（含 modes/ 子目录，递归）。stub 需满足 reader 解析：`:lem-user`/`:uiop`/`:lem`/`:asdf`/`:lem-core` 包存在，且配置里静态引用的各包符号须在 stub 中 **大写 export**（read 的 :upcase 语义）；运行用 `sbcl --noinform --load`（`--script` 静默丢输出）。
2. **行为自检（ncurses `--eval` 通道；LEM_HOME 沙箱与 webview `--eval` 均不可用，见第 4 节）**：`tmux new-session -d -s lemprobe -x 220 -y 50 "env -u WAYLAND_DISPLAY -u DISPLAY lem -i ncurses --eval '(load \"/tmp/xxx.lisp\")'"`——`-i ncurses` 强制 ncurses 前端（tabbar 已被 60-editor-config 关闭，不会崩），load 在**用户配置加载完成之后**执行（after-init → apply-args 序），直接读 `*vs-binding-registry*` 条数、变量 symbol-value、keymap 绑定即为生效态。断言写 /tmp log、文件末尾 `(sb-ext:exit :code 0)` 自退出；**flet/labels 局部函数名勿用 `log` 等 CL 外部符号**（包锁违规 → load 编译期 fatal）。延迟执行用 `sb-thread:make-thread` + sleep（timer 不 fire，见第 4 节），**零按键、零焦点纠缠**。
3. **--eval 的 reader 限制**：eval 表达式在启动 parse 期就被 read 进 cl-user（先写的 in-package 救不了，符号包已固化），所以必须经 load 文件、文件内 in-package 才生效。
4. **tmux 观测**：capture-pane 看画面；字符注入只用 `set-buffer` + `paste-buffer`（`send-keys -l` 首字符后必丢）；启动后必须先发一键才触发 post-command 启动钩子（无按键只见 dashboard，不是加载失败）。
5. **渲染类改动（侧栏/主题/字体）必须真机 capture 验证**，静态检查不算数。webview 前端在 xvfb 下恒黑屏（webkit 无 GPU 渲染问题，加 WEBKIT_DISABLE_* 环境变量也无效），渲染验证走**真机 wayland：沙箱 LEM_HOME 起实例 + grim 截屏 + 及时 kill**。webview 字号不持久化，字体改动重启即生效。注意：**桌面处于锁屏时 grim 只能截到锁屏层**（编辑器被虚化不可读）——夜间自动化遇到锁屏时，webview 视觉验证只能改期，可先用 ncurses 通道验证非前端相关的渲染逻辑（侧栏 buffer 内容与码点可 capture-pane 校验）。
6. **探针执行模型三教训（2026-09-02 explorer 点击排查实测）**：① 外来线程（make-thread + sleep 轮询）会**无声死掉**（错误进被吞的 *error-output*，日志一行不留）——复杂探针改走 `(lem:send-event #'fn)` 在**编辑线程内**执行，观察步骤再 `send-event` 链式排队（FIFO 保序，不用 sleep）；② lem 编辑线程绑定 `*print-readably`=T，探针日志用 `~S` 打印 lem 对象（window/cursor/package）必抛 print-not-readable，**日志格式串一律 `~A` 并先 `(let ((*print-readably* nil)) ...)`**；③ 合成鼠标点击：`(lem:receive-mouse-button-down x y px py :button-1 1)` 传 frame 单元坐标——leftside 侧栏行 N 的 frame-y = `(window-y win) + N - (view-point 行号)`，写错一行就静默点空（上游无任何报错）。探针文件发布前先 python 括号平衡检查（本轮三份探针各炸一次）。
7. **`--eval` load 期禁窗口操作（2026-09-02 终端重写实测）**：load 阶段（apply-args 序）直接 funcall 涉及 split-window/delete-window/switch-to-buffer 的命令（如 vscode-toggle-terminal）会让进程**当场死掉**（无 LDB 输出、tmux session 连带消失）——与 90-startup「after-init 期窗口操作 display 层拒绘」同根。探针里的窗口动作一律 `make-thread sleep → send-event` 延后到命令循环期执行。另：探针日志 `with-open-file` 勿用 `:if-exists :supersede`（每次调用截断覆盖，多行日志只剩最后一行），用 `:append`。

禁令沿用仓库根 AGENTS.md：不运行 `blue rebuild` / `guix system reconfigure`（提醒用户手动），不编辑 `channel.lock` 与 `tmp/`，不持久安装包。本目录为 mutable Stow 源，普通修改无需 `blue home`。
