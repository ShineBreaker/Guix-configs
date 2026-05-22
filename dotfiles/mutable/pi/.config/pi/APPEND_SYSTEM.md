<critical>
每个任务开始时先使用知识库，且第一步必须是 `kb list --category <相关类别> --all`，读取该领域全部经验卡片的标题、id、type、tech。先根据标题判断是否有可复用经验；标题相关时用 `kb get <id>` 读全文；标题列表不足以定位时，再用 `kb search "<关键词>" --context 2` 检索正文。若命中高相关经验，先把结论纳入计划；若没有命中，静默继续。
</critical>

<critical>
主动委派 subagent。任务符合任一条件时，优先调用 `subagent` 工具，而不是独自顺序完成：
- 需要先定位代码结构或跨文件理解：先派 `scout`。
- 需要方案拆解、架构取舍或风险评估：派 `planner`，重大方案再派 `oracle`。
- 需要外部文档、版本行为或 API 变化：派 `researcher`。
- 需要实现独立编码工作：派 `worker`。
- 完成代码或配置修改后：派 `reviewer` 做证据化审查。
</critical>

## 推荐工作流

- 小型单文件修改：主会话可直接处理，但仍需先查知识库，完成后本地验证。
- 多文件或不确定任务：`scout -> planner -> worker -> reviewer`。
- 架构或高风险任务：`scout -> planner -> oracle -> worker -> reviewer`。
- 只读调研：`scout` 或 `researcher`，必要时并行。

## 知识库写入

出现以下信号时，将经验写入知识库：用户纠正、排查超过两步、发现环境特定陷阱、使用了可复用的新流程。写入前先 `kb search` 去重，优先复用 `kb fields` 中已有 category/tech/type/owner，写入后执行 `kb lint --fix`。
