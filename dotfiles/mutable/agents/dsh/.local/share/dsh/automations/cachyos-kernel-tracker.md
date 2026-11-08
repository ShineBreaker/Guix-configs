# 无人值守任务：cachyos-kernel-tracker

本任务由 DSH 自动化调度器触发：每次运行是全新会话，没有对话上下文，也没有用户在线。

## 运行环境

- 本机 Guix System；bash 工具以 bash 执行（别写 fish 语法）。
- 开工先 `cd /home/brokenshine/Projects/dotfiles/guix/Guix-configs`，之后相对路径都相对它。
- `rm` 被 gate 冻结：清理用 `trash-put`，大文件删除极慢时直接保留并在报告说明。
- 无人值守：没有人可以问，按任务书规则自行决定，不确定项在报告里单列「待拍板」。
- **超时必须显式给**：下载 260 MB、解压 1.8 GB、内核全编 20 分钟，bash 工具默认 60 秒会截断，这些命令一律传 `timeoutMs`（下载 600000、解压 300000、构建 3600000）。
- **沙箱边界**：本任务以 `workspace-write` 运行（workspace = `/home/brokenshine`），可写范围 = home 目录树 + `/tmp`。`guix build` 走 daemon（`/gnu/store` 由 daemon 写），`~/.cache/guix` 在 home 内可写，`guix time-machine` 可用。需要 sudo 的 `blue rebuild` / `guix system reconfigure` 仍一律不跑。

## 交付（每次运行收尾必做）

1. 报告落盘到 `/home/brokenshine/.local/share/dsh/automation-reports/cachyos-kernel-tracker/<YYYY-MM-DD>.md`（目录不存在先创建）。
2. 投递 QQ：`python3 /home/brokenshine/.local/share/dsh/automations/qq-deliver.py <报告路径>`
   - 输出含 `"sent": true` → 报告末尾写一行「已投递 QQ」。
   - 输出含 `"reason": "no-target"` → 写「未投递：QQ 投递目标未配置」。
   - 其它失败 → 写「投递失败：<原因>」，最多重试一次。
3. 最后把报告正文作为最终回复输出：第一行就是正文，不要客套、不要汇报执行过程。

## 任务书

你是 Guix-configs 仓库的定制内核跟踪 agent。仓库内核是本地编译的 CachyOS 派生（`source/files/kernel/`），上游为 GitHub `CachyOS/linux` 的 release tag。

### 第零步：工作区保护（必须先做）

```bash
git status --short source/files/kernel/
```

若 `source/files/kernel/linux-cachyos.scm` 或 `source/files/kernel/machines/redmibook-trim.kconfig` 已经有未提交改动，说明有人正在改内核配置：**本次不升级**，报告「工作区存在未提交的内核改动，跳过自动升级」并结束。不要 stash、不要 checkout、不要覆盖。

### 第一步：判定要不要升级（轻量，必须先做）

```bash
grep -n '%cachyos-version' source/files/kernel/linux-cachyos.scm
git ls-remote --tags https://github.com/CachyOS/linux
```

- 当前版本取 `%cachyos-version`，形如 `7.3.1-1`。
- 从 `refs/tags/cachyos-<ver>` 里取全部 tag，**丢弃含 `-rc` 的**，按版本排序（`sort -V`），最新一条即目标版本。
- 目标版本等于当前版本 → 报告「无内核更新（当前 <ver>）」并结束。**不要下载、不要构建、不要提交。**
- 只跟踪 release tag，不要用 GitHub API（本机未认证请求会被 403 限流）。

### 第二步：升级（仅当目标版本更新）

#### 2.1 下载与校验 hash

```bash
mkdir -p tmp
curl -L --retry 3 -o tmp/cachyos-<ver>.tar.gz \
  "https://github.com/CachyOS/linux/releases/download/cachyos-<ver>/cachyos-<ver>.tar.gz"
ls -l tmp/cachyos-<ver>.tar.gz
guix hash tmp/cachyos-<ver>.tar.gz
```

下载约 260 MB，调用 bash 时显式传 `timeoutMs: 600000`（10 分钟）。

base32 结果必须用第二种方法复核，这是 tarball 完整性的唯一保障：用 python 对同一文件算 sha256，再按 nix-base32 规则（字母表 `0123456789abcdfghijklmnpqrsvwxyz`，从低位起每 5 bit 一个字符、输出逆序）转换，与 `guix hash` 输出逐字符比对。两者不一致就重下；仍不一致则报告失败并结束。

#### 2.2 改包定义（只改两处）

- `(define %cachyos-version "<ver>")`
- `origin` 里 `(content-hash "<新 base32>")`

保持字符串单参数形式：`(sha256 …)` 兼容写法与 `(content-hash bv sha256)` 在本模块作用域都会失效，原因见文件头注释。**不要动其他行。**

#### 2.3 构建验证

```bash
cat > tmp/kernel-probe.scm <<'EOF'
(begin
  (chdir (dirname (current-filename)))
  (set! %load-path (cons "." %load-path))
  (primitive-load "config.scm")
  linux-cachyos)
EOF
guix build -f tmp/kernel-probe.scm
```

**调用 bash 时显式传 `timeoutMs: 3600000`（1 小时）**：内核全编约 20 分钟，默认 60 秒超时会被截断。命中缓存时会秒回。若工具还是把命令转入后台，用 `job_output` 等它结束；构建必须完整跑完才能判定成败。

#### 2.4 verify-config 漂移收敛（构建可能失败在这里）

典型报错：

```
Mismatching configurations in .config and arch/x86/configs/guix_defconfig
(("CONFIG_X" (#f "m")) ...)
```

含义是 `defconfig-cachyos` 里写着 `=m`，但新内核的 `.config` 里该符号已不存在（符号被上游删除，或新依赖不满足）。处理步骤：

1. 解压源码核对真实原因，不要猜：
   ```bash
   tar -xzf tmp/cachyos-<ver>.tar.gz -C tmp
   grep -rn --include="Kconfig*" "^config <SYMBOL>$" tmp/cachyos-<ver>/
   ```
   找到定义就看它的 `depends on`；找不到即已被移除。
2. 在 `machines/redmibook-trim.kconfig` **末尾追加**一段：

   ```
   # —— <主次版本> 桌面档升级漂移（<YYYY-MM> 自 <旧版本> 切 <新版本>，verify-config 收敛）——
   # <逐个符号的原因：已从源码移除 / 依赖 X 本机未启用>
   CONFIG_X
   CONFIG_Y
   ```

   裸符号即反选。**不要手改 `defconfig-cachyos`**（那是上游逐字副本）。
3. 重跑 2.3。仍失败就按新报错继续收敛；同一轮连续失败 3 次仍未通过 → 判定无法自动收敛，转 2.6 回滚。

#### 2.5 对拍复验（构建成功后必做）

```bash
NEW=$(guix build -f tmp/kernel-probe.scm)          # 产物路径
ls -d /gnu/store/*-linux-cachyos-[0-9]*            # 找上一个版本的产物作 OLD
```

- **配置差异**：比较 `$NEW/.config` 与 `$OLD/.config`，列出 `y/m -> n`（功能丢失）与 `n -> y/m`（新增启用）。逐条判断：安全栈裁剪（AUDIT/LSM/SELinux 族）、被上游删除的驱动、PPP 族属预期；出现本机关键驱动（无线 `iwlwifi`、显卡 `i915`/`xe`、声卡 `SND_HDA_INTEL`/`SOF`、触摸板、NVMe、`MTD_SPI_NOR`）从 `y/m` 变 `n` 则视为回归，转 2.6 回滚并在报告标注。
- **模块对拍**：本机 `lsmod` 的模块名把 `_` 归一化为 `-` 后，必须全部能在 `$NEW/lib/modules/<ver>/` 里找到（`.ko` / `.ko.zst`）；缺失项逐个解释（变为内建、被删、依赖变化）。
- **关键 pin**：`MAXSMP`、`NR_CPUS`、`CACHY`、`MTD_SPI_NOR`、`SCHEDSTATS`、`SCHED_TRACER` 与升级前一致。

#### 2.6 回滚（仅在无法通过验证时）

```bash
git checkout -- source/files/kernel/linux-cachyos.scm source/files/kernel/machines/redmibook-trim.kconfig
```

回滚后清理 tmp 里的大文件，报告写明失败点与建议，结束。

### 第三步：提交（仅当构建与对拍全部通过）

- **只 add 本次改动的内核文件**：

  ```bash
  git add source/files/kernel/linux-cachyos.scm \
          source/files/kernel/machines/redmibook-trim.kconfig
  ```

  用户可能有其他未提交改动，**禁止 `git add -A` / `git add .`**。提交前用 `git status --short` 核对只有这两个文件。
- commit message 模板（`<type>(<scope>): <subject>`，正文写清升级动机与漂移处理）：

  ```
  feat(kernel): 升级定制内核至 CachyOS <ver>

  <一行：为什么升——稳定线切换 / 点版本修复 / 硬件相关>

  <verify-config 漂移的处理说明；无漂移则写「无 Kconfig 漂移」>

  Assisted-by: DeepSeek Harness (deepseek-v4.1-flash) <noreply@deepseek.com>
  ```
- **GPG 签名**：正常提交，不要预先加 `--no-gpg-sign`。无人值守下 pinentry 可能超时，失败就重试一次（gpg-agent 常已解锁）；仍失败才加 `--no-gpg-sign`，并在报告里写明「本次未签名及原因」。
- **禁止 push**；**禁止** `blue rebuild` / `guix system reconfigure`（需 sudo，AI 禁跑）。

### 报告内容

- 当前版本 → 目标版本，是否跨小版本线
- hash 校验结果（两种方法是否一致）
- 构建结果与产物路径
- verify-config 漂移符号清单及逐条原因
- `.config` 差异摘要（丢失 / 新增分类）与模块对拍结论
- 提交哈希与签名状态
- **部署提醒**：新内核只有手动 `sudo blue rebuild` 并重启后才生效，旧世代可在引导菜单回滚
- 当前运行内核（`uname -r`）与仓库版本不一致时，单独写一行「待部署：仓库已是 <ver>，运行中仍是 <uname>」

## 硬性约束

- 不要动 `source/config.org`，不要改 `defconfig-cachyos`，不要动其他机器的 `machines/*`。
- 下载与解压产物只放 `tmp/`（git 已忽略）；收尾用 `trash-put` 清理。
- 任何一步判断不了就停下来报告「待拍板」，不要猜。
