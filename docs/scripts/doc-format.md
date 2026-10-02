<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# doc-format.sh — 文档格式化编排（`blue format` 的后端）

`tools/doc-format.sh` · 不部署（`blueprint.scm` 以仓库内路径调用）· 调用方：`blueprint.scm` 的 `format-command`；可单独运行

仓库文档规范分两级落地：中文标点与中英间距归 `doc-punct.py`，Markdown 结构归 prettier。本脚本只做编排——决定文件清单、决定两级顺序、把退出码汇总。

## 用法

```bash
blue format                      # 全部仓库自有文档（经 format-command）
blue format FILE...              # 只处理指定文件
blue format --check              # 只报告待处理项，有改动退出 1
./tools/doc-format.sh            # 不经 blue 直接跑，等价于 blue format
```

## 实现与约束

- **两级顺序不可颠倒：先 doc-punct，后 prettier**。doc-punct 把半角标点转全角会改变表格单元的显示宽度，prettier 必须在它之后按最终宽度对齐列宽；反序（prettier 先跑）第一遍跑完仍有表格待对齐，要跑第二遍才收敛。当前顺序实测**一遍收敛**（第三遍零改动）。
- **文件清单只有一个真相源**：不带 FILE 时走 `doc-punct.py --list`，即 doc-punct.py 的 `EXCLUDE` 边界（排除 vendored 子模块与 agent skills）。编排脚本里不复制第二份排除清单——两份清单必然漂移。
- **按 realpath 去重**：`CLAUDE.md` 是指向 `AGENTS.md` 的软链。去重既避免同一文件被处理两遍，也绕开 prettier 对「显式指定的软链」直接报错退出的行为（`[error] Explicitly specified pattern ... is a symbolic link`，退出码 2）。
- **正文不折行**：`prettier --prose-wrap preserve`，与仓库根 `.prettierrc.json` 的同名配置重复是有意的——仓库规范禁止把段落按固定列宽切断，而 prettier 的默认值会按 `printWidth` 重排正文（80 列），一旦失效就等于把这套规范整个推翻。写在调用点是第二道保险。
- **不重排文档内嵌的代码块**：`.prettierrc.json` 的 `embeddedLanguageFormatting: "off"`。JSON / TS 示例紧凑还是展开是作者的表达选择，格式化器不该替作者改；否则文档内容会随格式化器的代码风格偏好漂移。
- **`.org` 只跑标点一级**：prettier 不认 org。格式化 org 结构需要另一个工具，当前不做。
- **`--check` 汇总退出码**：doc-punct 与 prettier 任一有待处理项即退出 1，可直接用于 CI 卡点。
- **前置依赖**：`python3`、`prettier`（配置包里是 `prettier-bin`）。缺 prettier 时报错并提示只跑标点的命令，而不是静默跳过——`blue format` 的名字承诺的是完整格式化。

## 排障

| 现象                                                  | 原因与处理                                                                             |
| ----------------------------------------------------- | -------------------------------------------------------------------------------------- |
| `blue format` 后 `git diff` 只有表格                  | 正常：prettier 主要工作是按 CJK 显示宽度对齐列宽，外加补文件末尾换行                   |
| `Explicitly specified pattern ... is a symbolic link` | 传入的路径是软链。编排脚本已按 realpath 去重，直接用 `blue format` 走全量即可避免      |
| `找不到 prettier`                                     | profile 里缺 `prettier-bin`；临时只跑标点用 `python3 tools/doc-punct.py`               |
| 有序列表里的手工列对齐被压成单空格                    | prettier 归一化列表标记后的间距。示例想保留对齐就改成表格，不要靠空格排版              |
| 想让某文件不被格式化                                  | 该文件应落进 doc-punct.py 的 `EXCLUDE`（vendored / agent skills 语义），而不是加白名单 |
