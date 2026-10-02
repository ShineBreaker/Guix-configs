<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# doc-punct.py — 中文技术文档标点规范化（`blue format` 的后端）

`tools/doc-punct.py` · 不部署（`blueprint.scm` 以仓库内路径调用）· 调用方：`blueprint.scm` 的 `format-command`

本文是全仓唯一的中文文档排版规则权威清单：规则变更改这里，并同步补进 `--self-test` 回归用例。

## 用法

```bash
python3 tools/doc-punct.py                 # 全仓 git 可见的 .md/.org，逐处报告并写回
python3 tools/doc-punct.py --check         # 同上，只报告不写盘
python3 tools/doc-punct.py FILE...         # 只处理指定文件并写回
python3 tools/doc-punct.py --check FILE... # 只处理指定文件，只报告
python3 tools/doc-punct.py --self-test     # 跑回归自检后退出
```

`blue format [FILE...]` 是 `format-command` 对本脚本的直传，只报告不写盘用 `blue format --check`；`blue --dry-run format` 走 `%run` 的 dry-run 短路，**根本不跑脚本**，只打印 `[预演] python3 …/doc-punct.py --check`（见 [blueprint.md](blueprint.md)）。

每处改动打 `=== <相对路径>  (N 处) ===` 并逐条列出去重后的上下文，末尾汇总 `合计 N 处`，`--check` 模式追加 `（未写入，--check 模式）`；路径不存在则跳过并在 stderr 打 `跳过（不存在）：<path>`。

## 规则清单

七条 `rule_*` 按 `PIPELINE` 顺序串联，每条返回 `(新行, 说明列表)`。表格行（`line.lstrip()` 以 `|` 开头）的空格由对齐与标记语法决定，只跑标「适用」的原地替换类规则。

| 规则 | 判据 | 表格行 |
| --- | --- | --- |
| `rule_halfwidth_to_fullwidth` | 中文语境的 `,;:?!()` 转全角：`,`/`;` 一侧是汉字即转；`:` 两侧都是字母或汉字不转（`主:次` 是字段格式说明）；`()` 按内容判，内含汉字才转；`?`/`!` 邻接汉字、中文标点或 `)]】」』*` 才转 | 适用 |
| `rule_strip_after_cjk_punct` | 全角标点后的半角空格删除，但下一字符是 `` =`~*_ `` 时保留（org 等宽/行内代码/粗体标记前的空格是排版惯例） | 不适用 |
| `rule_ellipsis` | `...` → `……`；紧邻字符是字母数字则不动（版本号、省略范围） | 不适用 |
| `rule_fullwidth_alnum` | 全角数字/字母 → 半角 | 不适用 |
| `rule_unit_space` | 数值与单位符号之间补半角空格（`8MB` → `8 MB`），单位词表见 `UNIT_RE` | 不适用 |
| `rule_dash_unspace` | `——` 前后去空格；单个 `—` 是连接号，前后空格是正确排版，不动 | 适用 |
| `rule_han_ascii_spacing` | 汉字/中文标点之间的空格（含全角空格）删除；汉字与 ASCII 字母/数字之间补空格 | 不适用 |

`rule_han_ascii_spacing` 的补空格另有三重排除：汉字后紧跟空白、闭括号、竖线或中文标点时不加（`安装 guix。`）；上下文已以 `[\w.-]+]` 或 `=\s*key$` 收尾时不加（配置项名 `[connection]`、枚举值 `2=disable省电`、org 键值 `=pkg-bin=`）。

## 实现与约束

- **每条规则在自己收到的行上重算 protected spans（最关键的不变量）**：`PIPELINE` 逐条串联，后一条拿到的是前一条的输出、行长已变；会改变行长度的规则（删空格、补空格、省略号整体替换）若复用调用方算出的旧坐标，保护区间会错位，把 org 等宽/行内代码边界吃掉——`=(路径 挂载点)=` 里的空格就是这么被误删过的。
- **13 类保护区间**：`protected_spans` 返回行内不该碰的字符区间——行内代码、org 等宽、org 波浪、org 链接与 org 裸链接、md 图片、md 链接、URL、模板变量 `{{...}}`、org 关键字行、org 旧式块名整行、org 块起始行、org 块结束行（正则以源码为准）。
- **中文语境按行判不按邻接判**：中文句子常夹整段英文代码片段，靠标点邻接汉字判断会漏；一行里没有汉字则整行跳过。
- **括号按内容判**：内含任何中文才转全角，内全英文留半角（`(c,d)` 与 `(最常见坏法)` 分别是反例与正例）。
- **`.` 不机械转 `。`**：小数、版本号、句点边界歧义三重风险，划入人工处理——`HALF_TO_FULL` 表里刻意没有 `.`。
- **块内原样保留**：`scan` 跟踪围栏状态，`` ``` `` / `~~~` 与（仅 `.org` 的）`#+begin_` … `#+end_` 整块跳过。
- **文件枚举用 git 不用 glob**：`own_files` 跑 `git ls-files --cached --others --exclude-standard -- '*.md' '*.org'`；glob 的 `**` 不穿透 `.config` / `.zcode` 等隐藏目录，会漏掉一大批文档。
- **排除清单以源码 `EXCLUDE` 元组为准**：vendored 子模块（`tools/linux-setup/`、`tools/appimage-run/`、`fcitx5/rime/`）、技能树（`.local/share/hermes/skills/`、`.config/agents/skills/`、`agents/skills/`）与归档目录 `.archive/`。
- **保守变换 + 逐处报告**：不追求全自动正确，追求「误改一眼能复核、能 `git diff` 找回」。

## 排障

误改文档：`git diff <文件>` 复核后 `git checkout -- <文件>` 还原。确认是规则缺陷而非用法问题时，先把坏样例加进 `_self_check` 的回归用例再改规则——用例复现失败之前不动 `PIPELINE`。