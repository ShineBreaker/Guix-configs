# gpg-agent / pinentry 范式：把 `$HOME`-relative 路径换成绝对 store 路径

> 沉淀自 2026-07-18 实操。用户报："为什么我的 gpg 填写密码不走 pinentry-qt 了，奇怪"。诊断链 + 根因 + 范式修复。

---

## 症状

gpg 操作（GPG commit 签名 / `gpg --clearsign` / pass / keepassxc）需要输入密码时，弹出来的是 **TTY 提示**（直接在终端里读 passphrase），而不是预期的 `pinentry-qt` 图形窗口。

`~/.local/share/gnupg/gpg-agent.conf` 看起来配得好好的：

```
pinentry-program ~/.guix-home/profile/bin/pinentry-qt
default-cache-ttl 600
...
```

`which pinentry-qt` 也指向 `/home/brokenshine/.guix-home/profile/bin/pinentry-qt`，二进制存在。

---

## 诊断命令链（按顺序跑）

```bash
# 1. 关键诊断:gpgconf --check-programs 报告的"注册路径"
gpgconf --check-programs
# 典型输出(注意 pinentry 一行):
#   gpgconf: 运行'/home/brokenshine/.guix-profile/bin/pinentry'时出现错误:可能未安装
#   pinentry:密码条目:/home/brokenshine/.guix-profile/bin/pinentry:0:0:

# 2. 磁盘上 conf 的实际内容(注意 symlink target 是否变)
cat ~/.local/share/gnupg/gpg-agent.conf
# 同样注意 readlink -f 看 symlink 指向哪个 store hash

# 3. 在跑的 gpg-agent 进程是谁起的
pgrep -af gpg-agent
# PID=17280  gpg-agent --homedir /home/brokenshine/.local/share/gnupg --use-standard-socket --daemon
# PPID=1851   guile ... shepherd --silent --config /gnu/store/.../shepherd.conf
# → 确认是 home-shepherd 起的(Guix Home 标配),不是用户手动起

# 4. gpg-agent 用哪个 conf(symlink 跟踪)
readlink -f ~/.local/share/gnupg/gpg-agent.conf

# 5. 进程实际读哪个 conf 路径 / 有无命令行覆盖
cat /proc/<pid>/cmdline | tr '\0' ' '
# --homedir /home/brokenshine/.local/share/gnupg  → gpg-agent 在该 homedir 找 conf
```

---

## 根因(为什么 conf 里写对了,但 gpg-agent 还是走 tty)

**`gpgconf --check-programs` 报的"注册路径"是 `gnupg` 包 build-time 硬编码的 fallback 路径**,不是从 conf 读出来的。换句话说:

- 用户 conf 里写 `~/.guix-home/profile/bin/pinentry-qt`(依赖 `$HOME` 解析 + PATH)
- gnupg 包 build 时假设有 `~/.guix-profile/bin/pinentry`(标准 Guix 系统级位置)
- gpg-agent **如果没读到 conf**,就走 build-time fallback,fallback 不存在就退到 tty

**为什么 gpg-agent 没读到 conf**:home-shepherd 启动 gpg-agent 时,它有自己的 `gpg-agent-configuration` service-type,参数里**不会**自动读取 `~/.local/share/gnupg/gpg-agent.conf`(这是 dotfiles 自管的,不归 service 管)。如果用户 conf 跟 service-type 冲突,**服务端的参数优先**,用户的 conf 被无视。

具体症状链:

1. 用户 conf 写 `pinentry-program ~/.guix-home/profile/bin/pinentry-qt`
2. home-shepherd 启动 gpg-agent 时,**不传 `--pinentry-program` 参数**(service-type 没声明)
3. gpg-agent 启动 → 读 homedir 下的 conf → conf 里写的是**相对 `$HOME` 的 `~/...`**
4. gpg-agent 做路径展开时,`$HOME` 在 daemon 上下文里**未必是 `/home/brokenshine`**(herd 启动时 HOME 可能为空或别的)
5. 路径展开失败或解析到错误位置 → gpg-agent 标记该 pinentry 不可用
6. fallback 走 build-time 默认(即 `~/.guix-profile/bin/pinentry`,也不存在)→ 再次 fallback → **TTY 直接读 passphrase**

**`gpgconf --check-programs` 的诊断价值**:它显示的 pinentry 路径**永远不会**反映 conf 里 `pinentry-program` 行写的是什么 —— 它显示的是"如果现在 gpg-agent 要启动 pinentry,它会试哪条路径"。如果显示的是 `~/.guix-profile/bin/pinentry` 而你 conf 里写的是 `~/.guix-home/profile/bin/pinentry`,**100% 确认 gpg-agent 没读你的 conf**。

---

## 范式修复:conf 改用绝对 store 路径

### 步骤 1:在 `source/files/` 放模板

新位置:`source/files/gpg-agent.conf`:

```
# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

pinentry-program $$bin/pinentry-qt$$
default-cache-ttl 600
max-cache-ttl 7200
default-cache-ttl-ssh 1800
max-cache-ttl-ssh 7200
```

`$$bin/pinentry-qt$$` 是 rosenthal `computed-substitution-with-inputs` 的路径注入语法,编译期替换为绝对 store 路径,例如:

```
pinentry-program /gnu/store/hybbv1akqc4pc39dyblml0zcdyq5azzs-pinentry-qt-1.3.2/bin/pinentry-qt
```

### 步骤 2:改 `source/config.org` 的 `home-files-services` 块

**删除**原来在 `dotfiles/immutable/utilities/.local/share/gnupg/gpg-agent.conf` 的 dotfile 源(`git rm`),改用 `home-files-service-type` 模板注入:

```scheme
(".local/share/gnupg/gpg-agent.conf" ,(computed-substitution-with-inputs
                                       "gpg-agent.conf"
                                       (local-file
                                        "../source/files/gpg-agent.conf")
                                       (specs->pkgs
                                        "pinentry-qt")))
```

注意 `specs->pkgs "pinentry-qt"` 这一段:它把"哪些包要在编译时注入路径"声明出来。少了这一行,`$$bin/pinentry-qt$$` 不会被替换。

### 步骤 3:把模板加进仓库跟踪

```bash
git add source/files/gpg-agent.conf
# source/config.org 的 home-files-services 块改动一起 git add
```

### 步骤 4:blue home 部署 + reload

```bash
cd ~/Projects/Config/Guix-configs && blue home
# 部署完成,store 副本会有新 hash

# 验证 symlink 指向新 store
readlink -f ~/.local/share/gnupg/gpg-agent.conf
# 应该显示绝对 store 路径,内容是绝对路径的 pinentry-qt

# 让正在跑的 gpg-agent 重读 conf
gpgconf --reload gpg-agent
# 这一步必须!blue home 只部署,不会重启已在跑的 gpg-agent

# 触发一次签名验证
echo "test" | gpg --clearsign
# 应弹 pinentry-qt 窗口(密码在 GUI 输入),而不是 TTY
```

---

## 通用范式(推广到其他"daemon + 配置文件 + 路径"场景)

**只要 daemon 跑在 shepherd / dbus / 不继承 login shell 的上下文里,`$HOME`-relative 路径就不可靠。改用绝对 store 路径才是稳的。**

具体可推广场景:

| 场景                                | 反例(不可靠)                                       | 正解(绝对 store 路径)                                                |
| ----------------------------------- | -------------------------------------------------- | -------------------------------------------------------------------- |
| gpg-agent `pinentry-program`        | `~/.guix-home/profile/bin/pinentry-qt`             | `/gnu/store/...-pinentry-qt-1.3.2/bin/pinentry-qt`(via `$$bin/...$$`) |
| mako / swaync 配置里引用图标路径    | `~/.local/share/icons/...`                         | `/gnu/store/...-icon-theme/share/icons/...`(via `computed-file`)      |
| river / Hyprland 配置里引用 cursor  | `$HOME/.local/share/icons/...`                     | 绝对 store 路径                                                      |
| 任意 daemon 在 herd 起的服务里跑    | 任何 `~` 或 `$HOME/...`                            | 全部换成 `$$bin/...$$` 或 `$$share/...$$`                            |

**判断标准**:

- conf 文件用 `home-dotfiles-service-type` 部署 → `~` 解析**依赖部署时的 `$HOME`**,**对 daemon 不稳**
- conf 文件用 `home-files-service-type` + `computed-substitution-with-inputs` 部署 → `$$...$$` 在编译期展开成 store 路径,**对 daemon 稳**

---

## 反模式

- ❌ **保留 dotfile 在 `dotfiles/immutable/<app>/` 里 + 写 `~`-relative 路径** —— daemon 跑的时候 `$HOME` 未必正确,结果就是你这次的 tty 弹窗
- ❌ **改 gpg-agent.conf 后只 `blue home` 不 `gpgconf --reload gpg-agent`** —— 已在跑的 daemon 持有旧配置
- ❌ **gpg-agent.conf 里写绝对路径但忘了加 `specs->pkgs`** —— `$$bin/...$$` 不替换,conf 模板原样落到磁盘,pinentry 解析失败
- ❌ **改 conf 路径但不动 `source/config.org` 的 `home-files-services` 块** —— Guix Home 不知道要部署这个 conf
- ❌ **手动 `cp` conf 到 `~/.local/share/gnupg/`** —— store hash 是孤立的,下一次 `blue home` 会覆盖;正确做法是改源 + `blue home`
- ❌ **看到 tty 弹窗就去改 pinentry-qt 二进制本身** —— 二进制没问题,问题在 conf 路径没传到位

---

## 与已有 skill 章节的关系

- **§4 Guix service 排查**(home-shepherd 起的 daemon 不传用户 dotfile 里的 conf 参数)—— 本节是这个原则的另一个具体案例
- **§1 dotfiles 部署验证三步** —— 本节强调"daemon 跑的时候读哪个 conf"是更精细的问题,单纯的"md5sum 源 vs 部署位置" 验证完了 daemon 仍然可能不读

---

## 一句话总结

> **daemon 跑的 conf,路径必须绝对 store 路径,不依赖 `$HOME` 解析。**
> **改 conf 后 `blue home` + `gpgconf --reload gpg-agent` 两个都要。**
