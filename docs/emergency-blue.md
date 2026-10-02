<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# 应急操作手册 — blue 不可用时的应急部署

整条部署管线只是「tangle → 追加尾表达式 → 括号检查 → reconfigure」四步，用 bash + guix 就能原样重建，不该被 blue 单点绑死。`tools/emergency-blue.sh` 封装了这套操作；本文档另给出连脚本都跑不起来时的纯手动命令序列。

## 前置

以下任一症状说明 blue 已不可用，可转入本文档流程：

- `blue: command not found`——blue 本体（`~/.guix-home/profile/bin/blue`）不在 PATH；
- `incompatible bytecode version`——guile 版本漂移，见「排障」；
- 报 `~/.guix-home/profile/bin/blue` 不存在——Home 层未部署或已损坏；
- bluebox 频道不可达，blue 本体无法构建。

判断标准很简单：`guix` 本身还能跑、仓库里 `source/channel.lock` 还在，部署能力就完整保留。blue 本体是 bluebox 频道经 `source/channel.lock` 锁定 commit 提供的包，装进 Guix Home profile；`source/manifest.scm` 只声明 `("blue")` 一项。

脚本与手动命令都要求 bash + guix 可用，且必须在仓库根目录执行（脚本自检 `source/config.org` 与 `source/channel.lock`）。

## 操作

### 1. 应急脚本

```bash
./tools/emergency-blue.sh tangle        # 生成/复用 tmp/config.scm（比源新则复用）
./tools/emergency-blue.sh home          # 应用 Home 配置（无需 sudo）
./tools/emergency-blue.sh rebuild       # 应用系统配置（sudo，执行前打印并确认）
./tools/emergency-blue.sh init /mnt     # 装机到已挂载的目标盘（sudo）
./tools/emergency-blue.sh check         # 括号平衡检查（默认 tmp/config.scm）
```

全局选项：`--dry-run`（reconfigure/init 降级为 `guix <home|system> build --dry-run`）、`-y`（跳过 sudo 确认）。

- sudo 命令执行前先打印原样命令再要求确认；stdin 不可读（如管道调用）一律视为取消，绝不默认放行。
- tangle 复用判据：`tmp/config.scm` 的 mtime 新于 `source/config.org` 与 `source/information.scm`（后者经 noweb 进入产物，必须一并比较）。想强制重编，删掉 `tmp/` 再跑即可。
- `init` 假设分区/加密/挂载已完成（前置见 README.org 装机节，不在脚本范围）。

### 2. 纯手动命令序列

blue 与脚本都不可用时，在仓库根目录执行四步。

第 1 步：tangle。产物除主文件 `tmp/config.scm` 外还有 `mihomo-run`、`nftables.conf` 等伴生产物（系统配置以 file-like 对象引用它们，reconfigure 时必须存在）；首次会经 guix 下载 emacs-minimal，属正常。

```bash
mkdir -p tmp
env -u EMACSLOADPATH -u EMACSDATA -u EMACSDOC -u EMACSPATH -u INSIDE_EMACS \
  guix time-machine --channels=source/channel.lock -- \
  shell emacs-minimal -- \
  emacs --quick --batch -l org \
  --eval "(require 'ob-tangle)" \
  --eval "(org-babel-tangle-file \"source/config.org\")"
```

第 2 步：追加尾表达式（二选一，**不可跳过**）。tangle 产物只是定义集合，guix 取文件中最后一个表达式的值作为配置对象，跳过这步会报「没有找到配置」。

```bash
printf '\n%s\n' '%home' >> tmp/config.scm     # 应用 Home 层用这行
# printf '\n%s\n' '%system' >> tmp/config.scm # 应用系统层（rebuild/init）用这行
```

第 3 步（可选）：构建验证。手动场景可跳过括号检查——guix 构建期的 reader 会对括号失配直接报错；想先验证再写入，用 build 降级：

```bash
guix time-machine --channels=source/channel.lock -- home build tmp/config.scm --dry-run
# 或系统侧：guix time-machine --channels=source/channel.lock -- system build tmp/config.scm --dry-run
```

第 4 步：应用（三选一）：

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

### 3. 恢复 blue

在仓库根跑 `./tools/bootstrap.sh`：它用锁定频道开一个带 blue 的临时 profile shell（首次较慢，需克隆并构建频道），在该 shell 里 `blue home` 重新部署 Home 层，blue 本体即回到 `~/.guix-home/profile/bin/blue`。恢复后跑一次 `blue list` 确认命令集完整。

### 4. 频道锁的兼容性回滚

`blue update` 刷新 `source/channel.lock` 后，`blue rebuild` 可能在 derivation 计算阶段崩溃（guix 与新频道快照不兼容）；`blue update` 本身不带门禁，需要门禁时手动走：

```bash
cp source/channel.lock tmp/channel.lock.bak      # 1. 备份
blue update                                      # 2. 刷新锁文件（自带 git commit）
blue --dry-run rebuild                           # 3. 门禁：tangle + 检查 + 构建验证
# 通过 → 手动 blue rebuild 固化；失败 → cp tmp/channel.lock.bak source/channel.lock 回滚
```

归因提示：跑一次 `blue check` 区分责任——`check` 也失败说明是 `source/config.org` 的 WIP，与锁文件无关，别回滚（回滚只会掩盖真问题）。

## 关键约束

应急脚本与正式 blue 的真实差异（其余一致）：

- **括号检查**：blue 的 `blue check` 逐块检查并定位到块名，reconfigure 前另有整文件兜底；脚本只有整文件兜底（同一算法的 awk 移植），无逐块定位，且额外报「字符串未闭合」。两者的词法扫描都只跳过字符串与 `;` 注释，不处理块注释与 datum 注释。
- **产物复用**：blue 框架按 build manifest 增量构建；脚本简化为 mtime 比较，伴生产物缺失时需删 `tmp/` 强制重编。
- **`--dry-run`**：blue 只真跑 tangle 与括号检查，连 `guix … build` 都只打印；脚本的 `--dry-run` 真跑 `guix <home|system> build tmp/config.scm --dry-run`，验证更强。
- **尾表达式**：脚本追加前先剥掉上次追加的 `%system`/`%home`，避免换目标时累积。
- **省略项**：blue 的 clean-artifacts、rebuild 前的世代修剪（保留最近 20 代）、rebuild 成功后的 `guix locate --update` 脚本都没有；长期用脚本需手动 `sudo guix system delete-generations` 修剪。
- **`init` 挂载点**：blue 硬编码 `/mnt`，脚本取显式参数并尝试用 `mountpoint` 校验。
- **范围**：update / pull / stow 等其余 blue 命令不在应急范围。`source/channel.lock` 是生成物，勿手改。

两个与应急无关、但会咬人的点：

- `$$bin/foo$$` 占位符**不经过 tangle**，是 `source/files/` 模板里的路径注入标记，在 `guix home reconfigure` 的构建期由 rosenthal 频道的 `computed-substitution-with-inputs` 自动替换；应急时无需任何额外步骤。
- 所有 guix 调用都必须经 `guix time-machine --channels=source/channel.lock`，否则频道版本与锁文件不一致，构建结果不可复现。

## 排障

| 症状                                    | 原因                                                  | 处理                                                                                                                                                                               |
| --------------------------------------- | ----------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `blue: command not found`               | blue 本体不在 PATH                                    | 在仓库根跑 `./tools/bootstrap.sh`，在它开的 shell 里 `blue home`                                                                                                                   |
| `incompatible bytecode version`         | blue 的 guile 输入与系统 guile 编译的字节码版本不兼容 | `source/config.org` 的 `blue-fix` 变体已把 guile 输入换成 `guile-3.0-latest` 并关掉测试；跑一次 `blue home`（或 `blue rebuild`）让新包进 profile，否则 profile 里仍是旧的 pin 版本 |
| 系统重装/升级后 blue 不可用             | guile 路径变化、Home 层损坏导致 blue 本体丢失         | 同上：`bootstrap.sh` + `blue home`                                                                                                                                                 |
| `blue rebuild` 崩在 derivation 计算阶段 | guix 与刚刷新的频道快照不兼容                         | 走「频道锁的兼容性回滚」；先用 `blue check` 区分是不是 `config.org` 的问题                                                                                                         |

磁盘清理走系统自带 timer（每周日 18:00 `guix gc`、19:30 nix-gc）或 `blue gc`（删旧世代 + `guix gc` + 清 `/efi/EFI/Guix/OLD-*.EFI`，见 [scripts/blueprint.md](scripts/blueprint.md)）。

## 相关

- `tools/emergency-blue.sh`——应急脚本本体
- [scripts/blue-helpers.md](scripts/blue-helpers.md) §bootstrap.sh——恢复 blue 的引导 shell
- [scripts/blueprint.md](scripts/blueprint.md)——blue 完整管线、维护命令与世代修剪
