# hermes `state.db` 写入陷阱(实战汇总,2026-07)

> 这份文档给写 importer 直接 `INSERT` 进 hermes `state.db` 的 agent 看。如果你用 hermes 官方 `SessionDB.append_message()` / `create_session()` Python API,大部分陷阱已被库封装处理掉,只有 path/env 类陷阱仍适用。

## 表 schema 真相

### `messages` 表

```sql
CREATE TABLE messages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,   -- ← INTEGER 不是 TEXT
    session_id TEXT NOT NULL REFERENCES sessions(id),
    role TEXT NOT NULL,
    content TEXT,
    tool_call_id TEXT,
    tool_calls TEXT,                         -- ← 存 OpenAI 风格 JSON LIST,不是 dict
    tool_name TEXT,
    timestamp REAL NOT NULL,                  -- ← epoch 秒(不是 ms)
    token_count INTEGER,
    finish_reason TEXT,
    reasoning TEXT,
    reasoning_content TEXT,
    reasoning_details TEXT,
    codex_reasoning_items TEXT,
    codex_message_items TEXT,
    platform_message_id TEXT,
    observed INTEGER DEFAULT 0,
    active INTEGER NOT NULL DEFAULT 1,
    compacted INTEGER NOT NULL DEFAULT 0
);
```

`messages.tool_calls` 实测样本(hermes 内部产生):
```json
[{"id": "call_00_PmsulOa5PV0WRfySMu5Q0314",
  "call_id": "call_00_PmsulOa5PV0WRfySMu5Q0314",
  "type": "function",
  "function": {"name": "Bash", "arguments": "{\"command\":\"ls\"}"}}]
```

→ **直接 `json.dumps(dict)` 语义错**,要 `json.dumps([{...OpenAI-shape...}])`。

### `sessions` 表关键约束

```sql
CREATE TABLE sessions (
    id TEXT PRIMARY KEY,                       -- TEXT 随意,但官方 importer 沿用 zcode 原 id
    source TEXT NOT NULL,                       -- 命名空间;`imported-zcode` 是官方约定
    title TEXT,                                 -- ← **UNIQUE 约束**(silent fail 的元凶)
    ...
    FOREIGN KEY (parent_session_id) REFERENCES sessions(id)
);
```

`SELECT name, sql FROM sqlite_master WHERE type='index' AND sql LIKE '%UNIQUE%'` 能查到 `sessions.title` 的 UNIQUE 索引。

## 七个最常踩的坑

### 1. `INSERT OR IGNORE` 静默吞掉撞名行

```
INSERT OR IGNORE INTO sessions (id, source, title, started_at)
VALUES ('sess_x', 'imported-zcode', '我之前导过这个', 1.0);
-- title 已经存在于 hermes,row 被吞,messages 还在 INSERT,最终:
--   - 表里看不到这个 session
--   - messages 引用了不存在的 session_id(orphan)
--   - 用户感觉"导入成功了但 GUI 看不见"
```

**修复**:INSERT 前查重:
```sql
SELECT 1 FROM sessions WHERE title = :title
```
撞了就在 title 末尾加 hash 后缀(`[zc-<8位uuid>]`)。

### 2. `messages.id` 不是你说了算的

`PRAGMA foreign_keys=0` 是 hermes 默认(实测),所以 orphan messages 不会被 FK 拦下来。 但 AUTOINCREMENT INTEGER 是真的 —— **`INSERT INTO messages(id,...) VALUES('hash',...)` 不会失败但毫无意义,因为 SQL 类型转换把所有 column 强制成 INTEGER,字符串 id 落进 0/1**。

唯一可靠:id 不传,让 SQLite 自增;或 `INSERT OR REPLACE` 配 AUTOINCREMENT。

### 3. `journal_mode=DELETE` 的"database is locked"

`PRAGMA journal_mode=WAL` 是 hermes 默认(实测)。如果你写完想 `PRAGMA journal_mode=DELETE` 切回 rollback 模式,**GUI desktop hermes 持锁**,会抛:

```
sqlite3.OperationalError: database is locked
```

**这是无害的** —— 数据已经 COMMIT,只是日志模式没切回去。可以 `try/except` 吞掉。

### 4. `FOREIGN KEYS` 默认 off,但仍可能 orphan

PRAGMA `foreign_keys=0` 时 orphan 写入不会被拦,但 schema 里有 `REFERENCES` —— 检查完整性用 `PRAGMA foreign_key_check` (不是 `integrity_check`)。

### 5. `messages_fts` FTS5 trigger 自动维护

INSERT 进 `messages` → trigger 同步 `messages_fts` + `messages_fts_trigram`。不必手工写 FTS。但 trigger 用 `content || ' ' || tool_name || ' ' || tool_calls` 作为索引内容 —— **tool_calls 内的长 output 会膨胀 FTS 索引**。官方 importer 在 tool output >50KB 时截断(`import-zcode-to-hermes.py:297` 那段)。

### 6. `FTS5 MATCH` 对 `-` 和 `.` 不友好

`messages_fts MATCH 'GLM-5.2'` 召不回;`MATCH 'org-src-fontify'` 也召不回。**这是 unicode61 默认 tokenizer 的行为**,不是 importer 失败。FTS5 trigram fallback 兜底部分场景。要严格查 model 名 → 用 `LIKE '%GLM-5.2%'` 或在 tool_calls JSON 内做精确子串。

### 7. zcode 源的 `state.output` 落入 hermes 后可能很长

zcode 一个 Bash tool 输出动辄 20–80KB。如果走 hermes 官方 `append_message(role='tool', content=output)` —— content 会被 FTS5 trigger 全量索引。`import-zcode-to-hermes.py` 的策略是:**50KB 截断 + 加 [... truncated by importer ...] 标记**。下游 LLM resume 时不会尝试重读 50KB+ tool output(FTS 召回阶段就知道没结果)。

## 沙箱环境陷阱(跨工具)

### `$HOME` 被 hook/沙箱重定向

在嵌套 shell 里 `$HOME` 可能被改成某 SKILL.md 路径,导致:

```
mkdir /home/<user>/.local/share/hermes/skills/<skill>/SKILL.md/.zcode/v2/logs
↓
ENOTDIR: not a directory
```

**永远用绝对路径**做探测命令,不用 `~` 或 `$HOME`。遇到这错 `printenv HOME` 先确认。

## 写 hermes rows 的标准化流程

```python
import sqlite3, shutil, time
from pathlib import Path

# 1. hot backup(WAL-safe)
backup_path = f"{hermes_db}.pre-<task>-<int(time.time())}.bak"
src = sqlite3.connect(hermes_db)
src.backup(backup_path)
src.close()
# trash backup_path  ← (按用户偏好用 trash,不是 rm)

# 2. 主事务
db = sqlite3.connect(hermes_db)
db.execute("PRAGMA busy_timeout = 30000")
db.execute("BEGIN IMMEDIATE")

try:
    # 3. session 行:title 查重(陷阱 #1)
    title = "..."
    if db.execute("SELECT 1 FROM sessions WHERE title=?", (title,)).fetchone():
        title = title[:190] + f" [zc-{sid[-8:]}]"

    db.execute("""INSERT INTO sessions (...) VALUES (...)
                   -- 留出 CREATE TABLE 里所有 NOT NULL 字段""", (...))

    # 4. messages:不传 id(陷阱 #2),让 AUTOINCREMENT 分配
    for part in parts:
        db.execute("""INSERT INTO messages (session_id, role, content, timestamp, ...)
                       VALUES (?,?,?,?,...)""", (...))  # ← 没有 id column

    db.execute("COMMIT")
except Exception:
    db.execute("ROLLBACK")
    raise
finally:
    # 5. journal_mode 切回(WAL 默认;陷阱 #3 无害吞掉)
    try:
        db.execute("PRAGMA journal_mode = WAL")
    except sqlite3.OperationalError:
        pass
    db.close()

# 6. 一次端到端验证(陷阱 #5 #6):
#    SELECT role, COUNT(*) FROM messages WHERE session_id=? GROUP BY role
#    → 数字应与 zcode 源 DB 真实分布一致
#    SELECT ... FROM messages_fts WHERE messages_fts MATCH '<keyword>'
#    → 真实 token 应召回

# 7. idempotent probe:
#    再跑一次 importer,assert row count unchanged
```

## 检查清单

- [ ] Hot backup 在写之前完成(用 `db.backup()`,不用 cp)
- [ ] `PRAGMA table_info(sessions)` 看过所有 NOT NULL
- [ ] `PRAGMA index_list('sessions')` 看过所有 UNIQUE
- [ ] Title 查重逻辑写进 importer
- [ ] `id INTEGER` 而不是 `id TEXT` 假设
- [ ] `tool_calls` 字段是 JSON LIST,不是 DICT
- [ ] tool output 超过 50KB 截断
- [ ] `PRAGMA journal_mode=DELETE` 切换 try/except 吞错
- [ ] 跑完一次 session 端到端验证(SELECT role, COUNT(*) ... GROUP BY role)
- [ ] FTS5 抽样召回测试(注意 `-` `.` 分词陷阱)
- [ ] Idempotent probe(再跑一次 assert unchanged)

## 相关文件

- `references/zcode-schema.md` — zcode 源端 schema 表 + 字段映射
- `references/pi-schema.md` — pi agent 源端 schema 表(类似结构)
- `../scripts/import-zcode-to-hermes.py` — 完整的官方 importer 实现,几乎所有陷阱都有兜底
- `../scripts/import-pi-to-hermes.py` — pi 的对应实现,同样的 SessionDB API 模式

