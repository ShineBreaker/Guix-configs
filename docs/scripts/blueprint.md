<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# blueprint.scm — blue 任务运行器（项目主入口）

`blueprint.scm`（仓库根）· 不部署（`blue` 以**当前工作目录**为项目根加载本文件）· 调用方：用户与 agent 经 `blue <命令>` 调用；单命令用户视角的用法以 `blue list` / `blue help <命令>` 为准，help 文本即接口契约

`%repo-root = (getcwd)`，全部路径常量由此派生，因此必须在仓库根运行 `blue`。本篇面向维护者。

## 结构地图

文件按「从底层到上层」分节，源码中有对应单行节标（`;;; --- §N ---`）：

| 节  | 内容                                                               |
| --- | ------------------------------------------------------------------ |
| §0  | 路径常量（`%repo-root` 及其派生绝对路径，集中于此方便整体迁移）    |
| §1  | 子进程执行：`%run` 及 guix / emacs 包装（唯一直接子进程出口）      |
| §2  | 文件与管道 I/O：原子写、shell 拼接、管道读取                       |
| §3  | 括号平衡检查：手写词法扫描 + 统一报告                              |
| §4  | 配置管线与 Org 块解析：config.org → config.scm → reconfigure       |
| §5  | 密钥扫描：`secret-scan` 的实现                                     |
| §6  | 目录树生成器：`structor` 的实现                                    |
| §7  | GNU Stow 包装：`stow` / `stow-all` 的实现                          |
| §8  | 命令定义：每条 `blue <指令>` 的实际逻辑                            |
| §9  | 入口点：`(blueprint ...)` 把 buildable / testable / 命令注册给框架 |

## 与 blue 框架的接口

`blue build` / `blue check` / `blue clean` 是 blue 框架的**内建命令**；本文件用两个类告诉它们「建什么 / 测什么」：`<org-config>`（继承 `<buildable>`）输入 `source/config.org`、输出 `tmp/config.scm`，构建动作是 ob-tangle；`<paren-check>`（继承 `<testable>`）不接 tangle，直接解析 config.org 逐块做括号检查（定位到块名），再兜底检查 `source/channel.scm` / `information.scm` / `manifest.scm`，产物 `tmp/config.scm.check` 仅是占位标记。

§9 的 `(blueprint (buildables …) (testables …) (commands …))` 完成注册；命令清单由 `%command-categories` 单表同时驱动 `blue list` 展示与注册。

## 关键不变量（改动前必读）

1. **`%run` 是唯一允许直接启动子进程的地方**。`blue --dry-run` 时它默认短路（只打印 `[预演]` 不执行）；必须真跑的传 `#:real? #t`——tangle 与括号检查就是靠它，否则 dry-run 下无法验证语法。
2. **管道读取（`%pipe->lines` / `%pipe->string`）不经 `%run`，dry-run 下也真跑**。只读用途（git status / git ls-files / grep / elisp 块导出）可直接用，`%run-elisp` 走的就是这条；有副作用的管道命令必须像 `%update-guix` 那样手动判断 `dry-build?` 并改走 `%print-preview`。
3. **所有「跑配置 / 构建」类 guix 调用必须经 `%guix-command`**（`guix time-machine --channels=<lock> --`），否则频道版本漂移、构建不可复现。刻意不走 time-machine 的只有三处：`guix repl -- tools/gen-partial.scm`（本地 scm 不属任何频道）、`%clean-generations` 与 `gc` 的 `guix gc`（store 维护，与频道无关）。
4. **tools/_.scm 与 tools/_.el 必须跑在 guix / emacs 子进程环境**：blue 自身的 Guile 进程没有 guix 模块树，直接加载频道文件会因 `openpgp-fingerprint` 宏展开报 unbound variable。`%guix-command`（`guix repl`）与 `%emacs-command`（`emacs-minimal`）是两条既定通道。
5. **`%emacs-command` 用 `env -u` 清掉五个 `EMACS*` 变量**（`EMACSLOADPATH` / `EMACSDATA` / `EMACSDOC` / `EMACSPATH` / `INSIDE_EMACS`）：blue 可能运行在用户 emacs 的环境中，这些变量会污染子进程的 load-path / data。
6. **改源 ≠ 生效**：`~/.config/<app>/` 指向 `/gnu/store` 只读副本，改完 `dotfiles/immutable/` 要 `blue home` 才同步；`dotfiles/mutable/` 是 stow 直链，改源即生效。
7. **块读写协议是跨语言契约**：`tools/block-*.el` 的 stdout 格式（`>>>` / `<<<` 记录分隔、`lang=` / `noweb=` 行、body 纯文本）由 `%extract-all-blocks` / `block-show` / `block-replace` 消费，改格式须与 [org-block-tools.md](org-block-tools.md) 同步。

除 `%run` 与管道之外，Scheme 侧的直接副作用（如 `delete-file-recursively`）也必须显式守 `dry-build?`——`clean-artifacts` 曾因此在 dry-run 下真删目录，见下方「变更」。

## 配置管线（§4）

```
config.org ──tangle──▶ tmp/config.scm ──+尾表达式+括号兜底──▶ reconfigure
```

- `tangle-config`：`%tangle-file` 经 emacs-minimal 生成 `tmp/config.scm`，调用点带 `#:real? #t`。
- `prepare-config`：追加尾表达式（`%system` / `%home`——guix 取文件最后一个表达式的值为配置对象）再整文件括号兜底。
- `apply-config`：dry-run 降级为 `guix <subsystem> build --dry-run`；真跑时 `reconfigure --allow-downgrades --fallback`，system 另加 `--no-kexec`（reconfigure 默认 kexec-load 新内核，此后 elogind 的 reboot 会走 kexec 路径并挂死电源操作）；成功后删除 `tmp/` 中间产物。`#:after` 回调（rebuild 的 `guix locate --update`）在 dry-run 下也经 `%run` 预演。
- `blue --dry-run rebuild` / `home` 真跑 tangle 与括号检查，但 build 验证本身也是 `%run` 调用——会被短路成预演打印而不真正求值。要真做语义验证须手工跑 build 命令（`source/AGENTS.md` 验证流程一节有现成写法）。
- `blue init`（装机到 /mnt）dry-run 下同样 tangle + 预演打印，并保留 `tmp/` 产物；它**没有** build --dry-run 降级（init 本身无可预演形态；应急脚本 `tools/emergency-blue.sh` 用 `build --dry-run` 模拟，见 [docs/emergency-blue.md](../emergency-blue.md)）。

## 各命令组要点（§8）

### 部署

- **rebuild**：修剪 system 世代 → `clean-artifacts` → tangle + 括号检查 → `system reconfigure` → `locate --update`。
  - **世代修剪刻意放最前**：reconfigure 耗时久，若留到其后 sudo 宽限期（15 分钟）可能已过期、二次要密码；前置后全程最多输一次。
  - **为什么修剪**：limine 每次 reconfigure 按当时全部 system 世代在 ESP 重建 UKI（CURRENT.EFI + 每旧世代一个 OLD-N.EFI，单个约 50M），世代无上限会挤爆 ESP；`%keep-system-generations = 20`。`delete-generations` 顺带的 reinstall-bootloader 对 limine 只写无人读取的 grub.cfg；多余 UKI 由下一次 reconfigure 按剩余世代重建时自然收敛。
  - 世代号单调递增、**不因清理重新编号**，`%system-generation-numbers` 枚举 `/var/guix/profiles/system-*-link` 的实号而非假设 1..N 连续；未超限则静默跳过，不起 sudo。
- **home**：`clean-artifacts` → `home reconfigure`（无需 sudo，agent 首选调试方式）。
- **build-iso**：先 tangle 让 `:tangle ../tmp/live-iso-<variant>.scm` 块出产物，再对每个变体经 `guix repl` 调 `tools/build-image.scm`。变体表 `%images`（`desktop` / `minimal`，顺序即构建顺序）仿 Testament 项目的写法，前缀为本仓库名 `jeans`；产物 `dist/jeans-<variant>-<YYYYMMDD>.<arch>.iso`。构建耗时 30+ 分钟，细节见 [docs/iso-build.md](../iso-build.md)。

### 编辑（Org 块级）

- **block-show** 抽取命名块到 `tmp/block-<名>.scm`（前两行 `lang` / `noweb` 标记，第三行起 body）并打印路径。
- **block-replace** 用 BODY-FILE 替换块并原子写回 config.org；scheme 块自动 tangle + 括号检查验证。**dry-run 直接报错**——写 config.org 与 dry-run「不写入」承诺冲突，故在入口处整体拒绝而非半途留产物。
- 块名白名单逐字符要求 `char-alphabetic?` / `char-numeric?` 或 `-`、`_`：`../` 与空白因此被拒，因为 name 既拼进输出路径、也交给 elisp 做正则匹配。
- elisp 子协议与故障排查见 [org-block-tools.md](org-block-tools.md)。

### Guix 频道（update / pull）

- **pull**：`guix time-machine --channels=channel.lock -- pull --allow-downgrades --fallback`，只认 lock、不读 `channel.scm` 的未锁定改动（顺序：改 channel.scm → `blue update` → `blue pull`）。
- **update**：`--guix` / `--nix` 两侧可独立指定；`-c NAME` 单频道刷新、`-C COMMIT` pin 到 commit、`--flake NAME` 单 input 刷新，组合约束在 `%update-scope` 的 match 里逐条给出中文报错。
- `%partial-channels-file` 生成「目标频道可变定义 + 其余按 lock pin」的临时 channels 文件（`guix repl` 跑 `tools/gen-partial.scm`，契约见 [blue-helpers.md](blue-helpers.md) §gen-partial.scm）；随后 `guix time-machine --channels=<临时文件> -- describe --format=channels` 的输出原子写回 `channel.lock`。**dry-run 分支不生成临时文件、直接返回 `%channel-scm` 原件**，只打一行 `[预演]`——让后续 dry-run 分支有可用的 channels 参数可传。
- **`%update-guix` 里的 describe 是捕获 stdout 的管道命令，不走 `%run` 短路**——dry-run 分支在此手动 `%print-preview`，是「管道不短路」不变量的典型用例。
- `%commit-lock` 只在 `git status --porcelain` 显示锁文件有变化时才 `git commit -S`：单频道/单 flake 刷新常无新版本，空提交的非零退出会让 `%run` 误报失败；dry-run 下直接视作有变化以保留 commit 预演输出。
- `%update-nix`：全量时先 `nix-channel --update` 再 `nix flake update`；单 input 用 nix 2.19+ 的参数语法。全部走 `%run`，dry-run 自动短路。

### 维护

- **clean-artifacts**：文件型目标（`__pycache__`、`*.elc`、`*.o`、`*.a`、`*.so`、`main.el`、`org-roam.db`）走 `%run` 的 `find -delete`（dry-run 自动短路）；目录型目标（stow 包内 emacs 的 `etc` / `var` 缓存）由 Scheme 直接删，必须显式守 `dry-build?`。rebuild / home 前自动先跑本命令。
- **gc**：删旧 system/home 世代 → `guix gc` → 删 ESP 上 `OLD-*.EFI`。`%run` 经 popen 直 exec、无 shell 展开，所以 `OLD-*` 要在 Guile 侧 `scandir` 收集后逐个 `sudo rm`。ESP 挂载点是 `/efi`（limine-efi-removable-bootloader 的 targets），旧命令里的 `/boot/EFI/Guix` 在这台机器上并不存在——`blue help gc` 的 synopsis 仍写旧路径，以实现为准。
- **format**：委派 `tools/doc-format.sh`，两级编排（标点 → Markdown 结构，见 [doc-format.md](doc-format.md)）。注意 `format-command` 自己走 `%run`，`blue --dry-run format` 只打印 `[预演] bash …/doc-format.sh` 而**不执行脚本**；只报告不写盘要用 `blue format --check`，它有待处理项即退出 1。
- **structor**：见下节。
- **reuse**：`reuse annotate` 批量补 SPDX 头，走 `%run`。

### structor（§6）

每个 AGENTS.md 用标记对圈定自动生成区：

```
<!-- structor:begin depth=N -->   ← depth=N 可选，覆盖默认深度
... 自动生成的树 ...
<!-- /structor -->
```

- **可见性 = git 驱动**：对每个 target 所在目录跑 `git ls-files --cached --others --exclude-standard`；条目可见 ⟺ 列表里有等于它或以 `<它>/` 为前缀的路径。根 + 嵌套 `.gitignore`、submodule gitlink 自动正确。git 管不到的两类另行硬跳：AGENTS.md（树所在文件不能列自己）与 `*.swp`（可能被 git 跟踪的交换文件）。
- 深度优先级：标记内 `depth=N` > `ORG_STRUCTOR_DEPTH` > 默认 4；`ORG_STRUCTOR_DRY=1`（或 dry-run）只打印不写。
- target 枚举扫全仓库 `AGENTS|README` .md，排除 `.git/`、`disable/`、`tmp/`、`.blue-store/`、`.agents/`；无标记的文件跳过。写回走 `%write-file-atomically`。

### Stow（§7）

- `dotfiles/mutable/` 用 GNU Stow 直链仓库源（改源即生效，无需 `blue home`），与 `dotfiles/immutable/`（Guix Home stow，store 只读副本）互补，适合频繁手改且需 git 备份的配置。
- **包身份由标记文件显式声明**：`<PKG>/.stow-package` 存在即该目录是包（`stow-all` 枚举依据）；`<PKG>/.stow-folding` 对该包 opt-in 整目录折叠。此前用「目录内含 dot 条目」启发式判包，会被分组目录里的 dot 杂物（`.gitignore` 等）误触发、也会漏掉尚未放内容的空包，故改显式声明。
- 无标记目录只可能是分组容器，下钻一层找带标记子包；`group/pkg` 名字在 `%stow-split-pkg` 把分组前缀并入 `--dir`，stow 本身永远只收一级包名（GNU Stow 不保证接受带斜杠的包名）。
- 默认 `--no-folding`（目标目录保持真实目录、逐文件软链）保护应用运行时产物（logs/、state.db 等）不污染源；`--ignore=\.stow-(folding|package)$` 始终带上，标记文件本身永不部署到 `$HOME`（多包同名标记会冲突）。

### 校验 / Nix / 帮助

- **secret-scan**：对 `dotfiles/immutable`（可改 DIR）跑 18 条凭据正则（PAT、API key、私钥头、通用 `password=` 等），命中打 `[HINT]`；默认找到即 error 供 CI 卡点，`GUIX_SECRET_SCAN_FAIL_ON_FIND=0` 降级为警告。只报 <1 MB 文件避免误报二进制/大文件；裸参数可追加正则。
- **nix / nix-init**：备用 Nix home-manager 体系（与 Guix 不互通）；`nix` 经 `nh home switch --configuration Guix` 应用，`nix-init` 直接构建 flake 的 `homeConfigurations.Guix.activationPackage` 并执行 `/tmp/hm-activation/activate`，不依赖 channel / nh / 现有 profile，版本由 flake.lock 锁定。
- **list / help**：`%command-categories` 是命令分类单一清单，同时驱动 `blue list` 展示与 §9 注册；**必须定义在全部命令之后**——quasiquote 在定义求值时刻就取各命令变量的值。

## 内部实现注记

- `%subprocess-fail!` 用 `primitive-exit` 而非 `error` / `exit`：blue 框架会给异常打整套 backtrace，而「子进程非零退出」是预期内失败，堆栈无诊断价值。`popen` 返回原始 wait status（退出码在高位），须 `status:exit-val` 解包后再交 `primitive-exit`，否则低 8 位截断后失败也报 0。
- `%write-file-atomically`：`mkstemp!` 写 `file.XXXXXX` 再 `rename` 覆盖，异常清理临时文件——config.org / channel.lock / AGENTS.md 等关键文件绝不停留在「写一半」。
- `%shell-quote` / `%shell-command`：POSIX 单引号转义（`'\''` 切断重开），拼进 shell 字符串前逐参数 quote。
- 括号检查（§3）是手写词法扫描而非 guix `read`：config.org 的块含读取器宏（unquote 等），read 报错定位差。栈式配对要求 `[`/`(` 严格同类（`[` 配 `)` 算错）；跳过字符串字面量与 `;` 注释。**字符串未闭合不会单独报错**（emergency-blue 的 awk 移植版额外覆盖此点，见 [docs/emergency-blue.md](../emergency-blue.md) §7）。
- `%check-config-blocks` 只查 `scheme` 块（fish/bash 是嵌在 scheme 字符串里的内容）；`main` 块也查——`<<ref>>` 占位本身括号平衡。失败不立即中止，让用户一次看到所有错误。
- `%pipe->string` 在非零退出时先把已捕获的 stdout 转发到 stderr 再报错——`blue block-show <不存在的块>` 因此能直接看到 elisp 的 `[ERROR] 未找到代码块`，而不是只有一行「命令执行失败」。

## 变更

- 2026-09-29 两处行为级修复：`clean-artifacts` 的目录型目标原本直接 `delete-file-recursively`，不走 `%run`，故 `blue --dry-run clean-artifacts`（连带 `--dry-run rebuild` / `home`）会真删这些目录，现改为 dry-run 下打 `[预演] 移除`；`%pipe->string` 在子进程非零退出时把已捕获 stdout 转发到 stderr，`blue block-show` / `block-list` / `describe` 等失败现在能看到脚本自己的 `[ERROR]` 诊断。
