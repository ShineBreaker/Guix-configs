---
name: guix-configs-workflow
description: Use when the user works inside ~/Projects/Config/Guix-configs and mentions '改 dotfiles', 'blue home', 'guix system reconfigure', 'shepherd service', 'stow 死链', 'blue stow', 'AGENTS.md 翻新', 'fcitx', 'IME 没输入法', 'Electron 没输入法', 'wireplumber', '二轨 dotfiles', '恢复被删除的 dotfiles', or related. Ten sub-protocols — dotfiles deploy verification, worker delegation, multi-line edit safety, Guix service debugging, GNU Stow mutable config, restoring deleted dotfiles, ISO 移植, 需求澄清, 模块归属陷阱.
---
# guix-configs-workflow — Guix-configs 仓库高频工作流

> Guix-configs 仓库内的高频工作流合集。所有内容提炼自 160 张 KB 卡片 + MEMORY.org F019/F021/F022/F025/F026 + 28 张 guix 卡片 + Guix-configs project memory。源数据在 ~/Documents/Org/ 由人类维护,本 skill 是缓存层。

## 关键不变量(仓库内一切工作的硬约束)

1. **dotfiles 改源 ≠ 生效**:`~/.config/<app>` 指向 `/gnu/store` 只读副本。验证三步:① 改源 ② `blue home` ③ grep 部署位置(`~/.config/`,不是仓库源)确认同步。restart service **不够**。
   - **`blue home` 不会重启已在跑的 home-shepherd 守护进程**——它只对 `on-change` gexp 求值并加载新配置,但已在跑的进程持有旧 `make-forkexec-constructor` 参数。要让新 service 定义生效,**必须手动 `herd restart <svc>`**(参见 §4.4)。如果改了 service 定义导致旧进程与新进程并存冲突(如带 `--replace` 的旧 gateway 占着端口不放),还需直接 `kill` 旧 shepherd PID(见 §4.5)。
2. **删除同理**:`~/.config/<app>` 下任何"清理"(rm 旧文件/孤儿/缓存/**pycache** 等)在下一次 `blue home` 时会从 store 副本重新软链接回来。删除 dotfile 必须在 `dotfiles/immutable/<app>/` 源里做,`blue home` 重新生成软链接;直接 `rm ~/.config/...` 只能算"临时清",**不持久**。典型场景:某 skill 整体从源删除后,`~/.config/<app>/skills/<name>/` 还会带 `__pycache__/` 孤儿 — 必须从源删。

   **例外 — `~/.local/share/hermes/skills/` 不归本不变量管**。该目录是 Hermes 安装包自带的 read-only bundle(`0555`),不在 `dotfiles/immutable/` 仓库源里;`blue home` 不会重新生成它(它走 `source/nix/configuration/programs/hermes.nix` 装 hermes-agent `full` 输出)。对此目录做"临时清"不会被 `blue home` 回滚。详细精简流程见 `hermes-skill-curation` skill 的"XDG trash 范式"小节。

3. **AI 禁跑** `blue rebuild` / `guix system reconfigure` / `guix home reconfigure` (sudo 卡死 CLI)。改源后只能 `blue home` 暂用,固化等用户操作。**例外**:`blue structor` 只重写 AGENTS.md 标记对内容,AI 可以跑(见 §5.3)。
4. **AI 禁直接编辑** `/gnu/store` 只读副本、`tmp/` 下 blue 产物、已部署的 `~/.config/` `~/.local/`。
5. **commit 严格遵循 gitmessage 规范** + 逐文件 serial(禁并发) + 撤回用 `--soft/--mixed`(禁 `--hard`) + 混合文件立即修复。
6. **subagent 委派** 必须显式传 `cwd` + 任务描述用绝对路径(双保险),worker 默认 cwd 不是项目根。
7. **AGENTS.md 目录树** **禁止手写**(用户偏好 2026-06-21)。所有 `## 目录结构` 段必须用 `<!-- structor:begin -->...<!-- /structor -->` 标记对 + `blue structor` 自动重写。详细见 §5。

---

## 1. dotfiles 部署验证三步(高频,任何 dotfile 改动前必读)

```
① 改源(dotfiles/immutable/<app>/ 或 source/)
② blue home(在仓库根跑,见下方 ⚠)
③ 校验同步:
   md5sum <源文件> vs md5sum ~/.config/<app>/<同路径>
   或 readlink ~/.config/<app>/<file> 看 store hash 是否变
   然后 restart service + 行为验证
```

**反例**: 改 source/config.org + emacs 重启 → 读到旧配置(假阳性)。F019 + KB 20260615-232932。

**根因机制**: Guix Home 的 `home-dotfiles-service-type` 把文件复制到 store,再软链接到 $HOME;改源后 store 副本不变,软链接 target 不变,所有读 ~/.config 的程序读到旧内容。

### ⚠ `blue home` 必须在仓库根跑(用户反复踩过的坑)

```bash
# ✅ 正确
cd ~/Projects/Config/Guix-configs && blue home

# ❌ 错:从子模块 cwd 跑(典型:emacs 子模块在 dotfiles/mutable/emacs/.config/emacs/)
blue home
# → 报 "&external-error / No command with this name"
# → 看起来像 blue 命令本身挂了,实际是子模块 cwd 找不到 blueprint.scm / source/config.org
```

**根因**: `blue` 读 cwd 的 `blueprint.scm` + `source/config.org` 才能正常求值;子模块 cwd 没有这两个文件,blue 启动后报"无子命令"。在子模块里改完 .el 必须先 `cd` 回仓库根再 `blue home`。

**完整路径约束**(常见子模块 cwd):

| 子模块                                  | cwd           | 仓库根命令                                                      |
| --------------------------------------- | ------------- | --------------------------------------------------------------- |
| `dotfiles/mutable/emacs/.config/emacs/` | Emacs 配置根  | `cd ~/Projects/Config/Guix-configs && blue stow --restow emacs` |
| `dotfiles/immutable/agents/`            | Hermes agents | `cd ~/Projects/Config/Guix-configs && blue home`                |
| 其他 `dotfiles/immutable/<app>/` 子目录 |               | `cd ~/Projects/Config/Guix-configs && blue home`                |

### 仓库源直接验证 ≠ 部署生效(假阳性陷阱)

改完 .el 后,**仅做仓库源语法验证**(`emacs --batch` / `emacsclient --eval` 读仓库源)是不够的——

- `emacsclient --eval` 走的是运行中的 daemon,daemon 读的是 `/gnu/store` 软链,不是仓库源
- 仅当 daemon 重启后 + store 副本已同步(走完 `blue home` + md5sum 校验)时,emacsclient 验证才是真验证
- **byte-compile-file 通过 ≠ 变量名正确**:Emacs 31 对不存在的变量 `setq` 不报 warning,代码可编译但运行时静默失效(典型:把废弃的 `line-number-display-width` 写成 `display-line-numbers-width` —— 本案例踩过)

**完整验证四步**(缺一不可):

1. 改源
2. `cd ~/Projects/Config/Guix-configs && blue home`
3. `md5sum` 源 vs `~/.config/<app>/` 部署,确认 store hash 变了
4. `herd restart <service>` + **行为模拟**(开 buffer 触发 hook,inspect 实际变量值),不要只信 byte-compile

### Emacs 配置调试专属四陷阱(踩坑合集)

#### 陷阱 1:变量名废弃/拼错,byte-compile 不会报

Emacs 31 对不存在的变量 `setq` 不发 warning。`byte-compile-file` 静默通过,运行时 hook 直接 `void-variable` 静默失效。

**典型案例**: 行号列宽控制变量是 `display-line-numbers-width`(Emacs 27+),`line-number-display-width` 早已废弃。写错后 `setq` 不会报错,只有 `symbol-value` 取出来才发现是 `void` 触发 nil。

**防护**: 行为模拟阶段必须 `inspect` 实际值(见陷阱 3),不能只信编译通过。

#### 陷阱 2:hook 里用 buffer-local 变量做守卫,绕过 global-mode 延迟启用

`global-display-line-numbers-mode` 启用时,把 buffer-local `<mode>-mode` 翻成 t 的动作发生在 `find-file-hook` 之后。若 hook 用 `display-line-numbers-mode` 做守卫,hook 跑时该值为 nil → 整个 `when` 跳过 → 配置未生效 → 后续 global-mode 翻成 t 但配置仍未设 → 用户看到原始默认行为 + 极端情况下触发 `arith-error`(如 `display-line-numbers-type 'relative` + 行号算术溢出)。

**正确做法**: 守卫用 global 开关(`global-display-line-numbers-mode`),不要用 buffer-local 那个。或者改挂到 `after-change-major-mode-hook` / `hack-local-variables-hook` 等延后到 mode 启用之后才跑的钩子上。

#### 陷阱 3:emacsclient --eval 多字符输出被吞

`emacsclient --eval` 在某些情境下会把多行 `format` / `message` 输出折叠成单行 `t` 或 `*ERROR*`,看不到具体值。

**绕路(按优先级)**:

1. **`write-region` 到文件**:`emacsclient --eval "(write-region (format \"...\" ...) nil \"/tmp/out\")"`,然后 `cat` 文件
2. **读 `*Messages*` buffer**:`emacsclient --eval "(prin1 (with-current-buffer (get-buffer \"*Messages*\") (buffer-string)))"`
3. **避免 `t` 结尾**:表达式最后别放 `t`,让 elisp 返回值本身就是字符串

**根因**: emacsclient 走 server 协议传回 `t` 当"成功"标识,把多字符输出收成单行。具体触发条件不固定(daemon 版本、message 长度、是否触发 echo-area 截断),所以**最稳就是写文件**。

#### 陷阱 4:org src block native fontification 触发 scheme-mode font-lock 死循环

Emacs 31 的 `scheme-mode` 在处理 quasiquote/unquote（反引号 `` ` `` 与逗号 `,`）语法时会触发 **font-lock 死循环**,导致 jit-lock 挂死 + buffer 渲染中断 + 行号消失。Guix 的 `config.org` 大量使用 scheme quasiquote,`org-src-fontify-natively t` 会把 scheme 块送进 native fontification,必然卡死。

**错误特征**:

- _Messages_ 里出现 `Native code fontification error in #<buffer config.org> at pos<NNNNN>`
- `backtrace-to-string(nil)` 堆栈
- 触发时机:`org-cycle` 展开或滚动到含 scheme quasiquote 的 src block 时
- 连带症状:行号列消失(`display-line-numbers-mode` 仍为 t,但渲染被 jit-lock 错误拖垮)

**正确修复**: 在 `org-src-font-lock-fontify-block` 的 `:around` advice 里,对 `lang="scheme"` 直接 `return nil`,让 org fallback 到基础高亮。不要用 `cl-letf` stub `treesit-ready-p`/`treesit-available-p`——本案中 `major-mode-remap-alist` 对 scheme 是 nil,tree-sitter 根本不在事故链上。

**防护**: org 模式下的调试,优先用 `find-file-noselect` + `font-lock-ensure`(不走 display/jit-lock 触发链)隔离问题。如果 `find-file-noselect` 正常而 `find-file` 卡死,排查 `scheme-mode-hook` 里的 Arei/geiser 等扩展是否也在卡。

---

## 2. worker 委派协议(并行委派 + 范围控制)

### 委派前

```bash
# 1. 记录 baseline(redirect 保存)
git status --short > /tmp/baseline-<task>.txt

# 2. tasks[].cwd 显式传项目根绝对路径
# 3. 任务描述里所有文件路径用绝对路径(双保险)
```

### 委派后

```bash
# 1. 拿变更文件列表
diff <(git status --short) /tmp/baseline-<task>.txt

# 2. 二次验证改动范围
git diff --stat <限定路径>
git diff <路径> | grep -E '^\+' | head -50   # 关注新增行

# 3. 并行委派 N worker 用 path-scoped:
git diff --name-only -- ':!<task-path>'  # 空 = 零越权
```

### 撤回(绝不能批量)

- ✅ 逐个 `git checkout HEAD -- <file>` 对 task 范围**外**的文件
- ❌ `git checkout HEAD -- .`(W1 案例: 误删用户合法改动,不可逆)
- ❌ `rm -rf` / `git clean -fd`(可能误删用户未跟踪内容)

**根因**: working tree 中未 `git add` 过的改动 git 不备份(无 dangling object);任务开始前 M 状态的文件可能是用户之前未 commit 的合法改动。F025 + KB 20260617-000549。

**worker 越权高发三类型**:

1. 顺手改 home-config.org 加无关包
2. AGENTS.md 加死引用
3. 修一个文件时改坏同目录相邻文件

---

## 3. 多行编辑安全(edit 工具 chain-delete 防护)

### 跨 3+ 行精确修改

**优先** `python3 + str.replace()` 或 `git show + heredoc`,**不用** edit 工具的 range replace。

```python
# 优选范式
python3 << 'EOF'
path = "/path/to/file.el"
old = """<精确旧块>"""
new = """<新块>"""
with open(path) as f: content = f.read()
content = content.replace(old, new, 1)
with open(path, 'w') as f: f.write(content)
EOF
```

**根因**: edit 工具的 `LINE#HASH` 每次 read 都重生成(字母变化),多次 read/edit 循环频繁触发 `E_STALE_ANCHOR`;range replace 缺 dry-run,错删 anchor 范围外相邻行(chain-delete)不可逆,只能 `git checkout HEAD -- <file>` 单文件撤回。F026 + KB 20260618-191010。

**适用**: `.el` / `.scm` / `.org` 等任何代码文件的多行编辑。

**单行 / 2 行**编辑仍可用 edit 工具(节省时间)。

---

## 4. Guix service 排查(从 shepherd 角度)

### 黄金法则

> **不要**手动跑 `~/activate` 这类 service command(会绕过 service 上下文、破坏用户环境);从 shepherd service 角度排查。

### 标准排查 4 步

```bash
# 1. 看 service 状态 + cached PID + command 字段
pkexec herd status <service>
# 2. 确认进程是否真活着
pkexec cat /proc/<pid>/cmdline
pkexec ls -la /proc/<pid>/cwd
# 3. 拉取完整 service history(含 on-change gexp 错误 + backtrace)
pkexec grep "<service-keyword>" /var/log/messages
# 4. 修根因后 pkexec herd start <service> 触发重跑
```

### 典型陷阱

- **stow 死链残留**:`find ~ -xtype l` 清理 → `create-symlinks` 阶段遍历 .local/share 时 stat 报 ENOENT → activate 异常退出 → `.guix-home` 链接未切换。KB 20260613-040133。
- **shepherd cached PID 不可信**:`make-forkexec-constructor` 不 wait 子进程,子进程死后 shepherd 仍缓存 PID。真相只在 `/var/log/messages` + `/proc/<pid>`。
- **home-shepherd fork 不继承 WAYLAND_DISPLAY**: 调 wayland 客户端(`noctalia msg` / `makoctl`)需在 hook 脚本顶部动态探测 `$XDG_RUNTIME_DIR/wayland-*` 设 `WAYLAND_DISPLAY`。KB 20260619-195519 + F028。
- **shepherd service command 禁止带 `--replace`**: 任何 `make-forkexec-constructor` 命令里的 `--replace`(典型来源:hermes gateway CLI 的 self-replace flag)会触发**自踢循环**——新进程启动 → 给前任发 SIGTERM → 前任退出码非 0 → shepherd `respawn? #t` 视为失败 → 再重启 → 又踢自己。日志特征是 `Received SIGTERM as a planned --replace takeover — exiting cleanly` 与 `Another gateway instance is already running (PID XXXX)` 交替出现。修复:从 service 定义里删 `--replace`,详情见 §4.5 + `references/hermes-gateway-shepherd-service.md`。
- **NetworkManager 共享热点 DHCP 失败（dnsmasq 端口冲突）**: 手机连上热点但卡在"获取 IP 地址"——日志显示 `dnsmasq: failed to create listening socket for 10.42.0.1: Address already in use`。根因是 mihomo（或其他 DNS 代理）的 `dns.listen: 0.0.0.0:53` 占用了所有接口的 53 端口，NM 启动的 dnsmasq 无法绑定热点接口 DNS 端口而退出（exit code 2），DHCP 服务随之缺失。修复:把 DNS 代理的 listen 改为 `127.0.0.1:53`（劫持规则不受影响），重启代理 + 重新激活热点。完整诊断 + 修复流程见 `references/nm-hotspot-dnsmasq-port-conflict.md`。

### 4.4 改 shepherd 服务定义后的完整重启流程(blue home 不够)

`blue home` 部署新配置后,**在跑的 home-shepherd 不会自动重启**——它只对 on-change gexp 求值。要让 service 定义(比如 `start` 命令、`requirement`、`respawn?`)真正生效:

```bash
# 1) blue home(部署新 .scm 到 store)
cd ~/Projects/Config/Guix-configs && blue home

# 2) herd restart(让现有 shepherd 重新加载服务定义并 respawn)
herd restart <service-name>

# 3) 验证 command 字段已更新
herd status <service-name>   # 看 "命令:" 行是不是新值
```

### 4.5 多个 home-shepherd 并存时的清理范式

`herd restart` 只重启当前连接的 shepherd。**如果系统里有两个 home-shepherd 实例并存**(典型:旧 shepherd 还活着,新 `blue home` 启动了一个新的),`herd restart` 只影响新那个;旧 shepherd 的服务还在用旧配置。诊断方法:

```bash
pgrep -af "shepherd-for-home"   # 看到多个 PID = 并存
```

清理步骤:

```bash
# 1) 找出"旧的"那个(可能是 PID 较小的、或吃了旧 config hash 的)
ps -o pid,etime,cmd -p $(pgrep -f "shepherd-for-home")

# 2) kill 旧的(直接 SIGTERM,shepherd 会清理其 fork 的服务进程)
kill <old-shepherd-pid>

# 3) 验证只剩一个
pgrep -af "shepherd-for-home"   # 应只剩 1 个 PID

# 4) 此时旧服务若还占着端口/资源(典型:gateway 失败重启循环报 Another instance PID),再 kill 那个孤儿服务进程
ps aux | grep "<service-cmd>" | grep -v grep
kill <orphan-pid>

# 5) 让新 shepherd respawn 新服务
herd restart <service-name>
```

**为什么会并存**:`blue home` 部署新 .scm 后,如果 home-shepherd 守护进程没重启,Guix 不会主动终止它(它不是 `home-shepherd-service` 自身)。新 daemon 通常由用户手动起 / 由 PAM session 起;旧 daemon 继续持有旧服务定义,直到 logout / 重启才走。

**根因机制**:home-shepherd 没有 cgroup 隔离,两个 daemon 完全平等,各自维护自己的服务表。

---

## 5. AGENTS.md 翻新(blue structor 范式)

**用户偏好(2026-06-21)**: "路径不应该是手写的,应该全部依靠工具生成"。AGENTS.md 里的目录树段**必须**用 `blue structor` 自动维护,**禁止**手写。

### 5.1 翻新判断

- `grep -L "structor:begin" $(find . -name "AGENTS.md" -not -path './.git/*')` → 找出所有**手写**目录树的 AGENTS.md
- `blue structor` 的 `%structor-targets` 自动扫描所有 AGENTS.md(已过滤 `/disable/`、`/tmp/`、`.blue-store/`、`.agents/`),**有 `<!-- structor:begin -->...<!-- /structor -->` 标记对才处理**

### 5.2 翻新流程(4 步)

```bash
# 1) 决定哪些 AGENTS.md 要翻新
# 排除项:emacs/.config/emacs/AGENTS.md、rime/AGENTS.md —— 这些是 git submodule 内,不要直接编辑子模块内容

# 2) 在合适位置插入标记对(参考其他已标记 AGENTS.md 的格式)
# 模板:
## 目录结构
<!-- structor:begin -->

<!-- 此树形目录由 structor 自动生成,请勿手动编辑。 -->

\\`\\`\\`
<placeholder>/
\\`\\`\\`

<!-- /structor -->

# 3) dry-run 预览
ORG_STRUCTOR_DRY=1 blue structor 2>&1 | grep -A 20 "<目标文件>"

# 4) 实际重写
blue structor 2>&1 | grep -E "(WRITE|DRY|ERROR)"
```

### 5.3 关键约束

- **`blue structor` 不**自动给没标记的 AGENTS.md 加标记 —— 必须先手插标记对(但**只**插空标记 + 最小占位,内容由 structor 重写)
- **子模块内 AGENTS.md 不要动**: `dotfiles/mutable/emacs/.config/emacs/general-config/AGENTS.md`、`dotfiles/immutable/utilities/.local/share/fcitx5/rime/` 在独立 git 仓库里
- **重复手写段要删**: 翻新后顶部"## 目录结构"会重写完整树,文件下半部分如果还有手写的小节(`.config/agents/` 段等)就重复了 —— 删旧的
- **语言风格**: structor 默认生成 `<!-- 此树形目录由 structor 自动生成,请勿手动编辑。 -->` 中文注释。已有英文注释(由前人手动写的)会被覆盖
- **AI 可以跑 `blue structor`**: 它只重写标记对之间的内容,不涉及 system reconfigure/home rebuild —— **不**受不变量 #3 限制

### 5.4 dead git submodule 清理(配套)

精简 Guix-configs 仓库时,如果 `.gitmodules` 里有**从未 init 的 submodule 条目**(`.gitmodules` 列出但 `git submodule status` 没显示),按下面清:

```bash
# 1) 验证是真的 dead(没 init)
cd ~/Projects/Config/Guix-configs
git submodule status | grep <path>  # 空 = dead

# 2) 删 .gitmodules 条目(直接编辑文件;git 没批量删命令)
# 保留真正 init 的(emacs + rime)

# 3) 删 .git/config 里的 submodule section
git config --remove-section submodule."<path>" 2>&1
# 重复每条

# 4) 清 .git/modules/<path> 残留(用 find 找空目录,不用手写路径)
find .git/modules -type d -empty -delete 2>&1

# 5) 同步更新 AGENTS.md 里的 submodule 表格 / 文档里的引用
grep -rn "<submodule-name>" --include="*.md" --include="*.scm" --include="*.org" . \
  | grep -v ".git/" | grep -v ".agents/workfile"
```

### 5.5 反模式

- ❌ **手写或 patch 目录树段** —— 用户明确反对("路径不应该是手写的")
- ❌ **`patch` 工具删 5-10 行手写树** —— 结构性差,容易出 chain-delete 风险。用 `blue structor` 自动重写
- ❌ **改子模块内的 AGENTS.md** —— 硬约束"不要直接编辑子模块内容"
- ❌ **跑 `blue structor` 但不插标记对** —— 没标记的文件被静默跳过,看起来无效果

---

## 6. GUI 应用环境变量注入(niri / greetd / fcitx 三件套)

> 当**双击 .desktop 文件**启动的 GUI 应用缺环境变量时(IME 没弹 / Electron 应用不能打字 / Qt 应用字体不对 / proxy 没生效),改的不是各个 .desktop 文件,而是 niri 的"环境注入三件套"。改一次覆盖所有 GUI 应用。

### 6.1 黄金法则

> **任何 GUI 应用的环境变量问题,先问:** "它启动时,谁在喂它环境?"

在 Guix + niri + greetd 这套非 systemd 启动链里,GUI 应用的变量来源有且仅有:

1. **niri config.kdl 的 `environment { ... }` 块** —— niri 给它起的所有子进程注入环境(最权威,一次改覆盖所有)
2. **`spawn-sh-at-startup "dbus-update-activation-environment ..."`** —— 喂 dbus activation 环境,影响通过 dbus 启动的服务
3. **`spawn-sh-at-startup "herd set-environment ..."`** —— 喂 Guix shepherd 起的服务

**不在**这套链里的:

- `~/.profile` / `~/.bashrc` —— 只影响 login shell,不影响 GUI 应用
- `~/.config/environment.d/*.conf` —— **Guix 不用 systemd,所以这条几乎不起作用**;user session manager 不会读它
- `systemctl --user show-environment` —— 同上,systemd --user 没起就查不到任何东西
- `home-manager` 的 `i18n.inputModule.type` / `sessionVariables` —— 在 `source/nix/` 那条独立链里,跟 Guix Home 不互通(根 AGENTS.md 写明)

### 6.2 标准做法(修一次覆盖所有 GUI 应用)

改 `dotfiles/immutable/desktop/.config/niri/config.kdl`,三处一起改:

```kdl
environment {
  XDG_CURRENT_DESKTOP "niri"
  // 这一块加 GUI 应用需要的全局环境变量
  GTK_IM_MODULE "fcitx"
  QT_IM_MODULE "fcitx"
  XMODIFIERS "@im=fcitx"
  SDL_IM_MODULE "fcitx"
  GLFW_IM_MODULE "ibus"
}

spawn-sh-at-startup "herd set-environment graphical-session DISPLAY=$DISPLAY WAYLAND_DISPLAY=$WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=$XDG_CURRENT_DESKTOP XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR XDG_SESSION_TYPE=$XDG_SESSION_TYPE NIRI_SOCKET=$NIRI_SOCKET GTK_IM_MODULE=$GTK_IM_MODULE QT_IM_MODULE=$QT_IM_MODULE XMODIFIERS=$XMODIFIERS SDL_IM_MODULE=$SDL_IM_MODULE GLFW_IM_MODULE=$GLFW_IM_MODULE"

spawn-sh-at-startup "dbus-update-activation-environment WAYLAND_DISPLAY DISPLAY XDG_CURRENT_DESKTOP GTK_IM_MODULE QT_IM_MODULE XMODIFIERS SDL_IM_MODULE GLFW_IM_MODULE"
```

注意 `$VAR` 的写法 —— niri 自己的环境里没有 GTK_IM_MODULE,所以这条 `spawn-sh-at-startup` 第一次跑时 `$GTK_IM_MODULE` 是空。要么 `environment` 块先于 `spawn-sh-at-startup` 求值(实际 KDL 配置顺序保证这点),要么干脆把变量值字面量写死。

**改完三件套**:

1. `blue home`(让 store 副本同步)
2. **重启 niri 会话**(不是 reload;niri 主配置不支持热重载 —— `pkill -f 'niri --session'`,greetd 会自动重启)
3. 验证: `cat /proc/$(pgrep -f <app>)/environ | tr '\0' '\n' | grep GTK_IM_MODULE`

### 6.3 常见注入变量速查

| 类别    | 变量                                                                                 | 触发场景                                                   |
| ------- | ------------------------------------------------------------------------------------ | ---------------------------------------------------------- |
| IME     | `GTK_IM_MODULE` / `QT_IM_MODULE` / `XMODIFIERS` / `SDL_IM_MODULE` / `GLFW_IM_MODULE` | 双击 .desktop 启动的 Electron/Qt/SDL/GLFW 应用没法用输入法 |
| Wayland | `WAYLAND_DISPLAY` / `XDG_RUNTIME_DIR` / `NIRI_SOCKET`                                | GUI 应用找不到 wayland socket                              |
| 显示    | `DISPLAY` / `XDG_SESSION_TYPE`                                                       | XWayland fallback / session 识别                            |
| 桌面    | `XDG_CURRENT_DESKTOP`                                                                | 应用的 desktop integration(portal 等)需要                  |
| Locale  | `LANG` / `LC_ALL` / `LANGUAGE`                                                       | GUI 应用乱码                                                |
| Proxy   | `http_proxy` / `https_proxy` / `HTTP_PROXY` / `HTTPS_PROXY`                          | Electron / Qt 应用不走终端的 proxy                         |
| 字体    | `XCURSOR_PATH` / `FONTCONFIG_PATH` / `QT_QPA_FONTDIR`                                | 自定义字体 / cursor 主题找不到                             |

### 6.4 反模式(自己踩过的坑)

- ❌ **改各个 .desktop 文件的 `Exec=` 前缀加 `env`** —— 治标;每装一个新应用都要改;而且 nix-profile 装的 .desktop 是从 `/nix/store` 软链来的,改 `~/.local/share/applications/<x>.desktop` 也只对当前用户临时生效,home-manager / nix profile rebuild 会被覆盖。**例外**: §6.7 的 Electron 版本差异场景(三件套已生效、缺 cmdline flag),`.desktop` 覆盖是正确解法
- ❌ **在 `~/.config/environment.d/` 加 `.conf`** —— Guix 不用 systemd,这条不起作用(在 NixOS / Ubuntu 上有用,在 Guix 上没用)
- ❌ **`systemctl --user import-environment` 在 niri 启动时跑** —— 假设 systemd --user 在跑;但在 Guix 默认配置下,systemd --user 不一定起,要看 `pgrep -af 'systemd --user'`。不要假设它一定在
- ❌ **改 `~/.profile` 加 export** —— 只影响 shell 进程,GUI launcher 看不到
- ❌ **`home-manager` 那条独立链的 `i18n.inputModule`** —— `source/nix/` 与 Guix 不互通;改了 home-manager 配置但你用 `blue home` 部署,不会生效

### 6.5 与本节相关的诊断命令

```bash
# niri 起的 GUI 应用的环境里有什么(以 hermes-desktop 为例)
cat /proc/$(pgrep -f hermes-desktop | head -1)/environ | tr '\0' '\n' | grep -E 'GTK_IM|QT_IM|XMODIFIERS|WAYLAND'

# 对比两端环境差异(工作 vs 不工作)
cat /proc/<pid_ok>/environ | tr '\0' '\n' | sort > /tmp/env-ok.txt
cat /proc/<pid_fail>/environ | tr '\0' '\n' | sort > /tmp/env-fail.txt
comm -23 /tmp/env-ok.txt /tmp/env-fail.txt   # 看 OK 有、FAIL 没有的

# 对比 cmdline 差异(看 Electron 有没有缺失 flag)
cat /proc/<pid>/cmdline | tr '\0' ' '

# 当前 shell 有什么(对比)
env | grep -E 'GTK_IM|QT_IM|XMODIFIERS|WAYLAND'

# niri 配置软链接是否指向最新 store
readlink ~/.config/niri/config.kdl

# fcitx5 实际在跑吗 + 看 focus 状态
pgrep -af fcitx5
fcitx5-diagnose 2>/dev/null | grep -A1 'program:'

# electron 版本探查(readlink 拿到 store 路径,再 strings 搜版本号)
readlink -f /proc/$(pgrep -f '<app>' | head -1)/exe
strings <exe-path> | grep -oP 'Chrome/\d+' | sort -u

# systemd --user 是否在跑(诊断 environment.d 是否生效)
pgrep -af 'systemd --user'
```

### 6.7 Electron 版本差异：三件套全对但仍不工作

**前提确认**: 已在 §6.2 部署三件套、`/proc/<pid>/environ` 确认所有 IME 变量存在。

如果 **环境变量齐全但特定 Electron 应用仍不工作**(fcitx5 `focus:0`)，根因可能是 **Electron 版本差异**：

| Electron 版本            | 行为                                                                                                                |
| ------------------------ | ------------------------------------------------------------------------------------------------------------------- |
| **41**（最新）           | Wayland IME 默认工作,cmdline 零 flag 也正常                                                                        |
| **37**（QQ 3.2.29 内嵌） | `--ozone-platform-hint=auto` **无法激活** text-input-v3 focus;必须 `--ozone-platform=wayland` + `UseOzonePlatform` |
| **~29–32**（老版）       | 需要 `--enable-features=UseOzonePlatform` flag,缺则协议无法激活 focus                                              |

#### 诊断流程

1. 确认环境变量已注入:`cat /proc/<pid>/environ | tr '\0' '\n' | grep -E 'NIXOS_OZONE|GTK_IM|QT_IM|XMODIFIERS'`(应全有值)
2. 查 Electron 版本:从 crashpad handler 的 `--annotation=ver=` 获取最准;或用 `readlink -f /proc/<pid>/exe` 拿二进制路径、`strings` 搜 `Electron/` 或 `Chrome/`
3. 对比 cmdline flag:`cat /proc/<pid>/cmdline | tr '\0' ' '`,看是否有 `--ozone-platform=wayland`(不是 `=auto`)和 `UseOzonePlatform` feature
4. 验证 focus 状态:`fcitx5-diagnose 2>/dev/null | grep 'program:<app>'`,`focus:0` 持续 = 协议未激活

#### 解法（按优先级）

**方案 A — Nix 层(推荐,如果应用来自 Nix)**

在 `source/nix/configuration/00-main/packages.nix` 中 override `commandLineArgs`:

```ix
(qq.override {
  commandLineArgs = "--ozone-platform=wayland --enable-features=UseOzonePlatform,WaylandWindowDecorations --enable-wayland-ime --wayland-text-input-version=3";
})
```

或用 `xdg.desktopEntries` 生成 .desktop(如 hermes.nix)。然后 `home-manager switch --flake .#Guix`。

**方案 B — Guix dotfiles .desktop 覆盖(兜底)**

在 `dotfiles/immutable/desktop/.local/share/applications/<app>.desktop` 创建覆盖,Exec 行补齐:

```
Exec=<app-wrapper-path> --ozone-platform=wayland --enable-features=UseOzonePlatform,WaylandWindowDecorations --enable-wayland-ime=true --wayland-text-input-version=3 %U
```

然后 `blue home`。此方案适用于 Nix 修复尚未生效的过渡期,或应用来自 nix profile 不受 home-manager 管理的场景。

**注意**: Nix 包的 `.desktop` wrapper 可能用自己的条件逻辑(如 QQ 的 `NIXOS_OZONE_WL` 条件仅加 `--ozone-platform-hint=auto`)。`.desktop` 覆盖的 `--ozone-platform=wayland` 会覆盖 wrapper 的 `=auto`。

#### 关键 flag 对照

| flag                                 | 作用                                 | 何时需要                                         |
| ------------------------------------ | ------------------------------------ | ------------------------------------------------ |
| `--ozone-platform=wayland`           | 强制 Wayland Ozone(非 `hint=auto`)  | Electron < 41,`auto` hint 可能不激活 text-input |
| `--enable-features=UseOzonePlatform` | 显式启用 Ozone 平台                  | Electron < 37 必需;37+ 默认启用但建议加         |
| `--enable-wayland-ime`               | 启用 Wayland IME                     | 所有 Electron 版本                               |
| `--wayland-text-input-version=3`     | 使用 text-input-v3 协议              | 配合现代 compositor(niri、sway 等)               |

详细调试流程见 `references/electron-wayland-ime-debug.md`。

### 6.8 典型场景排查清单

1. **双击 .desktop 没输入法** → §6.2 三件套 + `blue home` + 重启 niri
2. **终端能起 GUI 应用但 .desktop 起不行** → 100% 是环境变量;走 §6.5 对比两端 `/proc/<pid>/environ` 差异
3. **nix-profile 装的应用没输入法(hermes-desktop / QQ)** → 同一根因,同一解法;不要去改 nix 那条链
4. **应用能在 Chromium 系工作但 Electron 系不行** → Electron 需要 `GTK_IM_MODULE=fcitx` 而不是 `ibus`;检查 §6.3 速查表里所有 IM 变量都写了
5. **改了不生效** → 检查 `blue home` 是否跑了(store hash 是否变了) + niri 会话是否重启了(改 .kdl 不会热重载)
6. **环境变量已全、fcitx5 IC 正常但 focus:0** → §6.7 Electron 版本差异;对比工作/不工作进程的 cmdline flag + Electron 版本;可能需要 `.desktop` 覆盖补 `UseOzonePlatform`

---

## 7. GNU Stow 二轨 dotfile 部署（stow/ + blue stow）

适用场景：**频繁手改 + 需要 git 备份**的配置文件(agent context、SOUL.md、MEMORY.md、prompt 等),不想为每次小改付 `blue home` 的代价。

机制：`dotfiles/mutable/<pkg>/` 用 GNU Stow 直接建软链接到 `$HOME`,**改源即生效**。与 `dotfiles/immutable/`(Guix Home stow,源指向 store 只读副本)的双轨分工:

| 部署模型                           | 源-目标                               | 改源后           |
| ---------------------------------- | ------------------------------------- | ---------------- |
| Guix stow(`dotfiles/immutable/`)  | 源 → /gnu/store 只读副本 → $HOME 软链 | 必须 `blue home` |
| GNU Stow(`dotfiles/mutable/`)    | 源 → $HOME 软链                       | 直接生效         |

**常用命令**(`blueprint.scm` `stow-command`):

```bash
blue stow hermes                 # 从源部署
blue stow --adopt hermes         # 首次:~ 下文件移源 + 建链
blue stow --restow hermes        # 重建链
blue stow --delete hermes        # 撤销链(~ 下变回实际文件)
```

**关键陷阱**：

- 不要用 `rm` 删 ~ 下原文件 —— Hermes 硬保护。安全范式：`cp` 到源 → `mv` 原文件到 `/tmp/hermes-mv-backup/` → `blue stow hermes` → `rm -rf /tmp/hermes-mv-backup/`
- 不要让 `dotfiles/mutable/` 与 `dotfiles/immutable/` 部署同一文件(双链冲突)
- `blue structor` 扫 `dotfiles/mutable/AGENTS.md` 默认 depth=4 会截断到 `hermes/`;用 `ORG_STRUCTOR_DEPTH=6 ORG_STRUCTOR_TARGET=dotfiles/mutable/AGENTS.md blue structor`

完整协议(备份策略、md5 三方验证、实时生效测试、commit 规范、反模式清单、故障排查表)见 `references/gnu-stow-two-tier-dotfiles.md`。

---

## 8. 改 `source/config.org` system 层 service 定义的安全协议

> 适用场景：需要直接修改 `source/config.org` 的某个 `#\+NAME:` 服务块(典型：`networking-services` / `kernel-services` / `home-shepherd-services` / `basic-services`),新增 `(service ...)` 或 `(simple-service ...)`。**与 §3(多行编辑)和 §4(service 排查)互补**——本节专门覆盖「改源 → DRY_RUN」的端到端流程与五类常见踩坑。

### 8.1 标准 4 步流程(必走)

```
① cd ~/Projects/Config/Guix-configs          # 必须在仓库根
② 用 patch 工具精确改 source/config.org(§3 安全提示)
③ blue check                                # 括号平衡检查,秒级
④ GUIX_DRY_RUN=1 blue rebuild                # 完整构建,不写入系统
```

DRY_RUN 通过后才能让用户跑 `blue rebuild`(AI 禁跑,sudo 卡 CLI)。

### 8.2 五类典型坑(必看)

#### 坑 1：`patch` 工具 fuzzy match 偷偷换括号数

`patch` 用 9 种 fuzzy 策略之一匹配 `old_string`,当末尾 `)))))` 链的 `)` 数量被误判为"近似匹配"时,可能把原文 5 个 `)` 替换成 6 个,**多出 1 个**，`blue check` 立刻报 `多余 1 个右括号 (open=905 close=906)`,但 git diff 里两行看着一样。

**防护**：

- 改前用 `cat -A` 精确数,或 python：`print(line.count('('), line.count(')'))`
- `old_string` 和 `new_string` 末尾的 `)` 数量必须**字节级一致**
- 出错就 `git checkout source/config.org` 重做

#### 坑 2：凭空捏造 Guix service 字段名

`GUIX_DRY_RUN=1 blue rebuild` 报 `extraneous field initializers (regulatory-domain ...)` —— 说明你写的字段在该 service 当前 commit 的 record-type 里**不存在**。

**防护**(**动笔前先查 upstream**):

```bash
# 1) 拿当前 Guix commit
guix describe --format=channels | grep -oP 'commit "\K[^"]+'
# 典型:ecd4ab5994c4cfd02414f0b2e86125fdc25fd877

# 2) 拉对应 commit 的 service 定义文件
curl -fsSL "https://git.savannah.gnu.org/cgit/guix.git/plain/gnu/services/networking.scm?id=<commit>" > /tmp/svc.scm

# 3) 查字段定义
grep -n -A 20 "define-record-type\* <network-manager-configuration>" /tmp/svc.scm
```

实测：Guix `ecd4ab5` 的 `network-manager-configuration` **只有 7 个字段**(`network-manager` / `shepherd-requirement` / `dns` / `vpn-plugins` / `iwd?` / `extra-configuration-files` / `dnsmasq-configuration-files`),**没有** `regulatory-domain` / `wifi-scan-rand-mac-address` / `packages`。改 regulatory 得走 `simple-service 'iw-reg-cn` + `iw reg set CN`;改 wifi 行为得走 `extra-configuration-files` 注入 `NetworkManager.conf`。

#### 坑 3：`simple-service` 在 `(append ...)` 链中位置错位

DRY_RUN 报 `Wrong type argument in position 1 (expecting empty list): #<<service> type: #<service-type iw-reg-cn ...>>` —— `append` 第一个参数**不是 list 而是单个 service 对象**。

**根因**：服务块通常是 `(list (service ...) (simple-service ...))`,被 main 块的 `(services (append <<block1>> <<block2>> ...))` 处理。新加的 `simple-service` 如果漏了或多包了一层 `)`,会从 `list` 里"掉出来"被外层 `append` 误当 list 处理。

**防护**：每次新增 service / simple-service 前,**先确认它的父表达式是 `(list ...)` 还是 `(append ...)`**,再决定缩进和括号数。DRY_RUN 报 `Wrong type` / `expecting empty list` 时,第一反应是看新加的那行**是不是漏了或多包了一层 `)`**。

#### 坑 4：改 packages / services 列表时破坏既有列宽对齐

`source/config.org` 里很多 `(packages '("a" "b" "c"))` 列表被人手工对齐到固定列宽(典型：每行 33 字符长,按最长项 + 缩进对齐全列)。`patch` 工具**不会自动保持列宽**——直接 `old_string` / `new_string` 加一个短项,会让新行短一截,与同列表其他行不对齐。`blue check` 不会因为这个报错(语法上完全合法),但 git diff 看着"我加的没动结构"实则动了风格。

**防护**(**动笔前先看 baseline 周围风格**):

```bash
# 1) 改前看周围 5 行的对齐基线
sed -n '<改点行-2>,<改点行+2>p' source/config.org | cat -A

# 2) 如果是列宽对齐模式(如所有项缩进到 col 33)：
#    new_string 也要补足空格到一致列宽,不要"刚好引号结束就换行"
```

**典型案例**：wireplumber 配置那次,会话里 patch 加 `"wireplumber"` 到 packages 列表时,直接复用了原 `old_string` 但没补缩进,diff 里只看到 +1 行字面值,**实际破坏了"utilities"那行的右括号位置**(从 33 字符宽度变成 27 字符宽度),违反仓库 style 约定。

**反例对照**(同样内容,两种风格)：

```scheme
;; ❌ 不对齐(直接 new_string 缩到 27 字符)
(packages '("agents"
           "desktop"
           "utilities"
           "wireplumber"      ; 短一截
           "noctalia-suite")))

;; ✅ 对齐(new_string 也补足到 col 33)
(packages '("agents"
            "desktop"
            "system"
            "terminal"
            "utilities"
            "wireplumber"      ; 跟 "noctalia-suite" 对齐
            "noctalia-suite")))
```

#### 坑 5b：改 packages/services 列表时把单个 `append` 拆成两个 append（paren 失衡）

本会话实战（2026-07-07）：给 ISO 的 `live-installation-os` 加 labwc 时，patch 把原
`(append (specifications->packages '(...)) (operating-system-packages %live-base-os))`
在中间断开、另起一个 `(append (list labwc-wayland-session) (operating-system-packages %live-base-os))`。
结果第一个 append 只剩一个参数且**缺闭合括号**，`blue check` 报 `多余 1 个左括号 (open=116 close=115)`。

**防护**：
- 新增包/服务项时，**并进去同一个 append**，不要新开第二个 append（见 §10.6 (c)）。
- patch 的 `old_string` 必须覆盖**完整的**受影响行——本会话还顺带误删了相邻的 `"network-manager-applet"`（第二个 patch 的 old_string 没包含它）。写多个兄弟项的列表时，old_string 要把整段同列表行都包进去，不要为"精准"漏掉兄弟项。
- 出错先 `git checkout source/config.org` 重做；不要去动 `channel.lock` / `information.scm`。

#### 坑 5c：lightdm 自动登录必须配 user-session，否则停在 greeter

`(autologin-user "live")` 单独存在时，lightdm 自动登录后不知道进哪个桌面，**停在 greeter 等选 session**，
看起来像"没自动登录"。修复：补 `(user-session "xfce")`（值 = `share/xsessions/<name>.desktop` 去扩展名）。
完整字段表 + labwc Wayland session 注入法见 `references/iso-lightdm-labwc-wayland.md`（§10.6）。

#### 坑 5：`blue check` 报"括号不平衡"不一定是真括号错——可能是上游错误 cascade

`blue check` 报 `[ERROR] 多余 1 个右括号 (open=904 close=905)` 时,第一反应不一定是去 source/config.org 数括号。**这可能是更早阶段的错误(如 `wrong-number-of-args` 在 `(include "./channel.lock")` 阶段)cascade 下来,让括号计数器拿到不完整的输入导致偏差**。

**根因识别套路**：

```bash
# 1) 抓原始 Guile 报错(不仅是 blue 的"Build failed"摘要)
blue check 2>&1 | head -10

# 2) 看有没有 wrong-number-of-args / unbound-variable / Wrong type 这些
#    早于"括号"出现的错误

# 3) git stash 你的改动,单独跑一次 baseline blue check：
git stash push -m "verify-baseline" -- source/config.org
blue check 2>&1 | head -5
git stash pop   # baseline 报错 = 跟你的 patch 无关,别去动 channel.lock / information.scm
```

**典型误判路径**：看到 `open=904 close=905` → 以为自己刚加的某行多写了 `)` → 回滚 patch → 验证还是 -1 → 浪费时间。**用 git stash 30 秒就能排除**。

**反模式**：

- ❌ 看到括号错误就回滚最近 patch(可能是无关上游错误)
- ❌ 顺手去改 `source/channel.lock`(AGENTS.md 明确禁手动编辑,由 `blue update` 生成)
- ❌ 顺手去改 `source/information.scm` 的 `(include "./channel.lock")`(同上,不要碰加载机制)

正确做法：**先 stash 验证 baseline 是不是真有错**,如果 baseline 也有——是另一个独立 issue,跟当前任务**完全无关**,**不要让当前任务的部署卡在 pre-existing 问题上**。可以把 baseline 错误作为"另外发现的 issue"汇报给用户,但不要为此拖住当前任务进度。

### 8.3 字段引用小抄

| 想用                            | 来自                           | 已 use-modules?                 |
| ------------------------------- | ------------------------------ | ------------------------------- |
| `network-manager-service-type`  | `(gnu services)` re-export     | ✅                              |
| `network-manager-configuration` | `(gnu services networking)`    | ✅(7 字段,见上)                |
| `dnsmasq-service-type`          | `(gnu services dns)` re-export | ✅                              |
| `dnsmasq`(包)                  | `(gnu packages dns)`           | ❌ 需手动加 use-package-modules |
| `iw`(包)                       | `(gnu packages linux)`         | ✅ `linux`                      |

### 8.4 DRY_RUN 报错 → 排查速查表

| 错误特征                                           | 坑位                              | 修复                                      |
| -------------------------------------------------- | --------------------------------- | ----------------------------------------- |
| `[ERROR] 多余 N 个右括号`                          | §8.2 坑 1                         | git checkout 重做 patch                   |
| `extraneous field initializers (...)`              | §8.2 坑 2                         | 拉 upstream 查字段定义                    |
| `Wrong type argument ... expecting empty list`     | §8.2 坑 3                         | 检查新加 service 是否漏括号               |
| `列宽不一致 / 缩进跳格`                            | §8.2 坑 4                         | 看 baseline 周围列宽,补足到一致           |
| `blue check cascade (括号 / wrong-number-of-args)` | §8.2 坑 5                         | git stash 验证 baseline;别动 channel.lock |
| `unbound variable: <name>`                         | use-modules 没引                  | 加对应模块                                |
| `Symbol's value as variable is void: replaced`     | `blue block-replace` 工具自身 bug | 不用 block-replace,直接 patch            |

完整错误 transcript 和字段引用小抄见 `references/config-org-modify-safely.md`。

---

## 9. 系统服务 user-level 兜底配置(wireplumber / 之类 Lua 钩子范式)

> 适用场景：**用户态 daemon**(wireplumber / swayidle / gammastep / 各类 systemd --user 服务)的行为不符合预期,而 service 本身的 Guix 配置没有这个开关。需要在 `~/.config/<daemon>/` 下注入 user-level 配置或脚本,但 daemon 默认配置目录**在系统层(`/etc` 或 `/gnu/store`)**,用户态 `~/.config/<daemon>/` 不存在——直接放不会被加载。

### 9.1 典型症状

WirePlumber 案例(2026-06-26 实战)：默认输出 sink 总是 MUTED 状态。诊断：

```bash
wpctl status
# *   82. sof-hda-dsp Speaker                 [vol: 0.69 MUTED]
# 这时已经用 wpctl set-mute 82 0 临时解开,验证声音有了
# 然后看根因:~/.config/wireplumber/ 不存在(daemon 在用系统默认)
ls -la ~/.config/wireplumber/ 2>&1  # 没有该目录
```

### 9.2 根因分类(先判定再选路径)

| 根因分类                                  | 表现                                                               | 兜底路径                                                           |
| ----------------------------------------- | ------------------------------------------------------------------ | ------------------------------------------------------------------ |
| **A. daemon 自带"自动"行为被误触发**      | 某条件触发后 sink 状态被改 + 持久化                                | 配置层关闭那个自动行为(`*.conf` / `*.d/` 段)                     |
| **B. state 恢复时把上次的错误状态读回来** | 状态文件(如 `~/.local/state/<daemon>/`)里 `mute:true` 反复被回放 | 行为层 hook 强制覆盖(Lua / 脚本)                                 |
| **C. 启动顺序问题**                       | 某 service 启动比 daemon 早,配置没被读到                          | 行为层加 on-ready hook                                             |
| **D. 完全是上游 bug**                     | 等等                                                               | 工作量大于 value 时,**接受现状 + 写 workaround 脚本**,不跟上游斗 |

wireplumber 案例是 A+B 混合,**配置层 + 行为层双管齐下**。

### 9.3 配置层 + 行为层双管齐下范式(wireplumber 实战可复用)

**A. 仓库内建包**

```
dotfiles/immutable/system/
└── .config/
    └── wireplumber/
        ├── wireplumber.conf.d/
        │   └── 50-disable-automute.conf        # 配置层
        └── scripts/
            └── 40-alsa/                        # 目录名前缀控制加载顺序
                └── 40-force-unmute.lua          # 行为层
```

`AGENTS.md`(含 `<!-- structor:begin -->...<!-- /structor -->` 标记对,给 `blue structor` 重写)一并建好。

**B. `source/config.org` `dotfile-services` 块加包名到 packages 列表**

```scheme
(packages '("agents" "desktop" "system" "terminal" "utilities"
            "wireplumber"          ; ← 新加,跟其他项保持 col 对齐(见 §8.2 坑 4)
            "noctalia-suite"))
```

**C. wireplumber.conf.d 关闭自带自动行为**

`wireplumber.conf` 语法(GKeyFile 风格,**没有逗号**):

```ini
wireplumber.profiles = {
    main = {
        wireplumber.settings = {
            ["device.routes.mute-on-alsa-playback-removed"] = false
            ["device.routes.mute-on-bluetooth-playback-removed"] = false
        }
    }
}
```

**D. scripts/ 行为层兜底 Lua 脚本**

wireplumber 0.5.x API：监听 `node-state-changed` 事件,filter `device.api=alsa` + `media.class matches Audio/Sink` + `event.subject.new-state=running` → 拿到 `device.id` + `card.profile.device` → 遍历 device 的 Route 参数 → 把对应 route `mute = false` 写回去。

关键 hook 模板:

```lua
unmute_hook = SimpleEventHook {
  name = "force-unmute/alsa-sink-ready",
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "node-state-changed" },
      Constraint { "media.class", "matches", "Audio/Sink" },
      Constraint { "device.api", "=", "alsa" },
    },
  },
  execute = function (event)
    local node = event:get_subject ()
    if event:get_properties ()["event.subject.new-state"] ~= "running" then return end
    -- 拿 device_id + cpd,遍历 Route 把 mute = false
    ...
  end
}
unmute_hook:register ()
```

**E. 加载顺序:目录名前缀数字控制**

- `40-alsa/` 在系统自带的 `50-alsa/` 之前注册 hook
- 同 prefix 内按字典序加载
- 这条对所有"用户态脚本要早于系统脚本注册 hook"的场景通用

### 9.4 部署与验证

```bash
# 1) blue home(必须在仓库根,见 §1 ⚠)
cd ~/Projects/Config/Guix-configs && blue home

# 2) 验证部署到位
ls -la ~/.config/wireplumber/   # 应存在(原本是空/不存在的)
ls -la ~/.config/wireplumber/scripts/40-alsa/

# 3) 重启 daemon 让配置生效
systemctl --user restart wireplumber
# 失败时试试直接 kill:pkill -f wireplumber,然后 dbus 拉起新实例

# 4) 验证行为
wpctl status    # 看 sink 是否还 MUTED
```

### 9.5 兜底防线(**关键**)

如果 `blue home` 因为 §8.2 坑 5(上游错误 cascade)走不通：

- **不要**手改 `source/channel.lock` / `source/information.scm`
- **可以**手动 stow 验证效果(`stow --dir=dotfiles/enable --target=$HOME --no-folding wireplumber`)—— 临时验证后**回滚**手动 symlink,等 `blue home` 修好再统一部署
- 把 `channel.lock` 错误作为独立 issue 汇报给用户,**不要**让它卡住当前任务

### 9.6 反模式

- ❌ **写 `~/.config/wireplumber/...` 直接编辑(不走 stow)**——这文件会被 `blue home` 的 store 副本覆盖或冲突
- ❌ **只写配置层不写行为层**——wireplumber 这种 daemon 行为层兜底是必须的,配置层只能关 setting
- ❌ **只写行为层不写配置层**——下次 daemon 升级可能默认开启 automute,行为层永远在救火
- ❌ **把脚本放在 `scripts/` 顶层(不分子目录)**——失去加载顺序控制,跟系统 `50-alsa/*` 撞 race condition
- ❌ **在 Lua 脚本里 `print` 调试**——wireplumber 走 journal/log topic,**用 `log:info(device, "...")`** 才有 trace

---

## 10. 需求澄清顺序(用户偏好,2026-07-06)

> **任何"为仓库加新能力 / 新管线 / 新变体"的任务,开工前先问"你想要哪种 X",再列技术可能性。**

### 10.1 反模式:以工具可能性当目标

看到上游仓库(Testament)或文档里有 `minimal` / `niri` 两个现成变体,**直接默认沿用其中一个** —— 这是惰性,不是判断。**正确做法**:

1. **先问用户**:你想做什么用?想要哪个桌面/哪个形态?
2. **再列技术可能性**:基于用户的回答,去 Guix 手册 / Guix 仓库 / 上游频道里找现成 service-type
3. **最后给选项 + 默认**:clarify 给 3-4 个候选,每个候选附"现成度"和"工作量"

### 10.2 实证案例(ISO 移植,2026-07-06)

- ❌ 默认选 `minimal`("先做最简单的")—— 用户要的是带桌面
- ❌ 默认选 `niri`("Testament 有现成的")—— 用户没装过 niri,不熟
- ✅ 应该问:"你想要哪种桌面?XFCE / KDE / GNOME / MATE?" 给候选 + 工作量预估

### 10.3 模块归属陷阱(与 §8.2 坑 2 同套路)

§8.2 坑 2("凭空捏造 Guix service 字段名")说的是字段级陷阱。**类比到服务类型级**:

- 错把 `(gnu services xorg)` 当成"唯一桌面服务模块" → 漏掉 `xfce-desktop-service-type` / `gnome-desktop-service-type` / `plasma-desktop-service-type`
- 这些 service-type 都在 `(gnu services desktop)` 模块(见 Guix 1.5 手册 Desktop Services 节)
- 它们**不只是包装包**,还自动配齐 polkit / udisks / 权限规则

**防护**(动笔前先查 upstream,跟 §8.2 坑 2 同套路):

```bash
# 1) 拿当前 Guix commit
guix describe --format=channels | grep -A1 "name 'guix'" | grep commit | head -1

# 2) 用本地 repl 枚举"我要的 service-type 在哪个模块"
guix time-machine -C ~/Projects/Config/Guix-configs/source/channel.lock \
  -- repl <<'EOF'
(use-modules (gnu services desktop) (gnu services xorg) (gnu services))
;; 验证你以为是 xorg 模块的 service-type 是不是真的在 xorg 模块
(format #t "xfce in xorg: ~a / in desktop: ~a~%"
  (module-variable (resolve-module '(gnu services xorg)) 'xfce-desktop-service-type)
  (module-variable (resolve-module '(gnu services desktop)) 'xfce-desktop-service-type))
EOF
```

输出 `#<variable ... value: #<service-type xfce-desktop ...>>` 才算确认。**不要相信 `defined?` 的布尔返回**(它对 `bound vs unbound` 判断不靠谱)。

### 10.4 文档交接习惯(用户偏好 2026-07-06,**对 agent 的硬约束**)

> **核心规则**: 用户说 "不要动手" / "先好好细化文档" / "我后续让其他 agent 接手" —— **立刻停手,不再做任何代码改动**,只产出完整方案文档。这是用户偏好,**不是建议**。
>
> 用户原话: "不要动手！先好好细化一下文档,我后续让其他 agent 接手进行工作"。

执行细节:

如果用户说"让其他 agent 接手",**立刻停手**——不再做任何代码改动,只产出:

1. 一份**完整方案文档**(写到 `docs/<topic>.md`),包含 §0 决策记录 + §接手必读 + §1-N 实施步骤 + 验收清单
2. 决策记录的每条都要可追溯("为什么选 X 不选 Y"、"用户 YYYY-MM-DD 拍板")
3. 接手 agent 直接照文档干就行,**不需要再回头问**
4. 顺手把"接手 agent 必读"路径表塞进 SKILL.md 或 reference(让接手 agent 一加载 skill 就看到文档位置)

反模式:
- ❌ 边细化文档边写代码 —— 用户没让你写
- ❌ 文档只写到"思路"层,没到"完整代码 + 实施步骤" —— 接手 agent 还得重新调研
- ❌ 决策不写理由 —— 接手 agent 不知道为啥这么选
- ❌ 自己默认选变体/工具 —— 见 §10.1 "以工具可能性当目标"

### 10.5 ISO 移植相关参考

完整 ISO 移植方案(1986 行 / v0.5,§接手必读 + §0~§15)见 `~/Projects/Config/Guix-configs/docs/iso-build.md`。**接手 agent 必读路径**:

- **§接手必读**(第一屏) → 阅读路径 + 7 条工作纪律 + 30 秒 checklist
- §0 决策记录 → XFCE 首选 / jeans- 前缀 / live user 留空密码 / nonguix 频道自动配 / DM=slim
- §9.0 子文档索引 → 5 文件详细说明(脚本 + 配置 + 蓝图)
- §9.4.3 主体代码块 + §9.4.3.1 逐行解释 → 完整可粘贴的 `live-installation-os` 块(XFCE + slim + nonguix)
- §9.5.1 + §9.5.1.1 + §9.5.2 + §9.5.2.1 → build-iso-command 完整可粘贴 + 逐行解释
- §11 双维度诊断(症状 + 错误码) + §11.5 接手 agent 边界表
- §12 验收清单(19 项 + [A/U/R] 标签 + 期望输出样板 + 打假绿勾反模式)
- §15 维护纪律 + 版本表

ISO 移植沉淀详细复盘见 `references/iso-build-handoff.md`(本次会话沉淀,v0.5 已同步更新)。

### 10.6 ISO 里加 lightdm 自动登录 + Wayland session（labwc，2026-07-07 实战）

> 完整字段验证 + synthetic package 模板 + 改 packages 段的两个真实坑见 `references/iso-lightdm-labwc-wayland.md`。

- **先定位 tangle 目标**：`live-installation-os` 走 `tmp/live-iso.scm`（ISO）；主机桌面是另一套独立配置，不要混改。
- **lightdm autologin**：`lightdm-seat-configuration` 写了 `(autologin-user "live")` 还**必须**加 `(user-session "xfce")`，否则 autologin 后停在 greeter 等选 session（看着像没自动登录）。字段名对照锁定版 `guix 9e068cc` 的 `gnu/services/lightdm.scm`（`define-configuration` 在 :263）。
- **ISO 加 Wayland session（labwc）**：Guix 没有 `labwc-desktop-service-type`。**推荐做法 = Fedora `xfce4-session-wayland-session` 的三件套**（让 XFCE 跑在 labwc/Wayland 上，最贴合"xfce + labwc 获得更好 wayland 支持"）：
  1. 解包研究 Fedora RPM（`bsdtar -xf *.rpm`，无 `rpm` 命令时用 libarchive 的 `bsdtar`），得到三文件：`xfce-wayland.desktop`（`Exec=startxfce4 --wayland`）/`labwc-rc.xml`/`labwc-environment`。
  2. 造一个 synthetic package（`trivial-build-system`）把这三件套写进 `share/wayland-sessions/xfce-wayland.desktop` + `share/xfce4/labwc/{labwc-rc.xml,labwc-environment}`。labwc 包本身不提供这些文件。
  3. 装 `"labwc"` + `"xwayland"`（labwc 0.20 默认自动拉起 Xwayland，X11 app 在 wayland 下仍可用）。
  4. 把 synthetic 包并进去**同一个** `(append ...)`（不要新开 append，见 §8.2 坑 5b）。
  5. lightdm `user-session` 改成 `"xfce-wayland"` → autologin 直接进 Wayland 版 XFCE。
  - **前提已离线验证**：锁定版 `guix 9e068cc` 的 `xfce4-session` 已是 4.20.4，`startxfce4` 脚本原生支持 `--wayland`（设 `XDG_SESSION_TYPE=wayland` + `GDK_BACKEND=wayland,x11`）；`labwc` 0.20.1 包存在（`gnu/packages/wm.scm:4830`）。
  - **Fedora 版 rc 适配**：音量键 `amixer -D pulse` 在 ISO 上 pulseaudio 可能不在 → 改 `amixer sset Master`（去 `-D pulse`）。
  - **XML 属性用单引号**（`'<font name='sans'/>'`），避免 `(display "...")` 里出现 `\"` 转义，括号平衡 + 可读性都更好（见下）。
- **`blue check` 手写 multi-file synthetic package 的括号平衡坑（实战）**：`blue check` 只数真实 Scheme 结构括号（不计字符串内/注释内括号）。收尾 `))))))))` 极易数错且 `patch` fuzzy match 会偷改 `)` 数。**收敛手段 = 单调调收尾 `)` 数量 + 看 open/close 差值**，不要手算。本会话最终 6 个 `)` 平衡。完整三件套模板 + 调试路径见 `references/iso-xfce-on-labwc-fedora-approach.md`。
- #### §10.6 补遗：本次（2026-07-07）`blue build-iso` 实战暴露的两个硬坑

##### (a) `<<guix-substitutes>>` 是 `(list ...)`,services 字段必须 `append` 拍平

`live-installation-os` 的 `services` 字段最初写成：

```scheme
(services
 (cons* (service xfce-desktop-service-type)
        <<guix-substitutes>>          ; 展开后是 (list 4个 simple-service ...)
        (service lightdm-service-type ...)
        (operating-system-user-services %live-base-os)))
```

`<<guix-substitutes>>` 块本身返回 `(list ...)`,被 `cons*` 当**单个元素**塞进 services 列表 → services 里嵌了嵌套 list → guix 报：

```
tmp/live-iso.scm:225:4: 错误： 'services' field must contain a list of services
```

**修复**：把整段改成 `append` 拍平（不要 `cons*`）：

```scheme
(services
 (append
  <<guix-substitutes>>
  (list (service xfce-desktop-service-type)
        (service lightdm-service-type ...)
        (operating-system-user-services %live-base-os))))
```

即：noweb 块返回 list 时，**用 `append` 跟其他 services list 拍平**,不要用 `cons*` 直接 cons 一个 list 进去(那会变成嵌套 list)。

##### (b) `trivial-build-system` 的 builder 不导入 `(guix build utils)` → `no code for module`

`xfce-wayland-session` 这个 synthetic package 用 `trivial-build-system`,builder 里写 `(use-modules (guix build utils))` 调 `mkdir-p` / `call-with-output-file`。构建时 drv 报：

```
ice-9/boot-9.scm:3330:6: In procedure resolve-interface:
no code for module (guix build utils)
```

**根因**:`trivial-build-system` 的构建环境默认**不**把 `(guix build utils)` 模块编译进沙箱,gexp 里的 `(use-modules ...)` 找不到。

**修复**:用 `with-imported-modules` 把模块带入 gexp(它会在 gexp 展开时把该模块编译并注入构建环境)：

```scheme
(arguments
 (list #:builder
  (with-imported-modules '((guix build utils))
    #~(begin
      (use-modules (guix build utils))
      ...))))
```

`(guix gexp)` 已在 `live-modules` 导入,`with-imported-modules` 可用。完整 synthetic package 模板 + 调试路径见 `references/iso-xfce-on-labwc-fedora-approach.md`。

### 10.7 `blue build-iso` 运行范式（不需 sudo, agent 可后台直跑）

> **重要修正（用户 2026-07-07 拍板）**：`blue build-iso` **不需要 sudo**,与 `blue rebuild` 不同。Agent 可以直接后台跑它,**不要**在文档 / blueprint 里写“agent 别跑 / 建议手动执行”的警告。

**与 §关键不变量 #3 的区别**：#3 禁的是 `blue rebuild` / `guix system reconfigure` / `guix home reconfigure`(这些需 sudo 会卡 CLI)。`blue build-iso` 走 `guix time-machine ... repl ... scripts/build-image.scm`,全程用户态,**不碰系统**、**不需 sudo**。

**运行方式**（agent 直接干）：

```bash
# 后台跑（30+ 分钟,用 background=true + notify_on_complete）
cd ~/Projects/Config/Guix-configs && blue build-iso

# 只构建 xfce 变体（主目标,先验证再放量）
blue build-iso xfce
```

**调试关键**：`blue` 的 `%guix` 封装在 guix 非零退出时**只报** `命令执行失败 (256): (...)`,**吞掉** guix 的真实 backtrace。遇到 build-iso 失败,**手动复现同一条 guix 命令**抓完整报错：

```bash
cd ~/Projects/Config/Guix-configs
guix time-machine --channels=source/channel.lock -- repl -- \
  scripts/build-image.scm dist/jeans-xfce-<date>.x86_64-linux.iso \
  tmp/live-iso.scm --image-type=iso9660 2>&1 | tee /tmp/iso-xfce-build.log
```

本次（2026-07-07）实战的四个真实错误序列 + 各自修复见 `references/iso-build-debug.md`：
1. `'services' field must contain a list of services` → §10.6 (a) 的 `append` 拍平
2. `no code for module (guix build utils)` → §10.6 (b) 的 `with-imported-modules`
3. `缺少右括号`（手写 synthetic package 收尾 `)` 数错）→ §10.6 / `references/iso-xfce-on-labwc-fedora-approach.md` §4 的“调收尾 `)` 数量收敛”
4. **`多余一个类为'X'的目标服务`（X = account / pam / profile 等单实例核心服务）** → 根因 + 修复见下方「KDE Plasma 装配」段：services 字段**绝不能用 `operating-system-services`**（它会自动 append 一次 `essential-services`，导致 `system`/`pam`/`account` 注册两遍）；改用 `operating-system-user-services`，让 `operating-system` 自己补 essential 一次。这条**掩盖了前面所有括号错**——base-only 也报 account 错就是它在作怪，原 XFCE 版同样踩坑只是没真跑到 fold-services 阶段。

### 10.8 KDE Plasma 装配（2026-07-07 实战，已构建成功）

> 把 Live ISO 从 XFCE 换成 KDE Plasma 的完整装配要点 + 错误序列 + 端到端验证见 `references/iso-kde-plasma-assembly.md`。

关键差异（XFCE → KDE）：

- 桌面 service：`xfce-desktop-service-type` → `plasma-desktop-service-type`（来自 `(gnu services desktop)`）
- 显示管理器：`lightdm-service-type` → `sddm-service-type`（来自 `(gnu services sddm)`）；**plasma 不自带 DM，必须显式加 sddm**
- SDDM `auto-login-session` **必须带 `.desktop` 后缀**：`"plasma.desktop"`（lightdm 的 `user-session` 写 `"xfce"` 不带后缀 —— 两套 DM 字段约定不同）
- **必须显式加 `(service elogind-service-type)`**：installer 基座不含 elogind，SDDM 的 `display-server "x11"` 路径拉 `xorg-server` → 报 `xorg-server 需要 elogind`
- SDDM 字段对照锁定版 `gnu/services/sddm.scm` 验证：`(display-server "x11")` / `(auto-login-user "live")` / `(auto-login-session "plasma.desktop")`
- 已验证可启动产物：`dist/jeans-desktop-20260707.x86_64-linux.iso`（5.2 GB，ISO 9660 bootable）

**反模式**：
- ❌ 在 docs/iso-build.md 或 blueprint.scm 的 build-iso help 里写“agent 别跑 / 需 sudo / 建议手动” —— 用户已明确要求去掉（2026-07-07）
- ❌ 看到 `命令执行失败 (256)` 就回滚 config.org —— 先手动复现抓真实 guix 报错
- ❌ 把 `blue build-iso` 当成“需 sudo 的系统命令”而避开 —— 它不需要 sudo

**字段验证离线法**：本环境 `web_extract` 对 `guix.gnu.org` 报 "Blocked: URL targets a private or internal network address"（浏览器可开但分页找不到 `lightdm-seat-configuration`）。直接 grep 本地锁定的 guix 源码 `/gnu/store/*<commit>*/gnu/services/*.scm`（commit 来自 `source/channel.lock`），比 `curl` savannah 更稳且 commit-exact。

---

## 不变量与边界

- 本 skill **不缓存** KB 卡片全文;只缓存"反复出现的高频协议"。
- 任何工作流细节冲突 → 以 `~/Documents/Org/experiences/*/` 对应 KB 卡片为准(session_search 召回)。
- 新增协议不写本 skill,直接写 KB 卡片(人类主笔);本 skill 周期性从 KB 提取。
- 详细场景化案例见各 KB 卡片 ID(报告 .hermes-extract-report.md B 节有完整 ID 索引)。
- Emacs dotfiles 调试陷阱见 `references/emacs-org-capture-pitfalls.md`(org-capture-expand-file 不对内嵌 form 求值)。
- niri 桌面 + fcitx IME + nix-profile GUI 应用的环境变量注入实战见 `references/niri-gui-environment-injection.md`(三件套诊断、blue home + 重启 niri 会话流程、Guix 不用 systemd 的反模式)。
- hermes-desktop 启动失败诊断见 `references/hermes-desktop-diagnostics.md`(日志优先级、版本探测超时、cron 模块导入竞态、Nix flake lock 追溯、GC 检测)。
- hermes-gateway 作为 shepherd service 的 self-kick loop 诊断见 `references/hermes-gateway-shepherd-service.md`(日志模式识别、`--replace` 触发机制、清理多个并存 home-shepherd、orphan gateway 进程)。
- Electron Wayland IME 完整调试流程(QQ 案例、flag 对照表、Electron 版本速查、Nix 修复范式)见 `references/electron-wayland-ime-debug.md`。
- GNU Stow 二轨 dotfile 部署策略(`stow/` + `blue stow` 命令的完整使用、`mv`-not-`rm` 安全模式、与 Guix stow 的边界、`blue structor` depth 调整、git commit 规范)见 `references/gnu-stow-two-tier-dotfiles.md`。
- 从 git history 恢复已删除的 dotfile 到 `dotfiles/mutable/<pkg>/` 或 `dotfiles/immutable/<app>/`(过期 README 路径、删除 commit 索引、git archive 导出、多版本候选决策、gitlink 子模块跳过、用户已明确范围时的 clarify 边界)见 `references/git-restore-deleted-dotfiles.md`。
- **source/config.org system 层 service 修改安全协议**(五类坑位:patch 括号 fuzz、字段名捏造、append 链错位、列宽对齐破坏、错误 cascade 误判)见 §8 + `references/config-org-modify-safely.md`。
- **user-level daemon 兜底配置范式**(wireplumber 类、配置层 + 行为层双管齐下、加载顺序、blue home 部署失败兜底防线)见 §9。
- **需求澄清顺序**(以工具可能性当目标的反模式、模块归属陷阱、文档交接习惯)见 §10。
- **ISO 移植完整方案 + 接手协议**(XFCE 首选 / 1200 行方案文档 / 失败诊断树 / 验收清单 / 接手 agent 必读路径)见 §10.5 + `references/iso-build-handoff.md`。
- **ISO lightdm 自动登录 + labwc Wayland session 注入**(字段表 / synthetic package 模板 / append 拆分坑 / 离线查 guix 源码法)见 §10.6 + `references/iso-lightdm-labwc-wayland.md`。
- **ISO XFCE-on-labwc (Fedora 三件套落地 + `blue check` 手写 synthetic package 括号平衡调试)** 见 `references/iso-xfce-on-labwc-fedora-approach.md`(RPM 解包 / startxfce4 --wayland 机制 / 单引号 XML 属性 / 调收尾 `)` 数收敛)。
- **ISO `blue build-iso` 运行范式 + 四个真实构建错误序列**(不需 sudo / agent 可直跑 / `%guix` 吞报错需手动复现 / `append` 拍平 noweb-list / `with-imported-modules` 修 trivial-build-system 模块缺失 / `operating-system-services` 双倍注册 essential 导致 `多余一个类为'X'的目标服务`)见 §10.7 + `references/iso-build-debug.md`。
- **ISO KDE Plasma 装配**(XFCE→KDE 差异 / SDDM 字段带 `.desktop` 后缀 / elogind 必须显式加 / 完整错误序列 1-4 / 已构建成功的 `jeans-desktop-*.iso` 验证)见 §10.8 + `references/iso-kde-plasma-assembly.md`。