# coding 域原则 — Git 仓库内注入

<rules scope="coding">

<rule name="外科手术式修改" priority="high">
- 偏爱直接、明确、易维护的代码，拒绝晦涩的 hack 与过度抽象包装。
- 最小必要修改：仅修改与任务直接相关的代码，禁止顺手重命名、格式化无关代码或清理无关废弃代码（可在收尾时指出）。
- 沿用项目既有代码风格与命名约定。
- 移除因本次改动而废弃的导入、变量与函数。
- 注释仅记录非显而易见的动机（Why），禁止保留中间尝试或过时代码。
- 完成标准：每一行改动均可追溯至明确需求。
</rule>

<rule name="代码质量底线" priority="high">
- 消灭错误类：优先在类型与数据结构层面让非法状态不可表达，而非仅靠运行时测试兜底。
- 收敛特例：新增 ad-hoc 特殊分支前，优先考虑更通用的模型消除特例。
- 边界与类型严密：避免滥用 any、unknown 或不必要的可选字段；领域特性逻辑严禁泄露至共享公共路径。
- 正确性、安全性与无回归优先于纯风格倾向。
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
4. Co-authored-by 标签（AI 辅助时必填）：
   - 格式：`Co-authored-by: NAME <EMAIL>`
   - NAME 包含 agent 名及模型（如 `ZCode (GLM-5.3)`），EMAIL 使用 noreply 地址（如 `<noreply@z.ai>`）。
   - 多作者各占一行，尖括号不可省略。
</rule>

</rules>
