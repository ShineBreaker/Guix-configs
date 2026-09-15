# kernel/ — CachyOS LTS 裁剪内核配置指南

本目录是自包含的 Linux 内核定义与裁剪体系：`source/config.org` 的 `cachyos-lts-kernel` 代码块仅需一行代码载入 `linux-cachyos-lts.scm`。内核版本、源码来源、上游 Defconfig 引用、通用桌面优化以及针对具体设备的裁剪清单，**全部在本目录内集中维护**。

---

## 1. 目录结构与文件职责

| 文件 / 路径                    | 核心职责                                                                                            | 维护规则                                      |
| ------------------------------ | --------------------------------------------------------------------------------------------------- | --------------------------------------------- |
| `linux-cachyos-lts.scm`        | 内核包定义（`%cachyos-lts-version` + Origin）、通用桌面配置片段 `%kernel-common-configs` 与组装逻辑 | **版本升级入口**；导出 `linux-cachyos-lts` 包 |
| `defconfig-cachyos-lts`        | 上游纯净 Defconfig 模板（来自 Hako kernel-config）                                                  | **禁止手动编辑**，仅随上游版本整体替换        |
| `machines/<设备>.scm`          | 设备层配置：硬件特性钉住（Pin）与裁剪读取，导出 `%machine-configs`                                  | 文件头部记录实机硬件探针数据（裁剪依据）      |
| `machines/<设备>-trim.kconfig` | 针对非本机硬件的大类反选清单（~2000 行，裸符号表示 `=n`）                                           | 与 Defconfig 结构对齐，按硬件大类注释分组     |
| `install.sh` / `rollback.sh`   | 运维脚本：供用户手动执行内核构建部署与一键回滚                                                      | Agent 禁止直接运行，由用户手动触发            |

### 配置片段拼合顺序

```
通用桌面档 (%kernel-common-configs) → 设备硬件钉住 (Pin) → 大类裁剪 (Trim)
```

> **覆盖规则**：在 `modify-defconfig` 中**同键后者胜**（钉住优先于反选）；同一配置符号若在同层重复出现会触发构建校验错误。

---

## 2. 日常维护路径

### 2.1 内核版本升级（最常见）

1. 计算上游源码包的 Base32 Hash：
   ```bash
   guix hash <linux-cachyos-新版本.tar.gz>
   ```
2. 修改 `linux-cachyos-lts.scm` 中的 `%cachyos-lts-version` 与 `origin` 内的 `(content-hash "...")`（必须使用字符串单参数形式）。
3. 执行下文的验证流程。

### 2.2 迁移到新硬件平台

1. **采集硬件事实**：在新设备上收集 `lspci -nnk`、`lsusb`、`lsmod`、`cat /proc/asound/cards` 等信息，写入新 `machines/<新设备>.scm` 头部。
2. **生成裁剪清单**：钉住本机必需硬件驱动（`=m` 或 `=y`），并在 `<新设备>-trim.kconfig` 中反选非本机大类硬件（如各类 RAID 卡、冷门网卡等）。
3. **切换引用**：在 `linux-cachyos-lts.scm` 中调整 load 的设备文件名，并执行构建验证。

---

## 3. 验证流程（修改 Kconfig 后必做）

```bash
# 1. 语法与括号检查
blue check

# 2. 生成 tmp/config.scm（无副作用）
blue --dry-run rebuild

# 3. 触发真实内核构建（校验 configure 阶段的 verify-config）
# probe 文件放在仓库 tmp/ 内，通过 (current-filename) 自定位，
# 无需写死仓库绝对路径（config.scm 内部本就是相对 load）。
cat > tmp/kernel-probe.scm <<'EOF'
(begin
  (chdir (dirname (current-filename)))
  (set! %load-path (cons "." %load-path))
  (primitive-load "config.scm")
  linux-cachyos-lts)
EOF

guix time-machine -C source/channel.lock -- build -f tmp/kernel-probe.scm
```

> **构建失败排查**：`verify-config` 阶段会逐条打印 mismatch 的符号。可直接进入保留的失败构建目录 `/tmp/guix-build-linux-cachyos-lts-*.drv-0` 执行 `make ARCH=x86_64 guix_defconfig` 快速复现调试，根据提示调整 pin 或 trim 清单。

---

## 4. 裁剪方法论与关键陷阱

<critical>
1. **Default-Y 菜单门控翻转**：上游 savedefconfig 风格的配置省略了部分 default-y 的总线门控（如 `NETDEVICES`、`WLAN`、`ETHERNET`、`IIO` 等）。若门控意外翻成 `n` 会导致整个子系统（如 WiFi、网卡）被连带剔除。这些门控已在通用档头部显式钉住，**严禁删除**。
2. **符号三态与隐式依赖**：
   - 仅有 Prompt 的用户可见符号可反选；由其他符号 `select` 的隐式符号无法通过写 `=n` 裁剪（会被 `verify-config` 拦截）。
   - 依赖不满足时写 `n` 仅输出无害警告。
3. **6.18+ 符号命名变更**：Thunderbolt 驱动已并入 USB4（Kconfig 命名空间变为 `USB4`，模块名仍叫 `thunderbolt`）；Intel 声卡 Mach 符号需带有 `SND_SOC_INTEL_` 前缀。
4. **本机不可裁剪的特殊项**：
   - `CONFIG_MTD_SPI_NOR=m`：本机 BIOS 闪存访问必需（对应 `/dev/mtd0-3`）。
   - Initrd 模块依赖全套（在通用档尾部，对应 `%default-initrd-modules`）。
5. **MAXSMP 约束**：上游 defconfig 包含 `CONFIG_MAXSMP=y`，它会强制锁定 `NR_CPUS=8192`。必须先显式反选 `CONFIG_MAXSMP=n`，才能将 `CONFIG_NR_CPUS` 设定为实际核心数（如 64），从而减少位图内存开销。
</critical>

---

## 5. 消融实验与优化结论

所有内核调优均通过 QEMU 无盘基准压测与双轮噪声比对验证（数据位于 `/var/tmp/kopt/`）：

- **已落地的优化**：
  - `CONFIG_MAXSMP=n` + `CONFIG_NR_CPUS=64`：使 CPU 位图回到栈上，系统调用吞吐提升 4.6%，Fork 性能提升 1.7%。
  - 关闭 `NUMA_BALANCING`（单 Node 拓扑设备无性能倒退）。
  - 关闭调试用的 `SCHEDSTATS` 与冗余 Tracer。
- **未采纳的方案（收益不足以抵消代价）**：
  - `spectre_bhi=off`：在 MTL 架构（具备 BHI_DIS_S 硬件缓解）上无明显收益，保持默认安全策略。
  - `init_on_alloc=0` / `init_on_free=0`：微基准增益在噪声带边缘，不足以抵消内核内存安全硬化损失。
  - Clang ThinLTO / AutoFDO：增量微弱（1~3%）但极大增加跨编译与外部模块（v4l2loopback 等）的复杂度。

---

## 6. 对拍复验（大改与重构后的校验方法）

1. **配置层比对**：提取运行中内核的 `/proc/config.gz` 与新构建产物的 `.config` 进行 `y`/`m`/`n` 三态差异对比。
2. **模块层比对**：将运行时的 `lsmod` 输出与新产物 `lib/modules/` 下的 `.ko` 列表进行比对（注意：内核模块文件名中的连字符 `-` 与 `lsmod` 中的下划线 `_` 需归一化后再比对）。
3. **重构零变化校验**：记录重构前后的 `.config` MD5 哈希，确保重构过程未意外引入语义漂移。
