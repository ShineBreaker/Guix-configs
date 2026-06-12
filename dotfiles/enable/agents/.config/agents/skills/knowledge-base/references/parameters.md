# 参数取值

<critical> 
`category` 和 `tech` 均**不设白名单**，允许自由输入。Agent 在写入前应先用 `kb fields --category` 或 `kb fields --tech` 查看已有标签，优先复用；只有遇到全新领域时才创建新类别。
</critical>

## --category（类别，自由输入，优先复用已有标签）

请直接通过 `kb fields --category` 来获取已有的内容

## --tech（技术栈，自由输入，优先复用已有标签）

请直接通过 `kb fields --tech` 来获取已有的内容

同上，优先复用已有 tech 标签，无匹配时再创建。

## --type（类型）

| 值         | 说明        |
| ---------- | ----------- |
| `debug`    | 调试/排障   |
| `refactor` | 重构        |
| `research` | 调研/探索   |
| `workflow` | 工作流/流程 |
| `feature`  | 新功能开发  |
| `config`   | 配置调整    |

## --owner（执行者）

| 值              | 说明                |
| --------------- | ------------------- |
| `ai`            | AI 独立完成（默认） |
| `human`         | 人工独立完成        |
| `collaborative` | 人机协作            |

## --entry / --entry-type（条目语义，可选）

| 值         | 默认映射                               | 说明                 |
| ---------- | -------------------------------------- | -------------------- |
| `mistake`  | `type=debug`, `owner=collaborative`    | 用户纠错后的复盘卡片 |
| `note`     | `type=workflow`, `owner=collaborative` | 长期注意事项         |
| `ascended` | `type=debug`, `owner=collaborative`    | 飞升模式后的复盘卡片 |

显式传入 `--type` 或 `--owner` 时，以显式值为准。

## --status（状态，Phase 0 新增）

| 值        | 说明                                  |
| --------- | ------------------------------------- |
| `done`    | 写作完成（新建默认）                  |
| `stable`  | 经策展验证，长期有效                  |
| `stale`   | >30 天未 LAST_VERIFIED                |
| `archived`| 已归档                                |

`--status stable` 时自动更新 LAST_VERIFIED 为当前时间。

## PROPERTIES 新增字段

| 字段            | 说明                              |
| --------------- | --------------------------------- |
| `LAST_USED`     | 最后一次通过 kb get/touch 访问时间 |
| `LAST_VERIFIED` | 最后策展验证时间                   |
| `MERGED_INTO`   | 合并目标卡片 ID（被合并的卡片）   |
| `MERGED_FROM`   | 合并来源卡片 ID 列表（主卡片）    |
| `ARCHIVED_AT`   | 归档时间                          |
| `ARCHIVE_REASON`| 归档原因                          |

## 新命令概览

| 命令          | 用法                                | 说明               |
| ------------- | ----------------------------------- | ------------------ |
| `kb touch`    | `kb touch <id> [--used-only]`       | 更新时间戳         |
| `kb merge`    | `kb merge <primary> <sec>...`       | 合并卡片           |
| `kb archive`  | `kb archive <id> [--stale]`         | 归档               |
| `kb restore`  | `kb restore <id> [--status stable]` | 恢复               |
| `kb deduplicate` | `kb deduplicate [--threshold 0.7]` | 检测重复           |
| `kb review`   | `kb review <id> [--fix]`            | 审查卡片           |
| `kb health`   | `kb health`                         | 健康度报告         |
