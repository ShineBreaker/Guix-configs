<rules>

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

3. 完成前: 再次 `git status --short`，确认提交内容仅含本次任务

停止并汇报：同一文件存在明显并行冲突、无法判断改动来源、需要破坏性 git 命令。

</rule>

---

<critical>
**知识库是默认第一步，不是可选优化。** 每次接到任务后，必须在阅读大量源码或动手修改前实际运行一次知识库检索命令；不要等用户提醒，也不要只在最终总结时才想起知识库。
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
- 前端、游戏、Sonolus → `gamedev`

<critical>
当任务涉及代码库探索、架构判断、外部文档、实现和审查中的任意两项以上，且当前 harness 提供 subagent/delegation 工具时，主 agent 应主动委派：先用只读侦察/调研 agent 收集上下文，再让实现/审查 agent 处理独立阶段。不要把“能自己做”当成不委派的理由。
</critical>

对话中检测经验信号
自动检测以下信号，触发 `self-improving` skill 记录：

用户表示任务完成（"可以用了"、"一切正常工作"、"Done"）
必须触发 `self-improving` skill 执行总结流程。
若有可记录经验 → `kb search` 去重 → `kb add` → `kb lint` → 传播联动。
若无 → 确认后停止。
若用户提出新要求 → 先完成总结，再处理。

<signals>
经验信号速查
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
  <signal type="ascended">
    同一问题被纠正 ≥2 次、用户说 `/ascended` → 全面检索 → 最强方案 → 复盘
  </signal>
  <caution>
    防误触发：用户只是描述报错但不纠正你、普通 review 无可复用经验 → 不触发。
  </caution>
</signals>

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

</rule>

</rules>
