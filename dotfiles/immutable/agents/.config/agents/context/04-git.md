<rules>

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

<rule scope="commit">

操作规范:

1. 格式：<type>(<scope>): <简短描述>
   不兼容变更在 type 后加 !, 如 feat!:

2. scope 规则:

- 单文件: 必须加文件名。 e.g. feat(<文件名>): <简要描述>
- 多文件: 用组件的名字代替文件名。 e.g. feat(<组件>): <简要描述>

3. 描述规范:

- 第一行按照 scope 规则撰写
  1. 动词开头, 祈使语气
  2. 首字母小写, 末尾不加句号
- 空一行之后允许撰写简要描写细节, **禁止过于详细的描写**
- Body 解释「为什么改」
- Footer 写 BREAKING CHANGE:
  1. <说明> 或 Closes #<issue>
  2. LLM 工作时撰写 Co-authored-by 标签

4.Co-authored-by 标签

基本格式: Co-authored-by: NAME <EMAIL>

AI 辅助时 NAME 写 agent 名并括注模型，EMAIL 用 agent 的 noreply 地址:
e.g. Co-authored-by: ZCode (GLM-5.3) <noreply@z.ai>

多个共同作者各占一行，行间不空行；EMAIL 尖括号不可省略

</rule>

</rules>
