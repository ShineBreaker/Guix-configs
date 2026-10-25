# KB 双索引与 gitignore 收尾 — 2026-08-30 策展补漏

**来源**：`~/Documents/Org` 本月策展 200 卡、孤立率 39%→2% 批量互链后、`agenote commit` 残留 `M index.json` / `?? agenote/.gitignore` / `?? agenote/memories/projects/guix-configs.org`（大小写重复）三件收尾。

## 1. 双 index.json（human vs agenote）

- `~/Documents/Org/index.json` = `KB_ROOT/index.json`（human 域），`~/Documents/Org/agenote/index.json` = `AGENOTE_ROOT/index.json`（agent 域，`reindex` 实际写入目标）。
- human 域现 0 卡（`agenote --domain human list` 空），root index.json 应为空 `{"total":0}`。`reindex` 后 root index 被清空为 0 是正常（human 无卡），`HEAD` 旧版残留 1 卡属历史脏数据。
- `agenote commit` 的 `curated_paths` 含 `agenote/index.json` 但**不含** root `index.json`，前者自动 add，后者需 `git add index.json` 手动补。`git status` 残留 `M index.json` 时直接 `git add index.json` 再随策展 commit 一并提交。
- 判定：`agenote --domain human stats` 为 0 → root index 空为真；不为空则需 `uv run agenote --domain human reindex` 或查 `core.py KB_INDEX` 定义。

## 2. agenote/.gitignore（.agenote.lock）

- `agenote/.gitignore` 仅一行 `.agenote.lock`（KB 进程锁，`safeio.atomic_write` 的 fcntl 锁文件），首次出现时为 `??` 未跟踪，应 `git add agenote/.gitignore` 入仓，避免锁文件被误提交。
- `curated_paths` 未包含它，需手动 `git add`。

## 3. memories 大小写重复（case-sensitive 文件系统陷阱）

- `agenote/memories/projects/Guix-configs.org`（资本 G，20260711 可信 WiFi）与 `guix-configs.org`（小写，20260829 nonguix hash 失败）因 `agenote memory --project-touch` / `agenote add` 时大小写不一致产生重复，`MEMORY.org` 出现两条 `** Guix-configs` / `** guix-configs`。
- **合并**：小写节 `** guix 38a7797...` 追加到资本文件末尾，`MEMORY.org` 删小写块并把资本块 `UPDATED` 提至 2026-08-29，`trash-put` 小写文件。
- **预防**：memory 的 `project` 名大小写敏感，统一用 `Guix-configs`（首字母大写，与仓库名一致），脚本中 `agenote memory --project <name>` 前先 `grep -i` 查已有名。
- 关联 skill：`guix-configs-workflow` §1 强调 `blue home` 三步验证；memory 合并后需 `git add agenote/memories/projects/Guix-configs.org agenote/MEMORY.org` 再 `agenote commit` 之外单独 `git commit`（`curated_paths` 未含 `memories/projects/*` 的大小写修复，需手动）。
