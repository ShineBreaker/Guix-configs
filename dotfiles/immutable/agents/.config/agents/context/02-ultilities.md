<rules>

<critical>
**知识库和记忆系统是默认第一步，不是可选优化。**
每个任务开始时先使用知识库和记忆系统，且必须按照如下步骤进行：

**知识库预检**（可复用技术知识）：

1. `kb fields --category`
2. `kb list --category <相关类别> --all`

**记忆预检**（用户癖好 + 项目上下文）：

1. `kb memory --project .` — 获取当前项目的记忆（项目级决策、状态、上下文）
2. 反馈记忆和用户画像已通过 globalContext 自动加载，无需手动检索

**定位区分**：

- MEMORY（癖好/偏好）→ 用户行为模式、交互习惯、项目级不可推导信息
- KB（可复用知识）→ 技术经验、调试方案、配置技巧

读取该领域全部经验卡片的标题、id、type、tech。先根据标题判断是否有可复用经验；
标题相关时用 `kb get <id>` 读全文；标题列表不足以定位时，再用 `kb search "<关键词>" --context 2` 检索正文。
若命中高相关经验，先把结论纳入计划；若没有命中，静默继续。
每次接到任务后，必须在阅读大量源码或动手修改前实际运行一次知识库检索命令；不要等用户提醒，也不要只在最终总结时才想起知识库。
</critical>

<rule scope="knowledge-base">

每次接到任务时，按照以下步骤来调用知识库：

1. 调用 `knowledge-base` skill 加载 CLI 用法
2. 根据任务选择 category，**先运行 `kb list --category <category> --all`**，读取该领域所有经验卡片的 `id/title/category/type/tech`，先从标题判断是否有相关经验；不确定 category 时先运行 `kb fields`
3. 对标题明显相关的卡片运行 `kb get <id>` 读取全文；标题列表不足以定位时，再运行 `kb search "<任务关键词 工具 框架>" --context 2` 检索正文。`kb search` 默认按多关键词相关度排序，必要时用 `--all-terms` 收窄
4. 高相关经验 → 明确把结论纳入计划或提醒用户；空/低相关 → 静默继续
5. 如果 `kb` 不可用，明确报告工具缺失；不要假装已经查过

常用映射：

- Guix / 系统配置 / XDG / bwrap / shell wrapper → `guix` 或 `general`
- Emacs 配置 → `emacs` 或 `emacs-config`
- Pi / OpenCode / Crush / agent / skills / subagent → `general`，并用关键词二次 `kb search`
- 前端、游戏 → `gamedev`

---

<critical>
当任务涉及代码库探索、架构判断、外部文档、实现和审查中的任意两项以上，且当前 harness 提供 subagent/delegation 工具时，主 agent 应主动委派：先用只读侦察/调研 agent 收集上下文，再让实现/审查 agent 处理独立阶段。不要把"能自己做"当成不委派的理由。
</critical>

对话中检测经验信号和记忆信号
自动检测以下信号，触发 `self-improving` skill 记录：

用户表示任务完成（"可以用了"、"一切正常工作"、"Done"）
必须触发 `self-improving` skill 执行总结流程。
若有可记录经验 → `kb search` 去重 → `kb add` → `kb lint` → 传播联动。
若有可记录偏好 → `kb memory --add --type feedback`。
若有项目决策变化 → `kb memory --add --type project --project <id>`。
若无 → 确认后停止。
若用户提出新要求 → 先总结，再处理。

经验信号速查

<signals>

  <signal type="mistake">
    用户纠正（"不对，应该是…"、"你搞错了…"） → `mistake` 卡片
  </signal>
  
  <signal type="note">
    发现知识空白（文档过时、API 行为不符预期） → `note` / `research` 卡片
  </signal>
  
  <signal type="debug">
    踩坑/排查 >2 步、环境差异 → `debug` 卡片
  </signal>
  
  <signal type="refactor">
    发现更优方案 → `refactor` 卡片
  </signal>
  
  <signal type="config">
    配置陷阱（跨工具集成、非默认组合） → `config` 卡片
  </signal>

</signals>

记忆信号速查（写入 MEMORY）

<signals>

  <signal type="preference">
    偏好表达（"我喜欢..."、"不要..."、"停..."） → feedback 记忆
  </signal>
  
  <signal type="behavior-correction">
    行为纠正（纠正你的工作方式，非技术错误） → feedback 记忆
    区分："不要用 try-catch，用 Result 类型" 是偏好 → MEMORY
    "这个正则写错了" 是技术纠正 → KB
  </signal>
  
  <signal type="habit">
    习惯模式（同一偏好出现 ≥2 次） → feedback 记忆
  </signal>
  
  <signal type="project-decision">
    项目级决策或状态变化（不可从代码推导） → project 记忆
  </signal>
  
  <signal type="external-reference">
    外部系统/文档/资源的位置信息 → reference 记忆
  </signal>

</signals>

双重归属：项目决策同时有跨项目复用价值时，同时写入 MEMORY + KB。

<checklist>
规范速查
- 流程：写入前 `kb search` 去重，`kb fields` 复用已有标签
- 校验：写入后 `kb lint --fix` 校验并修复格式
- 标题应包含结论："X 导致 Y"而非 "Y 问题排查"
- 不确定结论标注 `(推测)` / `(单源)`
- 时效性声明附 `(截至 YYYY-MM)`
- 绝不孤立写入——每次至少检查一次关联
- 发现用户偏好/习惯/项目变化时，用 `kb profile --add` 更新用户画像
</checklist>

### 持续学习

除交互式经验记录外，定期运行 `kb-curator` skill 进行后台策展：

- 从对话历史提取潜在经验
- 诊断知识库健康度（重复、矛盾、空白）
- 调和矛盾、晋升 pattern、建立关联
- 输出策展报告

策展是增量式知识维护，与对话中的实时记录互补。

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

---

<rule scope="cli-design">

**CLI 设计原则**（当你被要求设计或审查 CLI 时）

面向人类的 CLI 常阻塞 agent（交互式提示、大量前置文档、无示例的帮助文本）。Agent 优先模式应是 headless 的。

| 原则                | 坏例子                                  | 好例子                                       |
| ------------------- | --------------------------------------- | -------------------------------------------- |
| **非交互优先**      | `mycli deploy` → `? Which environment?` | `mycli deploy --env staging`                 |
| **增量发现**        | 每次运行打印全部手册                    | 按 subcommand 的 `--help`                    |
| **`--help` 含示例** | 仅列举 flags                            | 包含 `mycli deploy --env staging` 等真实调用 |
| **stdin/管道**      | 不支持                                  | `cat config.json \| mycli import --stdin`    |
| **快速失败**        | 挂起等输入                              | 立即报错 + 正确示例调用                      |
| **幂等性**          | 重复运行有副作用                        | 安全 no-op 或显式"already done"              |
| **破坏性操作**      | 无 dry-run                              | `--dry-run` + `--yes/--force`                |
| **一致结构**        | 无规律                                  | `resource verb` 模式一致                     |
| **结构化输出**      | 只有装饰性输出                          | 返回 ID、URL、时长等机器可用数据             |

</rule>

---

<rule scope="code-review">

**审查标准**（当你被要求审查代码时）

审查优先级（从高到低）：

1. **结构回归** — 是否有让整层复杂度消失的重构机会？能否删掉一整类 helpers 或条件分支？
2. **简化机会** — 重复模式、可合并的 helpers、不必要的条件层
3. **意大利面条增长** — 新 ad-hoc 条件、纠缠的流程、随机复杂度
4. **边界/抽象问题** — 不必要的可选性、`any`/`unknown`、错层的逻辑
5. **文件大小** — 超过 1000 行需有强理由
6. **模块化** — 职责分离、耦合度
7. **可读性** — 命名、注释

**Diff 分组原则**（按 reviewer 价值排序）：

1. **核心逻辑** — 新行为、算法变化、状态转换（完整展示 + 上下文）
2. **连接与集成** — 路由注册、依赖注入、配置接线（精简版）
3. **样板与机械变更** — 导入重排、重命名、生成代码（仅文件名+统计）

**复杂逻辑处理**：

- 密集逻辑旁加简短伪代码摘要
- 令人惊讶的行为变化：选具体输入，新旧路径对比，标出分歧点
- 高风险块用短标签 + 一句话解释标注

</rule>

</rules>
