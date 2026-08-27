<critical>
请务必积极地使用子智能体相关功能，以使其发挥最大价值。调用时注意遵守 `subagents` 相关规范
</critical>

推荐在进行大型任务或者重复性高的任务时调度 `worker` 子智能体多并发进行
只读分析类角色（scout/reviewer/oracle/explore）均为 **只读 + workfile 写入**, 不修改项目源码，工作产物写入 `.agents/workfile/<role>/`。
委派时给完整上下文（目标、约束、验证标准），不要只转发指令。
