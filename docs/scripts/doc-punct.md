<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# doc-punct.py — 中文技术文档标点规范化（blue format 的后端）

- 源码：`tools/doc-punct.py`
- 部署：不部署（blueprint.scm 以仓库内路径直接调用）
- 调用方：`blueprint.scm` 的 `format-command`——`blue format [FILE...]`；`blue --dry-run format` 透传 `--check` 只报告不写盘

## 用法

```bash
python3 tools/doc-punct.py --check          # 全仓库只报告不改
python3 tools/doc-punct.py FILE...          # 写入指定文件
python3 tools/doc-punct.py --check FILE...  # 只报告不改
python3 tools/doc-punct.py --self-test      # 跑自检后退出
```

不带 `FILE` 时扫描 git 可见的仓库自有 `.md` / `.org`（`git ls-files` 驱动，`EXCLUDE` 排除 vendored 与 agent skills）。每处改动打印上下文，便于人工复核。

## 规则清单

只做保守的机械变换，逐行处理、逐处报告：

1. 中文语境的半角逗号/分号/冒号/问号/叹号 → 全角；包住中文的半角括号 → 全角
2. 全角标点两旁不留半角空格（org 等宽/代码/粗体标记前的空格例外保留）
3. `...` → `……`（前后是字母数字视为版本号/省略范围，不动）
4. `——` 前后不空格（单个 `—` 是连接号，空格是正确排版）
5. 汉字与 ASCII 字母/数字之间补半角空格
6. 汉字/中文标点之间的空格（含全角空格）→ 删除
7. 全角数字/字母 → 半角；数值与单位符号之间补半角空格（`8MB` → `8 MB`）

代码块、行内代码、URL、org 链接/等宽/波浪、md 链接/图片、模板变量 `{{...}}`、org 关键字与块边界行一律原样保留；纯英文行整行跳过。

## 工作原理

- `protected_spans` 给出行内不该碰的字符区间（13 类正则）。
- `PIPELINE` 按序套用七条 `rule_*` 规则，每条返回 `(新行, 说明列表)`；`convert` 对表格行只跑「原地替换」类规则（行首 `|` 判定），`scan` 跳过 md fence 与 org `#+begin_/#+end_` 块。
- `own_files` 用 `git ls-files --cached --others --exclude-standard` 枚举目标——glob 的 `**` 不穿透 `.config` 等隐藏目录，会漏掉一大批文档。

## 设计决策与不变量

- **每条规则在自己收到的行上重算 protected spans**（最关键的不变量）：会改变行长度的规则若复用旧坐标，保护区间会错位，把 org 等宽/行内代码边界吃掉——`=(路径 挂载点)=` 里的空格就是这么被误删过的。
- **「中文语境」按行判不按邻接判**：中文句子常夹整段英文代码片段，靠标点邻接汉字判断会漏。
- **括号按内容判**：内含任何中文转全角，内全英文留半角（`(c,d)`、`(最常见坏法)` 分别对应）。
- **句点不机械转**：`.` 转 `。` 风险高（小数、版本号、句点边界歧义），留人工。
- **保守变换 + 逐处报告**：不追求全自动正确，追求「误改一眼能复核、能 `git diff` 找回」。

## 故障排查

误改了文档：`git diff <文件>` 复核，`git checkout` 还原；若是规则缺陷，把坏样例加进 `_self_check` 的回归用例再修。

## 变更记录

- 2026-09-29：模块与规则 docstring 迁入本文档；修复 7 处 ruff 告警（两处 `open` 未用 context manager、嵌套 `if` 合并、`startswith` 元组化、删多余 coding 声明、补可执行位）。行为不变——`--check` 全仓输出与旧版逐字节一致。
