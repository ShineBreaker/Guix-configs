# assisted-by-zcode

[English](./README.md)

ZCode 会话的 AI 归因提交规范保障。插件名是历史遗留：实际强制的 trailer 是 `Co-authored-by`，其格式（`Co-authored-by: <AGENT> (<MODEL>) <EMAIL>`）来自 `~/.config/agents/context/domains/coding.md` 的 commit 规范——`~/.config/git/gitmessage` 只定义提交类型清单。

两层机制，与任何知识库/agent 集成刻意无关：

| 层     | 机制                                                                                        | 保障                     |
| ------ | ------------------------------------------------------------------------------------------- | ------------------------ |
| 提醒层 | `PreToolUse(Bash)` hook——`git commit` 时注入提醒，让模型写带模型名与版本号的完整 trailer    | 归因完整，但依赖模型遵守 |
| 兜底层 | `git-hooks/prepare-commit-msg` 装为全局 git hook——补 `Co-authored-by: ZCode <noreply@z.ai>` | 模型遗漏时也有 agent 名  |

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

## 兜底 git hook 安装

由于 `core.hooksPath` 会完全取代仓库级 hook 查找，同目录附带通用转发器，让仓库自身的 hook 继续生效：

```bash
mkdir -p ~/.config/git/hooks
ln -sf <插件根>/git-hooks/prepare-commit-msg ~/.config/git/hooks/
for h in post-checkout post-commit post-merge pre-push; do
  ln -sf <插件根>/git-hooks/forward-to-repo-hook ~/.config/git/hooks/$h
done
git config --global core.hooksPath ~/.config/git/hooks
```

转发器在仓库 `<repo>/.git/hooks/<同名>` 存在且可执行时执行之，参数与 stdin 透传。仓库实际用到哪些 hook 名就 symlink 哪些。

`prepare-commit-msg` 行为：

- 仅当 `ZCODE_APP_VERSION` 已设置（即 zcode Bash 会话内）才生效；手动终端不受影响。
- 只覆盖常规提交路径（`$2` 为空 / `message` / `template`）；merge、squash、amend 不动。
- 仅当消息里已有署名 zcode 的 `Co-authored-by:` 行时才跳过，模型写下的完整 trailer 原样保留；其他 agent 的 trailer 不算，会与它们并存追加本会话的署名。

## 边界说明

兜底层目前仅通过 `ZCODE_APP_VERSION` 识别 zcode 会话。由于 `Co-authored-by` 是所有 agent 共用的规范，要让 pi、crush 等也享受兜底，需泛化 env 检测并把资产从本 zcode 插件迁到 dotfiles 的 git 配置区——这是有意的后续步骤，此处不做。
