---
name: unknown-discovery
description: "Use when the user starts a new project, faces ambiguous requirements, says 'I don't know what I don't know', wants discovery/research before design. Triggers: '识别未知', '设计前的调研', '验证假设', '用户访谈设计', 'discovery phase', 'validate assumptions'. Distilled from Than Tibbetts' 'A Field Guide to Fable: Finding Your Unknowns' — gives a 5-stage workflow for finding unknowns before you can find their solutions."
version: 0.1.0
license: MIT
metadata:
  hermes:
    tags: [discovery, research, design, unknowns, validation, interviews, product, planning]
    related_skills: [task-planner, architecture-advisor, code-reviewer]
---

# Unknown Discovery

> The hardest part of any project is **not** finding the solution — it's
> finding the unknowns. Distilled from Than Tibbetts' *A Field Guide to
> Fable: Finding Your Unknowns*.

## Core thesis (read this first)

> "I've done some example artifacts for finding unknowns here, but be sure
> to come back to build the process for what to use them. **Knowing your
> unknowns is the most important part of this process** — it gives
> focus. Without it, every action lacks a point, the work feels scattered,
> and you're never sure where you are."

Five-stage workflow:

```
1. Find unknowns          → brainstorm your own unknowns
2. Prioritize             → remove invalid assumptions; rank what matters
3. Collect (both sides)   → research unknowns + interview users
4. Validate               → test the most important assumptions
5. Design                 → artifacts prototype what you're really after
```

The map is **not** the territory. Anything you find in research must
circle back to the unknowns list — if it doesn't, you're collecting trivia.

## When to load this skill

- User says "我要做个新产品/新功能,但不知道从哪里开始"
- User says "我有哪些 unknowns / 我不知道我不知道什么"
- User starts a new project and requirements feel vague
- User asks for help designing interviews, surveys, or early product research
- User wants to validate assumptions before committing resources
- User is at the "blank slate" stage and wants structure, not just brainstorming

**Don't load** when the user already has a clear problem statement and
just wants implementation help — that's a `task-planner` job.

## The 5-stage workflow (high level)

### Stage 1 — Brainstorm your unknowns

The goal is **breadth, not depth**. Write down everything you don't know,
without judging importance yet. Capture:

- **Known unknowns** — "I know I don't know X" (e.g. "I don't know which
  design approach is best for this problem")
- **Unknown unknowns** — surfaces only during Stage 3 research/interviews

Use the framework:
> "What are your unknowns? What is going to Claude with a problem I
> need to break down?"

Don't filter. Don't rank. Don't research yet. Just write.

### Stage 2 — Prioritize (remove invalid assumptions)

Two filters, in this order:

1. **Known Knownness**: This is essentially what is in your past work
   and training — what you already know but haven't articulated.
2. **Known Unknownness**: What hasn't I figured out because I'm new to
   design work, an expert, or just need to surface it.
3. **Unknown Unknownness**: What I don't know I don't know, but if I
   do know, what would recognize it for me?

   For example, you might not know you need a root cause of "I don't
   know how to approach my problem" until you're mid-research.

Then rank by:

- **Impact**: Does answering this change the design direction?
- **Risk**: How wrong could we be if we assume the wrong answer?
- **Cost**: How expensive is it to find out?

### Stage 3 — Collect (both sides, simultaneously)

Two parallel streams. **Neither alone is enough.**

- **Research the topic**: Read docs, study competitors, explore
  adjacent products, understand the ecosystem. This catches the
  *context* side — what the field already knows.
- **Interview users / stakeholders**: At least 5 conversations. Watch
  for what's *unspoken* — the biases, workarounds, and friction
  they don't realize they're revealing. This catches the *human*
  side — what your source actually does vs. what they say.

The goal is **understanding, not validation**. If you go in trying to
confirm what you already believe, you'll find it — and ship the wrong
thing.

### Stage 4 — Validate (test, don't assume)

Not every unknown needs validation. Validate the ones that:

- Are critical to the design direction
- Are easy/worth testing cheaply
- Carry the biggest risk if wrong

Common cheap validation techniques:

- **Fake door test**: Ship a button that "doesn't work yet" and
  measure clicks — proves demand before building
- **Concierge MVP**: Manually do the job the product would automate,
  for a handful of users
- **Wizard of Oz**: User sees an "AI", it's actually a human behind
  the scenes
- **A/B on copy/CTA**: Tests the assumption's *surface* before the
  deeper thing
- **Pre-order / waitlist**: Tests whether the value prop lands

If validation fails → update the unknowns list. If it passes →
move on.

### Stage 5 — Design with purpose

Visual design is something that is difficult to articulate, but I know
what I want when I see it. It's enough — but you might ask for several
design approaches early on.

Design artifacts are **how you make your unknowns concrete enough to
argue about**. A wireframe surfaces unknowns that a paragraph hides.

Loop back to Stage 1 if design reveals new unknowns. This is normal —
the workflow is **iterative, not linear**.

## Where to go for detail

| Need                              | Go to                                                  |
|-----------------------------------|--------------------------------------------------------|
| Stage-by-stage checklist with prompts | `references/uncertainty-checklist.md`              |
| Templates to copy & fill in       | `templates/unknowns-inventory.md`                      |
| Schema validator for unknowns JSONL | `scripts/validate-unknowns.py`                      |

## Pitfalls (read these before starting)

1. **Validation ≠ research.** Research *describes*; validation *tests*.
   Mixing them is the most common failure mode.
2. **Avoid priming in interviews.** "Does Claude help you find your
   unknowns?" is a leading question. Use open-ended asks: "Walk me
   through the last time you tried to [task]."
3. **Unspoken > stated.** People rationalize after the fact. Watch
   what they *do*, not just what they say.
4. **Map is not the territory.** A whiteboard, a user interview
   transcript, a competitive analysis — these are all artifacts
   representing the real thing, not the real thing. Verify against
   the world.
5. **Don't skip Stage 2.** Brainstorming everything feels productive.
   It isn't. Filtering is where the value crystallizes.
6. **5 conversations minimum.** Fewer than 5 and you're pattern-matching
   on individuals. More than 10 and you're hitting diminishing returns.
7. **Design before validation = guessing.** Visual design is
   seductive — it's hard to articulate but easy to recognize. Don't
   let aesthetics convince you the unknowns are answered.

## Quick-start

```bash
# 1. Copy the inventory template
cp ~/.local/share/hermes/skills/productivity/unknown-discovery/templates/unknowns-inventory.md \
   ./unknowns.md

# 2. Fill in Stages 1-2 (brainstorm + prioritize)

# 3. After Stage 3, optionally export to JSONL and validate:
python3 ~/.local/share/hermes/skills/productivity/unknown-discovery/scripts/validate-unknowns.py \
   unknowns.jsonl
```

For the full protocol, prompt library, and interview scripts, load
`references/uncertainty-checklist.md`.

## References

- `references/uncertainty-checklist.md` — detailed 5-stage breakdown,
  interview question prompts, validation technique playbook
- `templates/unknowns-inventory.md` — starter file (copy & edit)
- `scripts/validate-unknowns.py` — JSONL schema validator
- *Source*: Than Tibbetts, "A Field Guide to Fable: Finding Your Unknowns"
  (synthesized from the Fable design practice)