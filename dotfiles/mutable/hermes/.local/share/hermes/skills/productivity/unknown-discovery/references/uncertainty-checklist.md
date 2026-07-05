# Uncertainty Checklist — Detailed 5-Stage Breakdown

This is the deep-dive companion to `SKILL.md`. Load it on demand when the
agent needs prompts, scripts, or judgment calls per stage.

## Stage 1 — Brainstorm your unknowns

### Goal

Generate a *wide* list. No filtering, no ranking. The point is to surface
what you don't know — even things that feel obvious in retrospect count.

### Prompt set (use as many as you need)

Open every section with "What am I assuming about...?" — assumptions are
the most common hidden unknowns.

1. **The user**
   - Who, exactly, is the user? (demographics, role, context)
   - What problem are they trying to solve, in their own words?
   - What have they tried before? Why didn't it work?
   - What does "success" look like for them — and how would they know
     they got there?
   - What's their workflow *before* our product exists?
   - Who else is involved in their decision? (manager, customer, family)

2. **The problem**
   - Is this actually a problem? How often does it happen?
   - Is it a symptom of a deeper problem?
   - What's the *cost* of not solving it (time, money, pain)?
   - Is it getting better or worse over time?
   - Are there adjacent problems we should solve together?

3. **The solution space**
   - What constraints do we have? (tech, time, team, regulatory)
   - What's the minimum viable version?
   - What *can't* we do? (and is that a real constraint or a fear?)
   - What's been tried by others? Why did it fail or succeed?
   - What would a 10x version look like? (forces us to think beyond
     incremental)

4. **The ecosystem**
   - What tools/competitors/adjacent products exist?
   - What patterns have others established?
   - What's the user's mental model when they think about this space?
   - Where do users go to find solutions today? (Google, Reddit,
     colleagues, internal tools)

5. **The "I don't know I don't know" bucket**
   - What does our most confused user look like?
   - What would we need to know to *predict* their behavior?
   - What would surprise us about how this is used?

### Output format

One-line entries. Don't write paragraphs yet. Example:

```
- [USER] Who exactly is the primary user? Persona unclear beyond "designer"
- [PROBLEM] What does success look like for them? Have I observed it?
- [SOLUTION] Why hasn't this been solved? Existing tools status?
- [ECOSYSTEM] What patterns do competitors use? Worth borrowing?
- [META] Am I even framing the problem right?
```

Tag with `[USER]` / `[PROBLEM]` / `[SOLUTION]` / `[ECOSYSTEM]` / `[META]`
so you can sort later.

## Stage 2 — Prioritize (the filter)

### Three-pass filter

**Pass 1: Kill invalid unknowns.** Drop anything that's actually a
*known* — go check. "I don't know what programming language to use" is
a known if you've already chosen one. "I don't know if our existing
choice scales" might be unknown, might be known.

**Pass 2: Rank by importance × risk.** For each remaining unknown:

- **Importance**: How much does the answer change the design?
  (1-5)
- **Risk**: How wrong could we be if we assume the wrong answer? (1-5)
- **Cost**: How expensive is it to find out? (1-5)

Score = importance × risk / cost. Highest scores first.

**Pass 3: Pick top 3-5 to actively research.** The rest become
*background unknowns* — keep them on the list, but don't burn time
chasing them in Stage 3.

### Common filtering failures

- **Hoarding unknowns**: keeping everything on the list "just in case"
  → signals you didn't actually think about importance
- **Killing unknowns**: dismissing something because it's hard to
  research → usually the hard ones matter most
- **Assuming risk away**: "this is probably fine" → write down *why*
  you think so, so future-you can audit the bet

### Output

A re-prioritized list, with top 3-5 starred or marked.

## Stage 3 — Collect (both sides, simultaneously)

### Research side — the territory

- Read existing literature / docs / changelogs
- Study competitors (use their product, read their docs, look at reviews)
- Look at adjacent products (often the best patterns live in *adjacent*
  spaces, not direct competitors)
- Note industry conventions and standards
- Capture the *vocabulary* — what terms do practitioners use?

Output: a research notebook (one entry per source, with key takeaways
and *which unknowns* each one addresses).

### Interview side — the human

**Target: 5 conversations minimum, ideally 7-10.** Fewer than 5 and
you're pattern-matching on individuals; more than 10 and diminishing
returns kick in hard.

**Avoid these traps:**

1. **Leading questions**: "Would you use a feature that did X?"
   vs. "Tell me about the last time you tried to do X."
2. **Hypothetical questions**: "Would you pay $X?" → useless.
   "What did you pay for the last tool that did this?"
3. **Yes/no**: "Do you like this?" → useless. "Walk me through
   what just happened."
4. **Group think**: don't interview 3 people at once.

**Open-ended prompt set (use these):**

- "Tell me about the last time you [did the thing]."
- "Walk me through what happened next."
- "What did you do then? Why?"
- "What was the hardest part about that?"
- "If you could wave a magic wand and change one thing, what would
  it be?"
- "What did you expect to happen? What actually happened?"
- "Who else knows about this / is involved?"
- "Show me — can you literally show me your screen / workspace?"

**Capture both:**

- **Stated**: what they *say* they do (rationalized, post-hoc)
- **Unspoken**: what they *do* (revealed through observation and
  prompts like "walk me through")

The unspoken is **more valuable** than the stated. People rationalize
in real time; they can't fake the friction in their actual workflow.

**Document each conversation with:**

- Who (role, context, how you found them)
- What they said (paraphrase, not transcript — for your own use)
- What you *observed* (unspoken, environmental)
- Which unknowns this addressed (cross-ref your list!)
- What *new* unknowns surfaced

### When Stage 3 surfaces new unknowns

**This is normal and expected.** Add them to the list. Re-run Stage 2's
filter if the list grows much. Don't abandon the work — but don't
chase every new thread either. Update the priority, then continue.

## Stage 4 — Validate (test, don't assume)

Not every unknown needs validation. Validate the ones that:

- Are critical to the design direction
- Carry the highest risk if wrong
- Are cheap to test
- Have a clear pass/fail signal

### Cheap validation playbook

| Technique              | What it tests                              | Cost | Speed |
|------------------------|--------------------------------------------|------|-------|
| Fake door / smoke test | Demand exists for a feature                | $    | Days  |
| Concierge MVP          | Manual version works                       | $$   | Weeks |
| Wizard of Oz           | Users will accept the *appearance* of AI   | $$   | Weeks |
| A/B on copy/CTA        | Value prop lands / framing works           | $    | Days  |
| Pre-order / waitlist   | Will users commit money / attention        | $    | Days  |
| Landing page test      | SEO / positioning / market exists         | $    | Days  |
| Smoke prototype        | Core interaction feels right               | $$   | Week  |

### What validation looks like in practice

For each top unknown, write:

```markdown
## Unknown: [statement]

**Hypothesis**: We believe [X] because [reasoning].

**Cheapest test**: [technique]

**Pass criterion**: [what we'd see if hypothesis is correct]

**Fail criterion**: [what we'd see if hypothesis is wrong]

**Cost / time estimate**: [$X / N days]

**Status**: pending / running / passed / failed

**Result**: [what happened, what we changed]
```

### When validation fails

**Don't rationalize.** "The test was unfair," "users didn't get it,"
"we need to try harder" — these are all signals the assumption was
wrong. Update the unknowns list, the design, *or both*.

The point of validation isn't to confirm what you want to believe.
It's to *kill* bad ideas before they ship.

## Stage 5 — Design with purpose

Visual design is hard to articulate but easy to recognize — and that's
its danger. It's tempting to think the design is "right" because it
*feels* right. That's not validation.

### Design as forced clarity

The point of design artifacts (wireframes, prototypes, mockups) is
to make your unknowns **concrete enough to argue about**. A paragraph
hides ambiguity; a wireframe exposes it.

### Loop back to Stage 1

If design surfaces new unknowns (and it will):

1. Add them to the list
2. Decide if any are critical (impact × risk / cost)
3. If critical → loop back to Stage 3 to research them
4. Otherwise → proceed with what you have, note the assumption

This is **normal, not a failure**. The 5 stages are iterative, not
linear.

### Common design pitfalls

1. **Designing before prioritizing**: jumping into Figma with a list
   of 50 unknowns. Pick the top 3-5 first.
2. **Designing to confirm**: making the design look the way you
   already want it to look. Use fresh eyes.
3. **Skipping validation because the design "looks right"**: aesthetic
   confidence ≠ correctness.
4. **Confusing visual polish with design quality**: pixel-perfection
   on a wrong concept is still wrong.

## Cheat sheet — when in doubt

- **"I don't know what to ask"** → start with the Stage 1 prompt set,
  don't try to be clever
- **"I have too many unknowns"** → Stage 2 filter, kill invalid ones,
  rank the rest
- **"I keep adding unknowns without progress"** → pause new entries,
  research the top 3-5
- **"My research isn't converging"** → your unknowns list is wrong;
  revisit Stage 1
- **"The design feels right but I can't explain why"** → that's
  design, but it's *also* a sign you skipped validation
- **"I've been at this for weeks and feel lost"** → you skipped Stage
  2. Filter. Now.