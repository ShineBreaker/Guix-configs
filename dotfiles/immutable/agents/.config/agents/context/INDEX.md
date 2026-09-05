# 领域上下文 INDEX

通用原则见 00-core（恒注入）。本表是领域路由：识别到对应领域的任务时，主动 Read 该域文件获取完整原则；红线摘要在场即硬约束，全文是扩展细则。

新增领域：`domains/` 加文件 + `context-select.sh` 映射表加一行 + 本表加条目，三者一致性由 `context-select.sh --check` 校验。

## coding — 软件开发

场景：git 仓库内的编码、重构、调试、提交。zcode / omp / hermes 端由 selector 自动注入本域文件；crush 端无注入机制，识别到编码任务时手动拉取。
红线：

- 外科手术式修改：只动必须改的；禁止批量回滚或任何可能丢弃未 commit 改动的操作
- commit 遵守 `~/.config/git/gitmessage` 类型表与 commit 规范；`git commit` 必带 `-m`
- 禁交互式 `git add -p` / `git rebase -i`（无 TTY 会挂起）
  文件：~/.config/agents/context/domains/coding.md
