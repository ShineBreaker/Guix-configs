---
name: verify-harness-maintenance
description: "Use when fixing or judging a headless verify harness."
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

## Procedure

1. **Recon the harness before quoting it.** `grep -n "SCENES_ORDER="`, `grep -n "<scene>)"`, `grep -n SEED=`. Scripts get renamed and scenes get added underneath you between sessions; quote the file, not memory.
2. **Seed the conditions each scene needs, then prove the seed landed in the written artifact.** Read the run's config output (`settings.json`) and diff the seeded keys against the on-disk values. A log line saying the render ran proves the shell started, not that the seed was read.
3. **Run scenes, then triage the log before looking at a single PNG.** Log first tells you what failed; pixels only tell you what to look at.
4. **Read the harness's own error-summary tail first** (`=== error summary ===` / `total matching lines`). It is already the high-signum slice. Widen to full-log greps only for classes it misses.
5. **Classify every log hit** as product defect, environment noise, or transient, and write the attribution down. "It looked broken, then looked fine" is not a verdict.
6. **Look at the actual PNGs** for every scene in the report's scope. A `saved X.png` line proves `grim` ran.
7. **Write the report to the path the brief names**, then re-run any class that failed before calling it done.

## Seed/runtime version lockstep

A seeded settings file is only as valid as the version the shell expects:

- **A seed version behind the runtime version triggers the migration chain**, which rewrites the seed's keys back to defaults before the run starts. The seed then appears to be ignored, and the screenshots show default state while the log shows nothing wrong.
- **Find the runtime version in the code** (`readonly property int settingsVersion` or equivalent), not in the defaults file — the defaults file often carries a skeleton value (`0`).
- **Prove lockstep from the written artifact**, not from the log: read `settings.json` after the run and check the seed's keys survived. If they did not, the seed version is the first suspect.
- When the seed's version must track runtime, put the rule in a comment next to the literal so the next reader knows the coupling instead of re-deriving it.

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
- **Reverse signals in the command line are real.** When the user stops a line of work, it ends: no re-litigating the stopped item, and no expanding the task after the stop.
