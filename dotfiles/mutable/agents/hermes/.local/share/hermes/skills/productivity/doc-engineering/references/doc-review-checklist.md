# 文档校对 12 项人工清单

`scripts/doc-check.py` 检测**机器可读的 drift**（CLI count 漂移、引用路径缺失、
日期戳文件名 smell、未知 MCP tool 名）。本清单覆盖**机器不可读的**部分——任何
LLM 读 doc 时都该过一遍。两者互补。

## A. 与代码/工具对齐（4 项）

1. **每个 MCP tool 名在 `~/.local/bin/agenote_mcp.py` 注册？** 跑 `grep '^def
mcp__agenote__' ~/.local/bin/agenote_mcp.py | wc -l` 应 = 文档 MCP 工具表行数。
2. **每个 CLI 子命令在 `~/.local/bin/agenote` 注册？** 跑 `~/.local/bin/agenote --help | grep -c '^  [a-z]'` 应 ≥ 文档 CLI 表格行数。
3. **行为描述与代码真实行为一致？** 例如"默认 dry_run=True"——查函数签名确认。
4. **deprecated / 旧子命令被错误保留？** 用 `agenote help` 列出当前所有子命令，与文档对账。

## B. 与缺陷/任务书对齐（2 项）

5. **缺陷/任务书里 D1-D5 这种修复点都在文档里有对应章节？** "已落地修复"表是否齐全。
6. **每个修复点有"验证摘要"或回归测试 ID？** 不能只说"已修"。

## C. 文档结构卫生（3 项）

7. **没有日期戳文件名？**（如 `references/2026-07-04-foo.md`）—— 内容应归并到主题文件。
8. **没有"双份事实"？** 同一段既出现在主文档又出现在 references/—— 一份过期另一份不会跟。
9. **修订记录 / "as of" 日期标记存在？** 否则下次不知道上次验证什么时候。

## D. 风格与可发现性（3 项）

10. **CLI/MCP/磁盘路径三种引用风格统一？** `~/.local/bin/agenote` vs
    `dotfiles/mutable/agenote/...` vs `/home/brokenshine/.local/bin/agenote` 任意混用，
    读者不知道哪个是真路径。
11. **代码块都标 VERIFIED BY？** 没标的——agent 不知道上次手工验过没。
12. **章节标题 ≤ 4 层？** H1 / H2 / H3 / H4 之内；超过 → refactor。

## 用法

```bash
# 跑机器可读部分（自动）
python3 ../scripts/doc-check.py /path/to/doc.md --cli /path/to/cli --json

# 跑人工部分（手动，12 项每项打勾/叉）
cat references/doc-review-checklist.md | head -50
```
