<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# fish 自定义函数速查 — 构建派发、桌面动作、Git 签名、Java 学习工具与提示符

`dotfiles/immutable/terminal/.config/fish/functions/` · immutable → `~/.config/fish/functions/`（改后须 `blue home`） · 交互 shell 手动调用，各有同名 `completions/<name>.fish`

本篇覆盖 `functions/` 下的日常小函数。`denv`（1575 行、9 个 provider、6 个子命令）自成子系统，不并入本篇，见 [denv.md](denv.md)。

## 派发与重试

### run

按固定顺序探测当前目录的构建文件并派发，参数**全部透传不解析**：

| 探测文件              | 派发命令     |
| --------------------- | ------------ |
| `maak.scm`            | `maak $argv` |
| `blueprint.scm`       | `blue $argv` |
| `justfile`/`Justfile` | `just $argv` |

三者都不存在时错误写 **stderr** 并 `return 1`：

```
run: 当前目录下未找到 maak.scm / blueprint.scm / justfile
```

探测顺序是契约而非实现细节：本仓库根目录有 `blueprint.scm`，故 `run rebuild` 等价 `blue rebuild`。补全 `completions/run.fish` 的 `__run_complete` **复用同一套探测顺序**，按命中项转发 `complete -C "<cmd> <args>"` 让 fish 按目标命令补全——改探测顺序必须同步改补全。

### retry

最多重试 5 次；5 次仍失败时提示 `已重试 5 次失败。是否继续重试？(y/n)`，输入 `y` 把计数清零继续，**任何其它输入 `return 1`**。每次尝试执行 `eval $argv`，保留 shell 引号语义。

**sudo 保活**：`command -q sudo` 存在时在首次尝试前 fork 一个后台 fish，每 60s 跑一次 `sudo -n true` 续期票据（sudo 默认 5 min 过期），耗时重试只需输一次密码。keeper 自带判活自灭：

```bash
fish -c "while kill -0 $fish_pid 2>/dev/null; sudo -n true 2>/dev/null; sleep 60; end" &
```

成功返回与放弃重试两条路径都会 `kill` 掉 keeper。已知边角：`Ctrl-C` 强杀主 shell 会残留 keeper 进程（`jobs`/`kill` 清理）；无票据时 `sudo -n` 静默失败，不影响主流程。

## 桌面与电源

### screen-off

```bash
screen-off        # 5 秒后熄屏（默认）
screen-off 30     # 指定秒数
```

倒计时前提示 `N 秒后关闭显示器，Ctrl-C 取消`；参数多于 1 个时打用法（stderr）并 `return 1`。**`sleep` 失败时不熄屏**，并把状态原样透传给调用方——参数写错不能导致黑屏。熄屏动作是 `niri msg action power-off-monitors`，只在 niri 会话内有效。

## Git 签名

### git-resign

重签名 `<base-ref>..HEAD` 的全部提交，本质是交互式 rebase 的 `--exec` 逐提交 amend：

```bash
git rebase --exec 'git commit --amend --no-edit -S' <base-ref>
```

参数个数 ≠ 1 时打用法并 `return 1`；退出码透传 rebase 结果。成功后打印核验命令（`%G?` 显示 `G` 即签名有效）：

```bash
git log --format='%h %G? %s' $base..HEAD
```

冲突由 git 自身处理，无额外封装。

## Java 学习工具

### jdk / jbuild / jrun

```text
jdk set <version>   # 切 JDK（经 __set_jdk → guix build openjdk@<ver>）
jdk current         # 显示记录版本与 JAVA_HOME
jdk                 # 用法

jbuild <Class>      # javac -d bin src/<Class>.java（自动建 bin/）
jrun <Class>        # java -cp bin <Class>（要求 bin/<Class>.class 存在）
```

`jdk` 的持久化在 `conf.d/05-java.fish`：`__set_jdk` 校验纯数字版本号，经 `guix build openjdk@<ver>` 取 `-jdk` 结尾的 store 路径，设 `JAVA_HOME` + `fish_add_path` 后写两个记录文件。启动回放优先级固定为**缓存路径 > 记录版本 > 默认版本**：

| 变量                  | 默认 | 回放行为                     |
| --------------------- | ---- | ---------------------------- |
| `JDK_PATH_FILE`       | —    | 直接读缓存路径设 `JAVA_HOME` |
| `JDK_VERSION_FILE`    | —    | 读版本号重新构建路径         |
| `JDK_DEFAULT_VERSION` | `25` | 用默认版本构建               |

三个文件不传 `.java` / `.class` 扩展名：`jbuild Hello` 对应 `src/Hello.java`，`jrun Hello` 对应 `bin/Hello.class`。

**`jbuild`/`jrun` 的错误信息写 stdout 而非 stderr**（`jbuild`/`jrun` 的 usage 与 `Error:` 行都没有 `>&2`），补全据此展示，改写时别顺手改成 stderr。

## 提示符

### fish_prompt

上游 fish 自带 Informative 提示符的定制版：

- 普通用户两行式：`[HH:MM:SS] user@host cwd [pipestatus]` + 换行 + `> `。管道各段退出码经 `__fish_print_pipestatus` 以 `[a|b|c]` 形式渲染。
- root 用户单行：`user@host cwd# `。

`__fish_last_status` 必须 `set -lx` **导出**——`__fish_print_pipestatus` 读的是导出变量，不导出则 pipestatus 恒空。普通用户分支显示 `$PWD` 全路径，root 分支沿用 fish 的 `prompt_pwd` 缩写。
