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
