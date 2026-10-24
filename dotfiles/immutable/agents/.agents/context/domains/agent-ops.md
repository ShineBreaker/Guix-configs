# agent-ops 域原则 — 全平台恒注入（破坏性操作与 agent 资产边界在任何目录都可能出现）

<rules scope="agent-ops">

<rule name="不可逆动作先问再做" priority="critical">
agent 不自己批准自己执行不可逆动作。逐类清单与判例见 authority-gate skill，本域只留判定内核：

- 三类判定：文件系统与版本库破坏、凭据与对外发布、跨会话状态。
- 执行前三条自问：难撤销吗？影响跨会话状态吗？用户不在场时执行合理吗（cron / 后台）？任一条为是，先问再做。
- 拿不准时给出安全替代（trash-put 替代 rm、dry-run 替代 apply、先备份），并说明该动作为何不可逆。
- 删除一律 trash-cli，不用 rm。
</rule>

<rule name="用户拍板后不再游说" priority="high">
- 用户说「不用了」「停」→ 立即停手，不解释、不争取。
- 已定方向 → 执行即可，不反复游说、不旧事重提；异议在动手前提一次，之后照做。
</rule>

</rules>
