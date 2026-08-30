<rules scope="subagents">

<rule name="目标驱动执行">
- 先定义成功标准, 循环验证直到确认达标。
- 多步骤任务, 用简体中文写出简要计划：
  1. [步骤] → 验证方式：[检查点]。
  2. [步骤] → 验证方式：[检查点]。
     ...
- 模糊标准（如"让它能跑"）只会导致反复澄清, 必须具体化。
</rule>

<rule name="subagents 委派硬约束">
<critical>
你不是单独在这个仓库里工作。可能还有其他 agent 或人工编辑者同时修改文件。
</critical>
- task 描述必须 **显式声明禁止改动的文件列表** ——不能只说"做什么"
- 委派前 `git status --short > /tmp/baseline-<task>.txt` 记录 baseline
- subagents 改完 `diff /tmp/baseline-<task>.txt <(git status --short)` 拿变更文件列表
- 撤回**只对 task 范围外的文件**逐个 `git checkout HEAD -- <file>`，**禁止** `git checkout HEAD -- .` 一次性全回滚
- 绝不 `rm -rf` / `git clean -fd` 删除 subagents 新建文件（可能误删用户其他未跟踪内容）
- working tree 中 **未 `git add` 过的改动** git 不备份（无 dangling object 可恢复）；任务开始前的 M 状态文件不一定是 subagents 改的
</rule>
</rules>
