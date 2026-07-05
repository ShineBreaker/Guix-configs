---
name: skill-authoring
description: "How to author a Hermes Agent skill the right way. Covers the two non-negotiable structural principles every skill must follow — **self-contained** (all runnable artifacts ship inside the skill directory so backup = usable) and **progressive disclosure** (SKILL.md is a thin router; details live under `references/`, `templates/`, `scripts/`) — plus the directory layout, file-type rules, decision trees for what goes in the main file vs. a support file, and a checklist before declaring a skill done. Trigger when: writing a new skill, refactoring an existing skill's structure, wondering 'should this go in SKILL.md or references/', preparing a skill for backup/share, noticing a skill violates the self-contained rule (e.g. references an external path outside the skill dir), or auditing existing skills against the two principles. Also trigger when the user complains that something in a skill 'is too verbose' or 'the docs are in the wrong place' — those are progressive-disclosure violations, not just style nits."
version: 1.1.0
license: MIT
metadata:
  hermes:
    tags: [skill-design, self-contained, progressive-disclosure, references, scripts, structure]
    related_skills: [hermes-skill-curation, hermes-agent, agent-session-import]
---

# Skill Authoring

The two principles a skill **must** follow. Violating either is a
structural defect, not a style preference — and the user will
notice.

## 1. Self-contained (backup = usable)

Every runnable artifact the skill references — scripts, fixtures,
templates, even a small CLI — must live **inside the skill
directory**, not in `~/.local/share/<agent>/tools/` or any other
side path. If a backup of `~/.local/share/hermes/skills/<name>/`
should not be enough to keep the skill fully working, the skill
is broken.

**Why this matters.** The user manages skill backups (often as a
single `tar` of `~/.local/share/hermes/skills/` or as a Guix stow
module). If the skill's importer script lives at
`~/.local/share/zcode/tools/import-zcode-to-hermes.py` and the
SKILL.md says "run this script", a backup that captures only the
skill directory leaves a working description with no working
tool. The user has to remember to also back up the external path.

**Layout that satisfies self-containment:**

```
~/.local/share/hermes/skills/<name>/
├── SKILL.md           # always present, ~500 lines hard ceiling
├── references/        # session-specific detail, schema tables,
│   │                  #   error transcripts, condensed knowledge
│   │                  #   banks — loaded on demand
│   │   ├── pi.md
│   │   └── zcode.md
├── templates/         # starter files meant to be copied &
│   │                  #   modified (boilerplate configs,
│   │                  #   scaffolding, known-good examples)
│   └── hermes-config.template.yaml
└── scripts/           # statically re-runnable actions the skill
                       #   can invoke directly (verification
                       #   scripts, fixture generators,
                       #   deterministic probes)
    └── verify-schema.py
```

**Three support-file kinds, three directories.** When in doubt
which one to use, see the decision tree in §3.

**What about duplicate copies in side paths?** If the user already
has a `~/.local/share/<agent>/tools/<script>` that other tooling
relies on, sync it from the skill's `scripts/<script>` (skill is
source of truth, side path is convenience copy). Do **not** point
SKILL.md at the side path — point at `scripts/`. The user's
backup discipline should not depend on remembering to mirror.

## 2. Progressive disclosure (SKILL.md is a router, not a manual)

`SKILL.md` answers three questions and three only:

1. **When does this skill fire?** (description: triggers,
   conditions, signal words)
2. **What does it do at a high level?** (the workflow steps, the
   conventions, the API contract — things the agent needs in
   *every* invocation of the skill)
3. **Where do I go for detail?** (one-line pointers to
   `references/<topic>.md`, `templates/<name>`, `scripts/<name>`)

Everything else — per-topic schema, per-tool field tables, worked
examples, error transcripts, reproduction recipes, session-specific
quirks — lives in `references/` and is loaded on demand via
`skill_view(name, file_path='references/<topic>.md')`.

**Hard rules:**

- SKILL.md **>500 lines is a smell.** If you're tempted to write
  more, you're probably dumping reference material into the main
  file. Move it to `references/<topic>.md` and link it.
- One `references/` file per topic, not per session. A
  `references/2026-07-04-zcode.md` is wrong; `references/zcode.md`
  with a "verified on 2026-07-04" note is right. Knowledge is
  reusable; dates are not.
- `templates/` and `scripts/` are **not optional** for skills that
  produce or invoke artifacts. If your skill is a procedure
  ("to import X, do Y then Z"), at minimum write a `scripts/`
  helper for the part that is mechanical and re-runnable, and
  reference it from SKILL.md.
- When a section in SKILL.md duplicates content that already
  exists in a `references/` file, **delete it from SKILL.md** and
  replace with a one-line pointer. The duplication will rot — one
  copy will get updated, the other won't.

## 3. Decision tree: which directory does this content go in?

```
Is it something the agent runs verbatim?  (a verification probe,
a schema detector, a re-runnable migration)
    → scripts/<name>.py
    → invoke it from SKILL.md / references/ as `scripts/<name>.py`
    → user can also `python3 scripts/<name>.py` directly

Is it a starting file the user copies and then modifies?  (a
scaffold config, a boilerplate elisp, a known-good example)
    → templates/<name>.<ext>
    → SKILL.md says "copy templates/<name> to <target> and edit"

Is it detail the agent reads on demand?  (a schema table, an
error transcript, a per-topic deep-dive, a research note)
    → references/<topic>.md
    → SKILL.md says "see references/<topic>"

Does the agent need it on *every* invocation?  (the SessionDB
API, the four verify probes, the time-handling rule)
    → stays in SKILL.md

Is it a transient scratch (a one-off probe, a temporary fixture)?
    → does NOT belong in the skill. If the result is interesting,
      promote it to references/ or scripts/ before deleting.
```

## 4. Frontmatter and metadata

The YAML frontmatter at the top of `SKILL.md` is what the
agent uses to decide whether to load the skill. **Get it right.**

```yaml
---
name: skill-name         # kebab-case, matches directory name
description: "..."       # 1-3 sentences. First sentence = trigger
                         #   conditions (signal words the user
                         #   might say). Second = what it does.
                         #   Third (optional) = a key gotcha that
                         #   affects *when* to load it.
version: X.Y.Z           # bump on content change. patch = fix typo /
                         #   one pitfall. minor = new section / new
                         #   support file. major = restructure
                         #   (progressive-disclosure refactor,
                         #   breaking rename).
license: MIT
metadata:
  hermes:
    tags: [a, b, c]      # search-discoverable keywords
    related_skills: [sibling-skill-1, sibling-skill-2]
---
```

**Description anti-patterns:**

- ❌ "Useful for X" / "Helps with Y" / "A skill that does Z" —
  the trigger words are in the verbs, not the structure. Use
  "When the user says 'X', 'Y', or 'Z', or when [condition]..."
- ❌ Burying the trigger in a 4-sentence description. The agent
  reads only the first sentence most of the time.
- ❌ "Use this skill for any agent-related task." — that
  description matches every skill and none.

**Versioning:**

- Bump `patch` when you add a one-line pitfall or fix a typo.
- Bump `minor` when you add a new section, a new reference file,
  or a new script.
- Bump `major` when you do a progressive-disclosure refactor or
  break a name. (The user's first instinct on a `major` bump
  is to re-read SKILL.md.)

## 5. Pre-publish checklist

Before declaring a skill "done", verify all of these. A skill
that fails any one of them is not done, even if the technical
content is correct.

- [ ] **`SKILL.md` is under 500 lines.** If not, refactor into
      `references/` first.
- [ ] **Every runnable artifact lives in `scripts/` (or
      `templates/` for starters).** No paths to
      `~/.local/share/<agent>/tools/...` or other side
      locations.
- [ ] **No `references/` file duplicates content that lives in
      `SKILL.md`.** If a section repeats, delete the SKILL.md
      copy and link to the reference.
- [ ] **Description frontmatter fires on real trigger words.**
      Try 2-3 ways a user would phrase the task; if none match,
      rewrite the description.
- [ ] **Tested the scripts in `scripts/` from a fresh shell.**
      The `python3 scripts/<name>.py` invocation must work
      with no manual setup.
- [ ] **If the skill has an external dependency on
      `$HERMES_AGENT_PY` or similar, the script auto-discovers
      it.** Don't hardcode a nix-store hash that breaks the
      next time the user runs `nix-collect-garbage`.
- [ ] **Sibling skills cross-link via
      `metadata.hermes.related_skills`.** When a user finds one,
      they should discover the others.

## 6. Common violations (audit signals)

When auditing or refactoring existing skills, look for these —
each one is a fix-on-sight.

| Violation | Why it's wrong | Fix |
|-----------|---------------|-----|
| SKILL.md references `~/.local/share/.../tools/script.py` | Self-contained violation — backup is incomplete | Move script to `scripts/`, update all references |
| SKILL.md has a per-tool field table that lives 1:1 in `references/<topic>.md` | Duplication rot | Delete the SKILL.md copy, replace with one-line pointer |
| `references/2026-MM-DD-topic.md` (date in filename) | Session-ifies what should be reusable | Rename to `references/topic.md`, add a "verified on" note inside |
| `SKILL.md` is 1000+ lines | Not progressive disclosure | Identify topics, split into `references/<topic>.md` per topic, keep main file under 500 |
| Description frontmatter is generic ("Helps with coding tasks") | Won't fire on real triggers | Rewrite with concrete signal words the user would actually say |

## 7. clarify() options belong in `choices[]`, NEVER inside `question`

When using the `clarify` tool during skill design — for scope decisions,
naming, support-file layout, etc. — every selectable option goes into
the `choices` array, **never into the `question` text**.

**Why this matters.** The UI renders `choices` as selectable rows.
Options written into the `question` string render as dead prose the
user can read but cannot pick. The user has explicitly corrected this
mistake in past sessions ("你的提问又出问题了,再试一下") — treat it as
a known sharp edge of skill authoring, not a typo.

**Anti-pattern** (what NOT to do):

```python
clarify(
    question="Which scope? 1) minimal 2) extended 3) full",  # ← options in text
    choices=[]                                              # ← empty
)
```

**Correct pattern:**

```python
clarify(
    question="Which scope fits the new skill?",   # question text only
    choices=["minimal", "extended", "full"]       # every option as a row
)
```

If the user's reply indicates the options didn't render
("选项没显示出来" / "你的提问又出问题了"),re-issue with `choices[]`
populated and the question string stripped of option lists.

## 8. Verification evidence lives in the same turn as the change

When `scripts/<name>.py` (or any runnable artifact) is added or
modified, the same turn that publishes the change **must also produce
passing verification evidence**. A summary of "ran it, looks good"
without fixtures and an explicit pass/fail tally is not enough.

**Minimum bar for ad-hoc verification of a new/changed script:**

1. Create N fixtures under `/tmp/` with the `hermes-verify-` prefix
   (`tempfile.mkstemp(prefix="hermes-verify-")` is the OS-safe path).
2. Cover: happy path, every distinct error category, edge cases
   (empty / comment-only / missing input), CLI flags that change
   behavior.
3. Print a `PASS/FAIL` tally per check and a final `<passed>/<total>`
   count.
4. Clean up fixtures (`os.unlink` each one) before exiting.
5. State the scope explicitly as "ad-hoc verification — not a test
   suite" so the user knows what kind of evidence they're reading.

A change without verification in the same turn will be re-prompted by
the runtime — bake the verification into the skill-creation workflow.

## Out of scope

- **Which skills to install/curate** is the job of
  `hermes-skill-curation` (lifecycle: add/remove/archive/audit).
  This skill is about how to *author* one.
- **Migrating prompts from other agents** is the job of
  `importing-agent-prompts`. The output of that workflow is a
  skill, but the workflow itself is separate.
- **Discovering what skills exist** is `find-skills`.

## References

- `agent-session-import` — worked example of all three principles
  applied at scale: SKILL.md is a thin router, `references/pi.md`
  and `references/zcode.md` hold the agent-specific detail, and
  `scripts/import-pi-to-hermes.py` and
  `scripts/import-zcode-to-hermes.py` are the runnable
  artifacts. Use it as the reference implementation when you're
  refactoring an existing skill or writing a new one.
