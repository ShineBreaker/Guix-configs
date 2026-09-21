<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# 应急操作手册 —— blue 不可用时怎么办

> 本仓库的部署能力不应该被单点绑死在 `blue` 上：整条管线只是
> 「tangle → 括号检查 → guix reconfigure」三层，用 bash + guix 就能原样重建。
> 应急脚本 `tools/emergency-blue.sh` 封装了这套操作；本文档解释原理，并给出
> **连脚本都跑不起来时的纯手动命令序列**。

## 1. 何时需要应急

出现以下任一症状，说明 `blue` 已不可用，可转入本文档流程：

- `blue: command not found` —— 包装脚本（`~/.local/bin/blue`）丢失或不在 PATH；
- `incompatible bytecode version` —— guile 版本漂移（见 §2，最常见的坏法）；
- wrapper 报 `/run/current-system/profile/bin/guile` 不存在 —— 系统 profile 异常；
- 报 `~/.guix-home/profile/bin/blue` 不存在 —— Home 层未部署或已损坏；
- bluebox 频道不可达导致 blue 本体无法构建。

判断标准很简单：只要 `guix` 本身还能跑、仓库里 `source/channel.lock` 还在，
部署能力就完整保留。

## 2. blue 是什么、怎么坏的

调用链（三层，任何一层断都会导致 blue 不可用）：

```
~/.local/bin/blue          ← bash 包装脚本（含 guile 变通）
  └─ exec /run/current-system/profile/bin/guile -e main -s
         ~/.guix-home/profile/bin/blue   ← bluebox 频道提供的 blue 本体
           └─ 加载仓库根 blueprint.scm，执行 blue <命令>
```

- **blue 本体**来自 *bluebox* 频道（经 `source/channel.lock` 锁定 commit），
  部署进 Guix Home profile；`source/manifest.scm` 只有一行 `("blue")`。
- **包装脚本的存在原因**：bluebox 把 blue 的 guile 输入 pin 在 3.0.9，而系统
  profile 的 guix 模块已是 3.0.11 编译的字节码，直接执行报 incompatible
  bytecode version。wrapper 借系统 profile 的 guile 3.0.11 以 `-s` 方式运行
  脚本主体绕开（shebang 被当作注释跳过）。
- **引导环境**：`tools/bootstrap.sh` 用
  `guix time-machine -C source/channel.lock -- shell -m source/manifest.scm`
  开一个带 blue 的临时 profile shell —— 这意味着 blue 的恢复不依赖 blue 自己。

坏法归结起来就是：系统重装/升级后 guile 路径变化、Home 层损坏导致 blue 本体
丢失、或 guile 版本漂移。共同点：**blueprint.scm 里定义的管线本身没有任何
blue 专有依赖**，它只是 guix / emacs 子进程的编排。

## 3. 核心管线（blue 三命令的精确实现）

以下是 `blueprint.scm` 中实测出的管线，应急脚本与其逐字对齐：

```
source/config.org ──tangle──▶ tmp/config.scm ──追加尾表达式──▶ 括号检查 ──▶ reconfigure
```

1. **tangle**：`guix time-machine --channels=source/channel.lock -- shell
   emacs-minimal -- emacs --quick --batch -l org --eval "(require 'ob-tangle)"
   --eval "(org-babel-tangle-file \"source/config.org\")"`。把 config.org 里
   所有 `:tangle ../tmp/<文件名>` 块写到仓库 `tmp/`：主产物 `tmp/config.scm`，
   另有 `mihomo-run`、`nftables.conf` 等伴生产物（系统配置以 file-like 对象
   引用它们，reconfigure 时必须存在）。前置 `env -u` 清掉五个 `EMACS*` 变量。
2. **追加尾表达式**：tangle 产物只是定义集合，blue 会向 `tmp/config.scm`
   末尾追加一行 `%home`（home 命令）或 `%system`（rebuild/init）——guix 取
   文件中最后一个表达式的值作为配置对象。**跳过这步 guix 会报“没有找到配置”**。
3. **括号平衡检查**：对追加了尾表达式的整份文件做词法扫描（数 `( )` 与
   `[ ]`，跳过字符串与 `;` 注释，且两者必须严格同类配对）。
4. **reconfigure**（全部经 `guix time-machine` 锁定频道）：
   - `blue home`：`guix time-machine --channels=… -- home reconfigure
     tmp/config.scm --allow-downgrades --fallback`（无需 sudo）；
   - `blue rebuild`：同上加 `sudo` 与 `--no-kexec`（仅 system 支持；防 kexec
     路径挂死电源操作），成功后还跑 `guix locate --update`；
   - `blue init`：`sudo guix time-machine --channels=… -- system init
     tmp/config.scm /mnt`（挂载点硬编码 `/mnt`）。

关于 `$$bin/foo$$` 占位符：它**不经过 tangle**，是 `source/files/` 模板里的
路径注入标记，在 `guix home reconfigure` 的构建期由 rosenthal 频道的
`computed-substitution-with-inputs` 自动替换。应急时无需任何额外步骤。

关于 `--dry-run`：blue 自己的 `--dry-run` 只真跑 tangle 与括号检查，连
`guix … build` 都只打印不执行；应急脚本的 `--dry-run` 则**真正执行**
`guix <home|system> build tmp/config.scm --dry-run`（只验证构建、不写入），
语义上比 blue 更进一步，对应 `source/AGENTS.md` 验证节建议的手动补充验证命令。

## 4. 应急脚本用法

前提：bash + guix 可用；**必须在仓库根目录运行**（脚本自检
`source/config.org` 与 `source/channel.lock`）。

```bash
./tools/emergency-blue.sh tangle        # 生成/复用 tmp/config.scm（比源新则复用）
./tools/emergency-blue.sh home          # 应用 Home 配置（无需 sudo）
./tools/emergency-blue.sh rebuild       # 应用系统配置（sudo，执行前打印并确认）
./tools/emergency-blue.sh init /mnt     # 装机到已挂载的目标盘（sudo）
./tools/emergency-blue.sh check         # 括号平衡检查（默认 tmp/config.scm）
```

- 全局选项：`--dry-run`（reconfigure/init 降级为 build --dry-run）、
  `-y`（跳过 sudo 确认）。
- tangle 复用判据：`tmp/config.scm` 的 mtime 新于 `source/config.org` 与
  `source/information.scm`。想强制重编，删掉 `tmp/` 再跑即可。
- `init` 假设分区/加密/挂载已完成（与 blue 相同，前置步骤见 README.org
  装机节，不在脚本范围）；挂载点为显式参数，blue 则硬编码 `/mnt`。

## 5. 纯手动命令序列（blue 与脚本都不可用时）

全部在仓库根目录执行。四步：tangle → 追加尾表达式 → （可选）检查 → reconfigure。

**第 1 步：tangle**（首次会经 guix 下载 emacs-minimal，属正常）：

```bash
mkdir -p tmp
env -u EMACSLOADPATH -u EMACSDATA -u EMACSDOC -u EMACSPATH -u INSIDE_EMACS \
  guix time-machine --channels=source/channel.lock -- \
  shell emacs-minimal -- \
  emacs --quick --batch -l org \
  --eval "(require 'ob-tangle)" \
  --eval "(org-babel-tangle-file \"source/config.org\")"
```

**第 2 步：追加尾表达式**（二选一，**不可跳过**）：

```bash
printf '\n%s\n' '%home' >> tmp/config.scm     # 应用 Home 层用这行
# printf '\n%s\n' '%system' >> tmp/config.scm # 应用系统层（rebuild/init）用这行
```

**第 3 步（可选）：构建验证**。手动场景可跳过括号检查——guix 构建期的
reader 会对括号失配直接报错；若想先验证再写入，用 build 降级：

```bash
guix time-machine --channels=source/channel.lock -- home build tmp/config.scm --dry-run
# 或系统侧：guix time-machine --channels=source/channel.lock -- system build tmp/config.scm --dry-run
```

**第 4 步：应用**（三选一）：

```bash
# Home 层（无需 sudo）
guix time-machine --channels=source/channel.lock -- \
  home reconfigure tmp/config.scm --allow-downgrades --fallback

# 系统层（需要 sudo；--no-kexec 仅 system 支持，勿省）
sudo guix time-machine --channels=source/channel.lock -- \
  system reconfigure tmp/config.scm --allow-downgrades --fallback --no-kexec

# 装机（需要 sudo；目标盘须已分区/加密/挂载，挂载点按实际情况替换 /mnt）
sudo guix time-machine --channels=source/channel.lock -- \
  system init tmp/config.scm /mnt
```

## 6. 恢复 blue

1. **首选**：在仓库根运行 `./tools/bootstrap.sh`。它会用锁定的频道开一个
   带 blue 的临时 profile shell（首次较慢，需克隆并构建频道）。在该 shell 里
   `blue home` 重新部署 Home 层，blue 本体即回到 `~/.guix-home/profile/bin/blue`。
2. **仅 wrapper 损坏**（`~/.guix-home/profile/bin/blue` 还在）时，最小重建
   `~/.local/bin/blue`（内容与现行 wrapper 一致，省略注释）：

   ```bash
   cat > ~/.local/bin/blue <<'EOF'
   #!/usr/bin/env bash
   # SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
   #
   # SPDX-License-Identifier: MIT
   exec /run/current-system/profile/bin/guile --no-auto-compile \
        -e main -s "$HOME/.guix-home/profile/bin/blue" "$@"
   EOF
   chmod +x ~/.local/bin/blue
   ```

3. 恢复后跑一次 `blue list` 确认命令集完整；wrapper 的 guile 变通随 bluebox
   升级其 guile 输入后可整体移除（见 wrapper 内注释）。

## 7. 与正式 blue 的差异清单

| 项目 | 正式 blue | emergency-blue / 手动序列 |
| --- | --- | --- |
| tangle | 同款 emacs-minimal batch 命令，完全一致 | 一致 |
| 频道锁定 | `guix time-machine --channels=source/channel.lock` | 一致 |
| 尾表达式追加 | tangle 后追加 `%home` / `%system` | 一致（脚本会先剥掉上次追加的旧尾表达式再追加，避免换目标时累积） |
| 括号检查 | `blue check` 逐块检查、**定位到块名**；reconfigure 前对整文件兜底 | 只有整文件兜底（awk 移植同一算法），无逐块定位；字符串未闭合会额外报错 |
| 产物复用 | blue 框架按 build manifest 增量构建 | 简化为 mtime 比较（config.scm vs config.org 与 information.scm）；伴生产物缺失时需删 `tmp/` 强制重编 |
| clean-artifacts | rebuild/home 前清理仓库编译产物 | 省略（纯卫生步骤，不影响正确性） |
| 世代修剪 | rebuild 前保留最近 20 个 system 世代 | 省略（维护步骤；长期用应急脚本需手动 `sudo guix system delete-generations`） |
| rebuild 后续 | 成功后 `guix locate --update` | 省略 |
| `--dry-run` | tangle+括号检查真跑，**guix build 也只打印** | build --dry-run **真跑**（更强的验证） |
| `$$bin/foo$$` 替换 | 构建期自动（rosenthal `computed-substitution-with-inputs`） | 同样自动，无需处理 |
| `init` 挂载点 | 硬编码 `/mnt` | 显式参数，并尝试用 `mountpoint` 校验 |
| sudo 交互 | 直接执行（前置修剪以延长 sudo 宽限期） | 执行前打印命令并要求确认（`-y` 跳过） |
| 其余命令（update/pull/gc/stow/…） | 有 | 无（不在应急范围；channel.lock 属于生成物，勿手改） |

> 提醒：应急流程跑通后，请尽快按 §6 恢复 blue，并运行 `blue --dry-run rebuild`
> 复核（两者的 tangle/检查结果应一致）。
