<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# darkman mode.d hooks — dark/light 入口薄 shim

- 源码：`dotfiles/immutable/noctalia-suite/.local/share/dark-mode.d/0-apply-theme.sh`、`.local/share/light-mode.d/0-apply-theme.sh`
- 部署：`~/.local/share/{dark,light}-mode.d/0-apply-theme.sh`（immutable，改后须 `blue home`）
- 调用方：darkman daemon 按 mode.d 约定扫描执行（**此路径文件必须存在且可执行**）
- 共享实现：`~/.local/libexec/theme-common.sh`（见 [theme-common.md](theme-common.md)）

## 用途

两个文件互为镜像，各一行实质内容：

```bash
exec "${HOME}/.local/libexec/theme-common.sh" dark   # 或 light
```

## 设计决策与不变量（部署约束）

- **不能用 symlink**：immutable 包经 Guix Home 把每个文件复制成**独立** store 项再软链到 `$HOME`——mode.d 目录里放 symlink 的目标解析在 store 布局下不可靠，所以复制一份实体 shim 用 `exec` 转发。
- **必须绝对路径**：`$0` 相对关系不存在（各文件独立 store 项，包内相对层级在部署形态不成立），故引用部署位置绝对路径 `~/.local/libexec/theme-common.sh`。
- **住 libexec 不住 share**：共享实现是内部脚本，统一放 `libexec`，不混入 `share` 数据层；mode.d 下只留 darkman 约定必须的入口。

## 变更记录

- 2026-10：重构——部署约束说明迁入本文档，注释压缩为不变量指引；行为不变。
