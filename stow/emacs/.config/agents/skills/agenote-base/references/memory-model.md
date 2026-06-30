# 记忆系统模型

agenote 的 memory 子系统记录跨会话的偏好与项目元数据，存储在 `~/Documents/Org/agenote/MEMORY.org` 和 `memories/projects/`。

## 四个标准节

| 节         | 用途     | agenote 场景                                        |
| ---------- | -------- | --------------------------------------------------- |
| feedback   | 行为偏好 | 用户对 agent 工作方式的偏好（如回复风格、工具选择） |
| project    | 项目记忆 | 按项目拆分，存 `memories/projects/<项目>.org`       |
| reference  | 参考资料 | 可跨项目复用的参考（常用 API、工具用法）            |
| deprecated | 归档     | 陈旧记忆归档区                                      |

## 检索方式

```bash
agenote memory                          # 全部概览
agenote memory --type feedback          # 只看 feedback
agenote memory --project <名称|路径|.>   # 按项目检索
agenote memory --get                    # 全文
agenote memory --get --type project     # 只看 project 节
agenote memory --stale                  # 陈旧记忆（超 30 天未更新）
```

## 写入

```bash
# feedback 记忆
echo "用户偏好简洁回复，不要长篇解释" | \
  agenote memory --add --type feedback --title "回复风格偏好" --stdin

# project 记忆（按项目拆分到独立文件）
echo "该项目用 Guix 构建，blue rebuild 部署" | \
  agenote memory --add --type project --title "构建方式" \
  --project Guix-configs --stdin
```

## feedback 条目格式

```org
** F001 回复风格偏好
   :PROPERTIES:
   :CREATED:  [2026-06-25]
   :UPDATED:  [2026-06-25]
   :END:
   用户偏好简洁回复，不要长篇解释
```

## 维护

```bash
agenote memory --touch F001              # 更新时间戳
agenote memory --archive F001            # 归档到 deprecated
agenote memory --stale --auto-archive-days 60  # 自动归档陈旧 feedback
```
