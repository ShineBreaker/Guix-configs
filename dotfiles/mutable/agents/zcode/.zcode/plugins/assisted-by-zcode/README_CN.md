# assisted-by-zcode

[English](./README.md)

ZCode 会话的 AI 归因提交规范保障。插件名是历史遗留：实际强制的 trailer 是 `Co-authored-by`，其格式（`Co-authored-by: <AGENT> (<MODEL>) <EMAIL>`）来自 `~/.config/agents/context/domains/coding.md` 的 commit 规范——`~/.config/git/gitmessage` 只定义提交类型清单。

两层机制，与任何知识库/agent 集成刻意无关：

| 层     | 机制                                                                                                          | 保障                     |
| ------ | ------------------------------------------------------------------------------------------------------------- | ------------------------ |
| 提醒层 | `PreToolUse(Bash)` hook——`git commit` 时注入提醒，让模型写带模型名与版本号的完整 trailer                        | 归因完整，但依赖模型遵守 |
| 兜底层 | `~/.config/git/hooks/prepare-commit-msg` 全局 git hook——模型遗漏时补宿主占位 trailer（多宿主映射，zcode 为一行） | 模型遗漏时也有 agent 名  |

兜底层已迁出本插件、入 git 配置区受管：源在 `dotfiles/immutable/utilities/.config/git/hooks/`（`prepare-commit-msg` + `forward-to-repo-hook` + 四个具名 stub），`core.hooksPath` 在 `~/.config/git/config`，随 `blue home` 部署生效，勿在本插件内再维护副本。

## 插件安装

在 `~/.zcode/cli/config.json` 的 `plugins.dirs` 指向本插件根目录（每条是一个含 `.zcode-plugin/plugin.json` 的插件目录）：

```json
{
  "plugins": {
    "dirs": ["/home/brokenshine/Projects/Config/Guix-configs/dotfiles/mutable/agenote/.zcode/plugins/agenote-zcode", "/home/brokenshine/Projects/Config/Guix-configs/dotfiles/mutable/agents/zcode/.zcode/plugins/assisted-by-zcode"]
  }
}
```

然后开新会话——插件 hooks 在会话启动时快照。

## 兜底 hook 行为（受管版）

- 按会话 env 识别宿主：`ZCODE_APP_VERSION`（zcode）、`HERMES_AGENT`（hermes）、`DSH_AGENT`（dsh wrapper 注入）、`PI_CODING_AGENT_DIR`/`PI_CONFIG_DIR`（pi/omp）、`CLAUDECODE`（claude）、`AI_AGENT`（devin 等通用归因变量）兜底；无任何标识的人工终端静默放行。
- 只覆盖常规提交路径（`$2` 为空 / `message` / `template`）；merge、squash、amend 不动。
- 仅当消息里已有本宿主署名的 `Co-authored-by:` 行时才跳过，模型写下的完整 trailer 原样保留；其他 agent 的 trailer 不算，会与它们并存追加本会话的署名。
- 识别到宿主但映射表未登记时写入显式占位 trailer 并退出非零，提示人工补全。
- 仓库自身 hook（如本仓库的 git-lfs 钩子）由同目录 `forward-to-repo-hook` 经具名 stub 转发，不被 `core.hooksPath` 吃掉。
