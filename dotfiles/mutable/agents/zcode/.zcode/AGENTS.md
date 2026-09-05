<critical>
请务必积极地使用子智能体相关功能，以使其发挥最大价值。调用时注意遵守 `subagents` 相关规范
委派时给完整上下文（目标、约束、验证标准），不要只转发指令。
</critical>

子智能体权限分层：

- scout / reviewer / oracle / visual 为 **只读 + workfile 写入**：不修改项目源码，工作产物写入 `.agents/workfile/<role>/`
- **Explore 是平台级强只读智能体，不能写任何文件**（明确授权也不行，harness 系统级约束），产出只能通过最终报告带回；需要落盘的侦察任务改派 scout
- worker 是唯一允许修改项目源码的子智能体；委派 task 时仍必须显式声明禁止改动的文件列表

子智能体功能分层：

- 进行大型任务或者重复性高的任务时：调度 `worker` 子智能体多并发进行
- 需要阅读图像/视频，且 **自己没办法做到** 的时候，请直接调用 `visual` 子智能体，不要调用外部工具（ OCR 工作除外）
- 遇到非常棘手的问题，或是用户强调 "仔细进行校验" 时，请调用 `oracle` 子智能体

subagents 委派纪律：

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
