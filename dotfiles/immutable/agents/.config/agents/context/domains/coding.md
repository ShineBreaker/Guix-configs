# coding 域原则 — git 仓库内注入（zcode/omp/hermes 由 selector 自动附加；crush 按 INDEX 指引手动拉取）

<rules scope="coding">

<rule name="外科手术式修改" priority="high">
- **偏爱直接、无聊、可维护的代码** : 反对 hacky/魔法代码、不必要的抽象、包装和 cast-heavy 契约。如果一种写法"聪明"但难维护，选 boring 的写法。
- **文件大小警觉** : 单个文件超过 1000 行必须问自己：这里有多少是重复模式、可提取的公共逻辑、或本不该在这层的代码？
- **注释只允许描述当前状态** : 注释只写 non-obvious reason，禁止保留 intermediate attempts；PR 描述只写最终行为，diff 里看不出来的取舍以及从未合入的状态一律不要提及
- **只动必须改的** : 不顺手优化旁边代码、注释或格式。
- **沿用现有代码风格** : 即使和你偏好不同。发现无关废弃代码, 在任务完成后用中文指出即可, 不擅自删除。
- **做好代码的清理工作** : 移除因你的改动而不再使用的导入、变量、函数。

检验标准：每一行改动都能追溯回用户要求。
</rule>

<rule name="代码质量底线" priority="high">
- **警惕随机意大利面条增长** : 新 ad-hoc 条件是设计问题而非风格问题。每添加一个特殊 case，都要质疑：能否用更普适的模型消除这个 case？
- **消灭错误类** : 与其「写测试抓住下一次同类错误」，不如「用更好的设计让这类错误根本不可能发生」——优先在类型/数据结构层面让非法状态无法表达，事后用测试兜底是下策。
- **类型和边界整洁** : 质疑不必要的可选性、`unknown`、`any`。逻辑应在规范层表达，特性逻辑不应泄露到共享路径。
- 正确性/安全性/回归优先于纯风格评论。不接受"能用但更乱"的代码。
</rule>

<rule name="git 操作规范" priority="high">
**禁止**：
- 整文件重写实现小功能、清理/格式化无关内容、提交无关文件
- 不遵守 `~/.config/git/gitmessage` 中的 commit 规范进行对应操作
- 批量 `git checkout HEAD -- .`，或任何可能丢弃未 commit 文件的更改（撤回逐文件进行）
- 在 commit 流程中顺手 push 到 remote

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

<rule name="commit 规范" priority="high">
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

- 基本格式: Co-authored-by: NAME <EMAIL>
- AI 辅助时 NAME 写 agent 名并括注模型，EMAIL 用 agent 的 noreply 地址:
  e.g. Co-authored-by: ZCode (GLM-5.3) <noreply@z.ai>
- 多个共同作者各占一行，行间不空行；EMAIL 尖括号不可省略
</rule>

</rules>
