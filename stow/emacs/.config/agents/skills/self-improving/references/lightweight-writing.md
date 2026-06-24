# 轻量写入模式

## 适用场景

不是所有经验都值得写完整卡片。以下场景用轻量写入：

- 一次性环境失败（不值得记录）
- 简单的参数/配置修正
- 已有卡片的补充说明
- 一句话注意事项

## 方式

### 1. kb inbox — 快速捕获

```bash
echo "注意: X 工具的 --flag 参数在 v2.0 后行为变更" | kb inbox
```

适合：尚未整理的想法、待后续分类的注意点。

### 2. kb update --append — 补充已有卡片

```bash
kb update <id> --append-to "关键发现" --append-text "补充: 新发现的边界条件"
```

适合：已有卡片需要补充新信息。

### 3. kb memory --add — 记录偏好/习惯

```bash
echo "内容" | kb memory --add --type feedback --title "偏好描述"
```

适合：用户偏好、行为模式。

## 自动模式

在自动策展（kb-curator）中：

- `kb health` 检查知识库状况
- `kb deduplicate` 清理重复
- `kb review --fix` 修复质量问题
- 状态转换自动处理（done → stable → stale → archived）

## 卡片生命周期

```
done ─── 策展验证 ──→ stable ─── >30天未验证 ──→ stale ─── >90天 ──→ archived
  ↑                                                                │
  └──────────── kb restore <id> ───────────────────────────────────┘
```
