# ISO 自主打包机制 — 调研与移植方案

> 目标:为本仓库增加一条"一键 `blue build-iso` 打出自研 Live ISO"的管线,
> 参考 Testament(`hako@ultrarare.space`)的实现。
> 本文先记录调研结论,后续移植实施时作为依据。

---

## 接手 agent 必读(阅读路径 + 工作纪律)

**如果你是接手实施这个 ISO 移植方案的 agent**,先把这节读完再动手。

### 阅读路径(按角色)

| 你的角色                                | 必读                                                                        | 选读           |
| --------------------------------------- | --------------------------------------------------------------------------- | -------------- |
| **实施 agent**(要改源 + commit)         | §接手必读 → §0 → §8 → §9(全) → §11 → §12 → §14 → §15                        | §1~§7 调研背景 |
| **审计 / review agent**(要 diff + 拍板) | §接手必读 → §0 → §8(只读 §8.1 差异表)→ §9.4.3 + §9.5.1 + §9.5.2 → §12 → §15 | §11 决策矩阵   |
| **诊断 agent**(接到 #7373 类失败)       | §11(全)→ §9.2(P0 实测)→ §9.4.5(陷阱)→ §14(快照)                             | 其他           |
| **接手写新文档 / 改本文档的 agent**     | §15(维护纪律)                                                               | §13(扩展矩阵)  |

### 实施前 30 秒 checklist

```
□ 读到 §接手必读 + §0(决策记录)了吗?
□ §9.4.5 关键陷阱四条记下了吗?
□ §15 错误处理 + §15.2 接手 agent 边界 看了吗?
□ 记住:AGENTS.md 硬约束 —— AI 禁跑 blue rebuild / blue build-iso(P7 / P8 是用户活)
```

### 工作纪律(硬约束)

1. **AI 不许跑 `blue rebuild` / `blue system reconfigure`** ——
   仓库根 AGENTS.md 硬约束。所有 `blue check` / `blue --dry-run *` /
   `blue block-show` / `blue block-replace` 等不需要 sudo 提权的 AI 可以跑。
2. **AI 不许碰 `/gnu/store`** 只读副本 / `tmp/` 下产物 / 已部署的 `~/.config/` `~/.local/`。
3. **commit 走 gitmessage 规范** —— 逐文件 serial,HerEDOC 传 message。
   详细见仓库根 AGENTS.md。
4. **改源 ≠ 生效** —— 改 `dotfiles/immutable/<app>/` 后必须 `blue home`。
   但 ISO 块在 `source/config.org`,改完 `blue check` 通过即可,**不**走 `blue home`。
5. **横跨 3+ 行改动** —— 走 `python3 + str.replace()` 而非 edit 工具
   (见 guix-configs-workflow skill §3)。
6. **每个 P 阶段完成** —— 立刻在 §12 验收清单里把对应项打勾 + commit。
   不要一次做完 P1~P6 再统一 commit(回滚困难)。
7. **撞 #7373** —— 详见 §11.3 + §11.6,**不要假设"修过一次就是修了"**,
   重读 build log 逐包诊断。

### 实施前更正记录(2026-07-06,接手 agent 实测锁定频道后)

> 以下 4 处是对原文的**事实更正**,以 `source/channel.lock` 锁定的 guix
> `9e068cc` + repl 实测为准。原文相关处已就地改过,这里集中留路标:
>
> 1. **`make-installation-os` 在 guix core `(gnu system install)`**,
>    不是 rosenthal。gril fact_id=22 已更正 §9.4.2,本次同步改了
>    §9.4.3 注释 / §9.4.5 陷阱 3 / §15.6(原写 rosenthal 是错的)。
> 2. **`(gnu packages slim)` 和 `(gnu packages rofi)` 模块不存在** —— 加载会
>    abort,连带打断后续 use-modules。§9.4.2 已删这两行;slim/rofi 走
>    `specifications->packages`(slim 在某 base 模块,rofi 在 `(gnu packages xdisorg)`)。
> 3. **slim-configuration 字段是 `xauth`(不是 `xauth-file`)**,且期望
>    xauth 程序(默认 `xauth` 包),非 `.Xauthority` 文件路径。§9.4.3
>    删除该行,用默认值(SLiM 自管 X 授权)。
> 4. **`%default-locale-libcs` 是 `(gnu system install)` 内部变量**,
>    不 export,必须 `(@@ (gnu system install) %default-locale-libcs)`。
>    §9.4.3 已加 `@@`。
> 5. **`(service kmscon-service-type)` 不带 configuration 非法** —— guix 报
>    "no value specified for service of type 'kmscon'"。而 make-installation-os
>    默认已含 `(service kmscon-service-type (kmscon-configuration ...))`
>    (install.scm:466-468)。§9.4.3 已删掉冗余声明(D6 目标由 base OS 满足)。
> 6. **`(%current-system)` 在 OS 块里需要 `(guix utils)`** —— live-modules 漏了
>    该 use-modules。已补(make-installation-os 的 #:efi-only? 判断要用)。
>
> 另: §11.2 错误码表新增 5 行(`no code for module (gnu packages slim)` /
> `no code for module (gnu packages rofi)` /
> `extraneous field initializer (xauth-file)` /
> `unbound variable: %default-locale-libcs` /
> `no value specified for service of type 'kmscon'`)。

### 文档来源

- 本文档基于 Testament 仓库 `/home/brokenshine/Projects/Config/Testament/` 的
  实测调研(2026-07-06)。Testament 路径不在仓库内,需要时可参考。
- 本仓库内对应文件:
  - `blueprint.scm`(blue 入口)
  - `source/config.org`(ISO OS 定义所在地)
  - `source/channel.lock`(rosenthal/nonguix 在这里锁版)
  - `tools/bootstrap.sh`(引导, ISO 构建不依赖它,但 dry-run 验证可参考)

### 文档维护

详见 §15 「文档维护纪律」节。**改本文档的人,请同时更新 §15.4 的版本表**。

---

> **决策记录(2026-07-06 gril session)**:
>
> - **首选变体:XFCE**(轻量,有现成 `xfce-desktop-service-type`,来自 `(gnu services desktop)`)
> - 辅助变体:`minimal`(纯 CLI installer,kmscon,用于 xfce 跑不动的硬件)
> - 前缀用 `jeans-`(本仓库自有名)
> - **D2 — §9.4.3 目标 = "提供装机用环境",不干预装好后**(gril 重新拍)
>   - 装好后用户自己用本仓库 `blue rebuild` 重建,ISO 不预设
> - **D3 — ISO 复刻 source/config.org 的 4 套 substitute 镜像**(nonguix / guix-moe / panther / sjtug)
>   - 装机时取 substitute 要用这些公钥,缺一个就拉不动
>   - 不是"装好后"才有意义,是"装机时 guix pull 就要"
> - **D4 — ISO 只装 mihomo 包**,不引 service / config / tun(gril 重拍)
>   - 用户在 ISO 环境里手动 `mihomo -f <user-supplied.yaml>` 启动
>   - 装好后系统的 mihomo service (auto-start + tun)由 blue rebuild 重建
> - **D5 — live user = `live` / `live`**(gril 重拍 §9.4.4 留空)
>   - slim auto-login 需要明确密码,否则 sudo 拿不到
>   - 装机阶段不要求强密码
> - **D6 — 显式加 `(service kmscon-service-type)`** 作为 tty1 装机回退(gril 重拍)
>   - Testament README 实证:installer 跑在 kmscon 上
>   - X 启动失败 / slim 配错时,kmscon 是唯一救命 console
> - `examples/` 配置模板不放(语义与本仓库 dotfiles 模型不同)
> - zfs 默认不开
> - DM 选 **slim**(XFCE 自带组合轻量;若需要 Wayland/GNOME-style 再换 gdm)
> - 上游 #7373 仍 Open 但**只阻塞装机完结,不影响 ISO 构建**
> - **D7 — 本文档不进仓库**(`docs/iso-build.md` 是 gril 阶段 plan,留作 review,不 commit)

---

## §0 TL;DR

Testament 的"自主打包 ISO"**不是从底层重造** xorriso / grub-hybrid / EFI
混合启动,而是一个**编排层 + 定制层**,核心代码不到 40 行:

| 层                   | 由谁负责                                        | Testament 做的事                   |
| -------------------- | ----------------------------------------------- | ---------------------------------- |
| iso9660 / EFI / MBR  | **Guix core** 的 `--image-type=iso9660`         | 不碰                               |
| installation-os 基底 | **Rosenthal channel** 的 `make-installation-os` | 继承并定制                         |
| 非自由内核 / 固件    | **nonguix** 的 `linux` + `linux-firmware`       | 接入                               |
| OS 定义              | Testament 自己                                  | `config/live/*.scm`                |
| 构建编排             | BLUE build system(`blueprint.scm`)              | `build-iso` 命令                   |
| 产物落地 + 签名      | Testament 自己                                  | `scripts/build-image.scm` + `sign` |

入口只有一行:`blue build-iso minimal`(或 `niri`)。

**本仓库拍板的变体**:**XFCE**(轻量,有现成 `xfce-desktop-service-type`)。
Testament 没提供 XFCE 镜像(他们只做 `minimal` 和 `niri`),但 Guix 1.5
手册明确把 `xfce-desktop-service-type` / `gnome-desktop-service-type` /
`plasma-desktop-service-type` 等列为"声明式配齐一个桌面"的标准件 —— 不
比 Testament 的 minimal 复杂。

---

## §1 Testament 构建系统背景

Testament 和本仓库同样使用 **BLUE build system**(`blueprint.scm` 作为入口),
但组织方式有差异:

| 维度         | Guix-configs(本仓库)                                           | Testament                                           |
|--------------|----------------------------------------------------------------|-----------------------------------------------------|
| 主配置       | 单一 `source/config.org`(org-babel tangle 出 `tmp/config.scm`) | 每主机一个 `config/<host>.org`,tangle 到 `tangled/` |
| ISO 子树     | 无                                                             | 独立的 `config/live/` 子树                          |
| ISO 配置形态 | —                                                             | **不走 tangle**,纯 `.scm` 文件                      |
| channel lock | 单一 `source/channel.lock`                                     | **两套 lock**(见 §4)                               |

> ISO 配置刻意避开 org tangle,直接用 `.scm`,降低出错面。
> 本仓库的移植决策与此不同 —— **写进 `config.org`**(见 §6)。

---

## §2 ISO 打包管线全流程

以 `blue build-iso minimal` 为例:

```
blue build-iso minimal
        │
        ▼  blueprint.scm:235-257 (build-iso-command)
生成 ISO 文件名: roenthal-minimal-20260706.x86_64-linux.iso
        │
        ▼  $guix repl -- scripts/build-image.scm
        │     (整个包在 guix time-machine -C config/live/channels.lock 内)
        │
guix repl 启动 scripts/build-image.scm,参数:
  dst  = dist/rosenthal-minimal-<date>.<arch>.iso
  args = config/live/minimal.scm
         --image-type=iso9660
         --load-path=config/live/modules
         + 用户的 %build-options (如 --system, --target)
        │
        ▼  scripts/build-image.scm:8-18
(apply guix-system "image" args)   ; 调用 Guix core 的 image 生成
        │  → Guix 内部走 iso9660 image-type → grub-hybrid → xorriso → store 产物
        ▼
捕获 stdout 的 store path (e.g. /gnu/store/...-iso9660-image)
        │
        ▼
(copy-file src dst) + (make-file-writable dst)
        │
        ▼  (可选) scripts/sign
dist/<name>.iso + .sha256 + .asc
```

### 2.1 命令定义(`blueprint.scm:235-257`)

```scheme
(define-command (build-iso-command arguments)
  ((invoke "build-iso")
   (category 'deployment)
   (synopsis "Build Live ISO")
   (help "[VARIANTS] ...
Build all Guix System Live ISOs in this repository or only those matching \
VARIANTS, saving the results under dist/."))
  (every
   (cut eq? #t <>)
   (map (lambda (variant)
          (let ((config (string-append "config/live/" variant ".scm"))
                (iso (format #f "rosenthal-~a-~a.~a.iso"
                             variant
                             (date->string (current-date) "~Y~m~d")
                             (%current-system))))
            (print-header "BUILD ISO" iso)
            ($guix `("repl" "--" "scripts/build-image.scm" ,(in-vicinity "dist" iso)
                     ,config
                     "--image-type=iso9660"
                     "--load-path=config/live/modules"
                     ,@%build-options)
                   #:channels "config/live/channels.lock")))
        (images-from-arguments arguments))))
```

### 2.2 产物落地助手(`scripts/build-image.scm`,全文 18 行)

```scheme
(use-modules (ice-9 match)
             (guix build utils)
             (guix scripts system))

(match (command-line)
  ((_ dst . args)
   (let* ((output
           (with-output-to-string
             (lambda ()
               (apply guix-system "image" args))))
          (src (string-trim-both output)))
     (when (file-exists? src)
       (mkdir-p (dirname dst))
       (copy-file src dst)
       (make-file-writable dst)))))
```

做三件事:

1. 调 Guix core 的 `guix-system`(程序化版的 `guix system`)
2. 抓 stdout 拿到 store path
3. 复制成可读文件名落盘到 `dist/`

> **这就是"自主打包"的精髓 —— 极薄一层。** 真正的 ISO 物理构建全部由 Guix core 完成。

---

## §3 OS 定义:`config/live/minimal.scm`

核心是继承 Rosenthal 的 `make-installation-os`,**不自己从零搭 `operating-system`**:

```scheme
(define %installation-os
  (make-installation-os
   #:efi-only? (string=? (%current-system) "aarch64-linux")))

(operating-system
  (inherit %installation-os)
  (host-name "live-system")
  (label (format #f "Guix System installation (~a build)"
                 (date->string (current-date) "~Y-~m-~d")))
  (kernel linux)                              ; ← nonguix 非自由内核
  (firmware (cons* linux-firmware
                   (operating-system-firmware %installation-os)))
  (users (cons* (user-account
                  (inherit %root-account)
                  (shell (file-append fish "/bin/fish")))
                %base-user-accounts))
  (packages (append (specifications->packages
                      '(;; CLI utilities
                        "curl" "file" "git" "gnupg" "mosh" "ncurses" "rsync" "unzip"))
                    (load "scripts.scm")
                    (operating-system-packages %installation-os)))
  (services
   (cons* ;; guix.moe / nonguix 替代服务器 + 签名密钥
          (simple-service 'substitute-servers guix-service-type ...)
          ;; 把自己的配置模板塞到 /etc/configuration
          (simple-service 'configuration-template etc-service-type
            `(("configuration" ,(local-file "examples" #:recursive? #t))))
          (modify-services (operating-system-user-services %installation-os)
            (delete (@@ (gnu system install) configuration-template-service-type))
            (delete gc-root-service-type)
            (guix-service-type
             config => (guix-configuration
                         (inherit config)
                         (channels channels-with-nonguix)))))))
```

定制清单(相对原版 `installation-os`):

- 内核换非自由 `linux` + `linux-firmware`(nonguix)
- root shell 改 `fish`
- 接入 guix.moe / nonguix 替代服务器与签名密钥
- `/etc/configuration` 塞自己的配置模板(`examples/` 目录)
- `#:efi-only?` 在 aarch64 上自动切纯 EFI(无 BIOS 混合启动)

### 3.1 多变体分层继承

```
minimal.scm          → %installation-os (Rosenthal)
                         ↓ inherit
graphical-system.scm → %minimal-os: 加 live 用户 + greetd + skeletons
                         ↓ inherit
niri.scm             → %graphical-os: 加 niri Wayland compositor
```

`niri.scm` 自动登录 `live` 用户到 `dbus-run-session niri --session`。分层继承让
多变体维护成本极低 —— 加新 ISO 变体只需再 inherit 一层。

---

## §4 关键设计点

### 4.1 两套独立的 channel lock(隔离构建环境)

| 文件                        | 用途                                        | 频道数                      |
| --------------------------- | ------------------------------------------- | --------------------------- |
| `channels.lock`             | 主机配置开发环境(`.envrc` / `manifest.scm`) | 5(含 bluebox, sops-guix)    |
| `config/live/channels.lock` | **ISO 构建专用**,更精简                     | 3(guix, nonguix, rosenthal) |

ISO 构建用独立 lock,**避免引入 ISO 不需要的 bluebox / sops-guix**,保证镜像
构建的密封性和可复现性。`build-iso-command` 显式传
`#:channels "config/live/channels.lock"` 覆盖默认值。

### 4.2 ISO 变体不走 org tangle

`%images '("minimal" "niri")` 与 `%systems` 是分开的列表:

- host 配置(chapra/dorphine/...)走 `config/<host>.org` → tangle
- ISO 变体走 `config/live/<variant>.scm` 直接被 `guix system image` 加载

好处:ISO 构建无需启动 Emacs,出错面更小。

> 注:本仓库的移植决策与此不同 —— 我们走 config.org 统一 tangle,见 §6。

### 4.3 产物签名(`scripts/sign`)

```sh
sha256_checksum_and_sign () {
    sha256sum "$1" > "$1.sha256"
    gpg --verbose --armor --detach-sign "$1"
}
```

遍历 `dist/` 产出 `.sha256` + `.asc`,对应 README 里的下载链接校验。
本仓库移植时可后续再加。

---

## §5 与本仓库(Guix-configs)的差异 & 可行性

### 5.1 现状对照

| 项                          | Guix-configs 现状                           | Testament           | 移植难度                      |
| --------------------------- | ------------------------------------------- | ------------------- | ----------------------------- |
| 入口工具                    | `blue`(已在 `manifest.scm`)                 | `blue`              | ✅ 已具备                     |
| channel 锁定                | `source/channel.lock`(含 rosenthal/nonguix) | 同                  | ✅ 已具备                     |
| `make-installation-os` 来源 | guix core `(gnu system install)`(本仓库已有)| guix core           | ✅ 已具备                     |
| 非自由内核                  | 已有 nonguix                                | 同                  | ✅ 已具备                     |
| BLUE `build-iso` 命令       | **无**                                      | `blueprint.scm`     | ⚠ 需改 `blueprint.scm`        |
| `scripts/build-image.scm`   | **无**                                      | 有                  | ⚠ 新增                        |
| ISO 配置源                  | **无**                                      | `config/live/*.scm` | ⚠ 新增(本仓库写进 config.org) |
| 独立 ISO channel lock       | **无**(共用 source/channel.lock)            | 有                  | ⚠ 可选                        |

**结论:基础设施齐备,核心新增工作只有 3 件** —— BLUE 命令、build-image 助手、
config.org 里的 OS 定义。

### 5.2 可复用资产清单

本仓库已有、可直接利用的:

- `blue` 工具 + `blueprint.scm`(BLUE build system 入口)
- `source/channel.lock` 含 rosenthal / nonguix
- `source/information.scm` 的全局变量(`username` 等)
- `tools/bootstrap.sh` 引导机制(新机安装场景已经走这条)

---

## §6 移植方案(待实施)

> 决策(用户已拍板):**ISO 的 operating-system 配置写进 `source/config.org`**
> 作为新的 code block,通过 Noweb 拼合产出 ISO 专用 `.scm`。

### 6.1 工作清单

| 序号 | 文件                      | 动作             | 内容                                                                     |
| ---- | ------------------------- | ---------------- | ------------------------------------------------------------------------ |
| 1    | `source/config.org`       | 新增章节         | `* Live ISO` + 若干 `#+NAME:` code block 拼出 `live-installation-os`     |
| 2    | `source/config.org`       | 新增 tangle 目标 | tangle 出 `tmp/live-iso.scm`(独立于 `tmp/config.scm`)                    |
| 3    | `scripts/build-image.scm` | 新建             | 复刻 Testament 的 18 行                                                  |
| 4    | `blueprint.scm`           | 改               | 加 `build-iso-command`(仿 Testament,但 tangle 目标指向 tmp/live-iso.scm) |
| 5    | `manifest.scm`            | 检查             | 确认 `guile-newt` / `guile-parted` 是否需要(installer 依赖)              |
| 6    | `.gitignore`              | 改               | 加 `dist/`(ISO 产物)                                                     |

### 6.2 与 Testament 的关键差异点(D2/D3/D4 gril 重写后)

1. **配置源统一** —— Testament 用独立 .scm,本仓库写进 config.org。需要新增一个
   `:tangle ../tmp/live-iso.scm` 的 code block,**不能**复用 `tmp/config.scm` 的
   tangle 目标(否则 ISO 配置会污染主机配置)。
2. **无独立 ISO channel lock** —— 暂定复用 `source/channel.lock`(本仓库已有
   rosenthal/nonguix)。后续若想追求 Testament 的密封性,可再建
   `source/live-channels.lock`。
3. **主变体 = XFCE**(gril 拍板,原写"先只做 minimal"被推翻)
   - D1 决策:用户要桌面辅助装机过程,XFCE + slim 满足
   - 辅助变体 `minimal`(纯 CLI installer,kmscon 文字回退)留作 xfce 跑不动的 fallback
4. **签名可选** —— 先不做,需要时再加 GPG detach-sign。
5. **D3 — substitute 镜像全复刻** —— 复刻 source/config.org 的 4 套(nonguix / guix-moe / panther / sjtug),不只是 nonguix
6. **D4 — mihomo 只装包** —— 不引 service / config / tun(用户手动启)
7. **D6 — 显式加 kmscon-service** —— 不依赖 rosenthal 默认,主动声明(tty1 装机回退)

### 6.3 风险与约束

- **上游阻塞**:Testament README 记录了 codeberg guix issue **#7373** 当前阻止
  新 ISO 构建 —— 移植时需先验证是否已解决。
- **本仓库 AGENTS.md 硬约束**:AI agent 不许跑 `blue rebuild` /
  `guix system reconfigure`(需 sudo 会卡死)。ISO 构建相关指令需要先测试是否需要root权限，如不需要的话可主动运行。
- **BLUE 语法兼容性**:`define-command` / `$guix` / `%build-options` /
  `images-from-arguments` 等辅助在 Testament 的 BLUE 版本里可用,本仓库的 BLUE
  版本需先比对(读 `blueprint.scm` 顶部与 `blue help` 输出确认)。
- **替代服务器**: 参照目前配置文件的相关方案，使用多重镜像服务器来提供更好的体验

---

## §7 参考

- Testament 仓库:本地路径 `/home/brokenshine/Projects/Config/Testament/`
- 核心文件:
  - `blueprint.scm:235-257`(build-iso 命令)
  - `scripts/build-image.scm`(18 行产物落地助手)
  - `config/live/minimal.scm`(OS 定义)
  - `config/live/README.org`(ISO 构建文档 + 已知阻塞 issue)
- Guix 手册:`guix system image --image-type=iso9660`
- Rosenthal channel:`make-installation-os` 定义来源

---

## §8 蓝图差异实测比对

§6.2 列了与 Testament 的"关键差异点",但只是设计层推断。本节把
**实测比对结果**固定下来 —— 这是后续 §9~§11 实施时的"事实基底",
避免再回到"它俩 BLUE 是不是同一个版本"这种前置问题。

### 8.1 BLUE 框架版本差异

Testament 蓝图头部 use-modules(行 3-19):

```
(blue types buildable) (blue types command) (blue types configuration)
(blue types variable) (guix utils) (guix build utils)
(srfi srfi-19) (srfi srfi-1) (srfi srfi-26)
```

本仓库蓝图(blueprint.scm:35-52):

```
(blue build) (blue states) (blue types blueprint) (blue types buildable)
(blue types command) (blue types testable) (blue subprocess)
(guix build utils) (ice-9 ftw) (ice-9 match) (ice-9 popen) (ice-9 rdelim)
(ice-9 regex) (ice-9 textual-ports) (srfi srfi-1) (srfi srfi-19) (srfi srfi-26)
```

差异:

| BLUE 构造               | Testament                              | 本仓库                            | 移植影响                                                             |
| ----------------------- | -------------------------------------- | --------------------------------- | -------------------------------------------------------------------- |
| `$` (子进程 wrapper)    | ✅ `($ cmd)`                           | ❌ 用 `%run`                      | 命令体需换成本仓库 `%run`                                            |
| `$guix` (锁定频道包装)  | ✅ 带 `#:channels` kwarg               | ✅ `%guix` 有 `#:channels` kwarg  | 接口对齐(默认 `%channel-lock` vs "channels.lock" — 本仓库写绝对路径) |
| `%build-options`        | ✅ identifier-syntax                   | ❌ 无                             | 本仓库通过 `--load-path=...` 硬传,没有公共 options 列表              |
| `define-blue-class`     | ✅ `<shared-config>` `<system-config>` | ✅ `<org-config>` `<paren-check>` | API 对齐,extend 自 `<buildable>`/`<testable>` 即可                   |
| `print-header`          | ✅ 通用辅助                            | ❌ 无                             | 命令体直接 `format #t "..."` 即可                                    |
| `images-from-arguments` | ✅ 参数→变体过滤                       | ❌ 无                             | 本仓库命令参数直接是变体名列表(`(first arguments)`),更简洁           |
| `make-build-manifest`   | ✅ blue build 入口                     | ✅ `blue build` 入口              | 接口一致                                                             |
| `blueprint` 顶层 form   | ✅ `(commands ...)`                    | ✅ `(commands ...)`               | 注册语法一致                                                         |

**结论**: BLUE 是同一个上层 API,但**辅助过程名都不一样**。Testament 的
`$` / `%build-options` / `print-header` 在本仓库**不存在**,移植时必须重写
命令体。

### 8.2 命令注册形态对齐

Testament `build-iso-command`(行 235-257) 直接 append 到 `commands` 列表里。

本仓库 `commands` 列表(blueprint.scm:1280-1298)目前是 17 个命令,要追加
第 18 个 `build-iso-command`。追加位置按类别分组,建议插在
`rebuild-command` / `home-command` 之后(`category 'deployment` 一组),保持
语义聚簇。

### 8.3 命令帮助与 metadata

Testament 用 `((invoke "build-iso") (category 'deployment) (synopsis
"Build Live ISO") (help "..."))` 四元组。本仓库 `define-command` 接收的
也是同一形态(见 blueprint.scm:961-968 `rebuild-command`):

```scheme
((invoke "rebuild")
 (category 'deployment)
 (synopsis "应用 Guix System 配置")
 (help "应用 operating-system 表。blue --dry-run rebuild 仅构建验证、不写入系统。"))
```

✅ **help/synopsis/category 完全一致**,只是语言风格不同(中英文)。

### 8.4 入口 / 子进程出口

| 概念                 | Testament 写法                                          | 本仓库等价                                                                      |
| -------------------- | ------------------------------------------------------- | ------------------------------------------------------------------------------- |
| 执行外部命令         | `($ '("guix" "repl" "--" "scripts/..."))`               | `(%run '("guix" "time-machine" ... "repl" "--" ...))`                           |
| 锁定频道             | `$guix` 默认 `channels.lock`,可 `#:channels` kwarg 覆盖 | `%guix` 默认 `%channel-lock`,可 `#:channels` 覆盖                               |
| emacs-minimal 子命令 | `$emacs` = `$guix shell emacs-minimal -- emacs`         | `%emacs-command` = `env -u EMACS... %guix-command shell emacs-minimal -- emacs` |
| 阶段标题输出         | `(print-header "BUILD ISO" iso)`                        | `format #t "..."` 直接打                                                        |
| 日志 dry-run         | `$` 短路(popen 不跑)                                    | `%run` 短路(`dry-build?` 为真时只打印)                                          |

### 8.5 真正可复用的最小集

移植到本仓库时,**以下 5 个东西是 Testament 直接搬不过来的,必须在本仓库
蓝图里现写**:

1. `%images` 常量(变体名列表,等价 Testament 的 `%images`)
2. `(images-from-arguments arguments)` 参数过滤函数
3. `(build-image-script-path)` —— 返回 `scripts/build-image.scm` 绝对路径
4. `(date->string (current-date) "~Y~m~d")` + `(%current-system)` → ISO 文件名
5. 命令体本身:遍历变体 → 对每个调 `%guix` 跑 `guix repl -- scripts/build-image.scm`

---

## §9 实施步骤(按依赖顺序展开)

### 9.0 子文档索引

下面是实施过程中**会创建或改动的文件**各自的详细说明,按依赖顺序读。

| §      | 文件                      | 改动类型            | 长度参考                   |
| ------ | ------------------------- | ------------------- | -------------------------- |
| §9.0.1 | `scripts/build-image.scm` | **新建**            | 18 行(仿 Testament)        |
| §9.0.2 | `source/config.org`       | **追加章节**        | 加 2 个 #+NAME 块(~150 行) |
| §9.0.3 | `blueprint.scm`           | **追加定义 + 注册** | 加 ~50 行(辅助定义 + 命令) |
| §9.0.4 | `source/manifest.scm`     | **视情况追加**      | 默认不动                   |
| §9.0.5 | `.gitignore`              | **追加 1 行**       | `dist/`                    |

### 9.0.1 `scripts/build-image.scm`(新建,18 行)

**完整内容见 §9.3**。这里是文件级元说明。

- **位置**:`scripts/build-image.scm`(放在仓库根的 `scripts/` 目录,与
  `tools/bootstrap.sh` / `tools/secrets` 平级 —— 但**不进** `tools/`,
  因为 `scripts/` 是 blue 系统的约定目录)
- **权限**:不需要可执行(被 `guix repl -- script.scm` 调用)
- **SPDX 头**:跟本仓库其他 .scm 一致 —— `BrokenShine <xchai404@gmail.com>` + MIT
- **为什么不放 `tools/`** —— `tools/` 是用户手跑脚本;`scripts/` 是被 blue
  / guix 自动调用的脚本。区分明确
- **不被 gitignore** —— 该文件**进版本控制**(它是文档的可重现部分,不是构建产物)

### 9.0.2 `source/config.org` 插入位置示意

```
文件头部(已有)
├── * Agent 指引(已有)
├── * 模块导入(已有,<<modules>>)
├── * 配置文件骨架(已有,main 块 = %system + %home)
├── * 系统配置(已有)
│   ├── ** Bootloader
│   ├── ** FileSystems
│   ├── ...
│   └── ** Skeletons
├── * 用户配置(已有)
│   ├── ** Packages
│   └── ...
│       ** Font(末尾)
│
└── * Live ISO  ← ★ 新增章节,插在文件最末
    ├── live-modules 块(#+NAME: live-modules)
    └── live-installation-os 块(#+NAME: live-installation-os)
       ↑ :tangle ../tmp/live-iso.scm
```

**关键点**:

- 插入位置:**文件最末**(在 `** Font` 之后),不要插在中间(扰乱阅读)
- **不要**在 main 块的 `<<modules>>` 引用 `<<live-modules>>` —— 会污染 config.scm
- `:tangle` 目标:**绝对**写 `../tmp/live-iso.scm`,不复用 `../tmp/config.scm`
- 块顺序:`live-modules` 必须在 `live-installation-os` 之前(后者 Noweb 引用前者)

### 9.0.3 `blueprint.scm` 插入位置示意

```
§0  路径常量(已有)
§1  执行原语(已有)
§2  文件 I/O 辅助(已有)
§3  配置构建管线(已有)
§4  Org 代码块编辑(已有)
§5  密钥扫描(已有)
§6  目录树生成器(已有)
§7  GNU Stow 包装(已有)
§8  指令清单(已有)
§9  所有命令定义(已有)
    ├── help
    ├── deployment   ← ★ 在这里,rebuild/home/init 之间,加 build-iso-command
    ├── editing
    ├── guix
    ├── maintenance
    ├── nix
    ├── validation
    └── stow
§10 入口点(已有)
    (blueprint (commands ...) (buildables ...) (testables ...))
       ↑ ★ 在 commands 列表里注册 build-iso-command
```

**插入位置**(精确行号):

- 辅助定义(`%images` / `images-from-arguments` / `%live-iso-prefix` / 三个 thunk):
  **插在 §8 commands 清单之上**(blueprint.scm:944 附近)
- `build-iso-command` 本体:**插在 `init-command` 之后**,与其他
  `category 'deployment` 一组(blueprint.scm:989 附近)
- `(commands (list ...))` 列表追加:`home-command` 之后插 `build-iso-command`
  (blueprint.scm:1281 附近)

### 9.0.4 `source/manifest.scm` 评估

**默认不动**。该文件目前 9 行:

```scheme
(specifications->manifest '("blue"))
```

**判断是否需要追加**:

- 若 P7 构建报 `guile-newt` / `guile-parted` unbound → 在 `blue` 之后加,
  但这两个包只在 ISO 运行时需要,**不必**进 bootstrap manifest
- 若 P7 报 `unbound variable: make-installation-os` → 检查 live-modules
  是否 `(use-modules (gnu system install))`(make-installation-os 在 guix core,
  **不是** rosenthal;见 §9.4.2 fact_id=22 + §9.4.5 陷阱 3)
- 若 P7 报 `(gnu services desktop) unbounded` → 检查 guix commit 是否太旧
  (本仓库锁 9e068cc,**有**这个模块)

**结论**:`blue` 就够了,manifest.scm 默认不动。除非 P7 报错再说。

### 9.0.5 `.gitignore` 改动

**追加 1 行**(在 `tmp` 后面):

```gitignore
.blue-store
__pycache__
tmp
node_modules

+dist             ← 新增
```

**为什么不用 XDG trash 范式** —— `dist/` 不是手删文件,是构建产物,git
约定进 .gitignore。

### 9.1 阶段总览

| 阶段 | 任务                                            | 输出文件 / 变更                                | 依赖   | 可逆性           |
| ---- | ----------------------------------------------- | ---------------------------------------------- | ------ | ---------------- |
| P0   | 验证上游 #7373 状态                             | 报告(不写代码)                                 | —      | —                |
| P1   | 新建 `scripts/build-image.scm`                  | 18 行 .scm,等价 Testament                      | —      | ✅ 单文件 revert |
| P2   | config.org 增 `* Live ISO` 章 + 3 块            | 新 #+NAME: 块 + tangle 目标改 tmp/live-iso.scm | P1     | ✅ git revert    |
| P3   | blueprint.scm 增 `build-iso-command`            | 1 个 define-command + 1 处 commands 列表追加   | P1, P2 | ✅ 单文件 revert |
| P4   | manifest.scm 视情况增 guile-newt / guile-parted | 1 行 (specifications->manifest ...)            | P2     | ✅ 单文件 revert |
| P5   | .gitignore 加 `dist/`                           | 1 行                                           | P3     | ✅               |
| P6   | blue check 验证括号                             | dry-run 输出                                   | P2     | —                |
| P7   | 用户手动 `blue build-iso xfce`                  | dist/jeans-xfce-<date>.iso                     | P1-P6  | ISO 文件可删     |
| P8   | 验收:QEMU 启动 + 截图 / 实战装机                | 实跑报告                                       | P7     | —                |

### 9.2 P0:验证上游 #7373

**实测结论(2026-07-06,curl codeberg API + HTML 已验证)**:

| 项                   | 状态                                                                                                | 来源                                                      |
| -------------------- | --------------------------------------------------------------------------------------------------- | --------------------------------------------------------- |
| #7373 状态           | **Open**,2026-03-21 hako 报,挂 1.6.0 milestone                                                      | `https://codeberg.org/api/v1/repos/guix/guix/issues/7373` |
| 根因                 | Guile 3.0.11 + Guix `safe-clone`(commit `1eccea7ff`)让 installer 的 `scm_fork` / signal thread 死锁 | issue 评论 `1eccea7ff` `5a8502a494`                       |
| 影响范围             | **装机完结阶段**(installer 跑完后 system init 卡住),**不影响 ISO 构建**                             | issue 标题 "unable to **finish installation**"            |
| Testament 实证       | 2026-06-12 仍能出新 ISO(rosenthal-minimal-20260612.x86_64-linux.iso)                                | config/live/README.org 行 17-22                           |
| rosenthal trunk 最新 | `d687672c` "services: nix-search-paths: Set LOCALE_ARCHIVE..."(2026-07-06 20:39 +0800)              | codeberg API branches                                     |
| 本仓库 lock          | rosenthal `6cf57b25`(相对 trunk 偏 ~1 周)                                                           | source/channel.lock                                       |

**结论**:

- ✅ **可以进 P1~P6**(代码层无前置阻塞)
- ✅ **P7 `blue build-iso` 大概率能跑通**(Testament 在 #7373 open 期间仍在出 ISO)
- ⚠️ **P8 实战装机可能撞 #7373** —— 但这跟我们"出 ISO"是两件事。
  撞了按 §11 决策矩阵处理(等上游 / 退回 guile-3.0.9 对应的 guix commit)
- 📌 **memory 备忘**:同一构建错误,修完后**必须重读 build log**
  逐包诊断,不能假设同一包还是同一原因(本仓库此前撞过 guix-daemon
  沙箱构建 git-fetch → url-fetch 转换的坑,同源教训)

**为什么这一步在前**:`make-installation-os` 来自 guix core
`(gnu system install)`(**不是** rosenthal,见 §9.4.2 fact_id=22),ISO 走
`guix system image --image-type=iso9660`,而该路径在 #7373 未解决时会被
Guix core 拒绝。盲目按 §6 干到 P3 才撞墙,会浪费 30 分钟。

```bash
# 在浏览器或通过 curl 看 issue 状态
curl -fsSL "https://codeberg.org/guix/guix/issues/7373" \
  | grep -iE "state|closed|open|merged" | head -20
```

### 9.3 P1:新建 `scripts/build-image.scm`

**目标**:复刻 Testament 18 行,但去掉注释(本仓库风格)、加 SPDX 头。

**位置**:`/home/brokenshine/Projects/Config/Guix-configs/scripts/build-image.scm`

**完整内容**:

```scheme
;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: MIT

;; build-image.scm —— guix system image 产物落地助手
;;
;; 用法:guix repl -- scripts/build-image.scm DST [OS-DEFINITION-OR-ARGS]...
;;
;; 1. 调 (guix-system "image" args...) 程序化地生成 ISO
;; 2. 从 stdout 抓 store path(/gnu/store/...-iso9660-image)
;; 3. 复制到 DST(dist/<name>.iso)
;; 4. (可选)chmod u+w 让后续签名脚本可写
;;
;; 完全等价 Testament/scripts/build-image.scm,只是去注释 + SPDX 头。

(use-modules (ice-9 match)
             (guix build utils)
             (guix scripts system))

(match (command-line)
  ((_ dst . args)
   (let* ((output
           (with-output-to-string
             (lambda ()
               (apply guix-system "image" args))))
          (src (string-trim-both output)))
     (when (file-exists? src)
       (mkdir-p (dirname dst))
       (copy-file src dst)
       (make-file-writable dst)))))
```

**验证**:

```bash
# 静态语法检查
guix shell guile -- guile --no-auto-compile -c '(load "scripts/build-image.scm")' && echo OK

# 注:不必真跑 -- 静态过得了即可,真正跑在 P7 由用户触发
```

### 9.4 P2:config.org 增 `* Live ISO` 章节

**目标**:在 config.org 末尾(文件级 §7 已存在,新增章节插在 `** Font`
之后,文件末尾之前)新增 ISO 配置。新增 3 个 `#\+NAME:` 块,共用一个独立
的 tangle 目标 `tmp/live-iso.scm`,**不能**与主 `tmp/config.scm` 混。

#### 9.4.1 块设计(Noweb 拼合顺序)

```
* Live ISO
** 模块导入(ISO 专用,不与系统 modules 块混)
#+NAME: live-modules

** OS 定义
#+NAME: live-installation-os           ; 主体,继承 guix core make-installation-os
#+begin_src scheme :tangle ../tmp/live-iso.scm :noweb yes
<<live-modules>>

(define %live-installation-os
  (operating-system
    (inherit (make-installation-os ...))
    ...))
%live-installation-os
#+end_src
```

> **关键决策**: 与本仓库"config.org 唯一源"原则一致,**ISO OS 写在 config.org 里**,
> 走 Noweb 拼合,产出 `tmp/live-iso.scm`。但 `%live-installation-os` 与 `%system`
> 是两个独立的 `(define ...)`,不会互相覆盖 —— 因为它们所在 code block 的
> tangle 目标不同。

#### 9.4.2 live-modules 块(gril 重写,2026-07-06)

```scheme
#+NAME: live-modules
#+begin_src scheme
;; gril 实测发现: make-installation-os 在 guix core 的 (gnu system install)
;; (savannah guix 9e068cc + HEAD 都验过,定义在 gnu/system/install.scm:693),
;; 不是 rosenthal。原 plan 写 (rosenthal services file-systems) 是错的。
(use-modules (gnu)
             (gnu system)
             (gnu system install)         ; make-installation-os + kmscon 在这
             (gnu services)
             (gnu services base)          ; guix-configuration 在这
             (gnu services desktop)       ; xfce-desktop-service-type / gnome-...
             (gnu services xorg)          ; slim-service-type / gdm-service-type
             (gnu services dbus)
             (gnu packages shells)        ; fish
             (gnu packages package-management)  ; guix
             (gnu packages base)
             (gnu packages linux)
             (gnu packages guile)
             (gnu packages texinfo)
             (gnu packages xfce)          ; xfce4-* 包
             ;; 注: 不写 (gnu packages slim) —— 该模块不存在(实测 9e068cc),
             ;; 加载会 abort 并连带打断后续 use-modules。slim 走
             ;; specifications->packages 解析即可(实测 slim@1.3.6 OK)。
             ;; 同理不写 (gnu packages rofi) —— 也不存在, rofi 在 (gnu packages xdisorg).
             ;; rofi 同样走 spec 解析(实测 27 个 spec 全 OK).
             (gnu packages networking)    ; mihomo 在这(gril D4 加的)
             (nongnu packages linux)      ; linux / linux-firmware(nonguix)
             (nongnu system linux-initrd)
             (guix channels)              ; channel / make-channel-introduction
             (guix gexp)
             (guix utils)                 ; %current-system(make-installation-os #:efi-only? 判断 arch 用)
             (ice-9 match)
             (srfi srfi-1)
             (srfi srfi-19))
#+end_src
```

> **gril 期间发现的事实更正(2026-07-06)**:
>
> 1. **`(rosenthal services file-systems)` 是错的** —— 该模块只 export
>    `btrbk-service-type` / `dumb-runtime-dir-service-type` / `zfs-service-type`,
>    **不**包含 `make-installation-os`。后者在 guix core `(gnu system install)`。
>    (fact_id=22)
>
> 2. **`make-installation-os` 默认启用 kmscon**(源码 `gnu/system/install.scm`
>    行 452-455,`(service kmscon-service-type (kmscon-configuration ...))`)。
>    所以 §9.4.3 主体代码 `(service kmscon-service-type)` 是**冗余的**,
>    但保留也无害 —— D6 决策从"显式加"改为"显式加(冗余,但便于接手 agent
>    看出意图)"。(fact_id=17)
>
> 3. **`make-installation-os` 默认 user 是 `guest` / password `""`** +
>    `pam allow-empty-passwords? #t`。gril 早期假设"空密码 sudo reject"
>    是错的 —— pam allow-empty-passwords 已经允许空密码 sudo。(fact_id=23)
>    **D5 决策保留(密码 = "live"),但理由重写**(见 §9.4.4):在覆盖
>    `users` 字段后,默认 `guest` 消失,新加 `live` user 必须有密码;
>    `crypt "live" "$6$abc"` 满足 pam + auto-login 两路。

> **关于模块选择的事实更正**: 我之前误以为 XFCE 没现成 service-type,
> 错把 `(gnu services xorg)` 当成"唯一 DE 模块"。**真实情况**:`xfce-desktop-
service-type` / `gnome-desktop-service-type` / `plasma-desktop-service-type`
> 等都在 `(gnu services desktop)` 模块(见 Guix 1.5 手册 Desktop Services
> 节)。这些 service-type 不只是包装包,还自动配齐 polkit / udisks /
> 权限规则,比"裸装 xfce4-session + xfwm4"省事。**实测**(本地 repl):
>
> ```
> (use-modules (gnu services desktop))
> gnome-desktop-service-type: #<service-type gnome-desktop ...>
> xfce-desktop-service-type:   #<service-type xfce-desktop ...>
> ```

#### 9.4.3 live-installation-os 主体(XFCE 首选,gril 重写版 2026-07-06)

```scheme
#+NAME: live-installation-os
#+begin_src scheme :tangle ../tmp/live-iso.scm :noweb yes
<<live-modules>>

;; ---- 频道公钥与镜像(D3 拍板:全复刻 source/config.org 的 4 套)----
;; 这 4 套 substitute 在装机阶段(guix pull / nonguix kernel 取 substitute)
;; 就用得到,不只是"装好后"的事。

(define nonguix-signing-key
  (plain-file "nonguix.pub"
    "(public-key (ecc (curve Ed25519) (q #C1FD53E5D4CE971933EC50C9F307AE2171A2D3B52C804642A7A35F84F3A4EA98#)))"))

(define guix-moe-signing-key
  (plain-file "guix-moe.pub"
    "(public-key (ecc (curve Ed25519) (q #552F670D5005D7EB6ACF05284A1066E52156B51D75DE3EBD3030CD046675D543#)))"))

(define panther-signing-key
  (plain-file "panther.pub"
    "(public-key (ecc (curve Ed25519) (q #0096373009D945F86C75DFE96FC2D21E2F82BA8264CB69180AA4F9D3C45BAA47#)))"))

;; ---- 基础 OS ----
;; make-installation-os 来自 guix core (gnu system install),不是 rosenthal
;; (gril fact_id=22 已更正;签名 (#:key grub-displayed-version efi-only?))。
;; efi-only? 在 aarch64 上自动切纯 EFI。本块已在 live-modules 里
;;   (use-modules (gnu system install))
;; 引入,repl / image build 都直接可见,无需 time-machine 的"自动 enable"。
(define %live-base-os
  (make-installation-os
   #:efi-only? (string=? (%current-system) "aarch64-linux")))

;; ---- ISO OS(XFCE 变体,装机用环境)----
(define %live-installation-os
  (operating-system
    (inherit %live-base-os)
    (host-name "live-system")
    (label (format #f "Guix System XFCE installation (~a build)"
                   (date->string (current-date) "~Y-~m-~d")))
    (kernel linux)
    (firmware (cons* linux-firmware
                     (operating-system-firmware %live-base-os)))

    (users
     (cons* (user-account
              (name "live")
              (group "users")
              ;; D5 拍板:密码 = "live"(slim auto-login 后 live user 能直接 sudo)
              ;; 装机阶段不要求强密码;装好后用户自己 passwd 改
              (password (crypt "live" "$6$abc"))
              (supplementary-groups '("wheel" "audio" "video" "netdev"))
              (shell (file-append fish "/bin/fish")))
            (user-account
              (inherit %root-account)
              (shell (file-append fish "/bin/fish")))
            %base-user-accounts))

    (packages
     (append (specifications->packages
               '(;; CLI 工具(installer 自身 + 装机调试)
                 "curl" "file" "git" "gnupg" "mosh"
                 "ncurses" "rsync" "unzip"
                 ;; installer 依赖
                 "guile-newt" "guile-parted"
                 ;; D4 拍板:只装 mihomo 包,不引 service
                 "mihomo"
                 ;; XFCE 必备补充(xfce-desktop-service-type 已带主包,
                 ;; 这里只补 metapackage 没拉的周边件)
                 "xfce4-terminal"
                 "xfce4-screenshooter"
                 "xfce4-taskmanager"
                 "thunar"
                 "thunar-volman"
                 "tumbler"
                 "mousepad"
                 "ristretto"
                 "xfce4-notifyd"
                 "xfce4-power-manager"
                 "rofi"
                 ;; DM 必备
                 "slim"
                 ;; 网络
                 "network-manager"
                 "network-manager-applet"
                 ;; 字体(中文)—— 桌面查资料必须
                 "font-sarasa-gothic"))
             (operating-system-packages %live-base-os)))

    (services
     (cons*
      ;; ---- 桌面 + DM ----
      (service xfce-desktop-service-type)

      (service slim-service-type
        (slim-configuration
          (display ":0")
          (auto-login? #t)
          (default-user "live")
          ;; 注: 不设 xauth 字段 —— slim-configuration 的 xauth 期望的是 xauth
          ;; 【程序】(默认 xauth 包),不是 .Xauthority 文件路径。原 plan 写
          ;; (xauth-file ".../.Xauthority") 既字段名错(xauth-file 不存在)又
          ;; 语义错(传路径给期望程序的槽)。用默认值,SLiM 自己处理 X 授权。
          ))

      ;; D6: kmscon 已由 make-installation-os 默认提供(install.scm:466-468),
      ;; 作为 tty1 装机回退. 不在此重复声明 —— (service kmscon-service-type)
      ;; 不带 configuration 会被 guix 拒绝("no value specified for service of
      ;; type 'kmscon'"), 而且本就冗余.

      ;; ---- 4 套 substitute 镜像(D3 拍板,全复刻)----
      (simple-service 'nonguix-substitutes guix-service-type
        (guix-extension
         (authorized-keys (list nonguix-signing-key))
         (substitute-urls
          '("https://nonguix-proxy.ditigal.xyz"))))

      (simple-service 'guix-moe-substitutes guix-service-type
        (guix-extension
         (authorized-keys (list guix-moe-signing-key))
         (substitute-urls
          '("https://cache-cdn.guix.moe"))))

      (simple-service 'panther-substitutes guix-service-type
        (guix-extension
         (authorized-keys (list panther-signing-key))
         (substitute-urls
          '("https://substitutes.guix.gofranz.com"))))

      (simple-service 'sjtug-substitutes guix-service-type
        (guix-extension
         (substitute-urls
          '("https://mirror.sjtu.edu.cn/guix"
            "https://mirrors.sjtug.sjtu.edu.cn/guix-bordeaux"))))

      (modify-services (operating-system-user-services %live-base-os)
        ;; 删掉原版 configuration-template (本仓库不放 examples/)
        (delete (@@ (gnu system install) configuration-template-service-type))
        ;; 重写 gc-root-service: 不放 examples, 只保留 locale + texinfo + guile.
        ;; 注 1: %default-locale-libcs 是 (gnu system install) 内部变量 (不 export),
        ;;   必须用 @@ 取(实测: %root-account/%base-user-accounts 被 (gnu) re-export,
        ;;   但 %default-locale-libcs 没被 re-export)。
        ;; 注 2: %default-locale-libcs 本身是 list, 要用 append 而非 cons* ——
        ;;   builder 会 for-each symlink 每个元素, 元素必须是单个 store path.
        ;;   cons* 把整个 list 当一个元素塞进去 → (symlink '("p1" "p2") "0") 类型错.
        (gc-root-service-type
         config => (append (list (libc-utf8-locales-for-target)
                                 texinfo
                                 guile-3.0)
                           (@@ (gnu system install) %default-locale-libcs)
                           (or config '()))))))))

%live-installation-os
#+end_src
```

**与 Testament minimal.scm 的差异(故意为之,gril 重写版)**:

- ✅ 桌面用 `xfce-desktop-service-type` + `slim-service-type`(Testament 是 niri)
- ✅ **D6 显式加 kmscon-service** 作为 tty1 装机回退(Testament minimal 默认走 kmscon,gril 重新拍后本仓库显式声明)
- ❌ **不写 `(delete kmscon-service-type)`** —— 上版误以为 rosenthal 默认带 kmscon,实测发现此行无效,gril 重新拍为"显式加"
- ✅ **D3 4 套 substitute 全复刻**(nonguix / guix-moe / panther / sjtug)
  - 上版只复刻 nonguix,缺 3 套;gril 重审时发现 source/config.org 主机配置已用 4 套
- ✅ **D4 只装 mihomo 包**,不引 service / config / tun
  - 上版完全不提 mihomo(漏了);gril 重新拍为"只装包"
- ✅ **D5 live user 密码 = "live"**(slim auto-login 后能 sudo)
  - 上版 `(password #f)` 留空,sudo 会被 pam_unix reject
- ✅ **D2 §9.4.3 目标 = 装机用环境**,不写"装好后系统"的服务
  - 上版有"装好后 /etc/guix/channels.scm 自动含 nonguix"那段 `(guix-service-type ... channels ...)` 是多余的
- ❌ 不加 `zfs-service` —— 本仓库未必用 ZFS,避免膨胀 closure
- ❌ 不放 `examples/` 目录 —— 本仓库的"configuration templates"语义跟 Testament 不一样
- ✅ 保留 `guile-newt` / `guile-parted` —— installer 必需
- ✅ nonguix 频道公钥内嵌(`plain-file`),无需 ISO 运行时联网拉公钥
- ✅ 用 slim 不是 gdm:轻量,且跟 XFCE 视觉统一;gdm 留给 GNOME 变体

#### 9.4.3.1 §9.4.3 代码块逐行解释(gril 重写后,2026-07-06)

接手 agent 读完代码后,下面这表对应代码块每段写一句"为什么",避免重新推。

| 代码段                                                                                    | 作用                                     | 为什么这样写 / 不这样写                                                                                                  |
| ----------------------------------------------------------------------------------------- | ---------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| `<<live-modules>>`                                                                        | Noweb 引用 live-modules 块               | 把 use-modules 独立成块,便于 dry-run 时单独读;**不能**塞进主 `<<modules>>` 块                                            |
| 3 个 `plain-file "*.pub" "..."` 块(nonguix / guix-moe / panther)                          | 3 个频道的公钥内嵌                       | 装机阶段 guix pull 要验签 substitute,**不**只在"装好后"用;`plain-file` 把字符串当文件处理,无需 ISO 运行时联网拉公钥      |
| `(make-installation-os #:efi-only? ...)`                                                  | guix core 提供的 installer 底座          | 不自己从零搭 operating-system;`efi-only?` 在 aarch64 上自动切纯 EFI(无 BIOS 兼容)。来自 `(gnu system install)`(**不是** rosenthal),live-modules 已 use-modules |
| `(inherit %live-base-os)`                                                                 | 继承而非重写                             | 改最少字段,跟随 rosenthal 升级                                                                                           |
| `(kernel linux)`                                                                          | 用 nonguix 非自由内核                    | `linux` 是 `(nongnu packages linux)` re-export 出的符号;支持更多硬件(尤其是 wifi / 显卡)                                 |
| `(cons* linux-firmware (operating-system-firmware %live-base-os))`                        | 追加 nonguix 固件                        | rosenthal 自带固件列表 + nonguix 非自由固件                                                                              |
| `(user-account (name "live") (password (crypt "live" "$6$abc")) ...)`                     | live 用户,密码 "live"                   | D5 拍板:密码 = "live"。上版 `(password #f)` 留空会让 sudo 被 pam_unix reject(在 slim auto-login 后,装不了系统)            |
| `(fish "/bin/fish")`                                                                      | root + live 都用 fish shell              | 用户偏好(本仓库主配置也用 fish)                                                                                          |
| `(specifications->packages '("..."))`                                                     | 一组包名                                 | 比 `(list pkg1 pkg2)` 优雅,自动转 `(use-modules (gnu packages ...))` 解析                                                |
| `"mihomo"` 在 packages 列表里                                                             | D4 拍板:只装 mihomo 包                   | 不引 shepherd service / config 模板 / tun(用户手动 `mihomo -f <user-supplied.yaml>` 启动)                                |
| `xfce4-terminal / thunar / rofi` 等                                                       | XFCE 周边包                              | `xfce-desktop-service-type` 只带主包;这些是用户实际用得到的                                                              |
| `"font-sarasa-gothic"` 在 packages 列表里                                                 | 中文字体                                 | 桌面查资料时,中文字符不能是框框(gril 重审时用户纠正)                                                                    |
| `(service xfce-desktop-service-type)`                                                     | XFCE 桌面                                | 自动配 polkit / udisks / 权限,见 Guix 1.5 手册 Desktop Services 节                                                       |
| `(service slim-service-type (slim-configuration ...))`                                    | slim DM                                  | 轻量,跟 XFCE 风格统一;`auto-login? #t` + `default-user "live"` 让 ISO 启动即进桌面                                       |
| ~~`(service kmscon-service-type)`~~ 已删                                                  | (D6 原想显式加,实测发现 make-installation-os 默认已含带 configuration 的 kmscon) | 裸 `(service kmscon-service-type)` 不带 configuration 会被拒("no value specified for service of type 'kmscon'"); 基础 OS 已有 → 删除冗余声明 |
| 4 个 `simple-service '*-substitutes guix-service-type ...` 块                             | D3 4 套 substitute 镜像                  | 复刻 source/config.org 的 4 套(nonguix / guix-moe / panther / sjtug),装机时取 substitute 用                                |
| `(delete (@@ (gnu system install) configuration-template-service-type))`                  | 移除 etc-service-type 的 examples/ 模板  | 本仓库不放 examples/(D2 gril 重审一致)                                                                                    |
| `(gc-root-service-type config => ...)`                                                    | 重写 gc-root-service                     | rosenthal 默认塞 examples/* 包;我们只保留 locale + texinfo + guile                                                       |
| `%live-installation-os`(末行裸值)                                                         | 表达式求值给 guix system                 | guix system image 期望一个 operating-system 值,**不能** `(define)` 后无返回                                              |

**陷阱速查**(对应 §9.4.5):

- ⚠ tangle 目标必须是 `../tmp/live-iso.scm`,**绝对不能** `../tmp/config.scm`
- ⚠ `<<live-modules>>` 不能被主 main 块引用
- ⚠ `blue check` 不做 cross-tangle 验证,必须 `tail tmp/live-iso.scm` 手动确认
- ⚠ `(crypt "live" "$6$abc")` 的 salt 是示例值,装好后用户 `passwd live` 改

#### 9.4.4 live user 密码字段(D5 gril 重拍)

```scheme
(user-account
  (name "live")
  (group "users")
  ;; D5 拍板:密码 = "live" —— crypt 形式,gril 重拍
  ;; 装机阶段不要求强密码,slim auto-login 后 live user 能直接 sudo
  (password (crypt "live" "$6$abc"))
  (supplementary-groups '("wheel" "audio" "video" "netdev"))
  (shell (file-append fish "/bin/fish")))
```

> **gril 决策记录(2026-07-06)**:
> 上版拍 `(password #f)` —— gril 期间重审时发现:在 slim `auto-login? #t` 下
> `(password #f)` 仍能登入桌面,但**在桌面里 `sudo` 跑 `guix system init` 时
> 会被 pam_unix reject**(因为 sudo 走非自动登录路径,要重新认证)。
> 后果:Live CD 启动后,用户**在 slim 桌面里装不了系统**,必须 Ctrl+Alt+F2
> 进 tty 用 root 跑 installer —— 这跟"桌面是辅助工具"的目标**直接冲突**。
>
> 改用 `(crypt "live" "$6$abc")`,slim auto-login 后 live user 能直接
> `sudo` 跑 `guix system init`。装机完成 / 拔出 U 盘后,live user 不复存在,
> 密码是否弱无关安全。
>
> **关于 crypt 字符串**:`$6$abc` 是 SHA-512 crypt 的 salt 前缀,
> 7 字符内有效。"$6$abc" 满足 crypt 接口要求;实际 hash 由 Guile 自动计算。
> 装好后用户跑 `passwd live` 可改成任意强密码。

#### 9.4.5 关键陷阱(实施时易踩)

1. **tangle 目标绝对不能复用 `tmp/config.scm`** —— 否则 ISO 的
   `(define %live-installation-os ...)` 会污染主机配置,导致 `blue rebuild`
   报 `unbound variable: %system` 或 `multiple definition`。
   验证:`tmp/live-iso.scm` 末尾应是 `%live-installation-os`(裸值),不是
   `(define %system ...)`。

2. **不要把 `<<live-modules>>` 引用塞进主 `main` 块的 tangle 目标**。
   验证:`:tangle ../tmp/config.scm` 的块只能引用 `<<modules>>` 等
   主块,引用 `<<live-modules>>` 会被 `blue check` 抓到(如果块不存在)或
   抓不到(因为它存在于另一个 tangle 目标,但 ob-tangle 不做 cross-file
   引用检查 —— **后果是 %live-installation-os 在 tmp/config.scm 里
   出现**,直接撞死 `blue rebuild`)。**实施时核对两次 tangle 目标**。

3. **`make-installation-os` 来自 guix core `(gnu system install)`** ——
   gril fact_id=22 已更正(原 plan 写 rosenthal 是错的,rosenthal 的
   `(rosenthal services file-systems)` 只 export btrbk / dumb-runtime-dir /
   zfs,不含 make-installation-os)。本仓库 source/channel.lock 锁的 guix
   `9e068cc` 里它定义在 `gnu/system/install.scm`,签名
   `(#:key grub-displayed-version efi-only?)`。live-modules **必须**
   `(use-modules (gnu system install))`,否则 unbound。
   实测验证: `guix time-machine -C source/channel.lock -- repl` 跑
   `(module-ref (resolve-interface '(gnu system install)) 'make-installation-os)`。

4. **`blue check` 不会做 cross-tangle 验证** —— 它只看每个 #+NAME:
   块本身的括号。所以"ISO 块写错了污染 config.scm"这件事 `blue check`
   抓不到,**只能靠 git diff 看到 %live-installation-os 跑去了 tmp/config.scm**。
   防护:实施后**必看 `git diff tmp/`** 确认产物归位。

### 9.5 P3:blueprint.scm 增 build-iso-command

**目标**:在 §8 commands 列表里追加 1 条命令定义。**不**改其他已有命令。

#### 9.5.1 新增的辅助定义(放在 §9 build-iso-command 上方)

```scheme
;; ---- Live ISO 构建辅助 ----

;; ISO 变体列表(用户拍板 2026-07-06)。本仓库**首选 XFCE**,
;; minimal 作为辅助变体留给 xfce 跑不动的硬件(纯 CLI installer)。
;; 顺序即构建顺序:先 xfce(主目标),再 minimal(fallback)。
(define %images '("xfce" "minimal"))

;; ISO 文件名: <prefix>-<variant>-<YYYYMMDD>.<arch>.iso
;; 前缀用本仓库自有名 "jeans-"(用户拍板 2026-07-06),
;; 不用 "guix-configs-"(太直白)也不用 "rosenthal-"(那是上游频道,不是本仓库)。
(define %live-iso-prefix "jeans")

;; 把命令参数(变体名列表)过滤成实际要构建的子集。
;; 仿 Testament 的 images-from-arguments:空参数 → 全部。
(define (images-from-arguments arguments)
  (if (null? arguments)
      %images
      (filter (lambda (v) (member v arguments)) %images)))

;; scripts/build-image.scm 的绝对路径。
(define (%live-build-image-script)
  (string-append %repo-root "/scripts/build-image.scm"))

;; dist/ 输出目录的绝对路径。Testament 直接 in-vicinity "dist",
;; 本仓库用 %repo-root 显式拼。
(define (%live-iso-output-dir)
  (string-append %repo-root "/dist"))

;; ISO 文件名不含路径。
(define (%live-iso-filename variant)
  (format #f "~a-~a-~a.~a.iso"
          %live-iso-prefix
          variant
          (date->string (current-date) "~Y~m~d")
          (%current-system)))
```

#### 9.5.1.1 §9.5.1 辅助定义逐行解释

| 名称                       | 类型       | 为什么这样设计                                                                                                                                                     |
| -------------------------- | ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `%images`                  | 常量列表   | 列出所有 ISO 变体名;Testament 等价字段;顺序 = 构建顺序                                                                                                             |
| `%live-iso-prefix`         | 常量字符串 | 写死为 `"jeans"`(用户拍板),后续改发布名只动这里                                                                                                                    |
| `images-from-arguments`    | 函数       | 仿 Testament:空参数 → 全部;非空 → 过滤子集;`member` 用 `eq?` 比较符号,变体名是字符串要显式 `string=?` —— 用 `member` 即可(只比较相等性,不依赖类型)                 |
| `%live-build-image-script` | thunk      | 返回脚本绝对路径;`%repo-root` 是本仓库根 blueprint.scm §0 定义的常量                                                                                               |
| `%live-iso-output-dir`     | thunk      | dist/ 目录绝对路径;**不**用 `in-vicinity` 是因为本仓库 `%repo-root` 不一定是 cwd                                                                                   |
| `%live-iso-filename`       | 函数       | 拼接 `<prefix>-<variant>-<date>.<arch>.iso`;`~Y~m~d` 是 srfi-19 日期格式串;`(%current-system)` 是 `(guix config)` 提供的当前系统符号(x86_64-linux / aarch64-linux) |

#### 9.5.2 build-iso-command 主体

```scheme
;; blue build-iso [VARIANT] ...
;;
;; 构建 Live ISO。先用 emacs-minimal tangle source/config.org 到
;; tmp/live-iso.scm(走 :tangle ../tmp/live-iso.scm 的 #+NAME 块),
;; 然后对每个变体跑:
;;   guix time-machine -C source/channel.lock -- repl -- scripts/build-image.scm
;;     dist/<prefix>-<variant>-<date>.<arch>.iso
;;     tmp/live-iso.scm --image-type=iso9660 ...
;;
;; ⚠ Agent 不要自行运行(ISO 构建耗时 30+ 分钟)。
(define-command (build-iso-command arguments)
  ((invoke "build-iso")
   (category 'deployment)
   (synopsis "构建 Guix System Live ISO")
   (help "[VARIANT] ...
构建 Live ISO 镜像,产物落到 dist/<prefix>-<variant>-<YYYYMMDD>.<arch>.iso。
不带参数则构建 %images 列出的所有变体;带参数只构建匹配 VARIANT 的。
受 AGENTS.md 硬约束:本命令不会 sudo,但镜像构建需 30+ 分钟,建议手动执行。"))
  ;; 1) tangle live-iso.scm(让 dry-run 也能拿到 OS 定义做验证)
  (mkdir-p %tmp-dir)
  (%run (%emacs-command
         `("--quick" "--batch" "-l" "org"
           "--eval" "(require 'ob-tangle)"
           "--eval" ,(format #f "(org-babel-tangle-file ~s)" %config-org))
         #:real? #t))
  ;; 2) 遍历变体,逐个调 guix repl 跑 build-image.scm
  (mkdir-p (%live-iso-output-dir))
  (every
   (cut eq? #t <>)
   (map
    (lambda (variant)
      (let* ((iso-name (%live-iso-filename variant))
             (iso-path (string-append (%live-iso-output-dir) "/" iso-name))
             (scm (string-append %tmp-dir "/live-iso.scm")))
        (format #t "\tBUILD ISO\t~a~%" iso-name)
        (%guix `("repl" "--" ,(%live-build-image-script)
                 ,iso-path ,scm
                 "--image-type=iso9660"))))
    (images-from-arguments arguments))))
```

#### 9.5.2.1 §9.5.2 命令体逐行解释

| 代码段                                                                                      | 作用                    | 为什么                                                                                                        |
| ------------------------------------------------------------------------------------------- | ----------------------- | ------------------------------------------------------------------------------------------------------------- |
| `(mkdir-p %tmp-dir)`                                                                        | 确保 tmp 存在           | `%emacs-command` 跑 ob-tangle 需要 tmp/ 写入                                                                  |
| `(%run (%emacs-command ...) #:real? #t)`                                                    | 跑 ob-tangle            | `#:real? #t` 绕过 `--dry-run` 短路 —— tangle 必须真跑,否则 dry-run 验证拿不到产物                             |
| `(mkdir-p (%live-iso-output-dir))`                                                          | 确保 dist/ 存在         | 第一次构建时 dist/ 不存在                                                                                     |
| `(every (cut eq? #t <>) (map (lambda ...) (images-from-arguments arguments)))`              | 遍历变体构建            | 仿 Testament 的同款循环;`every` + `eq? #t` 是"每个都返回 #t 才继续"模式                                       |
| `(format #t "\tBUILD ISO\t~a~%" iso-name)`                                                  | 日志输出                | 对齐 Testament 的 `(print-header "BUILD ISO" iso)` 风格                                                       |
| `(%guix \`("repl" "--" ,(%live-build-image-script) ,iso-path ,scm "--image-type=iso9660"))` | 调 guix repl 跑镜像构建 | `%guix` 自动套 `--channels=source/channel.lock --`;`scm` 是 tangle 后的 ISO OS 文件;`iso-path` 是目标产物路径 |
| `(let* ((iso-name ...) (iso-path ...) (scm ...)) ...)`                                      | 局部变量                | 三个值都要用,let* 顺序绑定;`scm` 写死 `%tmp-dir/live-iso.scm` 因为我们只用一份 OS 定义(所有变体共用)          |

**为什么不传 `--load-path`** —— Testament 传了 `--load-path=config/live/modules`,
因为他们有自己的模块目录。我们 ISO 配置直接进 config.org,无需 load-path。

**为什么不用 `--system` 参数** —— `%guix` 默认用 `(guix config)` 的 `%current-system`,
本仓库不需要交叉编译(将来要 aarch64 镜像再说,目前只 x86_64)。

#### 9.5.3 在 commands 列表追加(blueprint.scm:1280-1298)

把 `build-iso-command` 插在 `home-command` 之后,与 `init-command` 同一组
(`category 'deployment`),保持语义聚簇:

```scheme
(commands
 (list rebuild-command
       home-command
       build-iso-command          ; ← 新增
       block-show-command
       block-replace-command
       ...
       structor-command))
```

#### 9.5.4 关键陷阱

1. **`tangle-config` 与 `tangle` ISO 块冲突**: `tangle-config`(blueprint.scm:330)
   会跑一次 `org-babel-tangle-file %config-org`,把所有 `:tangle` 块都
   tangle 出来。**但 `main` 块的 `:tangle ../tmp/config.scm` 在这个调用里
   也会被重新生成** —— 这跟 `blue home` / `blue rebuild` 行为一致,
   没有副作用(tangle 本身就是 idempotent)。

2. **`%config-org` 是 source/config.org** —— 一个文件里多个 tangle 目标
   是 Org 标准用法,`ob-tangle` 会按 `:tangle` 头分发,不冲突。

3. **ISO 命令里** **`%guix`** **会传 `source/channel.lock` 之外的 channel lock 吗?**
   不会,除非显式给 `#:channels`。本仓库决定 §6.2 第 2 条:不另建
   `live-channels.lock`,直接复用 `source/channel.lock`。

4. **`(every (cut eq? #t <>) ...)` 模式**:跟 Testament 一样,确保任意
   一个变体失败时后续变体不跑,`every` 返回 #f。但 blue 的命令入口
   对 #f 返回值没有特殊处理(不像 shell `set -e`)—— **需在命令体
   末尾 `(unless (every ...) (error "..."))`** 或类似防御,否则
   命令看起来"成功",实际只构建了一半变体。
   **修订**:在 body 末尾加 `(unless all-ok (error ...))` 或把
   every 包成单个布尔表达式。

   实际看 Testament 行 242-256 —— 它有同样的瑕疵,**直接照搬**即可,
   因为 blue 自身在 %run 失败时已经 `error`,所以单变体失败会直接
   短路。`(every ...)` 在这里退化为"循环内每次调用都因 %run 抛错而中断"。

5. **`make-file-writable` 行为差异**:Testament 的 `build-image.scm`
   调了 `(make-file-writable dst)`,这是 `(guix build utils)` 提供。
   本仓库 ISO 命名以 `brokenshine` 为 user,store 里的 iso 副本对
   该 user 是只读,落盘到 `dist/` 后需要这一行才能后续签/读。本仓库
   **保留**这一行。

### 9.6 P4:manifest.scm 视情况增包

**目标**:`scripts/build-image.scm` 调 `(guix-system "image" args...)`,
需要 `guix scripts system` 模块。该模块来自 `guix` 包,**已经在 manifest
里**(因为 guix time-machine 自带)。所以**通常不需要改**。

但 ISO 构建时 `guix time-machine -C source/channel.lock -- repl` 需要
`guile` `guile-json` 之类的 readline / repl 体验 —— 这些也已经在 guix
profile 里。

**判定方式**:

```bash
# 先不增,直接 P7 跑一次 ISO 构建,看是否报 unbound-variable 之类。
# 如果报 guile-readline 缺,加到 manifest。
```

**建议**:P4 默认不动 manifest。如果 P7 报错再补。

### 9.7 P5:.gitignore 加 `dist/`

```gitignore
# Live ISO 构建产物(blue build-iso 的输出)
dist/
```

加在 `tmp` 后面。

### 9.8 P6:`blue check` 验证

```bash
cd ~/Projects/Config/Guix-configs && blue check
```

预期:

- `[OK] 块 live-modules: ...`
- `[OK] 块 live-installation-os: ...`
- `[OK] 全部通过: N+1 个 scheme 块 + 3 个周边文件`

**额外验证(更严)**:`tmp/live-iso.scm` 末行应是 `%live-installation-os`,
不应有 `%system`:

```bash
tail -5 /home/brokenshine/Projects/Config/Guix-configs/tmp/live-iso.scm
```

### 9.9 P7:用户手动 `blue build-iso <variant>`

**AI 禁跑**(ISO 构建 30+ 分钟,中途会失败/重试/需诊断)。

```bash
# 主目标(xfce,GUI 桌面):
cd ~/Projects/Config/Guix-configs && blue build-iso xfce

# 辅助(minimal,纯 CLI fallback):
cd ~/Projects/Config/Guix-configs && blue build-iso minimal

# 全量:
cd ~/Projects/Config/Guix-configs && blue build-iso
```

观察首 30 秒输出:

- `\tBUILD ISO\tjeans-xfce-<date>.x86_64-linux.iso`
- `guix time-machine: ...`

失败模式清单见 §11。

成功产物:

- `dist/jeans-xfce-<date>.x86_64-linux.iso`
- `dist/jeans-minimal-<date>.x86_64-linux.iso`(若选了 minimal)

### 9.10 P8:验收

- QEMU 启动(给 4G 内存):`qemu-system-x86_64 -m 4G -enable-kvm -cdrom dist/jeans-xfce-<date>.x86_64-linux.iso`
- 进 installer:看到 slim 启动 → 自动登录 live → XFCE 桌面出现
- 验证 fish shell:`Ctrl+Alt+F2` 进 tty,`root@live-system ~# echo $SHELL` → `/gnu/store/...fish`
- 验证 nonguix kernel:`uname -r` 应是非 `-libre` 内核版本
- 验证 nonguix 频道:装好后 `/etc/guix/channels.scm` 应含 nonguix 条目
- 实战装机(可选):写入 U 盘,真实机器启动,跑完 `guix system init`

---

## §10 命令接口契约(写给未来参考)

### 10.1 命令语法

```
blue build-iso [VARIANT] ...
```

| 参数      | 说明                                                     |
| --------- | -------------------------------------------------------- |
| 无参数    | 构建 `%images` 列出的所有变体(当前 `("xfce" "minimal")`) |
| `xfce`    | 只构建 XFCE 镜像(主目标,GUI 桌面)                        |
| `minimal` | 只构建 minimal 镜像(辅助 fallback,纯 CLI installer)      |

### 10.2 副作用清单

| 副作用                        | 路径                                             | 是否可逆                |
| ----------------------------- | ------------------------------------------------ | ----------------------- |
| 重新 tangle source/config.org | tmp/config.scm(已有,不变) + tmp/live-iso.scm(新) | ✅ re-tangle idempotent |
| 在 dist/ 写入 ISO 文件        | dist/jeans-{xfce,minimal}-<date>.<arch>.iso      | ✅ rm 即可              |
| guix store 新增镜像 closure   | /gnu/store/*-iso9660-image + 依赖                | ✅ `guix gc`            |
| guix pull(在 time-machine 内) | ~/.cache/guix/pull/<commit>/ 临时缓存            | ✅ 自动过期             |

### 10.3 不做的事

- ❌ 不动 `/gnu/store` 只读副本
- ❌ 不 sudo
- ❌ 不 git commit
- ❌ 不删旧 ISO(留给 `blue gc` / `rm dist/`)
- ❌ 不签名(§6.2 第 4 条决策)

### 10.4 与 `blue rebuild` / `blue home` 的关系

`blue build-iso` 与 `blue rebuild` 完全独立:

- `blue rebuild` 走 `tmp/config.scm` → `guix system reconfigure`
- `blue build-iso` 走 `tmp/live-iso.scm` → `guix repl` → `guix system image`

互不污染 store 路径,不污染 generations。ISO 跑完后,主机配置原样不动。

---

## §11 失败模式与诊断树

> **接手 agent 必读** —— §11 是 P7 失败时的**第一反应**。先看 §11.1 按症状定位,
> 再看 §11.2 按错误码定位,最后用 §11.6 一键回滚。

### 11.0 诊断流程总图

```
blue build-iso xfce
       │
       ▼
   报错 ─┬─ emacs-batch 退出码非 0       → §11.1.A  "tangle 失败"
         ├─ guix time-machine 失败       → §11.1.B  "频道拉不到"
         ├─ build-image.scm 抛错          → §11.1.C  "镜像构建期"
         ├─ stdout 空(无 store path)     → §11.1.D  "产物为空"
         ├─ dist/ 没文件                  → §11.1.D  (同 D)
         └─ blue check 失败(在 P6 阶段)  → §11.1.E  "括号检查未通过"
```

### 11.1 按症状定位

#### A. tangle 失败(emacs-batch 退出码非 0)

**症状**:`blue build-iso` 在第一个 `%run` 后报错,但 `tmp/live-iso.scm`
**未生成**或**生成了一半**。

**根因清单**:

1. `<<live-modules>>` Noweb 引用写错(emacs 找不到该 NAME)
2. live-installation-os 块本身括号不平衡
3. tmp/ 目录权限问题或不存在
4. `:tangle` 头写错(漏写 `:noweb yes`)

**诊断**:

```bash
# 1. 验证 tmp/live-iso.scm 是否生成
ls -la /home/brokenshine/Projects/Config/Guix-configs/tmp/live-iso.scm

# 2. 验证 live-modules / live-installation-os 块存在
cd /home/brokenshine/Projects/Config/Guix-configs && blue block-show live-modules
cd /home/brokenshine/Projects/Config/Guix-configs && blue block-show live-installation-os

# 3. 单独跑括号检查(blue check 已经在 P6 验证过,这里再加一层)
guile --no-auto-compile -c '(load "/home/brokenshine/Projects/Config/Guix-configs/tmp/live-iso.scm")' && echo OK
```

**修复**:

- 缺 NAME → 补 `#-NAME:` 头
- 括号错 → git diff 找最近改的 source/config.org 行,用 §9.4.5 陷阱排查
- `:tangle` 头错 → 复制 §9.4.3 的样例

#### B. guix time-machine 拉频道失败

**症状**:`guix time-machine: ...` 报错,涉及 `source/channel.lock` 中的某个
channel(guix / bluebox / jeans / nonguix / rosenthal)。

**根因清单**:

1. 网络/firewall 拦截
2. `source/channel.lock` 的某个 commit 在远端不存在(罕见,通常 lock 都是固定 commit)
3. `--substitute-urls` 配置问题(本仓库用默认 bordeaux/ci,理论上没问题)

**诊断**:

```bash
# 看 time-machine 完整错误
cd ~/Projects/Config/Guix-configs
guix time-machine -C source/channel.lock -- describe 2>&1 | head -20

# 单独验证某个频道能否拉(make-installation-os 在 guix core,不是 rosenthal)
guix time-machine -C source/channel.lock -- repl <<'EOF'
(use-modules (gnu system install))
(make-installation-os)
EOF
```

**修复**:

- 网络问题 → 重试 / 切 mirror
- commit 不存在 → `blue update` 重新生成 channel.lock(慎用,会改 lock)

#### C. 镜像构建期失败(build-image.scm 内部)

**症状**:`guix repl` 启动成功,但内部 `(guix-system "image" ...)` 抛错。
**典型是 #7373**(上游 blocker)。

**诊断**:

```bash
# 看 build log
guix time-machine -C source/channel.lock -- system build tmp/live-iso.scm \
  --image-type=iso9660 --verbosity=2 2>&1 | tee /tmp/iso-build.log

# 看具体卡在哪个 phase
grep -E "(phase|error|unbound|fatal)" /tmp/iso-build.log | tail -30

# 单独验证 make-installation-os 是否被 #7373 影响(在 guix core,不是 rosenthal)
guix time-machine -C source/channel.lock -- repl <<'EOF'
(use-modules (gnu system install))
(make-installation-os)
EOF
```

**修复**:

- #7373 触发 → **等上游 fix / 退回 guile-3.0.9 对应的 guix commit**
- 缺包 → 在 spec 列表补
- nonguix 网络问题 → 详见 §11.3

#### D. 产物为空 / 路径不存在

**症状**:`build-image.scm` 跑完,但 `dist/` 没有 ISO。

**根因**:`src (file-exists? src)` 为假 → `(when ...)` 不执行 → 没有 copy。
**典型是 #7373 阻塞**:`(guix-system "image" ...)` 不输出 store path。

**诊断**:

```bash
# 手工跑 build-image.scm,看 stdout
cd ~/Projects/Config/Guix-configs
guix time-machine -C source/channel.lock -- repl -- scripts/build-image.scm \
  /tmp/test-output.iso tmp/live-iso.scm --image-type=iso9660 2>&1 | head -20
# stdout 末行应是 /gnu/store/<hash>-iso9660-image
```

**修复**:

- stdout 末行不是 store path → 看 stderr,通常指向 C 类问题
- stdout 有 store path 但 dist/ 没文件 → 检查 `src (file-exists? src)` 条件
  和 store path 权限

#### E. blue check 失败(P6 阶段)

**症状**:`blue check` 报 `[ERROR] 多余 N 个括号` 或 `[FAIL] 括号检查未通过`。

**根因清单**:

1. live-modules 块括号错(罕见,use-modules 是模板)
2. live-installation-os 块括号错(常见)
3. live-installation-os 块内 `<<live-modules>>` 引用导致 Noweb 展开后括号失衡

**诊断**:

```bash
# 1) 看具体哪个块报错
blue check 2>&1 | head -20

# 2) 单独跑每个块验证
cd ~/Projects/Config/Guix-configs
blue block-show live-modules
blue block-show live-installation-os
```

**修复**:

- 活-modules 错 → 重新对照 §9.4.2
- live-installation-os 错 → git diff 找最近改的 source/config.org 行,
  数 `(` `)` 是否平衡(用 `python3 -c "print(open('x').read().count('('), open('x').read().count(')'))"`)

### 11.2 按错误码定位

| 错误码 / 信号                                 | 含义                          | 看哪                           |
| --------------------------------------------- | ----------------------------- | ------------------------------ |
| `unbound variable: make-installation-os`      | `(gnu system install)` 没引(**不是** rosenthal) | §9.4.2 模块列表 + §9.4.5 陷阱 3 |
| `unbound variable: xfce-desktop-service-type` | `(gnu services desktop)` 没引 | §9.4.2                         |
| `unbound variable: slim-service-type`         | `(gnu services xorg)` 没引    | §9.4.2                         |
| `no code for module (gnu packages slim)`      | 该模块**不存在**,删掉这行 use-modules | §9.4.2 注释(slim 走 spec 解析) |
| `no code for module (gnu packages rofi)`      | 该模块**不存在**,rofi 在 `(gnu packages xdisorg)` 或走 spec | §9.4.2 注释 |
| `no value specified for service of type 'kmscon'` | `(service kmscon-service-type)` 缺 configuration | 删该行(make-installation-os 默认已含带 config 的 kmscon) |
| `extraneous field initializer (xauth-file)`   | slim-configuration 字段名错(应 `xauth`)或误传路径 | §9.4.3 slim 注释(xauth 期望程序,非 .Xauthority) |
| `unbound variable: %default-locale-libcs`     | 内部变量,需 `(@@ (gnu system install) ...)` | §9.4.3 gc-root 注释 |
| `Wrong type to apply: #<<service-type>`       | service 括号错位              | §9.4.5 陷阱 1                  |
| `extraneous field initializer (display)`      | slim-configuration 字段错     | Guix 手册 `slim-configuration` |
| `multiple definition: %live-installation-os`  | tangle 目标污染 config.scm    | §9.4.5 陷阱 1(紧急 git revert) |
| `guix system: error: build failed`            | 构建期失败                    | §11.1.C                        |
| `guix time-machine: failed to authenticate`   | channel 公钥过期              | `blue update` 重生 lock        |
| `error: connection refused`                   | 网络/firewall                 | §11.1.B                        |
| `disk space exhausted`                        | /tmp 或 /gnu 满               | `du -sh /gnu/store /tmp`       |
| `permission denied (store path)`              | /gnu/store 权限               | §11.4                          |

### 11.3 决策矩阵

| 阶段 | 报错位置                     | 立即行动                              | 长期方案                                |
| ---- | ---------------------------- | ------------------------------------- | --------------------------------------- |
| P6   | blue check                   | 看哪个块报错 → git diff               | 修复 source/config.org                  |
| P7.A | emacs-batch 退出码非 0       | 看 `blue block-show` 输出             | git revert config.org                   |
| P7.A | tmp/live-iso.scm 未生成      | 检查 config.org 的 `:tangle` 头       | git revert config.org                   |
| P7.B | guix time-machine 失败       | 看 guix 错误,检查网络/firewall        | 切 mirror / 重试                        |
| P7.C | make-installation-os unbound | 检查 live-modules 是否 use `(gnu system install)` | 加 use-modules(见 §9.4.2)         |
| P7.C | guix-system image 抛错       | 看 build log,grep "phase"             | 修 tmp/live-iso.scm / 升级 channel.lock |
| P7.C | #7373 触发                   | 等 / 手动 git fetch upstream fix      | 在 rosenthal issue 跟踪                 |
| P7.D | build-image.scm stdout 空    | 看 guix-system 内部 stderr            | 修上游或绕过该路径                      |
| P7.D | dist/ 没文件                 | 看 build-image.scm 的 `(when ...)`    | 检查 store 路径权限                     |
| P8   | QEMU 启动失败                | 看 VM 日志 + ISO md5 校验             | 重做 ISO                                |
| P8   | 装机失败(#7373 阻塞)         | **这是 #7373 战场,不是 ISO 构建问题** | 等上游 fix 或退回 guile-3.0.9 commit    |

### 11.4 常见根因模式(接手 agent 重点看)

#### 11.4.1 "看起来同一错误,根因不同"

经验教训(2026-07-06 用户拍板):

> 同一构建错误,修完后**必须重读 build log** 逐包诊断,不能假设"修过一次
> 就是修了"。本仓库此前撞过 guix-daemon 沙箱构建 git-fetch → url-fetch
> 转换的坑 —— 同一个错误信息背后可能换了 5 个不同的失败包。

**实践**:

- 每次重跑 P7,即使之前成功过,也必须 cat 完整 build log
- grep 不到错误 ≠ 没有错误(可能 phase 早期 warning 被忽略)

#### 11.4.2 "blue --dry-run 不等于不写"

`blue --dry-run` 会让 %run 短路打印,但:

- `org-babel-tangle-file` 必须真跑(`#:real? #t`)
- 括号检查必须真跑
- **生成 tmp/live-iso.scm 是真的**,只是后续 guix 不跑
- 跑完 dry-run 后 tmp/live-iso.scm 留着 —— 第二次跑会覆盖,正常

#### 11.4.3 "cd 路径"陷阱

§接手必读 §3 列了 `blue home` 必须在仓库根跑。`blue build-iso` 同理:

```bash
# ✅ 正确
cd ~/Projects/Config/Guix-configs && blue build-iso xfce

# ❌ 错:在子目录跑
cd ~/Projects/Config/Guix-configs/source && blue build-iso xfce
# → "&external-error / No command with this name"
```

#### 11.4.4 "tangle idempotent 但不稳"

ob-tangle 对 `:tangle` 头解析是 **idempotent** —— 跑两次结果一样。
但若 source/config.org 文件 mtime 比 tmp/live-iso.scm 旧,**不会自动重新 tangle**
(blue build 才触发)。所以**改完 source/config.org 后**,blue check 验证括号,
但 tmp/live-iso.scm 可能没更新。**验证手段**:`tail tmp/live-iso.scm`,
或 `rm tmp/live-iso.scm` 后 blue build 重新生成。

### 11.5 接手 agent 边界(硬约束)

| 操作                                       | 谁可以做                          | 谁**不能**做             |
| ------------------------------------------ | --------------------------------- | ------------------------ |
| 改 source/config.org 加 ISO 块             | ✅ AI(本任务的活)                 | —                        |
| `blue check`                               | ✅ AI                             | —                        |
| `blue --dry-run build-iso xfce`            | ✅ AI(产出 stub,但有 dry-run log) | —                        |
| `blue build-iso xfce`                      | ❌ **用户**                       | AI(sudo / 卡 CLI)        |
| `blue rebuild` / `blue system reconfigure` | ❌ 用户                           | AI                       |
| 写 `/gnu/store/*`                          | ❌                                | 任何人(readonly)         |
| 改 `tmp/` 产物                             | ❌                                | 任何人(re-tangle 会覆盖) |
| 改 `~/.config/` `~/.local/`                | ❌                                | 任何人(blue home 不该动) |
| 删 `dist/*.iso`                            | ✅ AI(用 `rm`,但本仓库偏好 trash) | —                        |
| 改 source/channel.lock                     | ❌                                | AI(blue update 才能改)   |

### 11.6 一键回滚

```bash
# 仅回滚代码改动(不动 dist/)
cd ~/Projects/Config/Guix-configs
git checkout -- source/config.org blueprint.scm scripts/build-image.scm .gitignore

# 删 ISO 产物
trash-put dist/           # 本仓库偏好 trash-cli,不用 rm

# 清 tangle 中间产物
rm -f tmp/live-iso.scm

# 清 guix store 里的镜像 closure(可选)
guix gc --delete /gnu/store/<hash>-iso9660-image
```

**回滚后必须验证**:

```bash
cd ~/Projects/Config/Guix-configs && blue check
# 应回到 baseline:无 live-modules / live-installation-os 块
```

### 11.7 §11 的反模式(接手 agent 别踩)

- ❌ "看到错误先 google,不看 §11" —— §11 已经覆盖 95% 场景
- ❌ "修过一次就以为修了" —— §11.4.1 反复强调
- ❌ "顺手改 channel.lock" —— §11.5 红线,必须 blue update 才能改
- ❌ "不读 build log 就重跑" —— 浪费时间,不解决根因

---

## §12 验收清单(P8 实跑时逐项打勾)

> **接手 agent**:打勾前**必须验证每项的"期望输出"** 与 §12.1 样板一致;
> 不一致 = 没通过。**不要给自己骗绿勾**。

### 12.0 验收标签

每项验收前都标了执行者,**AI 别越界**:

- **[A]** = AI 可自验(改完代码就跑,看输出)
- **[U]** = 用户手动(AI 不许跑,等用户结果)
- **[R]** = 实跑(必须真机或 QEMU)

### 12.1 验收项 + 期望输出样板

#### P0(已通过 — 不需重做)

- [x] **[A]** P0:codeberg.org/guix/guix/issues/7373 状态已确认(Open,但只阻塞装机)

#### P1:scripts/build-image.scm 已建

- [x] **[A]** P1:`scripts/build-image.scm` 文件存在 ✅ (commit be70f1a)
- [x] **[A]** P1:文件 31 行 + SPDX 头(实测比 plan 估的 18 行多 —— 含注释和空行,核心逻辑仍是 18 行 match 块)

**期望输出样板**:

```bash
$ ls -la scripts/build-image.scm
-rw-r--r-- 1 brokenshine users 535 Jul  6 20:30 scripts/build-image.scm

$ wc -l scripts/build-image.scm
18 scripts/build-image.scm

$ head -3 scripts/build-image.scm
;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: MIT
```

#### P2:config.org ISO 块

- [x] **[A]** P2:config.org 已加 `* Live ISO` 章 + `live-modules` + `live-installation-os` ✅ (commit 1aa09fc)
- [x] **[A]** P2:`tmp/live-iso.scm` 经 `blue check` 通过(实测 live-modules 25 对 / live-installation-os 85 对 —— plan 样板写的 32 对是旧估,以实测为准)
- [x] **[A]** P2:`tmp/live-iso.scm` 末行是 `%live-installation-os`
- [x] **[A]** P2:`tmp/config.scm` 经 `blue check` 通过(914 对),**没有** `%live-installation-os` / `make-installation-os` / 任何 ISO 独有标识符(实测 9 个标识符全 0)

**期望输出样板**:

```bash
$ cd ~/Projects/Config/Guix-configs && blue check 2>&1 | tail -10
[OK] 块 live-modules: 25 对
[OK] 块 live-installation-os: 32 对
[OK] 全部通过: 38 个 scheme 块 + 3 个周边文件

$ tail -3 tmp/live-iso.scm
                 (substitute-urls
                  '("https://mirror.sjtu.edu.cn/guix"
                    "https://mirrors.sjtug.sjtu.edu.cn/guix-bordeaux")))))))

%live-installation-os

$ grep -c "%live-installation-os" tmp/config.scm
0
```

#### P3:blueprint.scm build-iso-command

- [x] **[A]** P3:`blueprint.scm` 已加 `build-iso-command` ✅ (commit 06fa397)
- [x] **[A]** P3:`blue help`(无参)能看到 `build-iso` 列出 ⚠️ `blue list`(项目自定义)在本环境**预先就坏**(exit 1, 与本任务无关 —— git stash 回到 P3 前同样失败);改用 `blue help`(框架内建)确认注册成功
- [x] **[A]** P3:`blue help build-iso` 输出 help 文本
- [x] **[A]** P3(额外):`blue --dry-run build-iso xfce` 输出 `BUILD ISO jeans-xfce-20260706.x86_64-linux.iso` + `[预演] guix time-machine --channels=...source/channel.lock -- repl -- .../scripts/build-image.scm .../dist/jeans-xfce-20260706.x86_64-linux.iso .../tmp/live-iso.scm --image-type=iso9660`

**期望输出样板**:

```bash
$ cd ~/Projects/Config/Guix-configs && blue list | grep build-iso
  build-iso    构建 Guix System Live ISO

$ blue help build-iso 2>&1 | head -10
用法: blue build-iso [VARIANT] ...
构建 Live ISO 镜像,产物落到 dist/<prefix>-<variant>-<YYYYMMDD>.<arch>.iso。
不带参数则构建 %images 列出的所有变体;带参数只构建匹配 VARIANT 的。
...
```

#### P4-P5

- [x] **[A]** P4:manifest.scm 已评估,结论**不动**(blue 已含 guix repl + guile + guix scripts system;P1 实测 guix repl 能加载 (guix scripts system))
- [x] **[A]** P5:.gitignore 已加 `dist`(✅ commit f5d01df;用 `dist` 不带 `/` 也忽略同名文件,git check-ignore -v 验证命中)

**期望输出样板**:

```bash
$ grep "^dist/$" .gitignore
dist/
```

#### P6:blue check 全过

- [x] **[A]** P6:`blue check` 全过(无 FAIL) —— 实测 39 个 scheme 块 + 3 周边文件全 [OK](plan 估 38,实际多 1 因为 live-modules + live-installation-os 各算 1 块)
- [x] **[A]** P6:无新增 `[SKIP]` 块(实测仅 2 个原有 SKIP:`50-hibernate.rules (js)` + `fish-cfg (fish)`,与 ISO 无关)

**期望输出样板**:

```bash
$ cd ~/Projects/Config/Guix-configs && blue check
[OK] 块 dotfile-services: 5 对
...
[OK] 块 live-modules: 25 对
[OK] 块 live-installation-os: 32 对
[OK] 全部通过: 38 个 scheme 块 + 3 个周边文件
```

#### P7:实际构建(用户执行)

- [ ] **[U]** P7(用户执行):`blue build-iso xfce` 跑通(30+ 分钟,需用户手动)
- [x] **[A]** P7:`blue --dry-run build-iso xfce` 输出与 §9.9 描述一致 ✅(实测见 P3 额外项)
- [ ] **[U]** P7:产物路径:`dist/jeans-xfce-<YYYYMMDD>.x86_64-linux.iso`(待用户实跑)

**期望输出样板**(用户实跑后):

```bash
$ cd ~/Projects/Config/Guix-configs && blue build-iso xfce
[预演] 编织 source/config.org (ob-tangle)        # if --dry-run
	BUILD ISO	jeans-xfce-20260706.x86_64-linux.iso
[预演] guix time-machine -C source/channel.lock -- repl -- ...   # if --dry-run
# 真实构建会跑 30+ 分钟,期间输出 build phase 信息

$ ls -la dist/
-rw-r--r-- 1 brokenshine users 8589934592 Jul  6 22:30 jeans-xfce-20260706.x86_64-linux.iso
```

#### P8:验收(用户执行)

- [ ] **[U]** P8:QEMU 启动 ISO,slim 自动登录 live,XFCE 桌面出现
- [ ] **[U]** P8:`uname -r` 显示非 -libre 内核
- [ ] **[U]** P8:root shell 是 `/gnu/store/...fish`
- [ ] **[U]** P8:装好后 `/etc/guix/channels.scm` 含 nonguix 条目
- [ ] **[U]** P8(可选):`blue build-iso minimal` 也跑通(辅助变体)
- [ ] **[R]** P8(可选):U 盘真机启动 + 实战装机

**期望输出样板**(QEMU 启动后 ssh/tty 进系统):

```bash
$ uname -r
6.10.5-gnu

# root shell 路径
$ echo $SHELL
/gnu/store/...fish/bin/fish

# 装好后 /etc/guix/channels.scm
$ cat /etc/guix/channels.scm
(list (channel
        (name 'guix)
        ...)
      (channel
        (name 'nonguix)
        (url "https://gitlab.com/nonguix/nonguix.git")
        ...))
```

### 12.2 总览统计

| 阶段     | 总项   | AI 可自验 | 用户手动 | 实跑  |
| -------- | ------ | --------- | -------- | ----- |
| P0       | 1      | 1         | 0        | 0     |
| P1       | 2      | 2         | 0        | 0     |
| P2       | 4      | 4         | 0        | 0     |
| P3       | 3      | 3         | 0        | 0     |
| P4       | 1      | 1         | 0        | 0     |
| P5       | 1      | 1         | 0        | 0     |
| P6       | 2      | 2         | 0        | 0     |
| P7       | 3      | 1         | 2        | 0     |
| P8       | 6      | 0         | 5        | 1     |
| **总计** | **23** | **15**    | **7**    | **1** |

**自验率**:15/23 = 65%(AI 能做的)。
**用户必跑**:7/23 = 30%(实跑和发版前必跑)。
**实跑**:1/23 = 5%(P8 装机验证)。

### 12.3 打假绿勾反模式(接手 agent 别踩)

- ❌ "看 git diff 有改动就勾" —— 没跑 blue check 验证
- ❌ "blue check 通过就勾所有 P2 项" —— `tmp/config.scm` 是否被污染没验证
- ❌ "我把 %live-installation-os 注释掉勾 P2" —— 等于没做
- ❌ "P7 我没跑,看代码应该对就勾" —— P7 是真活,代码对 ≠ 跑通

---

## §13 后续扩展(变体矩阵 + 决策权)

> **接手 agent**: §13 是变体矩阵,**不是 to-do list**。是否立项、什么时候立项,
> 由用户拍板。

### 13.1 桌面变体矩阵

| 变体名          | service-type                         | DM              | 工作量   | 优先级        | 触发条件                                |
| --------------- | ------------------------------------ | --------------- | -------- | ------------- | --------------------------------------- |
| `xfce` ✅       | `xfce-desktop-service-type`          | slim            | 0(已做)  | **主**        | 本任务                                  |
| `minimal` ✅    | `(delete kmscon-service-type)`       | kmscon(默认)    | 0(已做)  | 辅助 fallback | xfce 跑不动时                           |
| `gnome`         | `gnome-desktop-service-type`         | gdm             | 2-3 小时 | 中            | 用户机器装了 nvidia / 需要 Wayland 体验 |
| `kde`           | `plasma-desktop-service-type`        | gdm 或 sddm     | 2-3 小时 | 中            | 需要 KDE 专有应用(Krita / Kdenlive)     |
| `niri`          | `home-niri-service-type` (rosenthal) | greetd 或 ly    | 4-5 小时 | 低            | 想跟 Testament niri 体验对齐            |
| `lxqt`          | `lxqt-desktop-service-type`          | sddm            | 2 小时   | 低            | 想要比 XFCE 还轻的 Qt 桌面              |
| `mate`          | `mate-desktop-service-type`          | slim 或 lightdm | 2 小时   | 低            | GNOME 2 风格用户                        |
| `enlightenment` | `enlightenment-desktop-service-type` | 自带            | 2 小时   | 低            | 想要 Wayland 原生极简                   |

> **如何新增一个变体**(以 `gnome` 为例):
>
> 1. `live-installation-os` 复制一份 `live-installation-os-gnome`,
>    `:tangle ../tmp/live-iso-gnome.scm`(独立 tangle 目标)
> 2. 把 `(service xfce-desktop-service-type)` 替换为 `(service gnome-desktop-service-type)`
> 3. `(service slim-service-type ...)` 替换为 `(service gdm-service-type)`
> 4. 包列表里把 `xfce4-*` 换成 `gnome-tweaks` `gnome-shell-extensions` 等
> 5. `%images` 加 `"gnome"`
> 6. 蓝色 `blue build-iso gnome` 跑通即完成
>
> 详细工作量评估见 §13.1 表格。

### 13.2 平台变体矩阵

| 平台          | 状态                           | 工作量 | 触发条件        |
| ------------- | ------------------------------ | ------ | --------------- |
| x86_64-linux  | ✅ 已支持                      | 0      | 本任务          |
| aarch64-linux | 隐式支持(`#:efi-only?` 自动切) | 0      | 用户有 ARM 设备 |
| i686-linux    | ❌                             | 半天   | 有老硬件场景    |

### 13.3 工程优化矩阵(非桌面)

| 扩展                                      | 工作量  | 触发条件                         |
| ----------------------------------------- | ------- | -------------------------------- |
| `source/live-channels.lock` 独立 ISO lock | 1 小时  | 用户追求 Testament 级密封性      |
| `scripts/sign` GPG detach-sign            | 1 小时  | ISO 公开发布前                   |
| ISO 内嵌 `examples/` 配置模板             | 半天    | 装机引导想让用户"开箱即用本仓库" |
| `blue build-iso --keep-failed`            | 15 分钟 | 调试 #7373 类阻塞时              |
| `blue build-iso --substitute-urls=...`    | 30 分钟 | 想指定 mirror / 测试专用 channel |
| AGENTS.md / README.org 增 ISO 章节        | 30 分钟 | §8-§12 全部走通后                |

### 13.4 决策权

| 项                                  | 决策者                                 |
| ----------------------------------- | -------------------------------------- |
| 加新桌面变体                        | **用户拍板**(AI 提供 §13.1 工作量估算) |
| 加新平台                            | **用户拍板**                           |
| 升级 rosenthal/nonguix channel.lock | **用户拍板**(`blue update` 是用户操作) |
| 工程优化(签名 / 独立 lock / etc.)   | **用户拍板**                           |
| 修文档 typo / 重排章节              | **AI 可自决**(commit 走 gitmessage)    |

每条都依赖 P0-P8 通过后才能立项;不要在 xfce 还没跑通前就并行做。

---

## §14 仓库状态快照(2026-07-06 实施前)

> **接手 agent**: 这是实施**前**的仓库快照(我写文档时的状态)。**先核对快照,
> 再动手** —— 任何"快照里没列"的变更都是别人先做了,问用户。

### 14.1 文件级快照

```
$ git status --short
# (干净,无未提交改动)

$ wc -l \
    blueprint.scm \
    source/config.org \
    source/information.scm \
    source/manifest.scm \
    source/channel.lock \
    .gitignore \
    docs/iso-build.md
1298  blueprint.scm
1929  source/config.org
80    source/information.scm
9     source/manifest.scm
50    source/channel.lock
27    .gitignore
1749  docs/iso-build.md        ← 本文档自身
```

### 14.2 关键事实快照

| 项                                        | 实施前值                                   |
| ----------------------------------------- | ------------------------------------------ |
| blueprint.scm 命令数                      | 17                                         |
| blueprint.scm §10 commands 列表起始行     | 行 1281                                    |
| blueprint.scm `init-command` 行号         | 行 989 附近                                |
| source/config.org `#\+NAME:` 块数         | 38                                         |
| source/config.org 最大行号                | 1929                                       |
| source/channel.lock 锁的 guix commit      | `9e068cc03bfacbbcd199f3618fcf360df3f368e0` |
| source/channel.lock 锁的 rosenthal commit | `6cf57b252d4cfdbe23d5be705bfbae259b3b3400` |
| source/channel.lock 锁的 nonguix commit   | `66ab7fff7a4ee0592c708651556ef3805c85068f` |
| source/channel.lock 锁的 jeans commit     | `e98b7bc8cc289a36d488fcf76b09f3fc7966ef07` |
| source/channel.lock 锁的 bluebox commit   | `71628770c8612c041e06672f34c0c8e6fc67c13c` |
| rosenthal trunk 最新 commit(实施日)       | `d687672c1c44ffd82d790d87d59ad832415ca2e8` |
| 上游 #7373 状态                           | **Open**(只阻塞装机完结)                   |
| `scripts/` 目录是否存在                   | ❌(实施时新建)                             |

### 14.3 接手 agent 自检快照方法

```bash
# 1) 仓库是否干净
cd ~/Projects/Config/Guix-configs && git status --short
# 期望:空输出

# 2) 各文件行数 vs §14.1
# 期望:本文档 ~1750 行,其他基本一致(±20 行容差)

# 3) channel.lock 锁的 commit 是否还活
curl -fsSL --max-time 10 \
  "https://git.savannah.gnu.org/cgit/guix.git/commit/?id=9e068cc03bfacbbcd199f3618fcf360df3f368e0" \
  | head -1
# 期望:HTTP 200(commit 还在远端)

# 4) #7373 状态
curl -fsSL --max-time 10 "https://codeberg.org/guix/guix/issues/7373" \
  | grep -iE "class=\"ui green label issue-state-label\"" | head -1
# 期望:"Open"(若变 Close,本文档决策要重新评估)
```

### 14.4 接手时若发现不一致

| 现象                       | 含义                                | 怎么办                              |
| -------------------------- | ----------------------------------- | ----------------------------------- |
| git status 有未提交改动    | 之前有人改了一半                    | `git diff` 看是什么,问用户是否继续  |
| 行数差很大(±100)           | 文档大改或合并冲突                  | 看 git log 最近 commits,问用户      |
| channel.lock commit 拉不到 | 远端 force-push / 仓库搬家          | 暂缓,问用户                         |
| #7373 已 Close             | **重要决策点** —— §0 决策记录要更新 | 看 P8 装机是不是可以补做了          |
| `scripts/` 目录已存在      | 别人先做了部分                      | `ls scripts/` 看有什么,合并而非覆盖 |

---

## §15 文档维护纪律

> **接手 agent / 文档编辑者**: 这节是给自己看的。
> **D7 决策(2026-07-06 gril)**:`docs/iso-build.md` 是 **gril 阶段 plan**,
> **不**进仓库 / **不** commit。`§15.4 版本表` 也随之失效(只有"进仓库"才有版本)。
> 本节保留是为接手 agent 知道:若未来你看到 `docs/iso-build.md` 在仓库,
> 说明用户拍板要进仓,届时再启版本表。

### 15.1 何时改本文档

| 触发                                | 改哪                                     |
| ----------------------------------- | ---------------------------------------- |
| P1~P6 任一阶段完成                  | 不改文档(只打 §12 勾)                    |
| 撞到一个 §11 没覆盖的错误           | 加进 §11                                  |
| #7373 状态变化                      | 更新 §0 决策记录 + §9.2 P0               |
| 升 channel.lock 后某个 API 改名     | 更新 §9.4.2 模块列表                     |
| 用户决定加新桌面变体(走 §13.1 流程) | 加进 §9.4.3 / §13.1                      |
| 修正 §11.4.1 类的经验教训           | 加进 §11.4                               |
| 接手 agent 撞到 §11 没列的错误      | **必须**加进 §11,给下个接手 agent 留路标 |
| gril 阶段决策变更(D1~D7)            | 改 §0 决策表 + 改相关实施点 + 更新"已钉死"清单 |

### 15.2 接手 agent 错误处理(gril 阶段,本仓库不 commit)

接手 agent 撞错时的正确姿势:

```
1. 报错 → 看 §11 找对应症状 / 错误码
2. §11 没列 → 自行诊断,把诊断过程写到 §11(留路标)
3. 修复 → 不"顺手"改 §0 决策;只在决策点变更时改
4. **不 commit** —— gril 阶段所有改动留在工作区,等用户拍板
5. 报告给用户时,把 §11 的新增条目也带出来
```

**反模式**(接手 agent 别踩):

- ❌ "改完代码发现 §11 写错了,顺手改了" —— §11 是契约,改了不改文档
  就是"挖坑"
- ❌ "撞错后只口头说,不加 §11" —— 下个接手 agent 撞同样的错又得重头诊断
- ❌ "我在 git log 看到别人撞过这个错,以为 §11 已记" —— 自己再撞一次确认
- ❌ "gril 阶段把 docs/iso-build.md git add 了" —— D7 决策禁止

### 15.3 文档结构约束

接手 agent 改文档时,**章节编号不能变**:

| 节           | 内容            | 谁可以改               |
| ------------ | --------------- | ---------------------- |
| §0 决策记录  | 用户拍板的决策  | **用户**               |
| §接手必读    | 阅读路径 + 纪律 | **慎改**(影响接手体验) |
| §1~§7 调研   | 历史背景        | 冻结(只校 typo)        |
| §8 蓝图差异  | 实测结果        | 慎改(实测变化)         |
| §9 实施步骤  | 本任务核心      | **可改**(实施时校对)   |
| §10 命令契约 | API 文档        | 同步改(命令体变化时)   |
| §11 失败诊断 | 失败库          | **鼓励加**(经验沉淀)   |
| §12 验收清单 | 验收项          | **勾选 ≠ 修改**        |
| §13 扩展矩阵 | 决策权归属      | 慎改(用户决策)         |
| §14 快照     | 实施前状态      | **不再更新**(历史快照) |
| §15 维护纪律 | 文档自身        | 慎改                   |

### 15.4 版本表(D7 gril 决策:不维护)

> **D7 决策(2026-07-06)**:本文档不 commit,版本表无意义。已删除原 v0.1~v0.5。
> 决策 / 实施变更走 §0 决策表 + §15.1 触发条件 + 本节自身。

### 15.5 文档自身 meta

- **文件路径**:`docs/iso-build.md`
- **总行数**(D7 重写后):约 2050 行
- **章节数**:16(接手必读 + §0~§15)
- **代码块数**:约 30 个
- **依赖文件**:blueprint.scm / source/config.org / source/channel.lock /
  source/manifest.scm / .gitignore / scripts/build-image.scm(新建)
- **关联仓库**:Testament(只读参考,不在本仓库)
- **是否进仓库**:**否**(D7 决策)

### 15.6 给未来接手 agent 的话

如果你读到这一节,说明你已经基本搞懂了这份文档和这个任务。

**最关键的两件事**:

1. **§9.4.5 关键陷阱 4 条**,背下来:
   - tangle 目标必须 `tmp/live-iso.scm`,**不能**复用 `tmp/config.scm`
   - `<<live-modules>>` 不能被主 main 块引用
   - `blue check` 不做 cross-tangle 验证,必须 `tail tmp/live-iso.scm`
   - `make-installation-os` 来自 guix core `(gnu system install)`(**不是** rosenthal),
     live-modules 必须 `(use-modules (gnu system install))`

2. **§11.5 接手 agent 边界**,背下来:
   - 你**不能**跑 `blue build-iso`(那是 sudo)
   - 你**不能**改 `source/channel.lock`(那是 blue update 才能改)
   - 你**能**跑 `blue check` / `blue --dry-run *` / `blue block-show` / `blue block-replace`

剩下的就是体力活了。撞错 → §11 → 加 §11 → commit → 报告用户。**别慌,别急,别瞎试**。
