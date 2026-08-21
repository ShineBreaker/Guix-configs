# assisted-by-zcode

[中文文档](./README_CN.md)

Assisted-by commit trailer enforcement for ZCode sessions, implementing the trailer format defined in `~/.config/git/gitmessage`: `Assisted-by: <AGENT_NAME>:<MODEL_VERSION> [TOOL1] [TOOL2]`.

Two layers, deliberately independent of any knowledge-base/agent integration:

| Layer | Mechanism | Guarantee |
| --- | --- | --- |
| Reminder | `PreToolUse(Bash)` hook — on `git commit`, injects a reminder to append a full trailer with the model's name and version | Full attribution, but relies on model compliance |
| Fallback | `git-hooks/prepare-commit-msg` installed as a global git hook — appends `Assisted-by: zcode` only when the message lacks a trailer | Agent name even when the model forgets |

## Plugin install

Point `plugins.dirs` in `~/.zcode/cli/config.json` at this plugin root (each entry is one plugin directory containing `.zcode-plugin/plugin.json`):

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

Then open a new session — plugin hooks are snapshotted at session start.

## Fallback git hook install

Because `core.hooksPath` replaces per-repo hook lookup entirely, the same directory ships a generic forwarder so repository-level hooks keep working:

```bash
mkdir -p ~/.config/git/hooks
ln -sf <plugin-root>/git-hooks/prepare-commit-msg ~/.config/git/hooks/
for h in post-checkout post-commit post-merge pre-push; do
  ln -sf <plugin-root>/git-hooks/forward-to-repo-hook ~/.config/git/hooks/$h
done
git config --global core.hooksPath ~/.config/git/hooks
```

The forwarder executes `<repo>/.git/hooks/<same-name>` when it exists and is executable, passing through args and stdin. Add one symlink per hook name your repositories actually use.

`prepare-commit-msg` behavior:

- Runs only when `ZCODE_APP_VERSION` is set (i.e. inside a ZCode Bash session); manual terminals are untouched.
- Covers plain commit paths only (`$2` empty / `message` / `template`); merge, squash and amend are left alone.
- Appends `Assisted-by: zcode` only when no `^Assisted-by:` line exists — the full trailer written by the model is preserved.

## Scope note

The fallback detects ZCode sessions via `ZCODE_APP_VERSION` only. Making it cover other AI agents (pi, crush, …) means generalizing the env detection and moving the asset out of this ZCode plugin into the dotfiles git configuration area — a deliberate future step, not done here.
