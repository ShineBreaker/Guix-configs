# VC 状态翻译映射表

mode-line 中 `custom/modeline--vc-segment` 使用的 VC 状态英文到中文映射：

| 英文状态 | 中文翻译 | icon | face |
|----------|----------|------|------|
| clean | 已同步 | nf-md-check_circle | success |
| edited | 已编辑 | nf-md-pencil | warning |
| unsaved | 未保存 | nf-md-content_save_alert | warning |
| added | 已添加 | nf-md-plus_circle | success |
| removed | 已删除 | nf-md-minus_circle | error |
| missing | 缺失 | nf-md-alert_circle | error |
| conflict | 冲突 | nf-md-alert_octagon | error |
| merge | 合并 | nf-md-source_merge | warning |
| update | 更新 | nf-md-cloud_download | warning |
| ignored | 已忽略 | nf-md-eye_off | shadow |
| untracked | 未跟踪 | nf-md-help_circle | warning |

# 诊断格式翻译

| 英文格式 | 中文格式 | 使用场景 |
|----------|----------|----------|
| E:%d W:%d | 错:%d 警:%d | mode-line wide 档诊断计数 |

# Dashboard 错误翻译

| 英文 | 中文 | 使用场景 |
|------|------|----------|
| agenote process failed | agenote 进程失败 | 异步进程失败时的错误消息 |
| agenote executable not found | 未找到 agenote 可执行文件 | agenote CLI 未安装 |
| knowledge refresh failed | 知识库刷新失败 | 知识库卡片数据刷新失败 |
| cache warmup failed | 缓存预热失败 | daemon 预热缓存失败 |

# 功能提示翻译

| 英文 | 中文 | 使用场景 |
|------|------|----------|
| feature not found | 未找到 feature | daemon 预加载白名单 feature 缺失 |
