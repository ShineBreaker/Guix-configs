---
name: agent-history-importer
description: 为外部 agent 工具的本地会话库(zcode SQLite / Claude Code JSONL / opencode SQLite / Codex sessions / Crush / pi-agent 等)做 schema 侦察,产出 importer 需要的字段映射、JSON 样本、时间单位、system-reminder 折叠规则、子会话嵌入策略。**触发信号**:用户说"做 importer / 把 X 的会话导进 hermes / 摸清这个 DB 的 schema / 从 X 拉历史记录 / 把 zcode 历史迁过来"等。属于"输出可消费的 schema 情报",不是 source-code 侦察(codebase-scout)也不是 prompt 迁移(importing-agent-prompts)。
version: 1.0.0
license: MIT
metadata:
  hermes:
    tags: [importer, schema-recon, agent-history, sqlite, jsonl, migration]
    related_skills: [codebase-scout, importing-agent-prompts, hermes-agent]
---

# agent-history-importer — 外部 agent 会话库 schema 侦察

你的工作是**给一个 importer 提供准确、可直接抄写的字段映射**。典型输入是某种 agent 工具的本地持久化文件(SQLite / JSONL / LevelDB / 自定义二进制),你要把里面的会话/消息/部件/工具调用结构摸清,产出下游能直接消费的 cheat sheet。

**这个 skill 不是:** source-code 侦察(那是 codebase-scout)、不是把外部 prompt 搬过来当 skill(那是 importing-agent-prompts)、也不是改 importer 本身。

## 风格定调

- **可消费 > 完整**:输出要够 importer 作者直接抄字段映射,不用回 DB 查证
- **样本 > 抽象**:每个分型至少给一段原始 JSON,而不是只写"含 X/Y/Z 字段"
- **可验证**:每条结论必须能用一句 SQL 复现,下游可以独立核对
- **诚实**:查不到的字段写"未观察到/可能不存在",不要脑补 schema

## 工作流(七步)

### 1. 锁定持久化文件

常见落点:

| 工具        | 路径                                                     |
| ----------- | -------------------------------------------------------- |
| zcode       | `~/.zcode/cli/db/db.sqlite`                              |
| Claude Code | `~/.claude/projects/**/*.jsonl`                          |
| opencode    | `~/.local/share/opencode/storage.db`(SQLite)             |
| Codex       | `~/.codex/sessions/**/*.jsonl`                           |
| pi agent    | `~/.pi/agent/sessions/*.json`(老格式)/ `sessions.db`(新) |
| Crush       | `<project>/.crush/crush.db`(SQLite,**项目级**,每个项目独立);全局 `~/.config/crush/.crush/crush.db` 只有 `goose_db_version`,无 session。完整 schema 见 `crush-session-extract` skill(`references/schema-cheatsheet.md`) |

用 `find` / `ls -R` 找到文件,记下大小和 mtime。

### 2. 列出所有表 + 字段类型(SQLite 用 `.schema`)

```bash
sqlite3 <db> ".tables"
sqlite3 <db> ".schema <table>"
```

对每个表记下:

- 主键列 / 外键列(`on delete cascade` 决定级联导入策略)
- 哪些字段是结构化(scalar),哪些字段是 JSON TEXT(`data text not null` 模式)
- 时间字段的类型(integer 毫秒?int64 微秒?string ISO?)
- 索引(影响导入时排序策略)

### 3. 列出每张表的行数 + 关键分型计数

```sql
SELECT json_extract(data,'$.role') AS role, COUNT(*) FROM message GROUP BY role;
SELECT json_extract(data,'$.type') AS type, COUNT(*) FROM part GROUP BY type;
```

→ 这一步直接告诉你"是否有顶层 tool_calls 字段?"、"是否有 system role?"、"part 分几种 type?"

### 4. 验证时间单位

**永远别假设**。直接:

```sql
SELECT (m2.time_created - m1.time_created) AS delta_ms,
       datetime(m1.time_created/1000, 'unixepoch') AS iso
FROM message m1, message m2 WHERE ...相邻两条...
```

常见坑:

- SQLite 的 `datetime(t/1000, 'unixepoch')` 假设输入是**秒**;如果存的是**毫秒**,必须除以 1000
- 有些工具存 ISO string,有些存 ms,有些存 microsecond int64 —— 一次验证

### 5. 抽样:每种 part.type 一段原始 JSON

每个分型至少看 2 条样本(简单 + 复杂),用 `json(p.data)` 直接打印而不是 json_extract 切片 —— importer 要看完整结构。

**关注:**

- 哪些字段**始终存在** vs **条件存在**
- 嵌套对象的层数(text → time → start/end? 还是 metadata → time?)
- 大文本字段的位置(state.output vs metadata.serialization)
- 是否带 trace_id / span_id(影响是否需要 de-dup)

### 6. 回答 8 个核心问题

写到 cheat sheet 上,下游必问:

1. message.data.role 的所有取值(有没有 system?)
2. part.data.type 的所有取值 + 各自字段形状
3. **tool call 存在哪?** —— 顶层 `tool_calls` 还是 part.type=tool? 这是 schema 最大的分歧点
4. user message 的 text 是单 part 还是多 part 拼接?
5. system message / 系统注入怎么存?(role=system / synthetic=true / metadata.runtimeMessage)
6. time_created 单位(ms / μs / ISO string)
7. message 顶层有没有 tool_calls / function_call 字段?(0% vs 100% 决定架构)
8. 子会话(subagent)怎么编码?(独立 row + parent_id / 嵌入主消息流)

### 7. 选一个目标 session 做 sanity check

找一个**非空、有真实对话、可能含子会话**的 session,从头到尾读一遍:

- 第一条 user 是 prompt 还是 system reminder
- 中间有没有 /compact / slash command 等特殊事件
- 最后一条 assistant 的 part 形状
- 子会话(如果有)的第一条 user 是什么(往往是 Agent tool 的 prompt 副本)

这一步**证明 schema 报告不是空对空**。下游 importer 拿这个 session 跑一遍应该能正常导入。

## 输出格式

```markdown
# <工具名> schema 报告

## 1. 表 DDL

## 2. message.data.role 取值

## 3. part.data.type 取值 + 字段形状(每种一段原始 JSON)

## 4. tool call 存储位置

## 5. user message 的 part 拆分模式

## 6. system 信息怎么存

## 7. 时间单位

## 8. assistant 顶层元数据

## 9. user 的 per-turn env metadata

## 10. subagent 怎么编码

## 11. 目标 session sanity check

## 12. 字段映射 cheat sheet(给 importer 直接抄)

## 13. 其它表(可选消费)

## 14. 验证清单 ✓
```

## 重要规则

1. **tool call 是 schema 第一分歧点** —— 永远先回答"顶层 tool_calls 字段是否存在"再展开其他;不同 agent 框架选择完全不同(LiteLLM 风格 vs Claude 风格 vs OpenAI 风格)
2. **每条结论要可复现** —— 把生成每条数字的 SQL 留在报告里,下游可以独立核对
3. **不要假设 role 集合** —— 总有工具会冒出 `tool` role 或 `developer` role,直接 grep 不写死
4. **time_created 是最高频踩坑点** —— 不验证单位直接除 1000 会得到 1970 年
5. **system reminder 的存储位置五花八门**:
   - Claude Code: role=user, system reminder 是 user message 里 `<system-reminder>` 文本
   - zcode: role=user + part.synthetic=true
   - Codex: 单独 system role
   - opencode: role=system 顶层
     → importer 的折叠策略完全不同,**这一步必查**
6. **样本要包含真实数据** —— 别只查空字段,找一个有 reasoning / tool use / file upload 的 session 才能验证完所有 part.type
7. **不要输出"完整文件内容"** —— 只输出代表样本 + 字段映射表,下游可自己看 DB
8. **如果表名带时间后缀**(sessions_v2 / messages_v3),说明 schema 在演进 —— 报告里注明版本号
9. **如果用户用 hermes —— 先看是否已有官方 importer 再动手** —— 写 importer 之前先搜 `~/.local/share/hermes/skills/*/scripts/`、跑 `session_search query:"<source> importer"`、看 `holographic memory` 是否存着 `category='project'` 的旧 importer 线索。可能存在沉淀好的 `import-<tool>-to-hermes.py` 走 hermes 内部 `SessionDB` API(比直接 INSERT SQL 更稳),重写是反自包含。

## 参考资料

- `references/zcode-schema.md` — zcode (`~/.zcode/cli/db/db.sqlite`) 完整 schema 报告。包含所有 part.type 样本、字段映射 cheat sheet、synthetic system-reminder 处理规则、subagent 嵌入策略、time=ms 验证。**importer 写 zcode 后端时直接对照抄**
- `crush-session-extract` skill(`references/schema-cheatsheet.md`) — Crush v0.81+ 完整 schema(DDL + 每种 part.type 样本 + 字段映射 cheat sheet + 时间单位自检)。本 skill 表里的 Crush 行只是入口指针,详细报告在该 skill 里

## 已知 pitfall

- **不要把 `.schema <table>` 输出当真相** —— zcode 里 schema 显示 `data text not null`,但**真正的结构在 JSON 里**。必须 `SELECT json(data) FROM ...` 抽样本
- **不要在 message 数量为 0 的 session 上做 sanity check** —— 验证不了任何 part type
- **不要假设 part 表一定有 time 字段** —— 一些工具(part 是 message 的 children)只存 message 级别的时间
- **不要漏查子会话** —— Agent/Task 工具调用的 subagent 在 DB 里通常是独立 row + parent_id,而不是嵌入主消息流的一部分
- **Crush schema 注释说 ms 但实际是秒** —— `sessions.created_at` 注释写 "Unix timestamp in milliseconds",实际存秒(2026 年的时间戳约 1.78e9,不是 1.78e12)。**永远 `datetime(v, 'unixepoch')` 直读,不要除 1000**,否则落回 1970
- **Crush 没有全局 db** —— `~/.crush/` 不存在,`~/.config/crush/.crush/crush.db` 是 goose migration header(0 sessions)。每个项目独立存 `<project>/.crush/crush.db`,要 `find ~ -name 'crush.db' -path '*/.crush/*'` 才能拿到真实数据
- **Crush `messages.id` 不全局唯一** —— subagent 的 tool_call 用 `<parent_session_id>$$<tool_call_id>` 复合形式复用了 id 字段。importer 写入 hermes 时把 (session_id, id) 当复合主键,不要单独 PRIMARY KEY(messages.id)
- **Crush 没有 `system` role** —— system / runtime 提示全部塞进 assistant 第一条消息的 `text` part。importer 的"折叠 system reminder"逻辑对 crush 走空 path,不要无脑套 zcode / claude-code 的折叠策略

### 来自实战 (2026-07 zcode → hermes 迁移):写 hermes state.db 时的隐藏陷阱

- **`sessions.title` 有 UNIQUE 约束** → `INSERT OR IGNORE` 会**静默吞掉撞名行**,messages 都写了但 session 看不到,表现为 "orphan messages"。**修复**:INSERT 前 `SELECT 1 FROM sessions WHERE title=?` 查重,撞了加 hash 后缀;或干脆用 hermes 官方 `SessionDB` API(`create_session()` 自己处理)。`PRAGMA foreign_keys=0` 是 hermes 默认,**FK 帮不了你挡 orphan**。
- **`messages.id` 是 INTEGER AUTOINCREMENT,不是 TEXT** → 用 hash 字符串当 id 会失败。三种修法:(a) 不传 id 让 SQLite 自增(最稳);(b) 用 `INSERT OR REPLACE` + 自增 ROWID;(c) 先 SELECT MAX 然后...❌(并发不安全)。
- **`messages.tool_calls` 是 TEXT 列,但存的是 OpenAI 风格 JSON list(`[{"id":..., "call_id":..., "type":"function",...}]`),不是 dict**。`json.dumps({...})` 语义错,GUI 看到的不是正常 tool call。
- **`PRAGMA journal_mode=WAL` 是 hermes 默认**,导入期间 GUI hermes 持锁时,`PRAGMA journal_mode=DELETE` 会报 `database is locked` —— 数据 commit 没问题,只是日志模式切不回来。**安全**:try/except 吞掉这个错。
- **复用官方 importer 时核对 id 约定** —— `import-zcode-to-hermes.py` 用 `sess_<原 zcode id>`(保留),不是 hash 缩写。如果你的临时 importer 用 hash 缩写,两边在 hermes DB 里并存同样内容但 id 风格不同,FTS 召回没问题但 GUI 列表会重复显示。
- **`messages.content/tool_calls` 自动喂 FTS5** → 长 tool output 会膨胀 FTS 索引。官方 importer 在 tool output >50KB 时截断,别忘了。
- **`grep_messages MATCH` 对 `-` / `.` 分词不友好** —— 这是 FTS5 unicode61 默认 normalizer 的行为。GLM-5.2 / org-src-fontify 这种 token 默认召不回,但真名(distrobox/fontify/host-spawn)召回良好。**不要因此怀疑 importer 失败**。

### 来自沙箱实战 (2026-07)

- **`$HOME` 被 sandbox/hook 重定向** —— 在嵌套 shell 或 hook 安装过的终端里,`$HOME` 可能被改成某个 SKILL.md 的绝对路径,导致 `~`/`$HOME`/`Path.home()` 都错(典型症状:`mkdir` 报 `ENOTDIR: not a directory, mkdir '/foo/bar/SKILL.md/.zcode/v2/logs'`)。**永远用绝对路径**(`/home/<user>/.zcode/...`)做探测命令;遇到这错先 `printenv HOME` 看真值。

## 写 hermes rows 的额外检查清单 (新增)

按用户偏好"先 1 个样本验证再放量",在第一次 INSERT 前必须:

1. **Hot backup**:`sqlite3 <db> ".backup <db>.pre-<task>-<ts>.bak"`(WAL-safe,比 cp 文件可靠)。完成后用 `trash` 工具(按用户偏好)而不是 rm。
2. **查 NOT NULL 列**:`PRAGMA table_info(<table>)` 而非 `.schema`(后者末尾噪声挡关键字段)。
3. **查 UNIQUE 约束**:`SELECT name, sql FROM sqlite_master WHERE type='index' AND sql LIKE '%UNIQUE%'` —— **INSERT OR IGNORE 之前必须知道哪些列会触发 silent fail**。
4. **临时关 FK(已知 hermes 默认 off,但写完后切回去)**:`PRAGMA foreign_keys=OFF`。
5. **挑 1 个 session 端到端验证**:不批量灌。看 hermes `messages` row 数对得上 zcode source 真实数(zcode:part 数 / hermes:row 数),再放量。
6. **FTS5 抽样召回**:`SELECT ... FROM messages_fts WHERE messages_fts MATCH '<keyword>'` 验 trigger 自动维护。
7. **跑 idempotent probe**:再跑一次导入,assert row count unchanged。我惨中过一次:首次写完 row count 比真实多 ~2x,二次 idempotent 跳过所以**重导前必须 DELETE + 重导**,确认一次写一次。
