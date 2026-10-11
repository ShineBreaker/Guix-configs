---
name: verify-harness-maintenance
description: "修复或评估无头验证 harness（质量判定、场景运行、加固）。触发：verify 套件坏了或结果可疑 / 搭无头验证环境 / 判断 harness 是否可信——任一出现即调用。"
version: 1.0.0
metadata:
  hermes:
    tags: [verify-harness, testing, headless, qml, parallel-agents, log-triage]
    related_skills: [quicksshell-qml-development, nosdshell-dev, monitoring-script-debugging, task-contract]
---

# Verify Harness Maintenance

## When to use

- A verify script (`Scripts/test/verify.sh`, scene runners, seeded-config harnesses) needs a scene added, a seed key fixed, or a snapshot taken.
- A verify run shows a defect and you must decide whether it belongs to the **harness**, the **product code**, or a **parallel agent's in-flight rewrite**.
- Someone hands you a brief listing scenes, noise entries, or acceptance items that may not match the repo's current script.

Companion to `quickshell-qml-development` (shell authoring/debug) and `nosdshell-dev` (nosDshell repo specifics). This skill owns the **harness** side and the **verdict discipline**.

## Always-on

1. **The scene list is the script's, not the brief's.** Before running anything, derive the scene set from `SCENES_ORDER` (or the script's own header) and compare against the brief. A scene absent from the script is absent, full stop — unless the brief names a fallback. Record every divergence in the report instead of silently substituting.
2. **Parallel writers own product files; you own your harness.** Never edit QML, plugins, or product source another agent is rewriting, even when a verify run names a line in them. Describe it for routing.
3. **A verify-harness change is yours to commit** when the user says so; product defects are not. Stage your exact paths only (`git add -- <paths>`), then `git diff --cached --stat`.
4. **Never delete a scene list entry without its case branch and header comment.** Three places carry the list (`SCENES_ORDER`, the `run_scene()` `case`, the header docs); fixing one and not the others leaves the harness inconsistent in a way later runs cannot see.
5. **A scene whose body toggles state is not a baseline.** Harnesses routinely write `call X toggle; shot; call X toggle` — that frame is a *post-toggle* state, and the toggle can tear down surfaces unrelated to the key you are testing (a dock toggle can take the wallpaper with it). For A/B comparisons use a scene that does not mutate persisted state, and derive baseline and variants from that scene in the same snapshot.
6. **A run with no usable PNG is a failed run, not evidence.** Check each PNG's byte size against its expected magnitude *before* reading it — a near-empty file means the shell never rendered, and reading it as a result manufactures a false verdict. Re-run that class.
7. **Recon the repo's own test tooling before writing a harness of your own.** `ls Scripts/test/`, `Scripts/dev/`, and every subdir of them (a `niri/`, `sway/`, or scene-runner dir is cheap to open and often lands mid-session). A harness the repo already ships carries the per-quirk config this shell needs — compositor flags, binary resolution, frame landing, stop semantics — that ad-hoc work re-learns the slow way, and it is maintained when the shell changes while yours is not.

## Procedure

1. **Recon the harness before quoting it.** `grep -n "SCENES_ORDER="`, `grep -n "<scene>)"`, `grep -n SEED=`. Scripts get renamed and scenes get added underneath you between sessions; quote the file, not memory.
2. **Seed the conditions each scene needs, then prove the seed landed in the written artifact.** Read the run's config output (`settings.json`) and diff the seeded keys against the on-disk values. A log line saying the render ran proves the shell started, not that the seed was read.
3. **Run scenes, then triage the log before looking at a single PNG.** Log first tells you what failed; pixels only tell you what to look at.
4. **Read the harness's own error-summary tail first** (`=== error summary ===` / `total matching lines`). It is already the high-signum slice. Widen to full-log greps only for classes it misses.
5. **Classify every log hit** as product defect, environment noise, or transient, and write the attribution down. "It looked broken, then looked fine" is not a verdict.
6. **Look at the actual PNGs** for every scene in the report's scope. A `saved X.png` line proves `grim` ran.
7. **Quantify every A/B diff you report.** A screenshot pair is one opinion; report the numbers — changed-pixel percentage, the changed bounding box, and the seed-key-relevant region. Byte-size comparison alone cannot separate "one row moved" from "entire shell redrawn"; a full-frame bbox means the comparison frame differed (post-toggle state, different scene, or a failed run), not that the key is dead.
8. **Write the report to the path the brief names**, then re-run any class that failed before calling it done.
9. **Cross-check every "dead key" verdict against a static grep.** A screenshot proves nothing reachable changed when the seed was written; it does not prove no consumer exists. Grep for the key in these forms before declaring it dead: direct (`data.<key>`), optional chain (`data?.sec?.key`), section capture (`const n = Settings.data.<sec>` then `n.key` / `n?.key` / `n["key"]`), destructure (`const {a} = Settings.data.<sec>`), and the singleton-function indirection (`getEffective<Thing>()` in a controller that rewrites the value). A key routed through a getter is alive everywhere the getter is called and dead at none of those call sites.

**For pixel math on Guix, resolve the interpreter explicitly.** `guix shell <py-pkg> -- python3` keeps the invoking user's `python3` first on PATH, so the import silently fails with a module error that looks like the tool is broken. Run the shell's own interpreter with the profile's site-packages, e.g. `guix shell python-numpy python-pillow -- sh -c 'PYTHONPATH="$GUIX_ENVIRONMENT/lib/python3.12/site-packages" python3 script.py'`. Verify the import in one throwaway call before building the comparison.

## Seed/runtime version lockstep

A seeded settings file is only as valid as the version the shell expects:

- **A seed version behind the runtime version triggers the migration chain**, which rewrites the seed's keys back to defaults before the run starts. The seed then appears to be ignored, and the screenshots show default state while the log shows nothing wrong.
- **Find the runtime version in the code** (`readonly property int settingsVersion` or equivalent), not in the defaults file — the defaults file often carries a skeleton value (`0`).
- **Prove lockstep from the written artifact**, not from the log: read `settings.json` after the run and check the seed's keys survived. If they did not, the seed version is the first suspect.
- When the seed's version must track runtime, put the rule in a comment next to the literal so the next reader knows the coupling instead of re-deriving it.

**Resolve seed paths against the harness's cwd, not yours.** Inner harness scripts commonly `cd` into an isolated work dir before parsing `--settings`, so a relative path resolves against that dir and fails. A seed-parse failure inside a `set -uo pipefail` script (no `-e`) does **not** abort the run — the write is skipped and the shell boots fresh. Pass an absolute path every time.

**A seed that never lands surfaces as a first-run state.** The tell is in the log, not the pixels: you get the fresh-install line (`Fresh install detected, skipping migrations`) where you expected the version line (`adapter.settingsVersion: N` plus `Migrating ...`). On the pixel side it looks like wizards, a dock-less desktop, or every variant rendering identically — all of which read as product behaviour and are actually harness failure.

**A seed value that reaches the shell can still be overwritten before the shot.** A migration, an upgrade pass, or a debounced save that round-trips the whole adapter can rewrite a seeded key back to its default. Verify from the artifact the run actually consumed, and re-read it after the run rather than trusting the seed file you handed in.

**A key the runtime never reads can still move the UI through a migration.** A legacy field whose consumer is gone is the classic negative control — but if a versioned migration copies legacy fields onto live ones (old auto-hide enum → new hide-mode field, old position → new position), seeding the legacy field *does* change the render. The control then looks dead and is not. Before using a legacy field as a negative control, read the migration that owns the boundary version and check whether it copies that field onto a live key — then **evaluate that migration's guard against the seed you actually wrote.** A migration guarded by `legacy !== undefined && live === undefined` never fires when your seed (or the harness's built-in seed) already carries the live key, so reading only the body attributes a diff to code that never ran. When the guard is false, drop the migration explanation and record the cause as unknown rather than inventing a plausible one.

Classify the result, and make the report say which class each key is in:

| Class | Meaning | Evidence needed |
|---|---|---|
| truly dead | zero read sites anywhere, zero migration input | grep of all forms + migration read |
| indirectly alive | read only via a getter/controller; getter may force a constant in some modes | read-through analysis of the getter, per mode |
| transitively alive | not read at runtime, but copied by a migration onto a live key | migration body |
| path-limited | read only by a component that does not render in this configuration | grep + component's render condition |

A single "dead keys" bucket mixes classes and misleads: a key dead in one mode and path-limited in another needs both stated, along with which mode was seeded. A component never rendered in the seeded mode is unexercised, not dead.

## Re-verifying after a change

When a task lands (your own or another agent's) and you are asked for a regression pass:

1. **Take the snapshot hash and the tree state first** (`git log --oneline -1`, dirty-file count), and record them in the report. Pixel numbers from before the change are only comparable to a run taken against the same tree.
2. **Rebuild the baseline in this session; never reuse the earlier one.** Same scene, same settings-root, same snapshot window as the variants.
3. **Reconcile the two scene sets.** The upstream change may have added, renamed, or dropped scenes; re-derive the scene list from the script and note which of the brief's items no longer exist.
4. **Re-run the same seeds with absolute paths** and compare each to its recorded expectation. Report the numbers, not a pass/fail word: a matching `changed %`/`npix`/`bbox` is evidence, a bare "works" is not.
5. **State a retraction in full when the change invalidates a prior verdict.** If an earlier report attributed a diff to the wrong cause, fix the original sentence in place rather than appending a correction below it — two statements of the same fact in one report is how the wrong one survives. Mark the superseded number explicitly as untrusted.

## Harness symptom vs. product defect

The failure mode that costs the most credibility is reporting a harness problem as a product problem:

1. **Reproduce under a corrected harness first.** If fixing the seed, the fixture, or the scene makes the symptom disappear, the symptom belonged to the harness. Say so in the report and mark the product verdict revised.
2. **A first-run state is not a product state.** Wizards, popups, telemetry notices, and changelog dialogs that a seed is supposed to suppress are harness evidence when they appear: the seed failed or the suppression key moved.
3. **When the harness cannot be fixed** (another agent owns the file), the right output is a description for routing — symptom, repro scene, file and line — not a verdict against product code you cannot change.
4. **Keep the verdict section honest about what is still unverified.** A scene not run, a tab missing from the script, a state gated behind a parallel rewrite: name each one. The report is evidence for someone else's decision.

## Reporting a product defect you may not fix

Write these five things and stop: location (file and line), symptom, repro (the scene or command), scope (which combinations fire it), and **what you did verify** so the next session does not repeat the work. If a log error count is read from a partial log (run still in flight), say the count is a time slice, and re-read the full log before reporting the final number.

## Pitfalls

- **A hedge written as "unverified" inside a verdict paragraph is read as "verified".** Put the hedge in a flagged row that states what is unproven, not inside a sentence that also claims success.
- **Visual colour is not evidence of a code path.** When a fallback renders and the intended path errors, the screenshot proves the fallback works. Attribute the visible pixel to the path that actually ran, not the path you expected.
- **Reading the log while the run is in flight yields a slice, not a total.** Re-grep the finished log before reporting counts.
- **A scene absent from the script is absent, not "unverified".** Say "not in SCENES_ORDER" rather than leaving the reader to guess whether it ran.
- **A default output root is a shared workspace.** When parallel agents share the harness's default root and it is wiped per run, a snapshot you took earlier in the session can be gone by the time you compare against it. Pin a per-task root or unique run names, and take baseline and variants inside one snapshot window.
- **An expectation from an earlier snapshot is not a control for this one.** On a regression re-run, rebuild the baseline against the current tree in the same window and compare there; a number carried over from a different commit state is only comparable if the tree demonstrably did not change. When the prior evidence has been overwritten and cannot be re-read, mark that number untrusted in the report instead of restating it beside the fresh result.
- **Accept a refactored settings surface by its search index, not by its look.** After a settings rework, query the rebuilt index by the **rendered label in every shipped language** (resolve `labelKey`/`descriptionKey` through the translation files) — a key-based or single-language query hides untranslated gaps and false positives. Check three things: entries land on the new page/tab id rather than removed pages; each new control is reachable by the noun a user would type for it (the dock "Size" control is unfindable by "icon size"); and a query whose hits are all legacy/compat entries is a gap even when the hit count is non-zero, because it routes the user onto inert controls.
- **Parallel writers cause nil-yield runs, not wrong-looking ones.** A run taken while another agent is mid-write fails at load (`Expected token '}'`) and produces zero PNGs; a run that loses a DBus race may produce a desktop with no shell at all. Neither is a product verdict — re-run the class and confirm the snapshot before attributing anything.
- **An identical-looking pair across every variant means the comparison never ran.** When all variants match the baseline byte-for-byte, suspect the seed path or the scene body before concluding every key is dead; a dead-key verdict costs the same work to produce as a good one, so spend it once, correctly.
- **A state reachable only through an interaction the harness cannot inject is a harness limitation, not a verdict.** When a feature's visible state needs a pointer click, a specific selection, or a mid-session IPC that the scene list does not exercise, the run neither proves nor disproves the key. Report it as unverifiable with the missing trigger named — never as "no effect".
- **An unexecutable control is not a dead control.** When an injected IPC returns only a function signature (or nothing) and the artifact shows unchanged keys and an identical before/after frame, the injection never ran. Say the write path is unverified; do not upgrade an unexecuted command into evidence that the target key is inert.
- **Reverse signals in the command line are real.** When the user stops a line of work, it ends: no re-litigating the stopped item, and no expanding the task after the stop.
- **Check the scene body, not just the scene name, against the brief's requested frames.** A brief that asks for the animation period (`0.5 s / 1 s / 3 s / 6 s`) is asking the scene to take a burst; a scene whose body is `call settings open 2; shot settings` takes one terminal-state frame and silently fails that requirement. Record the divergence in the report with whatever the probe log can supply instead, and flag the missing frames — do not let "the scene exists" read as "the requirement is covered".
- **Aggregate probe output per key across the batch before calling a layout stable.** Injected layout probes (`<Name>Probe <key> h= <n>`) are per-re-layout timestamps. The same key reporting `h= 646` then `h= 13` then `h= 56` inside one run is a layout thrashing between real content, its load placeholder, and a collapsed height — a defect invisible in every terminal-state screenshot, because re-snap machinery (`_snapTo`, quiet timers, pending-snap flags) repairs the final frame. Level-to-level jumps are the finding: they mean the container's height is bound to something still loading, and the harness's own compensating machinery is the corroboration.
- **A path a steering file names is a pointer to read now, not background.** When a repo's AGENTS.md says real-compositor runs go through `Scripts/test/niri/`, that directory is the tool this task needs; treating the mention as far-future context and building an equivalent from scratch costs hours and produces a harness the repo will never maintain. Same rule for any path a steering file names as *the* way to do a class of work — go open it and judge its maturity before deciding it does not apply.
- **A commit landing mid-session can turn your harness into a duplicate.** Re-check the repo's test tooling right before you finalize a report, not only at the start; if the repo has since gained the harness you built ad hoc, keep your verification results (same tree, same binaries) but redirect future runs to the repo's tool and say so in the report.
