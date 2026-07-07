# Worked example: ISO Live-CD grill session (2026-07-06)

This is one full session run under this skill's protocol. It's here as a reference so the next agent can see how the 8 steps play out on a real plan, not a textbook example.

**Do not** treat the ISO details as reusable for non-ISO plans. The value is in *how the protocol was applied*, not what was decided.

## Setup

- **Plan doc:** `~/Projects/Config/Guix-configs/docs/iso-build.md` (2009 lines, untracked)
- **User goal (initial framing):** "想用这个 ISO 装 Guix System"
- **Doc's claim:** XFCE + slim main variant, 4 substitute sets inherited from host config
- **Doc's snapshot (§14):** "git clean, no uncommitted changes" — *wrong; reality had 2 uncommitted files*

## Round 1 — initial grilling, D1–D7 ledger (2026-07-06 morning)

### Step 1: fact snapshot

Agent ran:
- `git status --short` → revealed `?? docs/iso-build.md` + `M dotfiles/.../SKILL.md` + `?? dotfiles/.../iso-build-handoff.md`
- `wc -l` on plan files → blueprint.scm 1298, config.org 1929, .gitignore 26 (vs §14 said 27)
- `search_files` for `mihomo` in `source/config.org` → **found full shepherd service + tun + config template**, contradicting the plan's claim that "ISO 不需要 mihomo 配置"

This snapshot **surfaced the central problem** before any question was asked: the plan was built on a stale mental model of the host config.

### Step 2: top-of-tree first

Agent's first question (paraphrased): "ISO 的 desktop 是给**装机过程**用的辅助工具,还是给**装好后系统**用的桌面?"

This was the right first question because:
- The doc implicitly conflated the two (slim auto-login → live user → XFCE, all for "装好后")
- The user's answer reframed everything: "**装机过程辅助** + 装好后用户自己 blue rebuild"
- This single answer invalidated ~60% of the existing `services:` block

### Step 3: confidence labels caught wrong claims

During grilling, agent asserted:
- ❌ "guix 本身不自带 kmscon" → user corrected; reality: rosenthal install ISO 默认启用 kmscon service
- ❌ "sjtug 没有公钥会 unauthorized" → user corrected; reality: sjtug 是 mirror,验签走原签发源
- ❌ "(password #f) 在 slim auto-login 后能 sudo" → agent assumed; reality: pam_unix 会 reject

Each was caught because the user answered in the agent's "restate in your own words" step (§8 of the skill). The agent's model was repaired **before** those assumptions baked into the plan.

### Step 4–7: decision ledger emerged

By session end of round 1, 7 decisions were pinned:

```
D1. main variant = XFCE + slim           (consistent with doc)
D2. scope = 装机用环境, 不干预装好后     (new — surfaced by step 2)
D3. 4 套 substitute 全复刻               (rewrites §9.4.3)
D4. 只装 mihomo 包, 不引 service         (rewrites §9.4.3)
D5. live user = "live" / "live"          (rewrites §9.4.4)
D6. 显式加 kmscon-service                (rewrites §9.4.3)
D7. plan doc 不 commit                   (rewrites §15)
```

The ledger is what makes the next agent able to pick up. Without it, a fresh agent would re-walk the same tree.

### Step 5 trigger (round 1)

User said: **"先根据目前的决策修改一轮方案,再继续提问"** — clear "apply now" signal. Agent restated: "I'll edit §0 / §6.2 / §9.4.3 / §9.4.4 / §9.4.3.1 / §12 / §15" before patching.

After the apply phase, user said **"继续向我提问吧"** — clear return-to-ask-mode signal. Agent switched back.

## What this session (round 1) shows

1. **Fact snapshot (step 1) saves whole questions.** Without grep'ing `mihomo` in `source/config.org`, the plan's gap on substitute URLs + mihomo would have surfaced only at implementation time.
2. **Top-of-tree question (step 2) reframes everything.** The scope question rewrote 60% of the implementation in one answer.
3. **Confidence labels (step 3) catch agent errors cheaply.** The three ❌ claims above would each have caused a 30-min implementation detour.
4. **The decision ledger (step 6) is the output.** The session's value is not "the patched doc" but "the 7 pinned decisions + the diff they imply". A fresh agent can re-derive the doc from the ledger.
5. **Mode-switching needs an explicit trigger (step 5).** User said "先根据目前的决策修改一轮方案" to switch to apply-mode; "继续向我提问吧" to switch back. Without those triggers, agent would have either kept asking past convergence or applied changes prematurely.

## Round 2 — implementation-layer grilling + source-code fact probes (2026-07-06 afternoon)

After round 1's apply-mode, user said "继续向我提问吧" and round 2 covered the *implementation-layer* risks round 1 skipped, plus source-code fact checks.

### Round-2 ledger additions (append to round-1, don't renumber)

```
D8.  blue build-iso sudo 边界 — 待验证 (P6.5 preflight)
D9.  §11.4 决策矩阵补 #7373 根因细节 (commit 1eccea7f + 5a8502a4)
D10. P8 实战装机验收门槛低 / 可能不验收 (user: "installer 本身就很难用")
D11. gril 期间 7 条事实沉淀进 fact_store (fact_id 17–24)
D12. D5 理由重写 — 覆盖 users 后默认 guest 消失, 必须新加密码
D13. §11.5 接手 agent 边界迁移至 agenote KB (跨 agent 共享)
D14. §9.4.4 crypt 实现正确 (Guile 内置 crypt, "$6$abc" 合规)
```

D5 and D6 were *rewritten in place* (not new D-numbers) because the user corrected the *reason*, not the decision itself. This is the **D-rewrite pattern** — keep ledger scannable.

### Round-2 fact probes (the ones that mattered)

| Probe | Method | What it disproved |
|---|---|---|
| `make-installation-os` is in **guix core**, not rosenthal | `git clone https://codeberg.org/hako/rosenthal.git` + `git grep make-installation-os` → 0 hits; then `git clone https://git.savannah.gnu.org/git/guix.git --depth 1` + `grep install.scm` → found at `gnu/system/install.scm:693` | Plan §9.4.2 listed `(rosenthal services file-systems)` as the module. Wrong module. Would have unbound-variable'd at build time. |
| `%installation-services` enables kmscon by default | `sed -n '441,500p' gnu/system/install.scm` → `(service kmscon-service-type (kmscon-configuration (kmscon kmscon-8) (virtual-terminal "tty1") ...))` | Plan §9.4.3 had `(service kmscon-service-type)` as a "must add" (D6) and `(delete kmscon-service-type)` as a "cleanup". The add was redundant; the delete was a no-op. |
| Default user + pam config in `make-installation-os` | `sed -n '690,770p' gnu/system/install.scm` → `(user-account (name "guest") ... (password "") ...)` and `(base-pam-services #:allow-empty-passwords? #t)` | Plan D5 ("(password #f) makes sudo reject") had wrong reasoning — pam already allows empty passwords. The *decision* stayed (password="live"), the *reason* got rewritten (D12). |
| `(crypt "live" "$6$abc")` produces valid SHA-512 hash | `guile -c '(display (crypt "live" "$6$abc"))'` → `$6$abc$F0HJKJ2Z...` | Salt `$6$abc` is valid (5 chars, in [a-zA-Z0-9./] range, below 8-char cap). `crypt` is built into `(guile)` top module, no import needed. |
| `#7373` is still Open, root cause locked | `curl https://codeberg.org/api/v1/repos/guix/guix/issues/7373` + comments API | Plan §9.2 still accurate, but the "rollback to guile-3.0.9" advice in §11.4 was wrong-shaped — actual root cause is Guile 3.0.11 commit `5a8502a4` + rosenthal `safe-clone` commit `1eccea7f`. D9 = rewrite §11.4 to "rollback to guile before 5a8502a4". |

### Pattern: fact_id bi-directional anchoring in the plan doc

When a decision in the plan doc rests on a fact that's been added to `fact_store`, the plan doc should **cite the fact_id inline**:

```scheme
;; §9.4.3 gril 重写 (fact_id=22: make-installation-os 在 guix core)
;; §9.4.3 gril 重写 (fact_id=17: kmscon 默认启用)
;; §9.4.3 gril 重写 (fact_id=23: 默认 guest user + pam allow-empty-passwords)
```

This way the next agent who reads the plan doc can:
1. See the assertion in the plan
2. `fact_store action='get' fact_id=N` to retrieve the verified probe transcript
3. Cross-check whether the assertion still holds in their session

Without bi-directional anchoring, the next agent re-probes everything from scratch — or worse, doesn't, and pins a wrong D.

### Pattern: fact_store as the gril session's "evidence locker"

While gril is running, every "I just verified X" probe is **not** a permanent artifact by default — it lives in chat history and dies when the session ends. The durable record goes to `fact_store action='add' category='project'`:

- `project` category for technical / codebase facts (commit hashes, file paths, verified API behavior)
- `tool` category for tool-quirk facts (crypt function visibility, repl unbound behavior)
- `general` category for project-level facts (workflow, conventions)

When the gril session ends and the plan doc is `git status` clean, **the fact_store entries are the only durable record** of what was probed. That's why round-2 added 7 fact_id entries (17–24) before ending — without them, the next agent can't distinguish "D6 was a guess" from "D6 was verified by reading guix core install.scm:452".

### Round-2 mode-switching triggers (in addition to round-1's)

| User said | Mode |
|---|---|
| "继续向我提问吧" | back to ask-mode |
| "补吧,但我也没想着会用 installer" | ack + ask-mode (mixing answer + correction) |
| "重写" (in reply to "D5 理由重写么?") | ack + ask-mode (decision rewrite, not apply-mode) |
| "你直接写,验证完成之后将相关事实利用 `agenote` 进行记录" | **end-of-session mode**: apply-mode + cross-agent KB write |

That last trigger is the **end-of-session switch**: user said "你直接写" (apply) + "利用 agenote 记录" (cross-agent knowledge export). When the user mixes apply + cross-agent-export triggers, the session is ending — finish the apply, then export facts to `agenote` via `mcp_agenote_agenote_add`, then stop. Don't keep grilling.

## What round 2 adds to the protocol

1. **Fact probes can happen mid-grill, not just at step 1.** Round 2 caught wrong claims via `git clone + grep` that round 1 missed. The protocol isn't "all probes first, then questions"; it's "probe whenever an assertion would otherwise be guessed".
2. **Decisions can be *rewritten*, not just *added*.** When the user corrects the *reason* of a D, edit in place. New D-numbers are for new decisions.
3. **Ledger needs a destination.** This skill says "the ledger IS the output" but doesn't say *where*. Round 2 produced an explicit pattern: plan doc gets the human-readable D1–Dn with inline fact_id anchors; `fact_store` gets the verified probe transcripts; `agenote` gets the cross-agent-shared "what to do / what not to do" lessons. See updated step 9 below.

## Step 9 — Product exit (added after round 2)

The session produces three artifacts, each with a different destination:

| Artifact | Destination | Trigger |
|---|---|---|
| Plan doc edits (apply-mode patches) | Plan doc itself (working tree, no commit unless user says) | User trigger "改一下" / "落地一下" / "apply now" |
| Verified probe transcripts (1 per gril claim) | `fact_store action='add' category='project' \| 'tool' \| 'general'` | Each successful probe |
| Cross-agent-shared lessons (D-summary + pitfalls + anti-patterns) | `agenote` via `mcp_agenote_agenote_add` (entry type `mistake` / `note` / `ascended`) | End-of-session trigger "用 agenote 记录" or `agenote-review` skill auto-trigger |

**Don't collapse these three.** Each has a different audience: the plan doc is read by humans in the project; fact_store is read by future agents in the same session/agent; agenote is read by other agents (pi / crush / opencode / ...) and stays across machine moves.

The user's "你直接写,验证完成之后将相关事实利用 agenote 进行记录" maps cleanly: "你直接写" → apply-mode to plan doc; "利用 agenote 记录" → step 9's cross-agent export, NOT fact_store (which is the per-session record).

## Anti-patterns to avoid (observed across both rounds)

- ❌ Asking "应该用 XFCE 还是 minimal?" before knowing the user's *target* — both could be right depending on "desktop 用来干嘛"
- ❌ Asking "should we add kmscon?" — the right question was whether the user's target needs a tty1 fallback, not whether to add a specific service
- ❌ Treating the doc's `§0` decision list as authoritative — it was; the user had to correct it
- ❌ Letting the agent's own confidence shape the question — "guix 本身不自带 kmscon" was stated as fact, not as a guess; the user had to override the framing
- ❌ Assuming transitive claims from one source — "Testament README says X" does not mean "rosenthal upstream does X". Probe the actual layer.
- ❌ Adding D-number for a *reason* rewrite — use D-rewrite, not D-append
- ❌ Treating the ledger as the only durable record — without fact_store anchors, the next agent re-probes everything