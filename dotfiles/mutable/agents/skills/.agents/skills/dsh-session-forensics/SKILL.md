---
name: dsh-session-forensics
description: "DSH 会话打不开、导入后侧栏不见、workspace.json 迁移、会话目录名异常时用；覆盖存储契约、可见性判定、离线迁移与停机替换。"
version: 1.0.0
license: MIT
metadata:
  hermes:
    tags: [dsh, session, migration, workspace-registry, zstd, forensics]
    related_skills: []
---

# dsh-session-forensics — DSH 会话文件取证、可见性修复与迁移

来源: agenote 20261030-160347 / 20261030-104354 / 20261029-204436 / 20261026-120314

## When to Use

- 侧栏点开会话报 `working-directory: directory does not exist`
- 导入/迁移进来的会话在 Web GUI 列表里整批不见
- 磁盘 `sessions/` 下有文件，UI 里没有
- `workspace.json` 需要迁移、重定点或修死路径
- 会话目录名异常（`im~003Aqq_x` 这类转义）、侧栏显示「未命名」

先读存储契约，再动手。**不要先改文件再查原因**——这个子系统里多数改动是「要么原子成套、要么制造新 corrupt」。

## 存储契约（先记住这五条）

1. **路径**：`~/.local/share/dsh/sessions/--<projectKey>--/<session-dir>/session.v<N>.jsonl.zstd`
2. **projectKey 编码**：cwd 按 `/` 拆开拼 readable → `replace(/^-+/, "")` → 两头包 `--`。
   `/home/u/Projects` → `--home-u-Projects--`。**前导 `-` 必须去掉**；写成 `---X--` 是 2026-10-26 迁移留下的旧规则 bug，会让 `assertStoredIdentity` 判 corrupt。
3. **会话目录名会转义**：`im:qq_x` → `im~003Aqq_x`。宿主按 **header.id** 定位会话，用目录名当 id 会双重编码并假报 `session not found`。凡需 id 一律从 header 读。
4. **分帧**：`session.vN.jsonl.zstd` 的**第一帧必须恰好是 header 一行**（明文非空且末字节为 `\n`），后续帧各自独立可解。违反时 `listArtifacts` **静默跳过**（不抛不警告）→ 会话不进 `WorkspaceRegistry.sessionPaths` 索引 → 一次读取失败即被 `mutate()` 永久除名。
5. **可见性只由 registry 决定**：`storages/workspace.json` 的 `tables.workspaces[].sessionIds`。磁盘上有文件 ≠ 可见；未登记的最多落到「未分组」。

## 可见性判定：candidateMatches

`WorkspaceEntity.sessionIds` 是 getter，按会话 cwd 过滤：

| cwd 状态 | 判定 |
|---|---|
| 路径存在 | `realpath(cwd) === workspace.path` 才算成员 |
| 路径不存在（ENOENT） | 进 `missingSessionPaths`，视为匹配**任意** workspace |
| 未归属任何 workspace | 落进 UI 的 Ungrouped 组 |

推论：**离线迁移只有在旧 cwd 已不存在时才有效**；cwd 仍存在的会话必须建 `path=realpath(cwd)` 的 workspace。被过滤掉的候选只在启动日志里 warn 一次。

## 诊断决策树

### 症状 A：会话打不开，报 `working-directory: directory does not exist`

根因在 `dsh-working-directory` 插件的 `ensure()`：每轮组装系统提示时取**有效 cwd**（投影状态，初值 = `header.cwd`，可被 `working-directory/change` 事件改写），stat 失败回退 `header.cwd` 再试；两者都死 → throw，整轮失败。

**注意：修工作区登记表没用**——宿主只认会话自己记录的 cwd。

修法三件套（缺一不可，同一个原子操作）：

1. 把 header 的 `cwd` 改写成工作区的现存路径（投影冷启动从 header.cwd 初始化，改这一条就够）
2. 会话目录搬到 `~projectKey(新 cwd)~` 下（`assertStoredIdentity` 用 header 的 id + cwd 反推预期路径，不符直接判 corrupt）
3. 删掉该会话的投影缓存 `storages/session_projcache/sessions/<id>.json`（缓存是「前缀检查点 + 尾段重放」，无新事件时旧 val 不自愈，会盖过改过的 header；删缓存是安全操作，缺失即重建）

### 症状 B：导入后侧栏整批不见

两个独立根因，**必须分别验证**：

1. **目录编码不一致**（见契约第 2 条）——`list()` 能读到 header，但反推路径不符 → 打开/校验报 corrupt
2. **registry 未登记**——目录名对但 `workspace.json` 里没有该 sessionId

修复流程：

```bash
# 1) 备份 sessions/ 与 workspace.json
# 2) node 解 zstd 读每个会话首行 header，导出 {id, cwd, dir} 清单
# 3) 旧编码目录 ---X-- → --X--；同名会话按体积取大者合并
# 4) 按 reorg 映射把旧 cwd 归到新项目 workspace；cwd 仍存在的直接建/复用 path=cwd 的 workspace
# 5) 校验：无重复 sessionId、无重复 path、global.workspaceIds 与 tables 一致
# 6) 停 host → 替换 workspace.json → 启动 → 启动日志里 filtered session 应为 0
```

### 症状 C：侧栏显示「未命名」

侧栏标题来自投影缓存 `storages/session_projcache/sessions/<id>.json` 的 `rows.title`（ver=1）。宿主只在会话被**打开**（冷折叠）时写该行 → 未点开的会话显示「未命名」。缺行只影响冷折叠效率，不影响正确性；可只写 title 一行预热。

### 症状 D：磁盘有文件但列表没有

先查分帧（契约第 4 条）：首帧是不是恰好 header 一行。离线改写过的日志（例如用 python 重打包 zstd）最容易破坏这一点，且**不会报错**。

## 两条验证路径（必须都跑）

只跑读取会漏掉 settlement 类问题（2026-10-30 曾漏掉 529 个会话）：

- `requireStoredLog` —— 读取路径
- `Session.fromRestore` —— GUI 打开历史走它

**宿主侧探针**（比读源码猜可靠）：把 `@deepseek-ai/dsh-session-persistence-jsonl` 的 `lib/index.js` 复制一份、末尾加 `export`，用桩 ctx（需 `logger` / `reflect.provide` / `effect` / `on` / `get` / `plugin`）实例化，直接调 `list()` / `listGenerations()` / `readGenerationHeader()`，与磁盘 `readdir` 对比，即知宿主实际能看见几个、能读几个。

## 迁移与停机替换

**宿主拥有 `workspace.json`**：运行中每次 mutation（attach/archive/pin）都重写文件；改完必须重启，否则宿主用内存旧表覆盖手改。启动时 `bootstrap()` 只补登记、不删；`validateStoredState` 强校验：路径唯一、会话唯一归属、`global.workspaceIds` 与 `tables` 一一对应，违反直接启动失败。

停机替换模式（已验证，服务瞬断约 2 秒）：

1. 脚本必须 **`setsid` 脱离宿主进程树**——`herd stop` 会连坐杀掉宿主（bash 工具的父进程）
2. 备份 → `herd stop dsh-web` → 等 `:3080` 释放 → `install -m 600` 新表 → `herd start` → 等监听
3. 重启后**只比结构**（工作区数 + 路径集合），不要字节比对——窗口期内 qqbot/automation 重连追加 sessionId 是正常的，字节不同就回滚会误杀
4. 结构坏了才回滚并 `herd restart`

## 陷阱清单

- **不要手改 v3 → v4**：v4 对消息语义有更强约束（`tool/result` 必须配 tool-role 消息、message 需 producer-owned source），直接升版本号会有大量文件被 catalog 拒。宿主读 v3 时自行内存迁移并保留 cwd，保持 version 3 即可。
- **`/data/Projects` 与 `~/Projects` 是同一物理树**（bind mount，同 inode），但 realpath 不合并 → 会裂成两个同名工作区。保留 home 拼写，把另一个的会话并过来后删记录。
- **`attachSession` 拒绝 ENOENT**：API 途径无法把死路径会话挂到新工作区（"its cwd does not resolve, so it cannot be validated"），只能直接改 JSON。
- **归档的旧目录可以回收**：整迁后旧 projectKey 目录全空；sessions 根目录数会明显下降（本机 93 → 51）。
- 修完的验收标准是**浏览器点开会话能渲染**，不是 `ls` 看见文件。

## 归档位置

本机历次迁移的备份与脚本：`~/.local/share/dsh/backups/2026-10-30-workspace-migration/`（cwd_fix_plan.json、rehome_sessions.mjs、verify_rehome.py、retired-logs/、projcache.bak/）、`~/.local/share/dsh/backups/2026-10-29-session-import-fix/`。回滚 = 旧日志搬回原目录 + 恢复 projcache.bak + 恢复 workspace.json.pre-rehome。
