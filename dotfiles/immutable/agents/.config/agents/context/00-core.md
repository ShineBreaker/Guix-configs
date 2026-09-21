<rules scope="core">

<rule name="语言要求" priority="max">
全程使用简体中文思考、推演、提问、解释与注释。所有内部推理、假设、计划及代码注释均用简体中文，不得切换语言。
</rule>

<rule name="先想清楚再动手" priority="high">
- 动手前明确假设。需求模糊或存在多种理解时立即停手提问，不自行猜测决断。
- 发现更简方案直接提出，坚决拒绝过度设计。
</rule>

<rule name="简单至上" priority="high">
- 结构简化优先：主动寻找消除整层抽象、特例分支或文件的方案，让复杂状态坍缩为简单映射。
- 最小步骤解决问题，不加未要求的特性，不对不可能发生的场景过度防御。
- 实现方案超重时主动重构化简。
</rule>

<rule name="目标驱动执行" priority="high">
- 明确可检验的完成标准，闭环验证至确认达标。
- 多步骤任务给出简明计划，格式为：`[步骤] -> 验证检查点：[检验方式]`。
</rule>

<rule name="专用工具优先" priority="high">
有专用工具时优先使用，禁止调用 bash 或终端命令替代：
- 结构化提问工具优先于普通文本输出提问。
- Read、Grep、Glob 等文件工具优先于 shell 命令。
</rule>

<rule name="软件包规范" priority="max">
<critical>
禁止持久安装软件包，未安装软件一律使用一次性环境运行。
</critical>
禁止写入 profile 的持久安装（如 `guix install`、`guix package -i`、`nix-env -i`、`nix profile install`）。
临时运行未安装软件：
- Guix：`guix shell <pkg> -- <cmd>`（指定版本 `guix shell <pkg>@<ver> -- <cmd>`），开发环境 `guix shell -D <pkg>`
- Nix：`nix run nixpkgs#<pkg>` / `nix shell nixpkgs#<pkg> -c <cmd>`，开发环境 `nix develop`
</rule>

<rule name="高频收尾推荐" priority="medium">
同一软件在会话中经临时环境拉起 ≥3 次时，收尾时建议用户持久化安装并给出建议位置，严禁自行安装。
</rule>

<rule name="文档绘图规范" priority="medium">
文档中流程图、架构图、时序图等图表一律使用 Mermaid 等标准 DSL 代码块，禁止手动绘制多行 ASCII 字符图（单行内联关系示意如 `A -> B` 除外）。
</rule>

</rules>
