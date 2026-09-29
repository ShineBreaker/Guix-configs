<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# anchors-lib.sh — anchors.json 分层加载与 ratchet 合并库

- 源码：`dotfiles/immutable/agents/.config/agents/anchors-lib.sh`
- 部署：`~/.config/agents/anchors-lib.sh`（immutable，改后须 `blue home`）
- 调用方：被同目录 `gate-core.sh` `source`（部署位置优先、同目录兜底，见 [gate-core.md §部署形态约束](gate-core.md)）；zcode `session-start.sh` 也直接 source 它
- 决策核消费者：zcode / crush / pi（`pi-gate/index.ts`）/ hermes（`plugins/gate/__init__.py`）/ DSH（`gate.js`）五端适配器经 gate-core 间接受益

## 用途

只做「读 + 合并」，判定语义全部在 `gate-core.sh`——规则源与决策核各自单一，避免五端适配器复制演化。

## 分层 ratchet 模型

1. **代码底层 DEFAULT**：`frozen_commands` 恒含 `"sudo"`（agent 任何场景都不需要提权）；其余字段空、
   `builtin_rewrite: true`。无任何 anchors.json 时返回纯 DEFAULT。
2. **全局** `~/.config/agents/anchors.json`：跨工作区通用约束，meta-frozen 人工维护。
3. **项目级** `<root>/.agents/anchors.json`：从起点向上遍历收集每一层，含 git 根后停止
   （`_find_anchors_files_near_to_root` 最多上溯 64 层）。

合并顺序：全局（底）→ 项目根 → … → 项目近。ratchet 语义（`_ANCHORS_MERGE_JQ`）：

- 数组字段（`frozen_commands` `frozen_paths` `frozen_globs` `interactive_commands` `bare_repl_commands`
  `human_only_actions` `anchor_measurements`）：unique 并集；`sensitive_patterns` 按 `.pattern` unique 并集。
- 映射字段（`redirect_conventions` `rewrite` `path_hints`）：近层覆盖远层（jq `*` 合并，单层 string 值等价浅合并）。
- `builtin_rewrite`：布尔值由给出该字段的层覆盖（未给出的层不影响）。
- **只加不减**：项目层无法移除全局或代码底层的条目——近层要削弱某条只能加 `unless_inside` 条件豁免。

## 接口

| 函数                                    | 语义                                                                              |
| --------------------------------------- | --------------------------------------------------------------------------------- |
| `load_merged_anchors [start_dir]`       | 合并全部层，stdout 输出合并 JSON；任何层损坏/合并失败 → 回退 DEFAULT 并记日志     |
| `find_git_root <dir>`                   | 向上找含 `.git` 的目录；找不到返回 `dir` 本身（即非仓库目录的 PROJ = 自身）       |
| `glob_to_ere <glob>`                    | glob → 锚定 ERE（`**`→`.*` 并吞 `**/` 斜杠、`*`→`[^/]*`、`?`→`[^/]`），见 §glob 语义 |
| `expand_tilde <path>`                   | `~/` 前缀按 `$HOME` 展开                                                          |
| `log_gate_error <ext> <where> <msg>`    | 错误日志写 `~/.config/omp/extensions/.load-errors.log`（对齐 pi-gate，防静默吞错） |

- 允许重复 `source`（`_ANCHORS_LIB_LOADED` 幂等哨兵）。
- `load_merged_anchors` 收集项目层用进程替换而非管道——管道右侧在子 shell 执行，`mapfile` 赋值会丢失。

## 契约（被 source 的库）

不改调用方 shell 选项（不设 `-e`/`-u`/`pipefail`）、不 `exit`、不依赖未被调用方声明的环境状态；
函数名前缀 `_` 表示内部实现细节。

## glob 语义

`glob_to_ere` 输出锚定 ERE（`^...$`），对齐 pi-gate 旧实现 `globToRegex`：

| glob           | ERE                   |
| -------------- | --------------------- |
| `*.lockfile`   | `^[^/]*\.lockfile$`   |
| `dist/**`      | `^dist/.*$`           |
| `a?b`          | `^a[^/]b$`            |
| `**/*.so`      | `^.*[^/]*\.so$`       |
| `deep/**/file` | `^deep/.*file$`       |
| `a.b`          | `^a\.b$`              |

由 `gate-core.sh` 在 `frozen_globs` 匹配时调用：含 `/` 的 glob 对 git-root 相对路径（RELP）匹配，
不含 `/` 的对 basename 匹配；且仅在目标位于项目内（INSP=1）时生效。

## 变更记录

- 2026-10：重构——文件头分层说明迁入本文档，注释压缩；函数与 merge 语义不变（语料矩阵验证一致）。
