# 迁 `~` 下的点目录到 XDG 目录

`~` 下堆了几十个 `.xxx` 目录，迁到 XDG 标准位置。两个阶段，**顺序不能反**：
① 查证能否迁 → ② 搬数据 → ③ 落环境变量。跳过 ② 是本文件最重要的一条禁令。

---

## 一、铁律：写完环境变量 ≠ 迁移完成

**只写 `~/.config` 里的环境变量、把数据留在原地，等于什么都没迁，还制造了坏状态。**

机制：新路径不存在 → 程序首次运行时**从头创建空目录 + 写默认配置** → 旧数据原地变孤儿，用户看到"历史全没了"。

正确顺序，每一步都可独立验证：

```
① 查证该工具有没有官方变量（本文件 §3 表）
② 停相关进程（lsof +D <dir> 为空）
③ 搬数据（同一 fs 用 mv；跨 fs 用 cp -a 后 trash 旧的）
④ 落环境变量到 source/config.org 的 xdg-basedir-env-vars 块
⑤ 实测：程序在新位置读写 + 旧位置没被重建
```

**若变量要等 `blue home` 才生效，搬迁数据会有一段"变量还没生效"的窗口**——见 §2。

---

## 二、三个把数据搞丢的坑（都实际踩过）

### 坑 1：变量只覆盖"一部分"子树 → 数据分裂成两处

一个工具可以同时有**多个** home 类变量，各管各的子树，只设一个必然分裂。

zcode 实例：`ZCODE_HOME` 与 `ZCODE_DATA_BASE_DIR` 都只覆盖桌面段（`v2/`、崩溃上报），而占 40G 的 `cli/` 子树在 `app.asar` 里多处硬编码 `homedir` 拼接，**绕过所有环境变量**。设了变量的结果是：桌面数据在 `~/.local/share/.zcode/`，CLI 数据仍写 `~/.zcode/cli/`——两处都"有数据"，两边都不完整。

**判定法**：在 asar / 二进制 / npm 包里 grep 变量名，再 grep `homedir()` 与 `".xxx"` 拼接点，看目标目录到底由谁算。**不要只看官方文档说有这个变量就认为整目录都归它管。**

结论：这类工具**不设变量**（设了比不设更糟）。在 `xdg-basedir-env-vars` 块里留注释写明原因，防止下一个人再踩。

### 坑 2：搬迁后跑了一次程序 → 旧路径被重建 → `mv` 回滚时套娃

回滚 `mv <新位置> <旧位置>` 时，**目标路径已经存在**（坑 1 里那次测试运行重建出来的空壳），`mv` 会把整个目录塞进去变成 `~/.zcode/.zcode/`，外层只剩空壳。

正确回滚姿势：

```bash
# 1) 先确认外层是真数据还是空壳——比大小，不比存在
du -sh <旧位置> <新位置>

# 2) 真数据在套娃内层时，不要 mv 整个目录，逐项合并
cp -an <内层>/. <外层>/      # -n 不覆盖，保留外层较新/较全的
# 3) 单个文件被空壳盖住时，用绝对路径强制复制（相对路径会被同名前缀干扰）
cp -p /abs/path/to/real.db /abs/path/to/target.db
# 4) 校验一致性后再把副本移走
diff -rq <副本> <目标>       # 逐项比对，只允许预期差异
mv <副本> /tmp/verify-only    # /tmp 重启自清，是安全暂存区
```

### 坑 3：用 `fuser -m` 判占用 → 结论全错

`fuser -m <dir>` 报的是**整个挂载点**的占用者——`~` 下所有目录同盘时它会把所有进程都列出来，看着像"满地都是占用者"，实际与该目录无关。判"这个目录有没有进程在用"只能用 `lsof +D <dir>`，它只报持有该目录下文件的进程。

---

## 三、可迁性判定表

判据优先级：**官方文档 > 源码/app.asar 实码 > 二进制 strings > 文档站搜索**。查不到就写"查不到"，不要猜。

### 有官方变量，可迁

| 目录 | 工具 | 变量 | 落点 |
|---|---|---|---|
| `~/.cua-driver` | Cua Driver | `CUA_DRIVER_RS_HOME` | `$XDG_CONFIG_HOME/cua-driver` |
| `~/.paseo` | Paseo | `PASEO_HOME`（模型另有 `PASEO_LOCAL_MODELS_DIR`） | `$XDG_DATA_HOME/paseo` |
| `~/.pi/context-mode` | pi 的 context-mode 扩展 | `CONTEXT_MODE_DIR` | `$XDG_STATE_HOME/pi/context-mode` |
| `~/.copilot` | GitHub Copilot CLI | `COPILOT_HOME` + `COPILOT_CACHE_HOME` | `$XDG_CONFIG_HOME/copilot` |
| `~/.zcode-proxy` | zcode-proxy | `ZCODE_PROXY_STORE_DIR` | `$XDG_CONFIG_HOME/zcode-proxy/store` |
| `~/.npm` | npm | 无 env var，见 §4 | npmrc 的 `cache=` |
| `~/.rustup` | rustup | `RUSTUP_HOME` | `$XDG_DATA_HOME/rustup` |
| `~/.mysqlsh` | MySQL Shell | `MYSQLSH_USER_CONFIG_HOME` | `$XDG_STATE_HOME/mysqlsh` |
| `~/.android` | adb | `ANDROID_USER_HOME` | `$XDG_CONFIG_HOME/android` |
| `~/.bun` | bun | `BUN_INSTALL_CACHE_DIR` | `$XDG_CACHE_HOME/bun` |

`~/.rustup` 迁前先 `command -v rustup`——没有 rustup 二进制时那 1.3G 是孤儿重量，迁了也没用。

### 看似有变量，实则迁不动

| 目录 | 为什么迁不动 |
|---|---|
| `~/.xwechat` | 微信 Linux 版 4.1.1.8，数据路径是编译期字面量；二进制里零个 `*_HOME/_DIR` 变量 |
| `~/.workbuddy` | flatpak manifest 硬绑 `--filesystem=~/.workbuddy:create`，沙箱外变量进不去；启动代码还自我覆写 |
| `~/.zcode` | 见 §2 坑 1 |
| `~/.pki` | NSS 源码 `getUserDB()` 搜索顺序写死 `~/.pki/nssdb` **优先**，存在就永不走 XDG；无 env var 可改。删掉会回落到 `.local/share/pki/nssdb` 但证书私钥"看起来丢失" |
| `~/.java` | 路径由 `${user.home}` 拼，JVM 在 Linux 上**不跟随 `$HOME`**（实测 `HOME=/tmp/x java -XshowSettings:properties` 仍报原值） |
| `~/.commandcode` | 官方 env 表里只有 `HOME`/`USERPROFILE` 用于解析该目录——改 HOME 会连带废掉全局 XDG |
| `~/.dsh-tui` / `~/.mimosa` / `~/.duckdb` / `~/.subversion` | 无目录变量；后两者只有 CLI 开关 / SQL `SET` |

### 残留/空壳，可清（清理用 `trash-put`）

判据是**「新位置已有活跃数据 + 旧位置无近期写入」**，两者都满足才是残留。逐个用 §6 的命令实测，别凭目录名或 subagent 的结论下判断。

`.devin`+`.devin-shared`（真数据在 `~/.config/Devin`）、`.codeium`（windsurf 已卸）、`.opencode2dsh`（符号链接已断）、`.nix-defexpr`（`use-xdg-base-directories` 已接管，只剩空 symlink）、`.stow-overlay`（空目录全库零引用）、`.minecraft`（陈旧，PrismLauncher 有活跃副本）、`.claude/skills`（孤儿软链，真数据在 `~/.config/claude`）、`.gnupg`（空壳，真数据在 `~/.local/share/gnupg`）、`.bun`/`.officecli`/`.mysqlsh`/`.duckdb`/`.dbx`/`.cindy`（对应程序未安装，纯缓存或空壳）。

**同名的近邻目录不是一回事**：`~/.omp/context-mode` 与 `~/.pi/context-mode` 是两个工具各自的数据，搬走 pi 的不代表 omp 的也废弃——实测 omp 那份仍在活跃写入。

---

## 四、npm 缓存：为什么必须走 npmrc

`NPM_CONFIG_USERCONFIG` 只改 `.npmrc` 的**位置**，不管缓存目录。缓存看似能用 `NPM_CONFIG_CACHE` 迁，**实测不行**：

```bash
NPM_CONFIG_CACHE=/tmp/x npm run show    # 脚本里 process.env.npm_config_cache === undefined
```

大写变量不会下传成小写别名，lifecycle 脚本（`prebuild-install` 这类原生模块构建）读不到，仍把 `_prebuilds` 写回 `~/.npm`。走 npmrc 则正常下传：

```bash
# ~/.config/npm/npmrc（放 dotfiles/immutable/utilities/.config/npm/npmrc 随 blue home 部署）
cache=${XDG_CACHE_HOME}/npm     # npmrc 会展开 ${XDG_*}
```

设完 `npm config get cache` 确认指向新路径，再 install 一次看 `_cacache` 落在哪，最后才 trash 旧目录。

---

## 五、实测模板（`blue home` 未生效时也能验）

```bash
# 正向：程序读到了新路径吗
VAR=/new/path timeout 30 <cmd> --version 2>&1 | head -3
# 反向（关键）：旧路径有没有被重建 —— 这条才抓得出"变量只覆盖部分子树"
ls -d <old/path> 2>/dev/null && echo "变量没覆盖全，别迁" || echo "OK"
```

反向检查是 §2 坑 1 的唯一防线。**正向通过不代表全树覆盖。**

---

## 六、判"是否还在用"：只能看文件 mtime，不能看目录 mtime

**目录的 `mtime` 只反映最后一次增删子项，不反映子文件被改写。** 一个每天都在写 db 的目录，其 `mtime` 可能停在几周前。`stat -c %y` 单独用会得出"这是废弃残留"的错误结论。

```bash
# ✅ 唯一可信的判据：目录内有没有 N 天内被修改的文件
find <dir> -type f -mtime -7 | wc -l
```

实测打脸记录：`.omp` / `.hyperframes` / `.cc-switch` / `.i18nupdatemod` / `.cindy` / `.atuin` 目录 mtime 看着都停在数周前，实际都有 4~6 天内的写入。**这些 subagent 全判成"残留/已停更"，直接照做会删掉正在用的数据。**

顺带：`find DIR -newermt "-7 days"` 是**"早于 7 天前"**，与直觉相反，别用它判活跃度；用 `-mtime -7`。

**把这条做成脚本里的强制安全网**，而不是靠人记得：任何批量清理脚本都应先跑 `find -mtime -N` 过滤，命中的目录自动排除并在输出里列出——让判据在代码里生效一次，就不必在每次会话里重新判断。

### bash 陷阱：`set -o pipefail` + `find | grep -q` 会误判

```bash
# ❌ 在 set -euo pipefail 下：grep -q 找到第一个匹配就退出 → find 收 SIGPIPE
#    返回 141 → pipefail 判定整个管道为「假」→ 活跃目录被当成「没写入」
if [ -d "$d" ] && find "$d" -type f -mtime -7 2>/dev/null | grep -q .; then
  echo active
fi   # ← 永远不执行

# ✅ 无管道，不产生 SIGPIPE
active_recent() {
  [ -d "$1" ] && [ -n "$(find "$1" -type f -mtime -7 -print -quit 2>/dev/null)" ]
}
```

`-print -quit` 让 find 自己停下来，不经 grep。**这类"安全网自己失效"的 bug 只在稳定复现时才看得出来**——本例连跑三次都稳定误判同一个目录，才确认不是偶发。写完判据逻辑要用 `bash -c` 单独复现一次再信它。
