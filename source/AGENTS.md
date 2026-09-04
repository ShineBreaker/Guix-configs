# source/ — Guix 配置源目录

`config.org` 是唯一 Org 源（**不要新建第二个**），tangle 生成 `tmp/config.scm`；`blue rebuild` 完成 tangle → 括号检查 → reconfigure，单次同时应用 operating-system 与内嵌 guix-home-service。

<!-- structor:begin depth=1 -->

<!-- 此树形目录由 structor 自动生成，请勿手动编辑。 -->

```
source/
├── files/
├── nix/
├── channel.lock
├── channel.scm
├── config.org
├── information.scm
└── manifest.scm
```

<!-- /structor -->

## 修改 config.org 前必读

`config.org` 头部有两段 Agent 指引（`* System` 与 `* Home` 节）：系统层职责边界与决策规则、Home 层职责与 dotfiles 管理规则。**先读完这两段再动手。**

结构分区：模块导入 → 系统配置（Bootloader/FileSystems/Kernel/Packages/Services/Users）→ 用户配置（Packages/Services/Environment/Font）→ `dotfile-services`（`home-dotfiles-service-type` 分发 `dotfiles/immutable/`）。

## Org Noweb 机制

- `#+NAME: ref` 命名代码块；`<<ref>>` 引用（**Org 功能，非 Scheme 语法**）
- `#+begin_src scheme :tangle ../tmp/config.scm :noweb yes` 标记 tangle 目标
- `<<ref>>` 是功能开关：注释掉的引用即停用该块

## 全局变量与文件系统（`information.scm`）

被 `config.org` 头部 `(load "../source/information.scm")` 加载；变量清单直接读该文件。改前检查 `config.org` 各块引用是否需同步。

文件系统模型：根目录 tmpfs（重启清空）；持久化靠 Btrfs 子卷挂 `/var/lib`、`/gnu`、`/boot` 等；用户数据 `/data` 分区 bind-mount 到 `~`。**持久化目录必须同时在 `%data-dirs` 与 `%btrfs-subvolumes` 中登记**。头部代码块（全局变量、文件系统、内核）同时影响 system 与 home；启动时序敏感的服务集中在 `filesystem-services` 块。

## files/ 模板系统

存放**需要路径注入**的静态模板，由 `home-files-service-type` 直接部署；`$$bin/foo$$` 替换为 Guix 包绝对路径（rosenthal `computed-substitution-with-inputs`）。**纯配置文件不要放这里**，放 `dotfiles/immutable/<app>/`。

## 频道管理

`channel.scm` 可编辑（频道与分支定义）；`channel.lock` 自动生成，**禁止手动编辑**。流程：改 `channel.scm` → `blue pull` → `blue update`。

## blue 命令

```bash
blue rebuild               # tangle → 括号检查 → reconfigure → locate --update（agent 禁跑，提醒用户）
blue --dry-run rebuild     # 构建验证不写入（tangle/括号检查真跑）
blue home                  # 仅 Home 层（含 dotfiles），不需 sudo —— agent 调试用
blue check                 # 逐块括号平衡检查（定位到块名）

# 块级编辑（改单个 #+NAME: 块，避免读 2000 行 config.org）
blue block-show <name>                 # 提取块 body 到 tmp/block-<name>.scm（打印路径）
blue block-replace <name> <body-file>  # 替换 + 原子写回 + 验证
```

块级编辑要点：body 首两行是 lang/noweb 标记，第 3 行起是内容；括号验证仅对 scheme 块触发；body 可能含 `<<ref>>` 占位需自行追踪；失败时 `git checkout source/config.org` 恢复。适合低耦合小块，改大块仍建议读整段。

<critical>
- 优先改 `dotfiles/`，只在需要 Guix 介入时改 `config.org`；能用 Home 解决就不用 System
- 不要手动编辑 `tmp/config.scm`（重新 tangle 会覆盖）
- 新增 dotfile 子目录后必须更新 `dotfile-services` 的 `packages` 列表
</critical>
