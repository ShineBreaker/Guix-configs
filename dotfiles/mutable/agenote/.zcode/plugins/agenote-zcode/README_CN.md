# agenote-zcode

[English](./README.md)

[agenote](https://github.com/ShineBreaker/agenote) 的 ZCode 集成插件，对齐 pi 侧的 `agenote-hooks` 扩展。skills（`agenote-{base,curator,review}`）位于 `~/.agents/skills/`、跨 agent 共享——本插件只做「事件触发 + 命令快捷入口」，不重复维护 skill 内容。

## 组件

| 组件                                    | 事件 / 调用                                         | 作用                                                                                                                              |
| --------------------------------------- | --------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| `hooks/session-start.mjs`               | `SessionStart`                                      | 注入 agenote 使用规则（含必需的 `AGENOTE_AGENT=zcode` 归因前缀）与记事本健康度摘要                                                |
| `hooks/prompt-submit.mjs`               | `UserPromptSubmit`（hooks.json 里按完成词正则粗筛） | 精确信号匹配 + 5 分钟防抖（状态存插件数据目录），命中注入 `agenote-review` 评估提示；含 `<agenote-hook>` 标记的自注入回声跳过检测 |
| `hooks/pre-tool-use.mjs`                | `PreToolUse` matcher `Bash`                         | `agenote` 命令缺 `AGENOTE_AGENT=zcode` 前缀时提醒                                                                                  |
| `commands/{summarize,curate,health}.md` | `/agenote-zcode:summarize` 等                       | 斜杠命令快捷入口，对应 pi 的 `/agenote-*`                                                                                         |

有意未从 pi 移植的部分：

- **空闲兜底** —— zcode 无 `agent_end`；`Stop` hook 的续命请求会干扰正常会话结束。
- **MCP server** —— agenote 主路径是 CLI，skill 直接指示 bash 调用。
- **subagent 守卫** —— `UserPromptSubmit` 只在主会话用户输入时触发。

提交规范保障（`Assisted-by`）是独立关注点，单独成插件：见 `../assisted-by-zcode/`。

## 安装

在 `~/.zcode/cli/config.json` 的 `plugins.dirs` 指向本插件根目录（每条是一个含 `.zcode-plugin/plugin.json` 的插件目录，扫描到的默认启用）：

```json
{
  "plugins": {
    "dirs": ["/home/brokenshine/Projects/Config/Guix-configs/dotfiles/mutable/agenote/.zcode/plugins/agenote-zcode"]
  }
}
```

然后开新会话——插件 hooks 在会话启动时快照。可在「设置 → 插件管理」确认加载。

## 维护说明

- 完成信号的单一真相源是 `agenote-review/references/triggers.md`。改动信号需同步三处：triggers.md、`hooks/prompt-submit.mjs`（`COMPLETION_SIGNALS`）、`hooks/hooks.json` 的 `UserPromptSubmit` matcher 正则。
- 长驻状态（防抖时间戳）写入 zcode 注入的插件数据目录，缺失时退到 `~/.local/state/agenote-zcode/`。
