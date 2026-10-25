# 缺口矩阵模板

> 跨系统借鉴设计的核心对位工具。一张二维表能讲清"上游有但本机缺什么,
> 缺它的具体损失是什么"。本文件是模板,不是要灌满内容。

## 矩阵 A:能力 × 系统(对位矩阵)

**行 = 能力维度,列 = 系统,单元格 = 状态**。

| 能力维度            | 上游(参考实现) | 本机(目标)  | 损失/痛点 | 优先级 |
|-------------------|--------------|------------|---------|------|
| Actor 持久化索引       | ✅ SQLite actor_registry | ❌ 仅 status.json | crash 后丢失,跨进程盲查 | P0 |
| Orphan recovery   | ✅ init 时扫 pending/running | ❌ 无 | 崩溃后子 agent 失联 | P0 |
| Stuck detection   | ✅ 5min threshold | ❌ 无 | 跑飞了无人知道 | P1 |
| Completion gate   | ✅ TaskGate 扫 task list | ❌ self-report 优先 | 模型说 done 但 task 还 open | P1 |
| Return header 协议 | ✅ `**Status**:` 强制 | ❌ result.md 自由文本 | 解析靠 regex 猜 | P2 |
| ReAct 循环         | ✅ pre/post 各 MAX=3 | ❌ 无 | hook 无重入 | P2 |
| System agent 分类   | ✅ 白名单枚举 | ❌ 全混在一起 | prune/通知不区分 | P2 |
| ...               | ...          | ...        | ...     | ...  |

**优先级约定**:
- **P0** —— 没有它系统不能正确工作
- **P1** —— 没有它系统能用但有真实痛点
- **P2** —— 没有它也能跑,只是欠优雅
- **P3+** —— 锦上添花,先不做

## 矩阵 B:可复用资产清单(本机端)

| 资产 | 路径 | 状态 | 复用方式 |
|---|---|---|---|
| agent `.md` 文件 | `~/.config/pi/agents/*.md` | 6 个已就位 | 自动化注入 header 段,不手改 |
| prompt 模板 | `~/.config/pi/prompts/*.md` | 6 个已就位 | workflow 转换是自动的 |
| MCP server | `agenote_mcp.py` | 18 tool | 加新 tool 不动接口 |
| ... | ... | ... | ... |

## 矩阵 C:不可改动的边界

| 不能动 | 原因 |
|---|---|
| `<path>` | 不可变 store / 用户硬性偏好 / 上游 API 锁定 |
| `<path>` | ... |

## 怎么填这张表

1. **先填行** —— 列出上游的能力点(从代码里来,不是从 README)
2. **再填本机列** —— 现状是 ✅ / ⚠ / ❌,不要怕打 ❌
3. **痛点列要具体** —— "X 不好" 不算痛点,"用户启动后 30 分钟被 crash
   重启,所有 subagent 状态丢失" 才是痛点
4. **优先级不要全 P0** —— 区分 P0/P1/P2 是为了避免一次改太多
