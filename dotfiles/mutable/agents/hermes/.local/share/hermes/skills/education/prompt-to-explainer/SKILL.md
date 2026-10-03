---
name: prompt-to-explainer
description: Pick text, diagram, HTML, or video to explain a topic.
version: 0.1.0
author: Hermes
metadata:
  hermes:
    tags:
      - Explanation
      - Prompting
      - Format Selection
---

# Prompt to Explainer

Helps pick the output form an LLM should produce when the goal is understanding rather than answering: plain prose, a diagram, an interactive HTML page, or a custom explainer video. It also supplies the controlled-language rewrite (ASD-STE100) that keeps prose tractable, and routes execution to the skills that already build the heavy artifacts.

What it does NOT do: it renders nothing itself, calls no TTS or video tool directly, and does not replace `/show-me`, `/eli5`, `/md2html`, `/faceless-explainer`, or `/technical-explainer-video` — it decides which of those to invoke and how to phrase the ask.

Dependency stance: no new packages, no vendor clients (the HyperFrames CLI runs via `npx`; TTS is owned by the media skills). Uses only local skills plus `terminal`.

## When to Use

- User asks to "explain X", "break down X", "help me understand X", "what does this output mean"
- A model's answer is dense prose the user has to re-read, or an abstract system description that resists parsing
- User wants an explainer video, diagram, or interactive page and did not name a format
- User asks to tighten or clean up model-generated prose ("explain it in STE", "make it readable")
- Plain prose already failed and the user asks for something more visual or concrete

## Prerequisites

None for prose and diagrams. The HTML and video paths need the local skills named in "How to Run" — those own their own prerequisites (`npx`, TTS credentials, ffmpeg).

## How to Run

Two moves, always in this order: **pick the form**, then **write the ask**.

1. Pick the form with the ladder in "Procedure" step 2 (cost is monotonic: prose < diagram < HTML < video).
2. Write the ask with a template from "Quick Reference".
3. Heavy artifacts are dispatched to the existing skill rather than built ad hoc — see the routing table.

Routing (delegate, do not re-implement):

| Requested form | Route to |
| --- | --- |
| In-chat diagram or HTML sketch of the current topic | `/show-me` |
| Dead-simple picture explainer for a novice | `/eli5` |
| Markdown doc (plan, spec, notes) rendered as a page | `/md2html` |
| Video explainer with no source footage | `/faceless-explainer` |
| Technical or mechanism explainer video (inputs, process, evidence) | `/technical-explainer-video` |
| Anything video, or any ambiguity at all | `/hyperframes` — the intent layer owns the route decision |

## Quick Reference

Prompt templates (fill `X`, paste into the model as-is):

| Goal | Prompt shape |
| --- | --- |
| Plain prose, tightened | `Explain X in ASD-STE100.` |
| Prose, softened spec | `Explain X in ASD-STE100, but only about 80% of the way to the spec.` |
| Diagram | `Draw the flow of X as a diagram. Do not write prose around it.` |
| Interactive page | `Explain X as a single self-contained HTML page: no build step, no external assets.` |
| Explainer video | `Create a 3b1b-style video explainer on X. Use my ElevenLabs API key for narration audio.` |

ASD-STE100 numbers worth quoting back at the model: 53 writing rules, ~900 approved words, sentences <= 20 words (procedures) and <= 25 words (descriptive), one instruction per sentence, paragraphs <= 6 sentences, active voice, imperative for procedures, no contractions, American spelling. Rule numbers and sources are in `references/asd-ste100.md` — load it with `skill_view(name="prompt-to-explainer", file_path="references/asd-ste100.md")` when a rule citation is needed.

## Procedure

1. **Name the comprehension task before choosing a format.** One sentence, out loud: "the user needs to understand ___." A format chosen without this sentence is decoration. If the task cannot be named, ask — do not default to video.

2. **Climb the form ladder; stop at the first form that carries the answer.**

   | # | Form | Choose when | Skip when |
   | --- | --- | --- | --- |
   | 1 | Prose in a controlled language | The answer is a sequence of facts, definitions, or steps a reader must check item by item | The concept is spatial, causal, or multi-branch — words degrade fast there |
   | 2 | Diagram | There is structure to see: flow, hierarchy, dependency, state, geometry, before/after | The steps are inherently sequential and short |
   | 3 | Interactive HTML page | The user needs to poke at it: parameters, toggles, hover detail, a small simulation | The point survives as a static picture |
   | 4 | Explainer video | The topic has a time dimension, a build-up order, or a hook meant for handing to someone else | Forms 1-3 already answer the question |

   Two rungs can be combined in one pass (a script in STE plus a diagram), but never skip from prose to video without first asking what a diagram would have failed to show.

3. **Write the ask with a target, not a topic.** Every request names four things: audience, output artifact (file, page, video), what must be *visible* in it, and what to leave out. "Explain gradient descent" is a topic; "self-contained HTML page on gradient descent, audience: new ML engineer, must show one update step on real numbers, no chain-rule derivation" is a request.

4. **For prose, ask for the controlled language first, then relax if needed.** Request full ASD-STE100; if the result reads clipped, ask for a stated relaxation ("80% of the way to STE: keep sentence length and one idea per sentence, allow normal phrasing"). Pick one relaxation and name the rules that survive — do not renegotiate the rule set item by item.

5. **For diagrams and pages, constrain the shape so the model cannot hide in prose.** Demand an artifact (a file), state the required elements, forbid the fallback ("if the diagram needs paragraphs to explain it, the diagram failed"). Then verify the artifact exists and open it.

6. **For video, hand off instead of building.** Name the topic, the style reference, and where narration comes from. `Create a 3b1b-style video explainer on X. Use my ElevenLabs API key for narration audio.` is the canonical shape. When no key is available, ask the model for a local no-key narration option rather than silently producing silent output. Dispatch to `/faceless-explainer` or `/technical-explainer-video`; ambiguous requests go through `/hyperframes` first.

7. **Verify the deliverable, not the intent.** A claimed HTML page or MP4 must be opened and inspected at a real path, not accepted because the reply described it. A diagram the model "would show" is not a deliverable.

## Pitfalls

- **Video as the default.** It is the most expensive rung and the hardest to revise; reach for it only for time-ordered, hand-off-able, or emotionally pitched topics.
- **Under-specified asks produce walls of prose.** No audience, no visible-content requirement, no output artifact — the word "diagram" alone does not stop an essay.
- **Full STE on Chinese output.** STE is an English controlled language; for Chinese, ask for the equivalent discipline (short sentences, one idea per sentence, no hedging) rather than applying English word lists.
- **Silent video.** A video requested with narration but produced without audio is broken. State the narration source (key or local engine) and confirm an audio stream exists.
- **Treating a rendered page as verified.** Check the file exists and that what was asked to be visible is actually in it.
- **Discardable artifacts are the point.** These outputs are cheap to make and cheap to throw away; do not raise the stakes by promising to maintain, publish, or iterate on them.
- **The abbreviation trap.** "STE" also reads as the Simplified Technical English acronym in aerospace tooling contexts; when the audience is ambiguous, spell out ASD-STE100 in the prompt.

## Verification

One check per artifact type:

- Prose or diagram: every sentence is <= 20 words (procedures) or <= 25 words (descriptive) and carries one idea; no sentence needs a second reading.
- HTML: `terminal` runs `python3 -c "import pathlib,sys; p=pathlib.Path(sys.argv[1]); assert p.exists() and p.stat().st_size>0; assert b'<html' in p.read_bytes()[:512]" <file.html>`, then open the file and confirm the required elements are visible.
- Video: the MP4 exists at the stated path, has non-zero duration, and carries an audio stream.
