# Autonomous Convergence Loop — RecollectBeat Iterative Deepening

> Extracted from RecollectBeat multi-iteration convergence (BaseNote → note-render → game-consts → slide-window → hold → buildLevelData). Apply when user says "全部由你确认优先级，自行推动" / "不断重复 ... 直到无可选候选".

## Candidate Order (thinnest viable seam first)

1. Large shallow modules: `SlideNote` ~350-line 9×30 window branches (600 total), `buildLevelData` 440-line 8-branch chain (Speculative until second consumer).
2. 3-site shared helpers: Hold `ensureHoldEffect` singleton (Long/TopLong/Slide), `game-consts.ts` single source for `render-path` + `position-generator` (~18 constants each).
3. Thin duplication: remaining `scale(r, r*2*note.h).scale(1,-1)` sites (ReflecBullet, SlideSegment.drawNode, Stage indicators) → `note-render.ts` deep seam; `noteType`/`Side` enum unification; `note.h=0.5` compat field.

Gating: deletion test ("concentrates vs moves"), "two adapters = real seam", YAGNI termination.

## Per-Candidate Recipe

- **Read flow end-to-end** (trace imports/usages, git hotspots via `git log --oneline`), then climb ponytail ladder.
- **One candidate per commit** — `git add -- <exact paths>` + `git diff --cached --name-only` check + Conventional Commits + `Generated with Crush` footer; `--no-gpg-sign` fallback.
- **Verify `tsc ×5 / eslint / prettier` all green** before commit (use `node node_modules/.../tsc.js` etc — direct bin blocked by gateway).
- **One minimal runnable check** per non-trivial branch: e.g. `tests/slide-window.test.ts` 8 cases (sentinel / window open/close / `slideFinalJudgment` linkage) for `tryJudgeSegmentWindow` (7 position params, Sonolus compiler constraint).

## Seams Introduced

- `shared/src/level/data/game-consts.ts` — mirrors `consts.rs` for two consumers.
- `play/src/engine/playData/lib/note-render.ts` — `drawNoteCircle` / `drawChordGlow` / `drawHoldBodyTail` (Y-flip comment lives only here).
- `shared/src/level/data/slide-judgment.ts:tryJudgeSegmentWindow` — 7 position params, pure, testable.
- `play/src/engine/playData/lib/playHitEffect.ts:ensureHoldEffect` — singleton guard for Long/TopLong/Slide.
- `shared/src/level/data/index.ts:resolveArchetype` + `pushSlideEntities` — dispatch locality.

## Termination Condition

Stop when `grep "scale.*note\\.h" play/src shared/src` returns only `note-render.ts` + `levelData.ts` definition, and `shared/index.ts` has no 8-branch chain. Thin leftovers at 2 adapters (e.g. `drawHoldBodyTail`) stay until a third adapter appears.

Related: `improve-codebase-architecture` (external_dirs, read-only) defines HTML report / grilling contract; this file adds the autonomous extension. Recommend `hermes curator adopt improve-codebase-architecture` if edits needed there.
