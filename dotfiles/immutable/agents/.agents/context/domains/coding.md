# coding 域原则，Git 仓库内注入

<rules scope="coding">

<rule name="外科手术式修改" priority="high">
- 仅修改与任务直接相关的代码，沿用项目既有风格与命名约定。禁止顺手重命名、格式化无关代码或清理无关废弃代码，发现时留在收尾指出。
- 只用一次的逻辑直接写在调用处，除非它会复用或封装了独立复杂逻辑。能在一个函数内写完就不拆函数，能不用 try/catch 就不用。
- 移除本次改动废弃的导入、变量与函数。注释只写非显而易见的动机，不留中间尝试或旧代码。每一行改动都要对应明确需求。
</rule>

<rule name="代码质量底线" priority="high">
- 用类型与数据结构排除非法状态，用通用模型收敛特例分支。领域逻辑不得写入共享公共路径。
- 外部输入只在入口校验一次，内部传递已定型的值，禁止逐层重复校验。禁止滥用 any、unknown 或非必要的可选字段。
- 无预定有界重试或降级策略的外部调用失败时，直接返回错误并保留现场。禁止吞掉异常拿默认空值继续，也禁止将未处理的失败标为成功。需人工介入的环节保留可接管状态。
</rule>

<rule name="Git 操作规范" priority="high">
边界约束：
- 严禁整文件重写实现局部小改动。
- 严禁全量回滚 `git checkout HEAD -- .` 或 `git clean -fd`（丢弃改动不可逆，回滚必须逐文件明确执行）。
- 严禁在 commit 流程中自动执行 `git push`。

执行流程：

1. 起步：执行 `git status --short` 确认初始工作区状态。
2. 任务中：仅修改相关文件；已有修改的文件修改前先读取最新内容。
3. 完成前：
   - 运行针对性测试验证改动；pre-commit 检查失败时就地修复而非绕过。
   - 审查正确性、边界与安全性。
   - 再次执行 `git status --short`，核对提交清单仅包含本次任务文件。
4. 遇并行冲突、来源不明的改动或需破坏性 Git 操作时，停手向用户汇报。
</rule>

<rule name="commit 规范" priority="high">
提交遵循 `~/.config/git/gitmessage` 规范：
1. Header: `<type>(<scope>): <subject>`（不兼容变更使用 `<type>!:`）
   - 单文件 scope 为文件名（如 `feat(core.ts): ...`），多文件 scope 为模块名（如 `feat(auth): ...`）。
   - 动词开头，祈使语气，首字母小写，末尾不加句号。
2. Body: 空一行后阐述「为什么改」（Why），保持简明扼要。
3. Footer: `BREAKING CHANGE: <说明>` 或 `Closes #<issue>`。
4. Assisted-by 标签（AI 辅助时必填）：
   - 格式：`Assisted-by: NAME <EMAIL>`
   - NAME 按当轮 runtime 填实际 agent 名及模型名（`宿主 (模型)` 形态），EMAIL 用该宿主约定的 noreply 地址；历史 commit 与文档示例只是快照，禁止照抄。
   - 多作者各占一行，尖括号不可省略。
</rule>

</rules>
