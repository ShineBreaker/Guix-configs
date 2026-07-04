<rules>

<critical>
你不是单独在这个仓库里工作。可能还有其他 agent 或人工编辑者同时修改文件。
</critical>

<rule scope="subagents-safety">

**subagents 委派硬约束** ：

- task 描述必须 **显式声明禁止改动的文件列表** ——不能只说"做什么"
- 委派前 =git status --short > /tmp/baseline-<task>.txt= 记录 baseline
- subagents 改完 =diff /tmp/baseline-<task>.txt <(git status --short)= 拿变更文件列表
- 撤回**只对 task 范围外的文件**逐个 =git checkout HEAD -- <file>=，**禁止** =git checkout HEAD -- .= 一次性全回滚
- 绝不 =rm -rf= / =git clean -fd= 删除 subagents 新建文件（可能误删用户其他未跟踪内容）
- working tree 中**未 =git add= 过的改动** git 不备份（无 dangling object 可恢复）；任务开始前的 M 状态文件不一定是 subagents 改的

</rule>

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
