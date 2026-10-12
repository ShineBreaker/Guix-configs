# assisted-by-zcode

[中文文档](./README_CN.md)

AI-attributed commit trailer enforcement for ZCode sessions. The plugin name is historical: the trailer it actually enforces is `Co-authored-by`, whose format (`Co-authored-by: <AGENT> (<MODEL>) <EMAIL>`) comes from the commit conventions in `~/.config/agents/context/domains/coding.md` — `~/.config/git/gitmessage` only defines the commit-type list.

Two layers, deliberately independent of any knowledge-base/agent integration:

| Layer    | Mechanism                                                                                                                              | Guarantee                                        |
| -------- | -------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------ |
| Reminder | `PreToolUse(Bash)` hook — on `git commit`, injects a reminder to append a full trailer carrying the model's name and version             | Full attribution, but relies on model compliance |
| Fallback | `~/.config/git/hooks/prepare-commit-msg` global git hook — appends the detected host's placeholder trailer when the model forgets        | Agent name even when the model forgets           |

The fallback layer has moved out of this plugin into the managed git configuration area: source lives at `dotfiles/immutable/utilities/.config/git/hooks/` (`prepare-commit-msg` + `forward-to-repo-hook` + four named stubs), `core.hooksPath` is in `~/.config/git/config`, and it deploys via `blue home`. Do not maintain a copy inside this plugin.

## Plugin install

Point `plugins.dirs` in `~/.zcode/cli/config.json` at this plugin root (each entry is one plugin directory containing `.zcode-plugin/plugin.json`):

```json
{
  "plugins": {
    "dirs": ["/home/brokenshine/Projects/Config/Guix-configs/dotfiles/mutable/agenote/.zcode/plugins/agenote-zcode", "/home/brokenshine/Projects/Config/Guix-configs/dotfiles/mutable/agents/zcode/.zcode/plugins/assisted-by-zcode"]
  }
}
```

Then open a new session — plugin hooks are snapshotted at session start.

## Fallback hook behavior (managed version)

- Detects the host from session env vars: `ZCODE_APP_VERSION` (zcode), `HERMES_AGENT` (hermes), `DSH_AGENT` (injected by the dsh wrapper), `PI_CODING_AGENT_DIR`/`PI_CONFIG_DIR` (pi/omp), `CLAUDECODE` (claude), with `AI_AGENT` (devin and other generic attribution values) as the last resort; a terminal with no agent marker is passed through untouched.
- Covers plain commit paths only (`$2` empty / `message` / `template`); merge, squash and amend are left alone.
- Skips only when the message already carries a `Co-authored-by:` line naming this host, so the full trailer the model wrote is preserved. Other agents' trailers do not count — this session's line is appended alongside them.
- When a host is detected but missing from the trailer map, it writes an explicit placeholder trailer and exits non-zero, asking for manual completion.
- Repository-level hooks (e.g. this repo's git-lfs hooks) are forwarded by `forward-to-repo-hook` via named stubs, so `core.hooksPath` does not eat them.
