---
name: hermes-memory-routing
description: "诊断 Hermes 内置记忆的路由与落盘问题、按 agenote 接管需要关闭/复核宿主自带记忆；当用户提到 memory 不生效、MEMORY.md 未更新、记忆漂移或记忆检索异常时使用。先验证实际存储路径与 memory 工具写入，再用 agenote 归档项目经验。"
version: 0.2.1
metadata:
  hermes:
    tags: [hermes, memory, agent-routing, prompt-engineering]
    category: hermes-agent-ops
---

# Hermes 内置记忆路由

本机 Hermes 只使用内置 `MEMORY.md` / `USER.md`。`memory` 工具负责写入；`agenote` 是独立的跨 agent 经验库，不是 Hermes 运行时 provider。

## 适用边界

- 用户偏好、跨会话行为约定：`memory`，目标为 `user`。
- 跨任务通用的环境约定：`memory`，目标为 `memory`。
- 项目专属事实、调试结论、部署拓扑和命令诀窍：写入 `agenote` 卡片，按需 `agenote search`；不要为了容量把项目事实塞进内置 markdown。
- 内置记忆与 agenote 不互相镜像，也不做 session 启动同步。

## 验证实际落盘

不要只依据 SOUL.md 的描述判断写入结果；直接读目标文件并核对内容：

```bash
wc -c "$HERMES_HOME/memories/MEMORY.md" "$HERMES_HOME/memories/USER.md"
```

调用 `memory(action='add'|'replace', target='user'|'memory', content=...)` 后，重新读取目标文件。工具返回的 `entry_count` 不是磁盘真相。禁止用 `write_file`、`patch` 或 shell 重定向直接编辑内置记忆；外部修改会触发 drift 检查并可能留下备份。

## 迁移与归档

从旧的外部记忆库迁移时，先导出并逐条查重，再把仍有效的内容写入 `agenote`。不要恢复已停用的 provider、工具或镜像流程；历史问题记录可以作为事实来源，但必须明确标为历史背景。

## 关闭 / 复核宿主自带记忆（agenote 接管）

推进 agenote 作为事实层单一来源时，目标态 = 各宿主自带记忆关闭。关闭走各宿主自己的官方配置通道，改完统一用 `agenote doctor` 复核（zcode / claude / omp / hermes 四项应全绿、`dual-channel` 无警告）。

- **hermes**：`hermes config set memory.memory_enabled false` + `hermes config set memory.user_profile_enabled false`。**不要用 write/patch 直接编辑 config.yaml**——会被安全门禁拒绝（「Agent cannot modify security-sensitive configuration」）；`hermes config set` 是官方通道，且同样落在仓库源（stow 直链，mutable 保存即生效）。关闭 ≠ 删除：`memories/MEMORY.md` / `USER.md` 原样保留（只是停止注入与写入），`agenote scan-memories --source hermes` 依旧可读；关闭前先把两个记忆文件快照到工作区外目录。
- **zcode**：`~/.zcode/cli/config.json` 顶层加 `"features": {"memory": false}`。该文件可能被 zcode 运行时覆写为实体（不再是 stow 链接），回源与重建链流程见 `guix-configs-workflow` §8。
- **claude**：`~/.claude/settings.json` 置 `{"autoMemoryEnabled": false, "autoDreamEnabled": false}`（键缺失视为开启；文件不存在则新建）。
- 验证与收尾：`agenote doctor` 看四项全绿；配置变更按 Conventional Commits 入库（agent 不自动 push）。

## 经验卡片

- 工具/项目事实：`agenote add --entry note`，使用现有 category/tech/type，正文保留证据和适用边界。
- 踩坑或被纠正：`agenote add --entry mistake`。
- 多轮试错后的方案：`agenote add --entry ascended`。
- 写入前先 `agenote search`，命中既有卡片则 `touch` 或追加证据，不重复建卡。

## 验证原则

配置或 prompt 只说明意图；最终以配置文件、真实文件和 CLI 输出为准。涉及环境变量时读取真实进程状态，不能合成替身环境作为佐证。
