---
name: skill-authoring
description: "How to author a Hermes Agent skill the right way. Covers the two non-negotiable structural principles — **self-contained** (all runnable artifacts ship inside the skill directory; backup = usable) and **progressive disclosure** (SKILL.md is a thin router; details live under `references/`, `templates/`, `scripts/`) — the directory layout, file-type rules, decision trees, **which of the 12 existing categories a new skill belongs to (never top-level `<skill-name>/`)**, and a pre-publish checklist. Triggers: writing a new skill, refactoring an existing one's structure, wondering 'should this go in SKILL.md vs references()' / 'which category fits', preparing for backup/share, noticing a self-contained or progressive-disclosure violation, the user complaining 'too verbose' / 'in the wrong place', or **discovering a real use case the skill doesn't cover** — patch the skill (§6 last row) instead of inventing a workaround."
version: 1.6.1
license: MIT
metadata:
  hermes:
    tags:
      [
        skill-design,
        self-contained,
        progressive-disclosure,
        references,
        scripts,
        structure,
      ]
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
   _every_ invocation of the skill)
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
name: skill-name # kebab-case, matches directory name
description:
  "..." # 1-3 sentences. First sentence = trigger
  #   conditions (signal words the user
  #   might say). Second = what it does.
  #   Third (optional) = a key gotcha that
  #   affects *when* to load it.
version:
  X.Y.Z # bump on content change. patch = fix typo /
  #   one pitfall. minor = new section / new
  #   support file. major = restructure
  #   (progressive-disclosure refactor,
  #   breaking rename).
license: MIT
metadata:
  hermes:
    tags: [a, b, c] # search-discoverable keywords
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
- [ ] **If the script has a yaml/json/toml config dispatcher
      (e.g. `CHECKS = [(name, key, fn), ...]` reading from a
      config file), add a parity-check step that catches
      silent key drift.** See §10 for the pattern — without
      this, every config-driven check runs on empty cfg and
      emits GREEN by luck.
- [ ] **If the script parses external output (`--help`, MCP tool
      listing, OpenAPI schema) as ground truth, see §11.** Three
      silent traps: CJK help text in column 2, 1:N CLI→MCP
      fanning, and `help` meta-command counting. Any one of these
      will produce a verify that runs cleanly but reports the wrong
      expected value.
- [ ] **No `read_text()[:N]` + `write_text()` patterns in the
      workflow.** Any helper that "opens a file to change one
      field" must read the **whole** file, transform, then write
      the whole file back — and the post-write byte count must
      match the pre-write count (or the delta must be exactly
      the field-change size). See §6 (file-edit safety row) for
      why.

## 6. Common violations (audit signals)

When auditing or refactoring existing skills, look for these —
each one is a fix-on-sight.

| Violation                                                                     | Why it's wrong                                                                  | Fix                                                                                                                          |
| ----------------------------------------------------------------------------- | ------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| SKILL.md references `~/.local/share/.../tools/script.py`                      | Self-contained violation — backup is incomplete                                 | Move script to `scripts/`, update all references                                                                             |
| SKILL.md has a per-tool field table that lives 1:1 in `references/<topic>.md` | Duplication rot                                                                 | Delete the SKILL.md copy, replace with one-line pointer                                                                      |
| `references/2026-MM-DD-topic.md` (date in filename)                           | Session-ifies what should be reusable                                           | Rename to `references/topic.md`, add a "verified on" note inside                                                             |
| `SKILL.md` is 1000+ lines                                                     | Not progressive disclosure                                                      | Identify topics, split into `references/<topic>.md` per topic, keep main file under 500                                      |
| Description frontmatter is generic ("Helps with coding tasks")                | Won't fire on real triggers                                                     | Rewrite with concrete signal words the user would actually say                                                               |
| CHECKS tuples use different key names than the yaml sections they read        | Silent empty-cfg dispatcher — every check runs on defaults                      | Add parity check; align keys; see §10                                                                                        |
| `read_text()[:N]` + `write_text()` to "modify a single field"                 | Silently truncates files larger than the slice — wipes bodies of large SKILL.md | Use `patch()` for single-field edits; if doing read-modify-write, read the whole file and verify byte count before vs. after |
| Skill doesn't cover a real use case → agent invents a "bridge" / "wrapping layer" / "post-process step" **instead of patching the skill** | The skill accretes assumptions it can't enforce; every future session reinvents the bridge from scratch; the bridge isn't in the skill's references so it disappears from backups. **The user explicitly granted permission to patch skill files in the 2026-07-16 session ("请尽情修改")**, so the assumption "I can't touch the skill" is wrong. | Stop the workflow. Open `references/` or SKILL.md. Add the missing case as a new section, example, or pitfall. If the bridge has reusable parts (a scripts/ helper, a verified recipe), put them in the skill directory. Doing the workaround in the calling script is fine for one-off; **documenting the workaround *as the canonical path* in the calling code is what creates the debt.** |

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

### 8.1 Verify-script anti-patterns (pitfalls found in real sessions)

- **Same-second filename overwrite.** When the script-under-test
  writes timestamped files (`%Y%m%d-%H%M%S`) into a directory and
  retains N of them, two runs in the same second overwrite each
  other — silently. Use ms precision (`%Y%m%d-%H%M%S-%f` and slice
  to 3 digits) or include a counter. Verify the retention actually
  produces N distinct files, not just "N writes happened."
- **Verify script forgot to clean up → blocks next session.** Always
  wrap fixtures in `try/finally` with `shutil.rmtree(work,
ignore_errors=True)`. The verify script itself is a fixture and
  should be removed after the run; otherwise it lies around in
  `/tmp/hermes-verify-*.py` and the next session has to rediscover
  and decide whether it's current.
- **Ad-hoc verify ≠ suite green.** Print the scope line ("ad-hoc
  verification — not a test suite") at the bottom of every verify
  run. The user needs to know the difference between "9/9 PASS on
  curated fixtures" and "the test suite passes." Conflating the two
  trains the user to over-trust the verify.
- **Verify script edited after deletion = stale.** If the runtime
  re-prompts "no fresh verification evidence" and you re-write the
  verify script, that IS the new verification — say so, don't claim
  the previous run still covers the new edit.
- **Reproduce the bug, then assert it's gone.** When patching a
  known bug (e.g. cron ticker parser), the verify script must (a)
  reproduce the broken behavior in a separate fixture and (b)
  assert the patched behavior on the fixed fixture. Otherwise you
  have a "fix" with no proof it fixes anything.
- **The verify script itself is code — and it can be wrong.** When
  the first verify run produces a FAIL, do not assume "the script
  is right and the new code is wrong." Iterate: 5/7 → fix verify
  parser → 6/7 → fix another verify assumption → 7/7. A FAIL on a
  freshly written verify script is **often** a verify-side bug
  (wrong regex, wrong expected value, ground-truth construction
  flaw) — not necessarily a target-script bug. Three FAILs in a row
  with the same root cause (e.g. wrong expected value) means stop
  and re-read the verify script, not the target. This was the actual
  pattern in the doc-check.py / doc-engineering rollout: 5/7 → 6/7
  → 7/7 across three iterations, all in the verify layer.
- **Ground-truth construction must be explicit and inline.** When
  the verify script derives "what is correct" from another tool's
  output (e.g. parsing `agenote --help` to build the list of CLI
  subcommands), do not import a shared helper. Inline the parser
  so the failure mode is visible in the verify output. Otherwise
  the verify silently uses a broken ground-truth and produces
  wrong-but-internally-consistent FAILs.

### 8.2 Representative-sample-then-batch (one-skill-at-a-time)

For multi-skill or multi-feature work, follow the user's explicit
preference: **do one representative skill end-to-end before
batch-expanding**. This mirrors the session_search migration pattern
("先试着迁 1 个中等 session 做端到端验证，过了再说"):

1. Build the first skill end-to-end (SKILL.md + scripts/ +
   references/ + config file).
2. Run its ad-hoc verify, capture PASS/FAIL tally.
3. Estimate: time-per-skill, total-disk-for-N, side-effects on
   skill_index / session_search / memory.
4. Report "已验证 X, 待你决定是否放量" — let the user decide whether
   to scale up. Don't auto-batch.

Going straight to "build all N skills, then verify" means the user
can't intervene mid-stream if your design pattern is wrong, and you
have to throw away more work.

## 9. Categorization (which existing category does this skill belong to?)

`~/.local/share/hermes/skills/` is organized as **`<category>/<skill-name>/SKILL.md`** —
the top level holds categories, not skills. **Never** create a
top-level `<skill-name>/` directory; that is the bug that created 31
"pseudo-categories" with one skill each in the 2026-07-05 cleanup.

**Hard rule:** before creating a new category, prove every existing
one cannot host the skill. The 12 current categories (as of
2026-07-05) are:

| Category                | Hosts skills about…                                                                                                                 | Example sub-skills                                                                                          |
| ----------------------- | ----------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| `autonomous-ai-agents/` | Spawning / orchestrating sub-agents, importing external-agent histories                                                             | `worker-handoff`, `agent-session-import`, `claude-code`                                                     |
| `creative/`             | Creative content generation — design, video, music                                                                                  | `architecture-diagram`, `sketch`, `songwriting-and-ai-music`                                                |
| `desktop/`              | Desktop-environment troubleshooting (IME, Wayland, GUI env)                                                                         | `electron-wayland-ime`                                                                                      |
| `devtools/`             | Generic dev tools — repo recon, code review, debugging specific toolchains, exploratory QA                                          | `codebase-scout`, `code-reviewer`, `dogfood`, `emacs-config-debugging`                                      |
| `education/`            | Coursework, explainer videos, learning material                                                                                     | `academic-coursework-cn`, `elisp-explainer-video`                                                           |
| `guix-configs/`         | Workflows specific to this user's Guix-configs deployment (`~/Projects/Config/Guix-configs/`) and the personal `jeans` Guix channel | `guix-configs-workflow`, `jeans-channel-workflow`                                                           |
| `hermes-agent-ops/`     | Operating Hermes Agent itself — skill authoring, memory routing, prompt migration, library curation                                 | `skill-authoring` (this skill), `hermes-memory-routing`, `importing-agent-prompts`, `hermes-skill-curation` |
| `media/`                | Media content — transcripts, GIFs, music gen, audio viz                                                                             | `youtube-content`, `gif-search`, `heartmula`, `songsee`                                                     |
| `mlops/`                | ML/AI Ops — training, fine-tuning, serving, eval                                                                                    | (currently empty placeholder — bundled seeds here)                                                          |
| `planning/`             | Strategic planning, architecture advisory, task breakdown                                                                           | `architecture-advisor`, `task-planner`                                                                      |
| `productivity/`         | Documents, presentations, spreadsheets, discovery                                                                                   | `powerpoint`, `nano-pdf`, `ocr-and-documents`, `unknown-discovery`                                          |
| `research/`             | Research workflows — doc discovery, literature review, doc lint                                                                     | `doc-researcher`, `single-source-doc-lint`                                                                  |

**Decision tree for placement:**

1. **Does the skill act on the user's own Guix-configs repo or the
   personal jeans Guix channel?** → `guix-configs/`
2. **Does the skill configure / operate / debug Hermes Agent itself?**
   → `hermes-agent-ops/`
3. **Does the skill spawn, orchestrate, import from, or hand off to
   other AI agents / CLIs?** → `autonomous-ai-agents/`
4. **Does the skill help plan a project (architecture review, task
   breakdown, feasibility assessment)?** → `planning/`
5. **Does the skill produce or inspect documents / presentations /
   spreadsheets?** → `productivity/`
6. **Does the skill investigate, lint, or curate external knowledge
   (docs, papers, web)?** → `research/`
7. **Does the skill generate creative content (design, video, music,
   ASCII art)?** → `creative/`
8. **Does the skill work with media (transcripts, audio, video files)?**
   → `media/`
9. **Does the skill teach or produce educational material?** → `education/`
10. **Does the skill troubleshoot a desktop / GUI / IME issue?** → `desktop/`
11. **Is the skill a generic dev tool — repo recon, code review,
    debugging a specific toolchain, exploratory QA?** → `devtools/`
12. **Is the skill about training / serving / evaluating ML models?**
    → `mlops/`

If **none** of the 12 fit, _stop and ask the user_. Do not invent a
new category on your own. The user has stated this explicitly
("必须在当前分类中完全没有合理的文件夹可存放时再创建新分类文件夹").

**Scope guard:** this categorization rule applies **only** to
`~/.local/share/hermes/skills/`. The directory
`~/.config/agents/skills/` is a separate Guix Home immutable
deployment and must NOT be touched when reorganizing hermes skills.

**Anti-pattern: top-level `<skill-name>/`.** Creating `skills/<x>/SKILL.md`
directly at the top of the skills tree is the same bug as the
pre-cleanup state — it makes every skill look like its own category.
Always: `skills/<category>/<x>/SKILL.md`.

**Category-table drift hazard.** The 12-category table above is a
snapshot from 2026-07-05; it goes stale the moment a category is
added, renamed, merged, or removed by a future session using
`hermes-skill-curation`. When the snapshot and reality disagree:

- **Re-derive the actual category list** by reading
  `find ~/.local/share/hermes/skills/ -mindepth 1 -maxdepth 1 -type d`
  (the directory listing IS the source of truth — DESCRIPTION.md
  frontmatter is descriptive metadata, not the authority).
- **If reality shows a category not in the table** → extend the
  table inline in this skill (§9), bump version `minor`. Do not
  silently route the skill to the nearest table row.
- **If reality is missing a category the table lists** → remove
  the row, bump version `minor`. A row referring to a non-existent
  directory is worse than no row.
- **If the user is mid-reorganize and the table is out of date** →
  trust `hermes-skill-curation` (which sees the live filesystem)
  over this table. The curation skill owns the truth at that moment.

The companion `hermes-skill-curation` skill (§2.5 Reorganize
protocol) is the right place to perform category additions or
merges — this skill only routes placement decisions for _new_
skills, it does not own the categorization tree itself.

## 10. Config dispatcher naming contract (yaml/json/toml)

**Pattern.** A script that runs N checks against a config file
typically looks like:

```python
CHECKS = [
    ("1", "inject", check_inject),
    ("2", "skill_count", check_skill_count),
    ...
]
for num, key, fn in CHECKS:
    cfg = thresholds.get(key, {})
    status, detail = fn(cfg)
```

The string `key` is a **silent contract** between the script and
the config file. If the config file's section is named differently
(`inject:` in yaml vs. `key="inject"` in CHECKS tuple), the check
runs on `cfg = {}` and silently falls back to function defaults.

**This is silent.** No exception, no warning, no log line. The
check emits GREEN if the default happens to match env state, or RED
with garbage detail if it doesn't. **Both look like normal output.**

**Real-world hit.** The first version of `agent-config-metabolism`
shipped with 9 such mismatches across 14 checks — half the audit
was running on defaults, not thresholds. The bug was only caught
because a verify-script assertion probed one specific check
(`json_parseable` → "json") and surfaced the mismatch by
construction.

**Mitigation pattern.** If the skill ships a config dispatcher:

1. Pick ONE side as canonical (the side users edit less often).
   For tunable thresholds, yaml is canonical because users tune
   thresholds. For tool-name → handler mappings, code is canonical.
2. After editing either side, run a parity check. Add it as a
   `Verification` step in SKILL.md so future edits catch drift:

```bash
python3 -c "
import re, sys
src = open('scripts/<name>.py').read()
# adjust the regex to match your CHECKS tuple shape
check_keys = set(re.findall(r'^\s*\(\"(\d+)\",\s*\"([a-z_]+)\",\s*\w+\),', src, re.M))
config_keys = set()
for line in open('scripts/<config>.yaml'):
    m = re.match(r'^([a-z_]+):\s*\$', line)
    if m and not line.startswith(' '): config_keys.add(m.group(1))
config_keys -= {'output'}  # config-only sections, not dispatcher keys
missing = check_keys - config_keys
print('CHECKS not in config:', missing or '(none)')
sys.exit(1 if missing else 0)
"
```

3. **Bonus**: at script load time, log a warning if any CHECKS key
   has no matching config section. Doesn't replace the parity
   check (which catches orphans the other way too) but surfaces
   drift loudly.

This is the dispatcher-naming equivalent of the YAML key vs.
function name contract — it's worth its own checklist item because
**no error tells you when it's broken**. The only signal is "the
script looks healthy but every red/green is on defaults."

## 11. External-output parser traps (CLI help / MCP tool lists / API responses)

Scripts that derive their "ground truth" from another tool's
output (`--help`, MCP tool listing, OpenAPI schema, JSONL log)
face three quiet failure modes that §10 doesn't cover.

**Trap A — Chinese / non-ASCII help text.** When `<tool> --help`
output is in CJK, a parser like `awk '/^  [a-z]/{print $2}'`
silently picks up the **description column**, not the **command
name column**, because the next field after `add` is `添加经验卡片`.
Two distinct bugs result:

1. `$2` returns `添加经验卡片` instead of `add` (the wrong token).
2. Even with `LC_ALL=C`, the `[a-z]` regex matches only the ASCII
   command name — but `$2` still grabs the CJK description.

**Fix.** Take `$1`, not `$2`, when the first column is the
identifier you want. Anchor the regex on the _column_ you care
about, not the line shape. Verify the parser's first match by
hand-printing it before trusting it.

**Trap B — 1:N mapping between CLI subcommands and MCP/API tools.**
A single CLI subcommand often fans out into multiple server-side
tools (`agenote memory` ↔ `agenote_memory_add` /
`agenote_memory_get` / `agenote_memory_overview` /
`agenote_memory_search`). A verify script that checks
"doc lists N MCP tools, CLI has N subcommands" will report a false
"unknown" mismatch for every fanned-out tool unless the verify
script knows the expansion map.

**Fix.** Either:

- Maintain an explicit expansion table in the target script (e.g.
  `KNOWN_MULTI_TOOL_SUBCOMMANDS = {"memory": [...]}`) and expose it
  as a module-level symbol so verifiers can import it; **or**
- Have the verify script own the expansion table and re-state it
  inline (DRY violation but each side stays self-contained).

Pick one side as canonical (the side users edit less often). For
ground-truth tool lists, **the server is canonical**; for tunable
thresholds, the user's config file is canonical.

**Trap C — version counting.** Some `help` outputs include a meta
command (`help`) that distorts "how many subcommands does this
tool have" checks. The verify script must either subtract `help`
or include it — and declare which.

**These three traps** all share a symptom: the verify script's
expected value silently drifts from reality. The doc-check.py /
doc-engineering rollout hit all three in one cycle:

- Trap A: `awk '$2'` parsed `add       添加经验卡片` → `添加经验卡片`
  (caught when the verify reported 24 "unknown" tools, all CJK).
- Trap B: 4 `agenote_memory_*` MCP tools were unmatched against
  the 28-CLI ground truth (caught when verify reported those 4 as
  unknown).
- Trap C: counting 28 vs 29 depending on whether `help` is
  subtracted (caught when verify expected `actual: 28` and got
  `actual: 29`).

When all three fire in the same script, the agent runs
`5/7 → 6/7 → 7/7` across three iterations, each time fixing
one verify-side assumption. See §8.1's "verify script itself is
code — and it can be wrong" pitfall for the iteration pattern.

## Out of scope

- **Which skills to install/curate** is the job of
  `hermes-skill-curation` (lifecycle: add/remove/archive/audit).
  This skill is about how to _author_ one.
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
- `hermes-skill-curation` §2.5 (Reorganize protocol) — the
  counterpart that owns the categorization tree itself.
  `skill-authoring` only routes _placement decisions for new
  skills_; if a category needs to be added, renamed, merged, or
  removed, that's the curation skill's job. See §9's drift-hazard
  notes for what to do when the two skills' category views disagree.
