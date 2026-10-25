# 文档校对报告：<doc-name>

**生成日期**：<YYYY-MM-DD>
**校对 agent**：<agent-name>
**校对范围**：<doc-path>

## 1. 机器可读 drift（来自 `scripts/doc-check.py`）

```
<paste doc-check.py output>
```

| 检查项                 | 状态        | 备注  |
| ---------------------- | ----------- | ----- |
| real-doc-smoke         | <PASS/FAIL> | <msg> |
| json-parse-and-N-tools | <PASS/FAIL> | <msg> |
| missing-path-detect    | <PASS/FAIL> | <msg> |
| cli-count-drift-detect | <PASS/FAIL> | <msg> |
| no-unknown-mcp-tools   | <PASS/FAIL> | <msg> |
| --help-no-crash        | <PASS/FAIL> | <msg> |
| date-filename-smell    | <PASS/FAIL> | <msg> |

## 2. 人工 12 项清单（来自 `references/doc-review-checklist.md`）

### A. 与代码/工具对齐

- [ ] 1. 每个 MCP tool 在源码注册
- [ ] 2. 每个 CLI 子命令在源码注册
- [ ] 3. 行为描述与代码一致
- [ ] 4. deprecated 子命令被错误保留？

### B. 与缺陷/任务书对齐

- [ ] 5. 缺陷修复点（D1-D5 等）都有对应文档章节
- [ ] 6. 每个修复点有"验证摘要"

### C. 文档结构卫生

- [ ] 7. 没有日期戳文件名
- [ ] 8. 没有双份事实
- [ ] 9. 修订记录 / as-of 日期存在

### D. 风格与可发现性

- [ ] 10. 路径引用风格统一
- [ ] 11. 代码块标 VERIFIED BY
- [ ] 12. 章节标题 ≤ 4 层

## 3. 总结

- **整体状态**：<healthy / has-drift / major-rot>
- **建议行动**：<rewrite / expand / align / no-change>
- **优先级**：<P0 / P1 / P2>
