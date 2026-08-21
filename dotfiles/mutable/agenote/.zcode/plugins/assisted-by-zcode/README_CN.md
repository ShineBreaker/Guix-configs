# assisted-by-zcode

[English](./README.md)

ZCode 会话的 Assisted-by 提交规范保障，实现 `~/.config/git/gitmessage` 定义的 trailer 格式：`Assisted-by: <AGENT_NAME>:<MODEL_VERSION> [TOOL1] [TOOL2]`。

两层机制，与任何知识库/agent 集成刻意无关：

| 层 | 机制 | 保障 |
| --- | --- | --- |
| 提醒层 | `PreToolUse(Bash)` hook——`git commit` 时注入提醒，让模型写完整 trailer（含模型名与版本号） | 归因完整，但依赖模型遵守 |
| 兜底层 | `git-hooks/prepare-commit-msg` 装为全局 git hook——消息缺 trailer 时才补 `Assisted-by: zcode` | 模型遗漏时也有 agent 名 |

## 插件安装

在 `~/.zcode/cli/config.json` 的 `plugins.dirs` 指向本插件根目录（每条是一个含 `.zcode-plugin/plugin.json` 的插件目录）：

```json
{
  "plugins": {
    "dirs": [
      "/home/brokenshine/Projects/Config/Guix-configs/dotfiles/mutable/agenote/.zcode/plugins/agenote-zcode",
      "/home/brokenshine/Projects/Config/Guix-configs/dotfiles/mutable/agenote/.zcode/plugins/assisted-by-zcode"
    ]
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
- 仅当消息无 `^Assisted-by:` 行时追加 `Assisted-by: zcode`——模型按提醒写的完整 trailer 原样保留。

## 边界说明

兜底层目前仅通过 `ZCODE_APP_VERSION` 识别 zcode 会话。要让其他 AI agent（pi、crush 等）也享受兜底，需泛化 env 检测并把资产从本 zcode 插件迁到 dotfiles 的 git 配置区——这是有意的后续步骤，此处不做。
