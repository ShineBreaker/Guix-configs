# 卡片格式与字段

agenote 卡片是 Org mode 文件，结构与人类卡片完全一致（仅靠 OWNER=ai 和 agenote/ 目录区分）。

## 文件位置

```
~/Documents/Org/agenote/experiences/<category>/<timestamp>-<type>-<category>.org
```

## PROPERTIES 字段

```org
* DONE 卡片标题
:PROPERTIES:
:ID:       20260625-014305
:CREATED:  [2026-06-25 四 01:43]
:CATEGORY: general
:TECH:     general
:TYPE:     workflow
:ENTRY_TYPE: note
:STATUS:   done
:LAST_USED:   [2026-06-25 四 01:43]
:LAST_VERIFIED: [2026-06-25 四 01:43]
:EFFORT:
:OWNER:    ai
:WEIGHT:   1.0
:USAGE_COUNT: 0
:END:
:general:workflow:ai::
```

| 字段        | 说明                                             |
| ----------- | ------------------------------------------------ |
| ID          | 时间戳格式 `YYYYMMDD-HHMMSS`，get/touch 用它定位 |
| CATEGORY    | 自由分类，影响文件存放子目录                     |
| TECH        | 技术栈标签                                       |
| TYPE        | debug/refactor/research/workflow/feature/config  |
| ENTRY_TYPE  | mistake/note/ascended（见 entry-types.md）       |
| STATUS      | done/stable/stale/archived                       |
| OWNER       | 固定 `ai`（agenote 卡片）                        |
| WEIGHT      | 检索权重，agent 默认 1.0，curate 时动态调整      |
| USAGE_COUNT | 被引用次数，touch/get --used 时递增              |

## 章节模板

`note` 类型默认 body：

```
*** 事项内容
*** 为什么值得长期保留
*** 适用场景与例外
*** 后续行动
```

`mistake` 类型默认 body：

```
*** 原始问题
*** 用户纠错反馈
*** 这次到底错在哪里
*** 最终正确处理
```

`ascended` 类型默认 body：

```
*** 前几轮失败的根因
*** 检索过的知识源
*** 核对过的真实文件或输出
*** 最终采用的最强方案
```
