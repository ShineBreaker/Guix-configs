# kb-mcp

> **实现位置**:`server.py` 用 `_run_kb()` 统一调度,12 个工具均为装饰器 + argv 拼装。
> **添加新工具**:复制 `server.py` 末尾的模板(6-12 行)即可,无需触碰 `_run_kb()`。

知识库 CLI (`kb`) 的 MCP 瘦壳。

## 设计

- **薄壳**:不重写 kb 业务逻辑,只把 MCP 参数翻译成 `subprocess` argv。
- **单源**:kb 是 single source of truth;kb 升级/新增子命令后,这里只需加 1 个工具函数。
- **简单至上**:每个工具 = 1 个 `@mcp.tool()` 装饰器 + 1 个 2-4 行函数体(参照 F014)。
- **零日志**:出问题时由 kb 自身的 stderr 直接进 MCP `isError` 通道。

## 启动

`run.sh` 自动用 `uv run --with "mcp[cli]>=1.0"` 拉起 server。

```bash
# 直跑(本地调试)
./run.sh

# 接入 MCP 客户端(以 Pi 为例,mcp.json):
{
  "mcpServers": {
    "kb-mcp": {
      "command": "/home/brokenshine/Projects/Config/Guix-configs/dotfiles/immutable/agents/.config/agents/mcp-servers/kb-mcp/run.sh"
    }
  }
}
```

## 工具清单(12)

### 读取组(6)

| MCP 工具            | CLI fallback                                            | 说明                        |
| ------------------- | ------------------------------------------------------- | --------------------------- |
| `kb_search`         | `kb search <queries...> --context N --limit N`          | 全文检索,多关键词相关度排序 |
| `kb_list_cards`     | `kb list [--category X] [--type Y] [--owner Z] [--all]` | 列出卡片(默认 JSON 输出)    |
| `kb_get_card`       | `kb get <id>`                                           | 读取单张卡片详情            |
| `kb_project_memory` | `kb memory --project <name\|.>`                         | 读 MEMORY.org 项目记忆节    |
| `kb_fields`         | `kb fields [--category\|--tech\|--type\|--owner]`       | 列出已有字段值              |
| `kb_stats`          | `kb stats`                                              | 知识库统计概览(纯文本)      |
| `kb_tags`           | `kb tags <t1> <t2> ...`                                 | 按标签检索                  |

> 读取组实际是 7 个工具(`kb_fields` 与 `kb_stats` 单列),任务规格里 `kb_fields` 和 `kb_stats` 都属于读取组但分别列,合计 12 个工具。

### 写入组(4)

| MCP 工具           | CLI fallback                                                                    | 说明               |
| ------------------ | ------------------------------------------------------------------------------- | ------------------ |
| `kb_add_card`      | `kb add --title ... --stdin <<<body`                                            | body 通过 stdin 传 |
| `kb_update_card`   | `kb update <id> [--status S] [--append-to X --append-text Y] [--stdin <<<body]` | 支持多种原子更新   |
| `kb_touch_card`    | `kb touch <id> [--used-only]`                                                   | 更新时间戳         |
| `kb_connect_cards` | `kb connect <a> <b> --desc X`                                                   | 双向链接两张卡片   |

### 快速捕获(1)

| MCP 工具   | CLI fallback           | 说明                 |
| ---------- | ---------------------- | -------------------- |
| `kb_inbox` | `kb inbox "<content>"` | 想法快速进 inbox.org |

## 路径

| 用途     | 路径                                 |
| -------- | ------------------------------------ |
| CLI 工具 | `~/.local/bin/kb`                    |
| 经验卡片 | `~/Documents/Org/experiences/`       |
| 记忆文件 | `~/Documents/Org/MEMORY.org`         |
| 项目记忆 | `~/Documents/Org/memories/projects/` |
| 机器索引 | `~/Documents/Org/index.json`         |
| 收件箱   | `~/Documents/Org/inbox.org`          |

MCP 进程继承客户端环境变量，`KB_ROOT` 默认 `~/Documents/Org`。

## 参数速查

写入卡片（`kb_mcp_kb_add_card` / `kb add`）时的参数取值：

### `--type`（类型）

| 值         | 说明        |
| ---------- | ----------- |
| `debug`    | 调试/排障   |
| `refactor` | 重构        |
| `research` | 调研/探索   |
| `workflow` | 工作流/流程 |
| `feature`  | 新功能开发  |
| `config`   | 配置调整    |

### `--owner`（执行者）

| 值              | 说明                |
| --------------- | ------------------- |
| `ai`            | AI 独立完成（默认） |
| `human`         | 人工独立完成        |
| `collaborative` | 人机协作            |

### `--entry`（条目语义，可选）

| 值         | 默认映射                               | 说明                 |
| ---------- | -------------------------------------- | -------------------- |
| `mistake`  | `type=debug`, `owner=collaborative`    | 用户纠错后的复盘卡片 |
| `note`     | `type=workflow`, `owner=collaborative` | 长期注意事项         |
| `ascended` | `type=debug`, `owner=collaborative`    | 飞升模式后的复盘卡片 |

> 显式传入 `--type` 或 `--owner` 时，以显式值为准。`--entry` 映射详见 self-improving skill "Entry type 映射" 表。

### `--status`（状态）

| 值         | 说明                     |
| ---------- | ------------------------ |
| `done`     | 写作完成（新建默认）     |
| `stable`   | 经策展验证，长期有效     |
| `stale`    | >30 天未 `LAST_VERIFIED` |
| `archived` | 已归档                   |

### PROPERTIES 字段（`kb get` 可见）

| 字段             | 说明                                      |
| ---------------- | ----------------------------------------- |
| `LAST_USED`      | 最后一次通过 `kb get`/`kb touch` 访问时间 |
| `LAST_VERIFIED`  | 最后策展验证时间                          |
| `MERGED_INTO`    | 合并目标卡片 ID（被合并的卡片）           |
| `MERGED_FROM`    | 合并来源卡片 ID 列表（主卡片）            |
| `ARCHIVED_AT`    | 归档时间                                  |
| `ARCHIVE_REASON` | 归档原因                                  |

## CLI 专属命令（不在 MCP 工具集中）

以下 `kb` 子命令**未暴露为 MCP 工具**,低频/危险/仅需 CLI 场景使用。Agent 遇到这些操作时必须走 `bash` 调 CLI：

| 命令                                              | 说明               | 原因                      |
| ------------------------------------------------- | ------------------ | ------------------------- |
| `kb lint` / `kb lint --fix`                       | 格式校验与修复     | 批处理,很少在对话中触发   |
| `kb archive <id>` / `kb restore <id>`             | 归档/恢复卡片      | 低频,策展用               |
| `kb review <id>`                                  | 审查卡片质量       | 低频                      |
| `kb merge <主> <次>`                              | 合并卡片           | 低频,策展用               |
| `kb deduplicate`                                  | 检测重复卡片       | 低频,策展用               |
| `kb health`                                       | 知识库健康度报告   | 低频                      |
| `kb memory --add --type feedback/project --stdin` | 添加反馈/项目记忆  | stdin 交互复杂,CLI 更自然 |
| `kb memory --stale` / `--touch` / `--archive`     | 记忆生命周期管理   | 低频                      |
| `kb patterns` / `kb patterns --get`               | 向后兼容的模式命令 | 已弃用,走 MEMORY.org      |
| `kb reindex`                                      | 重建索引           | 低频                      |
| `kb init`                                         | 初始化知识库       | 一次性                    |
| `kb commit`                                       | 提交知识库变更     | git 操作,CLI 更安全       |

> **使用方式**：`bash kb lint --fix` 或直接调 `kb` CLI。这些命令的输出格式与人类终端交互一致。

## 错误处理

- kb 退出码非 0 → `RuntimeError(stderr)` → MCP 框架标记 `isError`。
- 超时 30s(读取 60s 宽松)→ `subprocess.TimeoutExpired` 透传。
- `kb` 不在 `PATH` → 启动时 import 失败会立即崩,客户端看到连接错误(比"工具调用后 500"友好)。

## 已知限制

- **kb 不支持 `--json`**:所有输出格式由 kb CLI 决定(目前 `kb list` 默认 JSON,其余纯文本/org)。如需结构化输出,前端解析。
- **`kb list --category` 当前有上游 bug**(`NameError: DEFAULT_LIST_COUNT`,不在本项目范围)。如命中,建议用 `kb search <category>` 兜底。
- **kb 知识库路径**:走 `KB_ROOT` 环境变量,默认 `~/Documents/Org`。MCP 进程会继承客户端环境变量。
- **每次调用都冷启动 uv**:首次调用约 1-2s 装 mcp 依赖,后续命中 uv 缓存 < 200ms。如需更低延迟,自行 `uv venv && uv pip install` 改成 venv 启动。
- **没有写日志**:刻意保持瘦壳。问题排查直接看 kb 自身的 stderr。
- **没接 home-config.org**:本目录随 `immutable/agents/.config/agents/` 整体由 Guix Home 部署,**mcp.json 注册**需要在 dotfiles/mutable/agents/.config/pi/mcp.json 里手动加(不自动改)。

## 加新工具的模板

在 `server.py` 末尾追加:

```python
@mcp.tool()
def kb_xxx(arg1: str, opt: int | None = None) -> str:
    """一句话描述。"""
    argv = ["xxx", arg1]
    if opt is not None:
        argv += ["--opt", str(opt)]
    return _run_kb(argv)
```

需要 stdin 时加 `stdin=body` 参数;需要更长超时加 `timeout=60.0`。

## Org 格式速查

卡片为 Org mode 格式（非 Markdown），写 `kb_mcp_kb_add_card` 的 body 时注意：

| Markdown        | Org mode                         | 说明     |
| --------------- | -------------------------------- | -------- |
| ` ```lang ``` ` | `#+begin_src lang ... #+end_src` | 代码块   |
| `**bold**`      | `*bold*`                         | 粗体     |
| `## heading`    | `*** heading`                    | 三级标题 |
| `- item`        | `+ item`                         | 无序列表 |
| `` `code` ``    | `=code=`                         | 行内代码 |

> `kb lint --fix` 可自动修复 Markdown 残留，但写入时就写对格式更省心。
> `** 任务描述`（`**` 后有空格）是 Org 二级标题，不是粗体。
> `kb_mcp_kb_add_card` 自动生成一级标题，body 从二级标题开始写。
