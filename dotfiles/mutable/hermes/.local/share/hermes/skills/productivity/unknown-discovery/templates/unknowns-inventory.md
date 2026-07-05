# Unknowns Inventory — Project: ___________________

> Track every unknown surfaced during discovery. Brainstorm first (Stage 1),
> filter and rank (Stage 2), research and interview (Stage 3), validate the
> critical ones (Stage 4), and let design surface new ones (Stage 5).
>
> See `references/uncertainty-checklist.md` for the full protocol.

## Stage 1 — Raw brainstorm

Brainstorm everything. No filtering. Tag each entry:

- `[USER]` — about the people using the thing
- `[PROBLEM]` — about the problem itself
- `[SOLUTION]` — about the design / implementation
- `[ECOSYSTEM]` — about the market, competitors, conventions
- `[META]` — about the framing of the project itself

```
- [____] ____________________________________________________________
- [____] ____________________________________________________________
- [____] ____________________________________________________________
- [____] ____________________________________________________________
- [____] ____________________________________________________________
- [____] ____________________________________________________________
- [____] ____________________________________________________________
- [____] ____________________________________________________________
- [____] ____________________________________________________________
- [____] ____________________________________________________________
```

## Stage 2 — Prioritized

After filtering invalid unknowns and ranking by **importance × risk /
cost**, mark the top 3-5 with `★` for active research.

```
- [____] ____________________________________________________________  (score: __)
★ [____] ____________________________________________________________  (score: __)
- [____] ____________________________________________________________  (score: __)
★ [____] ____________________________________________________________  (score: __)
- [____] ____________________________________________________________  (score: __)
★ [____] ____________________________________________________________  (score: __)
- [____] ____________________________________________________________  (score: __)
- [____] ____________________________________________________________  (score: __)
```

## Stage 3 — Research & interview log

For each ★-marked unknown, capture what you learned. Add new unknowns
that surface — they're a feature, not a bug.

### Unknown: _________________________________

**Sources reviewed:**

- _____________________________________________
- _____________________________________________

**Interviews conducted:** (target: 5+)

| # | Who (role, context) | Stated | Observed (unspoken) | New unknowns surfaced |
|---|---------------------|--------|---------------------|------------------------|
| 1 |                     |        |                     |                        |
| 2 |                     |        |                     |                        |
| 3 |                     |        |                     |                        |
| 4 |                     |        |                     |                        |
| 5 |                     |        |                     |                        |

**Synthesis** (what we now believe, what we still don't know):

```
___________________________________________________________________
___________________________________________________________________
___________________________________________________________________
```

### Unknown: _________________________________

(Repeat the structure above)

### Unknown: _________________________________

(Repeat the structure above)

## Stage 4 — Validation log

For each critical remaining assumption, design the cheapest test.

### Unknown / Hypothesis: _________________________________

**Hypothesis**: We believe ___________________________________________ because
___________________________________________________________________.

**Cheapest test**: ___________________________________________________

**Pass criterion**: __________________________________________________

**Fail criterion**: __________________________________________________

**Cost / time estimate**: ____________________________________________

**Status**: ☐ pending  ☐ running  ☐ passed  ☐ failed

**Result**: _________________________________________________________

**What we changed based on this**: ___________________________________

### Unknown / Hypothesis: _________________________________

(Repeat the structure above)

### Unknown / Hypothesis: _________________________________

(Repeat the structure above)

## Stage 5 — Design feedback loop

After each design pass, capture new unknowns that surfaced. Don't abandon
work to chase every thread — but record them.

```
- [____] ____________________________________________________________  (added: __/__)
- [____] ____________________________________________________________  (added: __/__)
- [____] ____________________________________________________________  (added: __/__)
```

**Decision on each new unknown**:

- ☐ Critical → loop back to Stage 3
- ☐ Background → keep on list, proceed
- ☐ Invalid → drop (with reason)

## Final state — what we know now

When the project is ready to ship (or pivot), capture the resolved
unknowns here as institutional memory.

```
1. _________________________________________________________________
2. _________________________________________________________________
3. _________________________________________________________________
4. _________________________________________________________________
5. _________________________________________________________________
```

**Unknowns we chose NOT to resolve (and why):**

```
1. _________________________________________________________________
2. _________________________________________________________________
```

---

## Notes

- This template is a **starting point** — modify for your project's shape
- Re-run Stages 2-3 whenever Stage 5 surfaces major new unknowns
- Keep it version-controlled (git diff over time tells the story)
- JSONL export: if you want machine-readable tracking, see
  `scripts/validate-unknowns.py` for the schema

**Skill:** `unknown-discovery` (Hermes Agent)
**Source:** Than Tibbetts, *A Field Guide to Fable: Finding Your Unknowns*