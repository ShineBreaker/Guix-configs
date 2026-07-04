---
name: hyperframes-creative
description: Non-animation creative direction for HyperFrames videos. Use for design spec (frame.md / design.md) handling, palettes, typography, narration, beat planning, audio-reactive visuals, composition patterns, and brand / style decisions. For atomic motion patterns and scene blueprints, use `hyperframes-animation`.
---

# HyperFrames Creative

Brand, pacing, style, narration, and composition direction. Use after the technical contract from `hyperframes-core` is in place.

For motion patterns, scene blueprints, transitions, and CSS marker effects, use `hyperframes-animation` — this skill is intentionally non-animation.

> **Read these two FIRST for any non-trivial composition — they override web instincts:**
>
> - `references/house-style.md` — "interpret the prompt, generate real content," the lazy-default list, and the background/foreground layer recipe. This is what turns a literal restyle into a _concept_.
> - `references/video-composition.md` — video-medium density, scale, foreground metadata (the "produced, not generated" detailing: data bars, registration marks, monospace readouts, 8-10 elements/scene).
>
> Skipping these is the single biggest cause of generic, web-page-looking output. They are not optional rows in the routing table below — for anything beyond a one-line edit, open both before you choose colors or write HTML.

## Workflow

1. If a project has a design spec, **read it first** and treat its frontmatter tokens as brand truth (colors, fonts, spacing, tone, constraints). Which file to read (precedence `frame.md` → `design.md` → `DESIGN.md`) and how to parse it (frontmatter = normative, prose = context) are defined once in [`references/design-spec.md`](references/design-spec.md) — resolve and load per that doc.
2. If no design spec exists and the user asks for visual direction, choose a route:
   - Ready-made frame-preset (optional) → `frame-presets/` (adopt a `FRAME.md` as `frame.md`; see `references/design-spec.md`)
   - Named style or mood → `references/visual-styles.md`
   - Fast defaults → `references/house-style.md`
   - Interactive selection → `references/design-picker.md`
3. For multi-scene work, plan beats and rhythm before writing HTML → `references/beat-direction.md`. For scene transitions, jump to `hyperframes-animation/transitions/`.
4. For motion-heavy work, read `references/motion-principles.md` (high-level guardrails), then go to `hyperframes-animation` for atomic rules.

## Routing

| Topic                                                                    | Read                                           |
| ------------------------------------------------------------------------ | ---------------------------------------------- |
| Adopt a ready-made frame-preset as `frame.md` (optional)                 | `frame-presets/` · `references/design-spec.md` |
| Default palettes, motion, typography, lazy defaults to question          | `references/house-style.md`                    |
| Named style presets, mood-to-style routing                               | `references/visual-styles.md`                  |
| Palette-specific color tokens                                            | `palettes/*.md`                                |
| Composition patterns — PiP, text-behind-subject, title card, slide show  | `references/composition-patterns.md`           |
| Stats / infographic presentation                                         | `references/data-in-motion.md`                 |
| Structured expansion for open-ended prompts                              | `references/prompt-expansion.md`               |
| Video-medium density, scale, color, frame composition                    | `references/video-composition.md`              |
| Per-beat direction, rhythm planning, transition timing                   | `references/beat-direction.md`                 |
| Post-authoring spec verification (colors, type, corners, spacing, depth) | `references/design-adherence.md`               |
| High-level motion guardrails and GSAP-quality rules                      | `references/motion-principles.md`              |
| Font selection, pairings, rendered-video type guardrails                 | `references/typography.md`                     |
| Script pacing, tone, openings, number pronunciation                      | `references/narration.md`                      |
| Precomputed audio bands mapped to motion                                 | `references/audio-reactive.md`                 |

## Structural visual (concept-teaching mandatory)

For any composition that **explains a concept with internal structure** — programming-language evaluation, data structures, type systems, state machines, network protocols, process lifecycles, scientific mechanisms, math derivations — apply this **before** picking palettes or composing scenes. The "produced, not generated" rule in `video-composition.md` is necessary but not enough; concept videos fail in a specific way: the agent renders the *text* of the source rather than the *thing the text describes*. The viewer could have read the source; the video must show them what reading cannot.

**Diagnostic, one question per scene**: *what does this concept look like in the world it inhabits?* The answer is a *concrete noun* that can be drawn or animated, not an abstract summary. Worked examples:

| Source text says…                  | WRONG visual                                            | RIGHT visual                                                                                       |
| ---------------------------------- | ------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| `(+ 1 2)` evaluates by recursion   | A 4-step bullet list with code                          | An SVG tree that grows root → edges → leaves, with a colored pulse travelling root→leaf→root       |
| "Integers are atomic values"       | A card with `42` and a label                            | A single memory cell with a typed `INT` tag, the cell is the visual — a counter ticks inside it     |
| "Strings are character arrays"     | A card saying `length: 6`                               | A row of cells, one per character, lights sweeping left→right reading them                          |
| `defvar` is "declare once"         | A bullet listing `defvar` vs `setq`                     | A binding-table on the right; when the row fires, an arrow tries to write, the cell rejects it     |
| "Closures capture lexical scope"   | A box of nested `let` calls                              | A scope-chain ladder, a function call site above it, the captured variable highlighted in a frame  |
| "TCP three-way handshake"          | Two boxes labelled "client / server"                     | A timeline lane with SYN → SYN-ACK → ACK packets travelling between two nodes with a clock counter |
| "Mitosis has four phases"          | A 4-bullet card with phase names                        | A cell that visibly splits; each sub-scene shows one stage with chromosomes migrating                |

**Rules for the visual designer / scene workers**:

1. The visual must change in a way the **code** of the concept would change. If the concept is "this function returns 3", the visual must show 3 *being computed*, not just appearing.
2. The "diagram" is a moving thing. Static diagrams with caption text on top are a slide deck. The animation IS the explanation.
3. Each non-trivial scene gets **at least one element whose motion is causally tied to the rule being explained** — a pulse that *is* the recursive call, a cell that *is* the binding, a token that *is* the value.
4. When the source's claim is **"X is a Y of Z"**, draw Y of Z — not "X: Y of Z" in a label. The user's eye should learn the structure by seeing it, not by reading the words naming it.

**When to skip this rule**: pure prose explainers with no structural claim (history, opinion, motivation, soft-skills) — those are still "type / abstract graphics" but not "structural visual". The test: if removing all animations from the scene still leaves the concept understandable from text alone, the visual is decorative and the scene should be re-scoped.

## Scripts

- `scripts/contrast-report.mjs` — inspect contrast warnings from rendered frames.
- `scripts/extract-audio-data.py` — pre-extract audio bands for audio-reactive compositions.
- `scripts/package-loader.mjs` — support script for bundled creative tooling.

Run from the repo root with explicit paths, for example:

```bash
python skills/hyperframes-creative/scripts/extract-audio-data.py <audio-file>
```

Animation analysis (`animation-map.mjs`) lives in `hyperframes-animation/scripts/`.

## Boundaries

- Do not override `hyperframes-core` technical rules.
- Do not require a design system for a minimal technical composition.
- Do not add extra scenes, narration, music, captions, or transitions unless the request calls for them or you first propose the expansion.
- Keep recipe references task-specific; do not read every reference for simple edits.
