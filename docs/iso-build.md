# ISO 自主打包机制

> 一条 `blue build-iso` 命令,基于本仓库 `source/config.org` 打出 Live ISO 镜像, 产物落到 `dist/jeans-<variant>-<date>.<arch>.iso`。

> 详细代码 / 决策 / 调试见 `source/config.org` 的 `* Live ISO` 章节、`blueprint.scm` §8.5 注释、`tools/build-image.scm` 文件头。本文档**只**说明功能模型、使用方式、关键设计权衡。

## §0 一句话模型

```
source/config.org  (Live ISO 章节)
        │
        ▼  blue build-iso 跑 ob-tangle
tmp/live-iso.scm
        │
        ▼  guix repl -- tools/build-image.scm
        │     (在 guix time-machine -C source/channel.lock 内)
        │
guix system image --image-type=iso9660
        │  → Guix core 走 iso9660 → grub-hybrid → xorriso
        ▼
dist/jeans-<variant>-<YYYYMMDD>.<arch>.iso
```

整条管线 ≤ 50 行自写代码,其余都是 Guix core + BLUE build system 的标准件。

| 层                   | 由谁负责                                                   | 本仓库做的事                           |
| -------------------- | ---------------------------------------------------------- | -------------------------------------- |
| iso9660 / EFI / MBR  | Guix core 的 `--image-type=iso9660`                        | 不碰                                   |
| installation-os 基底 | Guix core `(gnu system install)` 的 `make-installation-os` | 继承并定制                             |
| 非自由内核 / 固件    | nonguix 的 `linux` + `linux-firmware`                      | 接入                                   |
| OS 定义              | 本仓库                                                     | `source/config.org` `* Live ISO` 章节  |
| 构建编排             | BLUE build system                                          | `build-iso` 命令(`blueprint.scm` §8.5) |
| 产物落地             | 本仓库                                                     | `tools/build-image.scm`(~30 行)        |

## §1 用法

### 1.1 命令语法

```bash
blue build-iso [VARIANT] ...
```

| 调用                     | 行为                                 |
| ------------------------ | ------------------------------------ |
| `blue build-iso`         | 构建 `%images` 列出的全部变体        |
| `blue build-iso xfce`    | 只构建 XFCE 镜像(主目标)             |
| `blue build-iso minimal` | 只构建 minimal 镜像(纯 CLI fallback) |

变体清单定义在 `blueprint.scm` §8.5 的 `%images` 常量。文件名前缀在
`%live-iso-prefix`(`"jeans"`,本仓库自有名)。

### 1.2 产物

```
dist/
├── jeans-xfce-20260706.x86_64-linux.iso        # 主目标,GUI 桌面
└── jeans-minimal-20260706.x86_64-linux.iso     # 纯 CLI fallback
```

镜像内部:

- **live user**:`live` / `live`(密码故意弱,装机完成即销毁)
- **root shell**:`fish`
- **桌面**(xfce 变体):`xfce-desktop-service-type` + `lightdm` 自动登录 live
- **tty1 回退**:`make-installation-os` 自带 kmscon(可手动启用)
- **nonguix kernel**:`linux` + `linux-firmware`(支持非自由 wifi/显卡)
- **4 套 substitute 镜像**: nonguix / guix-moe / panther / sjtug

### 1.3 烧盘与验证

```bash
# 烧 U 盘
dd if=dist/jeans-xfce-20260706.x86_64-linux.iso of=/dev/sdX bs=4M status=progress conv=fsync

# QEMU 验证
qemu-system-x86_64 -m 4G -enable-kvm -cdrom dist/jeans-xfce-*.iso

# sha256 校验
sha256sum dist/jeans-xfce-*.iso
```

## §2 关键设计决策(为什么这样做)

### §2.1 OS 定义写进 `source/config.org`,不另起 `config/live/*.scm`

Testament 把 ISO 配置独立成 `config/live/<variant>.scm`,理由是"不走
tangle,出错面小"。本仓库选择**写进主 config.org**:

- 配置统一:主机 + ISO 同一份源,改公钥/镜像一次改两边
- Noweb 拼合已是熟练工具,分两个文件反而引入新概念
- 代价:`source/config.org` 多一个 tangle 目标(`tmp/live-iso.scm`),
  必须**绝对不能**与 `tmp/config.scm` 混 —— 见 §3.1 陷阱 1

### §2.2 变体列表用 BLUE 常量,不走文件枚举

Testament 用 `find` 扫 `config/live/*.scm` 推断变体。本仓库用
`blueprint.scm` §8.5 的 `%images` 常量,显式列举:

```scheme
(define %images '("xfce" "minimal"))
```

- 顺序 = 构建顺序(主目标先,fallback 后)
- 加新变体只改一处
- 配合 `images-from-arguments` 实现"无参全量,带参过滤"语义

### §2.3 `make-installation-os` 来自 guix core,不是 rosenthal

这是 gril 阶段的最大事实更正 —— 多个文档路径早期误以为它来自
`rosenthal services file-systems`,实测该模块**不**导出
`make-installation-os`,只导出 `btrbk-service-type` /
`dumb-runtime-dir-service-type` / `zfs-service-type`。

真实位置:`(gnu system install)`,`gnu/system/install.scm:693`(guix
`9e068cc`)。live-modules 块**必须** `(use-modules (gnu system install))`。

### §2.4 不复用 channel lock

Testament 有独立 `config/live/channels.lock`(3 个频道,精简)。
本仓库决定**复用 `source/channel.lock`**:

- 本仓库只有一份主机配置,ISO 用的频道是它的子集,重复 lock 是过度工程
- 代价:ISO 镜像 closure 包含 bluebox / sops-guix 等主机专用频道的依赖
  (实测未导致问题,若将来想精简,加 `source/live-channels.lock` 即可)

### §2.5 substitute 镜像全复刻(4 套,不只是 nonguix)

ISO 装机时 `guix pull` / nonguix kernel 拉 substitute 需要公钥,
**少一个就拉不动**。本仓库配置 `source/config.org` 主机环境用 4 套
镜像(nonguix / guix-moe / panther / sjtug),ISO 完整复刻 —— 而不是
只配 nonguix。

### §2.6 显式声明的 4 个 P 阶段(gril 拍板)

| 决策   | 内容                                              | 理由                                                    |
| ------ | ------------------------------------------------- | ------------------------------------------------------- |
| **D1** | 首选变体 = XFCE                                   | 用户要桌面辅助装机,`xfce-desktop-service-type` 是标准件 |
| **D2** | ISO OS 目标 = "提供装机用环境",不干预装好后       | 装好后用户自己 `blue rebuild` 重建                      |
| **D3** | 4 套 substitute 镜像全复刻(§2.5)                  | 装机时 `guix pull` 要用公钥                             |
| **D4** | 只装 mihomo 包,不引 service / config / tun        | ISO 内手动启;装好后由 `blue rebuild` 重建               |
| **D5** | live user = `live` / `live`                       | lightdm auto-login 后 sudo 需要明确密码                 |
| **D6** | 显式加 kmscon(由 `make-installation-os` 默认提供) | tty1 装机回退,X 失败时的救命 console                    |
| **D7** | 本文档**进**仓库                                  | 给接手 agent 留契约 —— 见 §6.2 维护纪律                 |

## §3 已知陷阱(接手维护必看)

详细错误码表 / 决策矩阵见 `source/config.org` `* Live ISO` 章节头部注释。
本节只列**最致命的 4 条**,改前请 grep 整个项目确认影响范围。

### §3.1 tangle 目标绝对不能复用 `tmp/config.scm`

若 `:tangle ../tmp/config.scm` 误用,`%live-installation-os` 会污染
主机配置,`blue rebuild` 报 `unbound variable: %system` 或
`multiple definition`。

**验证**:`tail tmp/live-iso.scm` 末行应是 `%live-installation-os`
(裸值,非 `(define ...)`);`grep -c '%live-installation-os' tmp/config.scm` 应为 0。

### §3.2 `<<live-modules>>` 不能被主 main 块引用

`blue check` 不做 cross-tangle 验证 —— 它只看每个 `#\+NAME:` 块自身的括号。
如果 main 块误引用 `<<live-modules>>`,`tmp/config.scm` 里会出现
ISO 块内容,直接撞死 `blue rebuild`。

**验证**:`grep -E 'live-(modules|installation)' tmp/config.scm` 应为空。

### §3.3 `blue --dry-run build-iso` 仍会真跑 tangle

`--dry-run` 短路的是 `%run`(guix reconfigure / ISO 镜像构建等),
但 `org-babel-tangle-file` 必须真跑(`#:real? #t`),否则 dry-run 验证
拿不到 `tmp/live-iso.scm` 产物。

### §3.4 `make-installation-os` 来自 `(gnu system install)`

(同 §2.3) 实施前更正记录里有 5 条相关修正,`source/config.org` `* Live ISO`
章节顶部注释里有完整留路标。**不要凭印象改 use-modules 列表**。

### §3.5 `services` 字段里 `<<guix-substitutes>>` 不能当 `cons*` 元素

`<<guix-substitutes>>` 块展开后本身是一个 `(list 4个simple-service ...)`。
若写成 `(cons* (service xfce-desktop-service-type) <<guix-substitutes>>
(service lightdm-service-type ...) ...)`,会把整个 list 当单个 service 元素
嵌进 services 列表,报 `'services' field must contain a list of services`。

**修复**:用 `append` 拍平 ——
`(services (append <<guix-substitutes>>
(list (service xfce-desktop-service-type)
(service lightdm-service-type ...) ...)))`。
`blue check` 只看块内括号平衡,**不会**抓到这类 "list-in-list" 类型错,
只能靠 guix 真跑报 `must contain a list of services` 才发现。

### §3.6 `xfce-wayland-session` 的 builder 必须 `with-imported-modules`

该包用 `trivial-build-system`,其 builder 默认**不**导入 `(guix build utils)`,
直接在 `#~(begin ...)` 里 `(use-modules (guix build utils))` 会报
`no code for module (guix build utils)`(drv 编译阶段失败)。

**修复**:用 `(with-imported-modules '((guix build utils)) #~(begin ...))`
包裹 gexp,把模块编译进构建环境。注意 `with-imported-modules` 多包一层,
结尾需补一个右括号,否则 `blue check` 报 `live-xfce-define` 多 1 个左括号。

## §4 出错怎么办(快速索引)

| 症状                                        | 看哪                                                  |
| ------------------------------------------- | ----------------------------------------------------- |
| `blue build-iso` 报 `unbound variable`      | `source/config.org` `* Live ISO` 章节顶部注释 + §3.4  |
| `'services' field must contain a list of services` | `<<guix-substitutes>>` 被当 cons* 元素,§3.5 改 append |
| `no code for module (guix build utils)`(drv 编译失败) | `xfce-wayland-session` builder 缺 `with-imported-modules`,§3.6 |
| `no code for module (gnu packages X)`       | 删该 use-modules,改走 `specifications->packages`      |
| `extraneous field initializer (X)`          | 字段名/值类型错,查 Guix 手册对应 service              |
| `Wrong type to apply: #<<service-type>>`    | service 括号错位,§3.1 排查                            |
| `blue check` 报多余括号                     | `blue block-show` 定位块名,git diff 找行              |
| `guix time-machine: failed to authenticate` | `source/channel.lock` 频道公钥过期,`blue update` 重生 |
| `error: connection refused`                 | 网络/防火墙,见 §5 网络镜像配置                        |
| `permission denied (store path)`            | `/gnu/store` 权限,见 §5                               |
| QEMU 启动但 X 启动失败                      | tty1 进 kmscon 调试,X 日志在 `~/.local/share/xorg/`   |

接手 agent 真撞错时:先 grep `tmp/build-*.log`(若 `blue build-iso --keep-failed`
启用),再查 Guix 手册对应 service / package 文档,最后才看上游 issue
(codeberg `guix/guix#7373` 跟踪 installer 阻塞)。

## §5 网络与镜像

装机时 substitute 拉取走 `source/config.org` 主机配置里 `simple-service` 块定义的
4 套镜像(nonguix / guix-moe / panther / sjtug),ISO `live-installation-os` 完整
复刻。公钥内嵌为 `plain-file`,**不**依赖 ISO 运行时联网拉公钥。

- 默认从 bordeaux 拉,nonguix 内核通常较快
- 若某镜像宕,guix 自动 fallback —— 不会因单点失败整体死
- 中国大陆环境:`sjtug` 镜像常比 bordeaux 快 5-10 倍

## §6 维护文档

### §6.1 何时改本文档

| 触发                        | 改哪                                               |
| --------------------------- | -------------------------------------------------- |
| 加新桌面变体(走 §7.1 流程)  | §1.1 变体表 + §2.6 D1 行                           |
| 升 channel.lock 后 API 改名 | §3.4 引用 → `source/config.org` 注释同步           |
| 撞到 §3/§4 没列的错误       | §3 / §4 各加一行,给下个接手 agent 留路标           |
| 修了 §2 设计决策            | §2.x 加修订记录,**不**改原段落(保留 gril 拍板原貌) |

### §6.2 维护纪律

1. **本文档是"功能说明",不是"实施史"** —— 详细代码 / 调试留到 `config.org` 注释
2. **章节编号不变**(`§X` 是交叉引用锚点)
3. **新增内容加进对应章节**,不开新文件
4. **改完跑** `git diff docs/iso-build.md` 自查:行数应 ≤ 600
5. **改本文档的人,不是 gril 拍板者** —— 决策变更需在 §2.x 末尾加修订注,
   不直接改原决策行(原 gril session 的决定保留可见)

## §7 扩展矩阵(用户拍板,非 to-do)

### §7.1 桌面变体

| 变体      | service-type                        | DM      | 工作量  | 触发条件                 |
| --------- | ----------------------------------- | ------- | ------- | ------------------------ |
| `xfce`    | `xfce-desktop-service-type`         | lightdm | ✅ 已做 | 本任务                   |
| `minimal` | (用 make-installation-os 默认)      | kmscon  | ✅ 已做 | xfce 跑不动的 fallback   |
| `gnome`   | `gnome-desktop-service-type`        | gdm     | 2-3h    | nvidia 显卡 / Wayland    |
| `kde`     | `plasma-desktop-service-type`       | sddm    | 2-3h    | KDE 专有应用             |
| `niri`    | `home-niri-service-type`(rosenthal) | greetd  | 4-5h    | 对齐 Testament niri 体验 |

### §7.2 平台

| 平台          | 状态                       | 工作量 |
| ------------- | -------------------------- | ------ |
| x86_64-linux  | ✅ 已支持                  | 0      |
| aarch64-linux | 隐式(`#:efi-only?` 自动切) | 0      |
| i686-linux    | ❌                         | 半天   |

### §7.3 工程优化

| 扩展                                      | 工作量 | 触发条件                   |
| ----------------------------------------- | ------ | -------------------------- |
| `source/live-channels.lock` 独立 ISO lock | 1h     | 追求 Testament 级密封性    |
| `tools/sign` GPG detach-sign              | 1h     | ISO 公开发布前             |
| ISO 内嵌 `examples/` 配置模板             | 半天   | 装机引导想"开箱即用本仓库" |
| `blue build-iso --keep-failed`            | 15min  | 调试阻塞时                 |
| `blue build-iso --substitute-urls=...`    | 30min  | 测试专用 mirror            |

---

**相关阅读**:

- `source/config.org` `* Live ISO` 章节 —— 实施细节 / 全部 use-modules / 块代码
- `blueprint.scm` §8.5 —— `%images` / `images-from-arguments` / `build-iso-command`
- `tools/build-image.scm` —— guix-system image 产物落地助手(~30 行)
- `docs/secrets.md` —— 同期构建的年龄加密入仓参考
