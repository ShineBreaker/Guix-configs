# agenote-zcode

[中文文档](./README_CN.md)

[agenote](https://github.com/ShineBreaker/agenote) integration for ZCode, mirroring the pi-side `agenote-hooks` extension. Skills (`agenote-{base,curator,review}`) live in `~/.agents/skills/` and are shared across agents — this plugin only does **event triggering + command shortcuts**, never duplicating skill content.

## Components

| Component | Event / Invocation | What it does |
| --- | --- | --- |
| `hooks/session-start.mjs` | `SessionStart` | Injects agenote usage rules (incl. the mandatory `AGENOTE_AGENT=zcode` prefix for attribution) plus a KB health summary |
| `hooks/prompt-submit.mjs` | `UserPromptSubmit` (regex pre-filter on completion words in `hooks.json`) | Precise signal match + 5-min debounce (state under the plugin data dir), then injects an `agenote-review` evaluation prompt. Self-injections carrying `<agenote-hook>` are skipped |
| `hooks/pre-tool-use.mjs` | `PreToolUse` matcher `Bash` | Reminds to prefix `AGENOTE_AGENT=zcode` when missing |
| `commands/{summarize,curate,health}.md` | `/agenote-zcode:summarize` etc. | Slash-command shortcuts mirroring pi's `/agenote-*` commands |

Deliberately not ported from pi:

- **Idle fallback** — ZCode has no `agent_end`; the `Stop` hook's continuation request would interfere with normal session end.
- **MCP server** — agenote's primary path is the CLI; skills instruct bash invocation directly.
- **Subagent guard** — `UserPromptSubmit` only fires on user input in the main session.

Commit-trailer enforcement (`Assisted-by`) is a separate concern and lives in its own plugin: see `../assisted-by-zcode/`.

## Install

Point `plugins.dirs` in `~/.zcode/cli/config.json` at this plugin root (each entry is one plugin directory containing `.zcode-plugin/plugin.json`; scanned entries are enabled by default):

```json
{
  "plugins": {
    "dirs": ["/home/brokenshine/Projects/Config/Guix-configs/dotfiles/mutable/agenote/.zcode/plugins/agenote-zcode"]
  }
}
```

Then open a new session — plugin hooks are snapshotted at session start. Verify under **Settings → Plugin Management**.

## Maintenance notes

- Completion signals have a single source of truth: `agenote-review/references/triggers.md`. When editing signals, sync all three places: triggers.md, `hooks/prompt-submit.mjs` (`COMPLETION_SIGNALS`), and the `UserPromptSubmit` matcher regex in `hooks/hooks.json`.
- Long-lived state (debounce timestamp) goes to the plugin data directory injected by ZCode, falling back to `~/.local/state/agenote-zcode/`.
