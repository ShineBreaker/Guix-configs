# Guix-configs — 仓库导引

以 Guix 为核心的个人系统配置仓库：系统层（`operating-system`）与 Home 层（`home-environment`）由单一 `source/config.org` 声明，经 `blue` 构建落地（tangle → `tmp/config.scm` → 一次 reconfigure 同时应用两层）。

<!-- structor:begin depth=1 -->

<!-- 此树形目录由 structor 自动生成，请勿手动编辑。 -->

```
Guix-configs///
├── .agents/
├── docs/
├── dotfiles/
├── screenshots/
├── source/
├── tools/
├── .gitattributes
├── .gitignore
├── .gitmodules
├── .prettierrc.json
├── .zcodeignore
├── CLAUDE.md
├── LICENSE
├── README.org
└── blueprint.scm
```

<!-- /structor -->

目录树由 `blue structor` 生成，不手改（手改会被下次刷新覆盖）；新增、移动或删除文件后跑一次刷新，旗标见 `blue help structor`。

## 硬约束（全分支适用）

<critical>
1. **就近优先**：更近目录的 `AGENTS.md` 覆盖本文件；文档与源码冲突时以源码为准。命令清单以 `blue list` 为准，本文不缓存它，单命令详情见 `blue help <命令>`。
2. **改源，不改部署位**：`~/.config/`、`~/.local/` 等已部署位置是产物，要改的是仓库里的配置源。改完是否即刻生效由部署模型决定——`dotfiles/immutable/` 各包构建时复制进 `/gnu/store` 只读副本再软链到 `$HOME`，须 `blue home` 重建才生效；`dotfiles/mutable/` 由 Stow 直链仓库源码，保存即生效。源码与部署位对不上时用 `md5sum` 比对。
3. **sudo 边界**：调试只跑 `blue home`（无需 sudo）；`blue rebuild`、`guix system reconfigure`、`blue init` 需 sudo，由人执行——配置确认无误后提醒用户手动 rebuild 固化。guix 命令一律经 `blue` 走，否则失去频道锁定。
4. **生成物与第三方内容不手改**：`tmp/` 下的产物与 `source/channel.lock`（均由 `blue update` 重新生成）、本文件的目录树、子模块内部（用户点名除外，如 `tools/linux-setup`；改动留在子模块自身工作区与 `docs/`）；mutable 文件不进 `immutable/` 目录，否则双重部署冲突。
5. **不覆盖用户未提交的工作**：`blue home` 会把工作区的 `source/config.org` tangle 出来实际部署，该文件有未提交改动时先征得用户同意（`blue check`、`blue --dry-run rebuild` 不部署，可照跑）。用户可能正在同时编辑：写这类文件前留副本与 sha256，写回前重新核对，文件变了就停下报告；`git checkout` / `stash` / `reset` 会覆盖他人改动，一律不用。
</critical>

## 按任务找入口

改动落在哪一类，就只读对应行的文件；末列是该分支特有的收尾规矩。

| 你在改                                                                                                   | 先读                                                                                       | 收尾                                                                                     |
| -------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------- |
| 系统 / Home 声明、模板与全局变量：`source/config.org`、`source/files/`、`channel.scm`、`information.scm` | `source/AGENTS.md`（配置逻辑与 org 写法集中在此）                                          | `blue check` + `blue --dry-run rebuild`，两条都不写系统；语义改动按其 §验证 另做实际求值 |
| dotfiles 源：`immutable/` 各包、`mutable/` 各应用包                                                      | `dotfiles/AGENTS.md` 为索引，immutable 各子目录多带 `AGENTS.md`                            | immutable 须 `blue home` 才生效，mutable 保存即生效                                      |
| 任何脚本：`blueprint.scm`、`tools/` 与 `dotfiles/` 下的脚本、`config.org` 内嵌块                         | `docs/scripts/CONVENTIONS.md`（注释分工、§4 语言可靠性、§8 blue 本体、接口变更、验证方法） | 冻结的跨语言协议不得破坏（其 §6）；手册索引见 `docs/scripts/README.md`                   |
| 新增 `~/.local/bin` 入口                                                                                 | `dotfiles/mutable/AGENTS.md`                                                               | 一包一入口；`toolbox check` 阻断级执法                                                   |
