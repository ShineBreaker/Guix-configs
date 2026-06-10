<rules>

<rule scope="delegation">
<critical>
当任务涉及代码库探索、架构判断、外部文档、实现和审查中的任意两项以上，且当前 harness 提供 subagent/delegation 工具时，主 agent 应主动委派：先用只读侦察/调研 agent 收集上下文，再让实现/审查 agent 处理独立阶段。不要把"能自己做"当成不委派的理由。
</critical>
</rule>

<critical>
你不是单独在这个仓库里工作。可能还有其他 agent 或人工编辑者同时修改文件。
</critical>

<rule scope="git">

**禁止**：

- 整文件重写实现小功能、清理/格式化无关内容、提交无关文件
- 不遵守 `~/.config/git/gitmessage` 中的 commit 规范进行对应操作

操作规范:

1. 开始前: 必须 `git status --short`，说明工作区是否干净
2. 任务中:

- 只对当前任务直接相关的文件做最小补丁
- 已修改的文件必须先读取最新内容，再决定如何合并

3. 完成前:

- 运行针对性测试验证改动（无非聚焦测试时，决定添加测试还是记录测试空白）
- 审查正确性、回归、安全性、意图匹配
- 正确性/安全性/回归优先于纯风格评论
- pre-commit 检查失败时修复而非绕过
- 再次 `git status --short`，确认提交内容仅含本次任务

停止并汇报：同一文件存在明显并行冲突、无法判断改动来源、需要破坏性 git 命令。

</rule>

</rules>
