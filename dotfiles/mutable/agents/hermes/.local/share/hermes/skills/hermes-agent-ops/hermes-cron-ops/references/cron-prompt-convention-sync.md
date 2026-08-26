# Cron prompt 与全局约定的同步

## 问题

用户切换全局约定（commit 规范、报告格式、命名偏好等）时，通常只改 memory 和 skill，但**已有 cron job 的 prompt 是自包含快照**——里面可能内嵌着老规范，每次运行都会按老规范产出。

实例（2026-08-26）：用户全面切换 Conventional Commits 后巡检发现 cron `jeans-issue-fixer` 的 prompt 仍要求生成 `UPDATE: auto package update YYYY-MM-DD` / `FIX: <简述>` 格式的 gitmessage（大写前缀 + 非标准类型），与规范冲突。该任务每次运行都给用户产出可直接复制的提交信息，是漂移影响最大的位置。

## 同步流程

1. 列出所有任务：`cronjob(action='list')` 或读 `$HERMES_HOME/cron/jobs.json`（后者能拿到完整 prompt，list 只有 preview）。
2. 对每个 prompt 搜涉规范的指令性文本（如 gitmessage 要求、格式要求）。
3. 更新：`cronjob(action='update', job_id=..., prompt=<全文重发>)`。**工具没有局部编辑**——必须取原文、只改涉规范段落、其余原样带回；改完核对返回体的 schedule/workdir/enabled_toolsets 等字段未被误动。
4. 区分「规范指令」与「历史证据」：prompt/skill 里引用的老式 commit message 若是反模式教学或真实案例记录（hash + 原始标题），不改写；只改要求 agent *今后照做* 的文本。

## 关联

- 规范本体见 memory / fact_store「提交规范」与各仓库 AGENTS.md。
- 模型 pin 等其他 cron 运维见本 skill 主文档。
