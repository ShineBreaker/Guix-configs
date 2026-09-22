# dsh-sandbox 域原则 — DSH Harness 文件沙箱

<rules scope="dsh-sandbox">

<rule name="沙箱拒绝伪装成只读挂载" priority="critical">
DSH 以文件沙箱执行工具调用（策略见会话 runtime context，如 workspace-write / danger-full-access）。沙箱拒绝时有两种形态，第二种与真实故障完全同形：
- harness 直接拦的操作：报错带 `[sandbox: file access denied under <mode> mode]` 标记；
- 被拦的 bash 子进程（agenote / pnpm / git 等自身 open 失败）：只看到 `OSError: [Errno 30] Read-only file system`（EROFS），与真实只读挂载的 errno、文案一模一样。
</rule>

<rule name="EROFS 判别顺序" priority="high">
见到 "Read-only file system" / errno 30 / 写入被拒时，按序判别，不得跳步：
1. 结果里有 `[sandbox: ...]` 标记 → 沙箱，与挂载无关；
2. 无标记 → 默认怀疑沙箱（本 harness 的既定机制），不得反过来默认挂载；
3. 仍要区分 → 请用户执行 `findmnt -T <路径>`（或 `mount | grep <路径>`）看 ro/rw 并回报，不自行 sudo。
</rule>

<rule name="严禁把沙箱当挂载修" priority="critical">
不得因 EROFS 就建议 `sudo mount -o remount,rw` 等系统操作：沙箱拒绝 remount 多少次都不会消失，且属高危不可逆操作（参照 agent-ops 域）。正确出路只有两条：
- 把目标改到沙箱允许的位置（session workspace、平台临时区）；
- 请用户调整 harness 沙箱策略 / 审批项。
</rule>

<rule name="/tmp 不跨 bash 调用持久" priority="medium">
沙箱下每次 bash 调用的临时文件区相互隔离：本次调用创建的文件（含 write 工具落盘的内容），下一次调用可能不存在。跨调用传递状态一律放 session workspace，勿依赖 /tmp。
</rule>

<rule name="环境自证" priority="medium">
确认自己是否在 DSH 会话：`env | grep ^DSH_`（DSH_HOME / DSH_SESSION_ID / DSH_WEB_URL）存在即是。沙箱策略本身不暴露为环境变量，以会话 runtime context 的 DSH file policy 陈述为准。
</rule>

</rules>
