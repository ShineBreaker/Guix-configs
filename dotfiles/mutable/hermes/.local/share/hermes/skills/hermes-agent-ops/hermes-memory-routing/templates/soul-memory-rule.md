<!--
Append this block to ~/.local/share/hermes/SOUL.md (the stow-tracked source
under ~/Projects/Config/Guix-configs/stow/hermes/.local/share/hermes/SOUL.md).

It enforces Option A from the hermes-memory-routing skill: keep MEMORY.md as
the git-tracked canonical, but route structured facts to holographic
fact_store. Edit categories to match your own projects.
-->

## Memory 双通道分工

你有两个独立的 memory 系统，不要混用：

| 系统 | 入口 | 适用内容 | 存储位置 |
|---|---|---|---|
| `memory` 工具 | `memory(action='add', content=..., target='memory'\|'user')` | 用户画像、偏好、跨会话决策；按 `§` 分条 | `memories/MEMORY.md` / `memories/USER.md` |
| `fact_store` 工具 | `fact_store(action='add', content=..., category=...)` | 项目事实、调试结论、命令诀窍、环境拓扑 | `memory_store.db`（holographic SQLite） |

### 默认分流

- 用户偏好（我喜欢、我用、不要） → `memory` 工具
- 排查出某 bug 的根因 / 确认某 workaround / 部署拓扑 → `fact_store`，`category='project'`
- 工具 flag / 配置项语义陷阱 → `category='tool'`
- 其他通用事实 → `category='general'`

### 硬性约束

**禁止**用 `write_file` / `patch` / shell `cat >>` 直接编辑 MEMORY.md ——
会触发 `memory_tool.py::_drift_error`、丢数据，且 holographic 镜像收不到。
MEMORY.md 只能通过 `memory` 工具写入。

启动时如果 `memories/MEMORY.md` 已经有内容但 `memory_store.db` 里 facts < 5，
主动用 `fact_store(action='add', content=<条目>, category='project')` 把现有
条目 mirror 一遍。

### 检索顺序

回答关于用户的具体问题前，先 `memory(action='read')`；回答项目/技术事实前，
先 `fact_store(action='probe', entity='<entity>')` 或
`fact_store(action='search', query='<query>')`。