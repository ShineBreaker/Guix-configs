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
在进行任何任务之前，请先利用 `kb list --category <category>` 来获取相关领域的知识库内容
</critical>

<rule scope="knowledge-base">

每次接到任务时，按照以下步骤来调用知识库：

1. 调用 `knowledge-base` skill 加载 CLI 用法
2. 运行 `kb search "任务相关技术/"工具/"框架"` 检索历史经验
4. 高相关经验 → 作为上下文参考输出提醒；空/低相关 → 静默继续

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
