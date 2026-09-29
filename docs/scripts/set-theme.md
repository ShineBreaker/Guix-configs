<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# set-theme.sh — darkman 模板渲染器（`$$VAR$$` → 模式变量组）

- 源码：`dotfiles/immutable/noctalia-suite/.config/darkman/script/set-theme.sh`
- 部署：`~/.config/darkman/script/set-theme.sh`（immutable，改后须 `blue home`）
- 调用方：`~/.local/libexec/theme-common.sh`（由 darkman mode.d hook 触发）

## 用途

按 `script_dir/config.json` 中选定模式的变量组，把 `~/.config/darkman/config/` 下所有模板里的 `$$KEY$$` 占位符渲染后写入 `~/.config/` 对应相对路径。

## 用法

```bash
set-theme.sh <light|dark>
```

## 输入输出

- 输入：`$script_dir/config.json`（`.dark` / `.light` 变量组；`.colors` 子表会展平进顶层）、
  `~/.config/darkman/config/` 模板树（`-type f -o -type l`）。
- 输出：`~/.config/<rel>` 渲染文件（删除旧文件后 `sed -f` 生成；`chmod --reference` 保权限）。
- 固定注入变量：`mode`（当前模式）、`home`（`$HOME`）——模板可直接用 `$$mode$$`/`$$home$$`。

## 依赖

`jq`（必需，缺失即报错退出）、`sed`、`realpath`、`mktemp`、`find`、`chmod`。

## 设计决策与不变量

- **越界写防护**：渲染目标 `dst` 先做 `realpath -m` 前缀校验必须落在 `$HOME` 内——模板文件名可携带 `..` 或符号链接，防越界写到 `$HOME` 之外。
- **先删后写**：目标可能是 store 软链或只读副本，`rm -f` 后重建；sed 脚本的 key/value 都经转义（key 转 regex 元字符，value 转 `|&\`——`|` 是自定义分隔符）。
- **未定义占位符 fail-fast**：模板里出现不在变量组的 `$$KEY$$` → 报错 exit 1（宁可空文件不留半渲染态）。
- `mktemp` 的 sed 脚本用 `trap … EXIT` 清理。

## 故障排查

- `Error: no variables resolved for mode "X"` → `config.json` 缺该模式键或变量组为空。
- `Error: undefined placeholder "…"` → 模板用了未声明变量，补 `config.json` 键或改模板。

## 变更记录

- 2026-10：重构——工作原理与防护说明迁入本文档，注释压缩；行为不变（测试 HOME 全链路渲染验证一致）。
