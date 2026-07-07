---
name: plan-pressure-test
description: Stress-test a plan or design doc by walking the decision tree one branch at a time with the user. Triggers when the user says "压力测试这个方案 / 把这个计划拍一遍 / 我有个 plan 想跟你对一下 / 等等我有问题要问你 / grill this / 拍砖 / 我总觉得哪里不对 / 这个方案经不经得起推敲" or any other "challenge my existing plan" framing. Distinct from `task-planner` (which builds a plan from scratch) and `architecture-advisor` (which gives a second-opinion read on a finished design). The output is a numbered decision ledger (D1, D2, ...) that either becomes the new plan or marks which sections of the existing plan need rewriting.
---

# Plan pressure-test

The pattern in this skill emerged from real sessions where the user already has a plan doc and wants it stress-tested, not built. Most of the time, the doc's *claims* are wrong in ways that only surface when you ask one question at a time.

## Relationship to other skills

- **`/grilling`** (in `~/.config/agents/skills/`, may be Guix-deployed and read-only in some profiles): the **triggering protocol** — a one-liner that says "ask questions one at a time, walking the decision tree". This skill **operationalizes** grilling into an 8-step procedure that's been proven on real sessions.
- **`/task-planner`**: builds a plan from scratch. This skill is for **stress-testing an existing plan**.
- **`/architecture-advisor`**: gives a second-opinion read on a finished design. This skill is for **converging a half-baked plan via Q&A**.

When the user says "grill this" / "拍这个方案" / "压力测试", load this skill. When the user just says "ask me questions about X" without an existing doc, the bare `/grilling` skill (if loadable) is enough.

## When to use this skill

- The user already has a plan / design doc, possibly with decisions already written
- The user wants to know "is this right?" / "what's missing?" / "where am I wrong?"
- The expected output is **a list of decisions to pin or rewrite**, not a fresh plan

If the user wants a fresh plan from scratch, use `task-planner`. If they want a second-opinion architecture review of a finished design, use `architecture-advisor`. This skill is **for when the plan is half-baked and the user wants to converge it**.

## The protocol (8 steps)

### 1. Fact snapshot first

Before the first question, spend 1–3 tool calls verifying the plan's facts:

```bash
git status --short                    # what's uncommitted
wc -l <plan-files>                    # line counts
search_files pattern=<plan-claim>     # grep for reality
```

If the plan has a "snapshot" or "current state" section, cross-check it. Plans drift. Grilling on top of a stale plan is wasted motion.

### 2. Top-of-tree first, then branches

Don't walk the doc top-to-bottom. Pin **scope / target** before asking anything else:

1. **Scope / target** (1–2 questions): What does this thing *serve*? What's the user? When is it used vs. not used?
2. **Hardest single decision** (1 question): The one that, if wrong, makes everything below it wrong.
3. **Concrete next layer down**.

After each pinning, restate it as `D1. — title — rationale` so the running ledger stays scannable.

### 3. Mark factual claims with confidence

When you assert a fact during grilling, label it:

- ✅ **verified** — you grep'd / read it / probed
- ⚠️ **inferred** — you believe it but didn't directly check
- ❓ **assumed** — you're guessing; ask the user to confirm

This matters because the user will sometimes correct you, and the corrections only make sense if you can tell which of your claims were which. In one real session, three claims I made were all wrong:
- "guix 本身不自带 kmscon" → ❌ (assumed; user corrected)
- "sjtug 没有公钥会 unauthorized" → ❌ (inferred wrong; sjtug 是 mirror)
- "(password #f) 在 slim auto-login 后能 sudo" → ❌ (assumed; 实测 pam_unix reject)

If you don't know, say so — don't make the user pay for your confidence.

### 4. Use `clarify` only for crisp forks

The `clarify` tool's `choices[]` is for **mutually exclusive, equally-good** options. When the options aren't crisp (e.g. three of four could all be right), force the user into a bad choice.

**Rule of thumb:** if you can't write a one-line *distinguishing* question, prefer an open-ended `clarify` or ask in prose. When the user picks `Other` and types their own explanation, your choices weren't crisp — acknowledge that.

### 5. Don't change docs mid-grill unless the user says to

Default mode: **ask, listen, restate**. Don't autonomously `patch` the plan doc because you "have a clear picture now". The user controls when to switch from ask-mode to write-mode.

Triggers that mean "now apply":
- "先根据目前的决策修改一轮方案"
- "写到文档里"
- "你落地一下"
- "改一下"

Until one of those (or similar), keep asking.

When the user does signal "apply now", restate what you'll change *before* changing — a one-line summary of "I'll edit §0 / §9.4.3 / §15" so they can intercept.

### 6. The decision ledger IS the output

Maintain a running table of pinned decisions, named (D1, D2, ...). At session end:

```
D1. — (title) — (rationale)
D2. — ...
```

This is what makes the next agent able to pick up. The user can paste it into the doc or use it as a checklist for the next session.

### 7. Cross-validate against the codebase before each pinning

Before locking D3 ("ISO 复刻 X"), grep for X in the existing config and report what you find. If the user is unaware of existing config, that's a fact they need to weigh.

In one real session, the plan claimed "ISO 复刻 1/4 substitute 镜像" — but `source/config.org` already had 4 sets configured. The plan's claim was wrong because nobody grep'd the host config.

### 8. Restate before pushing back

When the user's answer doesn't match your model, **restate their answer in your own words and ask "is that right?"** — they'll often correct you in a way that fixes your model better than a yes/no would.

Bad pattern (forces a pick from a bad dichotomy):
> "你说 guix 不自带 kmscon, 但 Testment 文档说 installer 跑在 kmscon, 这看起来矛盾, 你怎么拍?"

Better pattern (converges):
> "你说 guix 不自带 kmscon — 我先核一下 rosenthal `make-installation-os` 是否启用 kmscon service。如果 rosenthal 默认就启用,这个矛盾就消失了;如果没启用,我再问你怎么处理。先让我跑一下..."

## Pitfalls

- ❌ **Asking implementation details before pinning scope.** "Should we add (service kmscon-service-type)?" is the wrong question before knowing whether the target is "装机辅助" or "装好后系统".
- ❌ **Treating the plan doc as authoritative.** Plans drift. Take a snapshot.
- ❌ **Multiple questions in one turn.** Each `clarify` is one fork. Ask the one that blocks the others first.
- ❌ **Asking "is X right?" when you could just check X.** Read the codebase.
- ❌ **Auto-applying changes when the user wanted to keep asking.** Default is ask-mode. Wait for the trigger.
- ❌ **Long preambles before each question.** One sentence of context, then the question.
- ❌ **Burying a decision in §9.4.3 when it belongs in §0 scope.** If a decision affects "what the thing is for", it's scope, not implementation.
- ❌ **Adding a new D-number when the user just corrected the *reason* of an existing one.** If the user says "D5 理由错了,重写", **rewrite D5 in place** — don't append D12 to "rewrite D5 reason". New D-numbers are for *new* decisions; rewrites of old ones are ledger edits. This keeps the ledger scannable and avoids "the reason I cared about was at D5 originally, not D12" hunt.
- ❌ **Assuming transitive claims from one source.** When a fact is documented in one place (e.g. "Testament README says installer runs on kmscon"), the natural assumption is the same is true elsewhere (e.g. rosenthal `make-installation-os` enables kmscon by default). Both could be wrong in different ways. Verify at the *actual* layer before pinning. See step 1.5 below.

## Step 1.5 — Verify at the actual layer (added after real session)

The plan often makes claims about what some upstream thing *does* — and the plan's author only verified one layer deep. Examples from real sessions:

| Plan claim | Source verified | Actual layer unverified | What broke |
|---|---|---|---|
| "Testament README says installer runs on kmscon" | README text | rosenthal `make-installation-os` service list | Plan added `(service kmscon-service-type)` as a "must" — but the function already enables kmscon by default in guix core, so the explicit add was redundant. Worse, plan had `(delete kmscon-service-type)` as a "cleanup" — which was a no-op against a base service that wasn't there. |
| "ISO 复刻 1/4 substitute 镜像" | doc said so | the host config the user *already had* | Plan was 60% wrong because the host config (`source/config.org`) had 4 sets all along. Nobody grep'd. |
| "`(password #f)` 让 slim auto-login 后 sudo reject" | assumed | actual pam config in `make-installation-os` | Plan claimed default empty-password rejected sudo. Reality: `make-installation-os` ships `base-pam-services #:allow-empty-passwords? #t`. Plan reasoning was wrong; D5 needed a *different* reason to be correct. |

**Rule of thumb:** if the plan's claim rests on a chain "X says Y, therefore Y", probe the actual "Y" by reading the source (`git show <commit>:<path>` or `git clone <repo>` to a scratch dir and `cat` it). Don't re-read the plan's citation — read what the citation cites.

The probe cost is one `git clone` + a few `grep`s. The cost of pinning wrong is a 30-min implementation detour and a D-number that has to be rewritten. Always probe.

## When to stop

- The user explicitly says "够了" / "OK" / "落地吧" / "开始实施"
- The decision ledger has all the top-of-tree questions resolved; remaining branches are implementation details
- The user pivots to a different concern

Don't keep grilling past convergence — you burn the user's patience on micro-decisions.

## What this skill is NOT

- Not a checklist of "questions to ask about a plan" — questions are plan-specific
- Not a fresh-plan builder (`task-planner` is for that)
- Not a second-opinion architecture review (`architecture-advisor` is for that)
- Not a writing/editing skill — once the user says "apply now", this skill is done; switch tools

## Reference

- `references/iso-build-session-2026-07-06.md` — full worked example from a real session (ISO Live-CD plan, **14 decisions across 2 rounds** + 7 fact_id anchors + cross-agent exit via `agenote`). Read it to see how the 8 steps + Step 1.5 + Step 9 play out on a non-textbook plan.