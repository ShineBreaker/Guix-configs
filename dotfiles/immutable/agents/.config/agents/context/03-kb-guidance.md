<critical>
知识库和记忆系统是默认第一步。每个任务开始前必须执行预检，完成后必须评估经验记录。
未实际运行 kb 检索命令就声称"已查过"是严重违规。
详细规范见 self-improving 和 knowledge-base skill。
</critical>

<pre_check>
1. `kb list --category <相关> --all` — 扫描相关领域
2. `kb search "<关键词>" --context 2` — 检索正文
3. `kb memory --project .` — 获取项目上下文
4. 高相关 → 纳入计划；无相关 → 静默继续
</pre_check>

<triggers>
经验信号（debug/config/refactor/research）→ `kb add`
偏好/习惯信号 → `kb memory --add --type feedback`
项目决策信号 → `kb memory --add --type project --project <name>`
<critical>
任务完成信号（"可以用了"/"Done"）→ 必须触发 self-improving 总结。
用户提出新要求 → 先总结再处理。
</critical>
完整信号列表见 self-improving skill 的 references/triggers.md。
</triggers>

<write_decision>
<critical>
不是所有经验都值得写完整卡片。轻量写入优先于完整卡片。
</critical>
| 目标 | 方式 | 条件 |
|------|------|------|
| 可复用技术经验 | `kb add` 完整卡片 | 排查 >2 步、跨工具、架构决策 |
| 偏好/习惯 | `kb memory --add` | 偏好表达、行为纠正 |
| 一句话注意 | `kb inbox` / `kb update --append` | 简单修正、补充 |
| 不写 | — | 一次性细节、环境失败、否定声明 |
优先级：纠正(mistake) > 调试(debug/config) > 工作流 > 功能
</write_decision>

<write_quality>
<critical>
写入后必须执行校验闭环：`kb lint --fix` → `kb search` 去重 → `kb connect` 关联。
</critical>
标题声明式结论 | 自包含 | 置信度标注 `(推测)`/`(单源)` | 时效性 `(截至 YYYY-MM)`
Org 格式：代码块 `#+begin_src`，粗体 `*text*`，列表 `+ item`
</write_quality>

<lifecycle>
<critical>
经验卡片有生命周期，策展时自动处理。详见 kb-curator skill。
</critical>
done → stable(策展验证) → stale(>30天未验证) → archived(>90天)
feedback >60天 stale 未验证 → 归档到 MEMORY-ARCHIVE.org
</lifecycle>

<new_commands>
kb touch <id>                    更新 LAST_USED + LAST_VERIFIED
kb merge <primary> <sec>...      合并卡片
kb archive <id>                  归档卡片
kb restore <id>                  恢复归档卡片
kb deduplicate [--threshold 0.7] 检测重复
kb review <id>                   审查卡片质量
kb health                        知识库健康度报告
kb memory --archive-to-file <id> 归档 feedback 到 MEMORY-ARCHIVE.org
kb memory --stale --auto-archive-days 60  自动归档陈旧 feedback
kb memory --project-touch <name> 更新项目 LAST_ACTIVE
</new_commands>
