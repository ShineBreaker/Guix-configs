# AGENTS.md — Lem 配置开发规范

本文件是 Lem 编辑器配置（复刻 VSCode Dark Modern 主题与交互）的 AI Agent 操作手册与技术备忘。

配置通过 GNU Stow 直链到 `~/.config/lem/`：
- **即时生效**：修改已有文件保存即生效，禁止直接修改 `~/.config/lem/` 下的部署软链。
- **新增文件**：新增文件后必须运行 `blue stow --restow lem` 补建单文件软链（因采用 no-folding 模式）。

---

## 1. 架构契约与加载顺序

| 文件 / 目录 | 角色定位 | 维护规则 |
| --- | --- | --- |
| `init.lisp` | 薄引导层 | 配置目录定位、读取求值器与模块遍历器（稳定，不常改动） |
| `modules/00-*` | 工具与基础层 | `vs$` 动态符号解析族、按键注册表、Trace 设施；被所有模块依赖，最先加载 |
| `modules/NN-*.lisp` | 功能业务模块 | `NN` 数字前缀决定加载顺序，间隔 10 留插入位；新建模块直接放文件，无需在 init 登记 |
| `modules/modes/*.lisp` | 语言 Mode 适配 | LSP 与 Paredit 接线；同层模块互不依赖，由 `init.lisp` 在 `80` 之后、`90` 之前统一载入 |
| `modules/90-*` | 启动与钩子注册 | 统一挂载启动 Hook，必须最后加载 |

### 模块依赖顺序
```
00-utils → 10-performance → 20-icons → 25-fonts → 30-themes
  → 40-explorer → 45-keyhelp → 46-problems → 50-terminal
  → 55-completion → 60-editor-config → 70-keybindings
  → 75-context-menu → 76-whichkey → 80-modes-base
  → modes/<lang> → 90-startup
```

### 核心硬约束（违反即导致启动崩溃）
1. **包锁声明**：每个模块开头必须声明 `(in-package :lem-user)`，防止编译期触发 SBCL 包锁崩溃。
2. **动态符号解析**：禁止在代码中静态书写 `包前缀:不存在符号`（编译期会直接炸裂进程，`handler-case` 无法捕获）。非 `:lem` 与 `:lem-user` 的符号一律通过 `vs$` 动态解析，缺失时告警跳过。
3. **命令对象绑定**：Keymap 绑定的符号必须由 `define-command` 生成。普通 `defun` 函数绑定后触发按键会引发异常。
4. **源码树路径**：当前 Git 源码构建（`lem-next-2.3.0`）在 Store 内包含完整源码树，API 疑问可直接查看源码验证。废除外部扩展补载，运行时仅允许通过 `vs-load-source` 加载配置目录内部文件。

---

## 2. 符号速查与踩坑指南

动态解析时，`vs$` 的第一个参数是**符号定义的源包**，而非使用处的包：

| 符号 | 定义所在包 | 说明 |
| --- | --- | --- |
| `*FIND-FILE-HOOK*` | `:lem/buffer/file` | **未 re-export 进 `:lem`**，通过 `:lem` 解析必然为 NIL |
| `RUN-COMPLETION` 等补全族 | `:lem/completion-mode` | 弹窗补全的核心公开 API |
| `ISEARCH-FORWARD` | `:lem/isearch` | 不再从 `:lem` 导出；`UNMATCH-ISEARCH-ATTRIBUTE` 已移除 |
| `*TERMINAL-MODE-KEYMAP*` | `:lem-terminal/terminal-mode` | 终端面板局部按键映射 |
| `LEGIT-STATUS` | `:lem/legit` | Git 面板入口；`PROJECT-GREP` 位于 `:lem/grep` |
| `LSP-RENAME` | `:lem-lsp-mode` | 泛型语言命令（如 `find-definitions`）位于 `:lem/language-mode` |

### 常见语义与运行时陷阱
- **路径类型**：`buffer-filename` 返回的是 Namestring（字符串），不是 Pathname 对象。
- **目录提取**：文件路径转目录必须使用 `(make-pathname :directory (pathname-directory file))`；切勿使用 `uiop:pathname-parent-directory-pathname`（它处理文件路径会错误返回祖父目录）。
- **`vs-setvar` 与 `vs-setglobal` 的区别**：
  - `vs-setvar`：操作 Lem 的 `variable-value` 属性列表（plist 机制）。
  - `vs-setglobal`：用于上游直接引用的 Special Variables（如 `*grep-command*`、`*auto-format*` 等），必须通过 `setf symbol-value` 全局赋值，否则运行时读到的仍是默认值。
- **Keymap 前缀树模型**：当前版本采用前缀树（`KEYMAP*` 类）模型，遍历绑定需通过 `lem-core:keymap-prefixes`，沿 Suffix 子 Keymap 逐层解析。

---

## 3. 键位映射与帮助体系

- **集中登记**：全局按键统一使用 `vs-bind`（参数：keyspec、包名、命令名、分组、中文描述）。它在绑定按键的同时注册到 `*vs-binding-registry*`，供 F1 菜单和 `C-c h` 帮助页检索。
- **Shift 组合键规范**：
  - 命名键（方向键、F 键、Tab 等）写全拼，如 `"Shift-C-Tab"`。
  - **Shift + 字母组合键必须绑定为大写形式**（如 `"C-F"` 代表 Ctrl+Shift+F，`"M-D"` 代表 Alt+Shift+D）。在 Webview 前端中，底层 JS 事件会将 Shift+字母派发为大写字符且清除 shift 标志，写 `"Shift-C-f"` 会导致按键无法匹配而失效。
- **高频按键分布（VSCode 风格）**：
  - `C-p`：文件速开；`C-f`：文件内搜索；`C-s`：保存；`C-b`：侧边栏切换；`C-j` / `C-\``：终端面板。
  - `C-t`：工作区符号搜索（带 `--hidden`，支持 `.config/` 等隐藏路径）；`C-L`：多光标全选当前符号。
  - `C-z`：Undo；`C-/`：行注释；`C-a`：全选；`C-.`：Code Action；`C-d`：多光标添加选区。
  - `F1`：命令面板/键位菜单；`C-c h`：键位帮助页；`F12`：跳转到定义；`C-I`：跳转到实现。

---

## 4. 上游缺陷应对与规避策略

1. **图形前端机制（Webview）**：
   - 当前采用 WebKitGTK + Canvas/JS 前端，不再使用 SDL2。
   - 字体与字号通过运行时 API `set-font-name` 与 `set-font-size`（CSS 逻辑像素）动态设置。
2. **定时器限制**：`make-timer` 在 Webview 前端由于缺少调度 Tick 不会触发；沙箱或延迟探测使用 `sb-thread:make-thread` 配合 sleep。
3. **只读 Buffer 光标移动防护**：
   - 属性渲染的只读 Buffer（如 Explorer）禁止响应原生 `next-line`/`previous-line`，须在 Mode Keymap 中拦截上下箭头，使用专用的点操作命令。
   - `with-pop-up-typeout-window` 悬浮窗响应光标移动会导致异常，帮助内容统一渲染进只读 Buffer 后切换。
4. **诊断与日志**：Lem 的 `with-editor-stream` 会静默吞掉 `*error-output*`，诊断输出统一使用 `vs-trace` 写入 `/tmp/vs-trace.log`。
5. **Tabbar 标签栏优化**：
   - 默认过滤临时 Buffer，仅展示文件 Buffer。
   - 引入内容缓存机制，当标题与状态未变化时跳过重复的 HTML 生成与 WebSocket 推送，大幅降低打字时的 CPU 开销。
6. **LSP 悬停提示（Hover）异步化**：
   - 鼠标移动事件（~60次/秒）仅记录目标坐标，由常驻线程进行 0.12s 防抖后通过 `send-event` 异步发起 LSP 查询，防止阻塞主编辑线程。
7. **Ripper / Grep 隐藏目录支持**：`ripgrep` 默认忽略点号开头的目录，在配置项目搜索时必须显式附加 `--hidden` 参数。
8. **目录 Prompt 默认值**：调用 `prompt-for-directory` 时必须显式传递 `:directory` 参数，避免上游透传 NIL 导致 Tab 补全抛类型错误。

---

## 5. 自动化测试与验证管线

1. **语法静态解析（每次修改后必跑）**：
   - 使用 SBCL Stub 脚本对 `modules/` 目录下所有 `.lisp` 文件进行只读解析，校验括号与宏展开。
2. **行为自检（ncurses `--eval` 通道）**：
   - 在 Tmux 隔离会话中拉起 `lem -i ncurses --eval '(load "/tmp/probe.lisp")'` 执行断言。
   - 断言脚本在配置加载完成后执行，校验按键注册表与变量状态。
3. **Webview 行为级验证（WebSocket 直连注入）**：
   - 直连 `lem-server` 的本地 WebSocket 端口，通过 JSON-RPC 2.0 `input` 与 `redraw` 方法注入按键和鼠标事件。
   - 绕过键盘焦点与桌面锁屏限制，配合临时 `vs-trace` 探针完成端到端行为验证。
