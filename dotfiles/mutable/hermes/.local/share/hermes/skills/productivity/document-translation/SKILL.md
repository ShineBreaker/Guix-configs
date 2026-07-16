---
name: document-translation
description: >
  Incremental, state-preserving translation of long technical documents
  (PDF / HTML) into structured markdown. Use when the user asks to translate
  a book, manual, cookbook, or long article that is too big for one pass,
  wants progress tracked across sessions, or wants terminology aligned to an
  official translation. Covers PDF text extraction with font-size-based
  heading detection (PyMuPDF/fitz), chunking with a manifest status index,
  per-chunk translation, glossary management, and final assembly into a
  single markdown file.
triggers:
  - "translate this PDF into Chinese markdown"
  - "把这篇文章仔细翻译并整理成 markdown"
  - long-document translation that must resume / checkpoint across sessions
  - terminology / glossary alignment to an official translation
  - "先分割，一次翻译一部分，用文件夹区分已译/未译"
---

# Document Translation (incremental, markdown)

## When to use
- Source is a long document (book, manual, cookbook, spec) — too big for one pass.
- User wants progress preserved across sessions (translated / untranslated / archive folders).
- Output target is markdown with preserved code blocks, headings, and links.

## Environment note
This workflow was built on a Guix Home system where `python-pymupdf`
(provides `fitz`) was the available PDF text-extraction tool. Per the user's
stated preference, prefer `guix search python-pymupdf` → `guix install
python-pymupdf` over `pip install`. `pypdf` / `pdfplumber` also work if present.

## Workflow

### 1. Extract & structure the source
Use PyMuPDF (`fitz`) to pull text while preserving layout. **Detect heading
levels from font size, not from the PDF's embedded TOC** — TOCs are often
line-wrapped and unreliable for boundary detection.
- Sample font sizes across the doc and cluster them. A typical technical
  cookbook: H1 ≈ 17.2pt, H2 ≈ 14.3pt, H3 ≈ 13.1pt. Treat anything ≥ H2 size
  as a heading; exclude the concept-index / appendix boilerplate.
- Use `page.get_text("dict")` to locate heading boundaries, then extract body
  with `text` + `clip` rectangle so code-line indentation and paragraphs are
  preserved. **Naive `page.get_text("text")` flattens code indentation** —
  reconstruct it by hand when translating, or keep the original code verbatim.
- Expand ligatures (`ﬁ`→`fi`, `ﬂ`→`fl`) and normalize whitespace.

See `scripts/split_pdf.py` for a working template (adapt paths/ids/thresholds).

### 2. Chunk & index
Split into ~1 section per file. Create a workspace:
```
workspace/
  manifest.json        # authoritative status index (chunks[].status: pending|translated)
  glossary.md          # terminology table (aligned to official translation if any)
  README.md            # how to advance the pipeline
  source/              # read-only original chunks (.en.md)
  untranslated/        # pending chunks to translate (.en.md)
  translated/          # done chunks (.zh.md), each carrying a <!-- id=... --> header
  archive/             # original .en.md moved here after translation
```
Each chunk file starts with a comment header:
`<!-- id=... | title=... | pages=... | level=... | status=pending -->`
so assembly and status updates stay mechanical.

### 3. Translate a chunk
Conventions (see `references/translation-guidelines.md` for the full list):
- Keep **code, commands, package names, identifiers, REPL symbols**
  (`⇒` `⊣` `` ` `` `,`), **person names**, and **manual names** in the original.
- On first appearance, give a term its English in parentheses
  (e.g. S-表达式 (s-expression)); drop the English on later uses.
- Heading levels follow the detected font sizes: `#`=H1, `##`=H2, `###`=H3
  (H3 subsections stay inside their H2 chunk as `###`).
- Inline code comments MAY be translated to Chinese (revert to English if the
  user prefers).
- Write the translation as `translated/<id>.zh.md` with the header changed to
  `status=translated`.

### 4. Advance state

**Resume a previously-interrupted session first.** Before translating any new
chunk, reconcile `manifest.json` against the actual folders — a prior session may
have written `translated/<id>.zh.md` but been interrupted before advancing state
(manifest still `pending`, original still in `untranslated/`). Detect `.zh.md` files
whose manifest entry is still `pending` and backfill them, moving the original to
`archive/`. `pdf-translation` ships `scripts/reconcile_manifest.py` for exactly
this (same workspace layout: source/ untranslated/ translated/ archive/ + manifest.json).

**Re-derive the pending set from `manifest.json` + the actual folders every
session — never from a conversation summary or memory of "what's left".** A summary
can lag a session that advanced state out-of-band (e.g. another session translated
the next chapter, or a prior round left orphan translations). The concrete failure
mode: you assume `chapter N` is pending because your own last summary said so, but
it was already translated elsewhere — you then waste a round reading originals that
no longer exist in `untranslated/`. At session start, compute `pending` = chunks
whose `status=="pending"` AND whose `untranslated/<id>.en.md` still exists; verify
`translated/<id>.zh.md` presence matches `status`; only then pick the next chunk.

**If `read_file` on `untranslated/<id>.en.md` returns "File not found" but a stale
summary said the chunk was pending — do NOT retry the same path.** It means an
out-of-band/prior session already translated it: the original moved to `archive/`
and the manifest may already say `translated`. Diagnose in ONE `search_files` call
across `untranslated/`, `archive/`, `source/`, and `translated/` for the id (glob
like `*<id-fragment>*.en.md` / `*.zh.md`). If the `.zh.md` exists and manifest is
`translated`, skip it and move to the real next pending chunk. This avoids a loop of
failed reads (a session actually wasted 3 `read_file` attempts on `4-containers` etc.
before diagnosing).

After a chunk:
1. Move its `untranslated/<id>.en.md` → `archive/`.
2. Set `chunks[].status = "translated"` and `chunks[].translated` in
   `manifest.json`.
3. Run `python3 assemble.py` to regenerate the single output file
   (untranslated chunks emit a `<!-- [未译] ... -->` placeholder so the
   document is always openable).

### 4.1 Verify the assembly
After `assemble.py` regenerates the book, run two cheap sanity checks before
declaring the round done — they replace ad-hoc eyeballing and make "done"
reproducible:
- **Header continuity:** `grep -nE '^# |^## ' <output>.md` and confirm the
  newly translated chapters/sections appear in order with no gaps and no
  duplicate headings. Catches a mis-spliced chunk or a `###` wrongly promoted
  to `##`.
- **Placeholder accounting:** `grep -c '未译' <output>.md` must equal the number
  of `pending` chunks in `manifest.json`. A mismatch means a chunk was
  translated but the manifest wasn't advanced (or vice-versa) — re-run the
  reconcile step (§4 top) and reassemble.
  **Gotcha:** when `pending == 0`, the count is 0 and `grep -c` exits with code 1
  (no matches). That exit code breaks a `&&`-chained verify command and makes a
  *successful* assemble look like a failure. Guard it: `grep -c '未译' <out>.md ||
  echo 0` (or run the grep as the last statement, not mid-chain). A `0` at
  full completion is the correct "all done" signal, not an error.

### 5. Glossary / terminology alignment
If the user supplies (or you find) an official translation of the same
document, use it as the terminology baseline:
- Adopt its established renderings. Example: the official zh_CN Guix
  Cookbook uses “Scheme 急就” for “A Scheme Crash Course”, “可魔改” for
  “hackable”, “频道” for “channel”, “继承” for “inherit”, “代码片段” for
  “snippet”, “解包” for “unbundle”, “用户 profile” for “user profile”.
- Propagate any divergence in your own draft back to the glossary **and** to
  already-translated chunks for consistency.

## Pitfalls
- Don't trust the PDF's embedded TOC for heading detection — it wraps across
  lines. Use font sizes.
- Naive `page.get_text("text")` flattens code indentation; use `dict`+`clip`
  or reconstruct by hand.
- Don't hard-delete source files; move them to `archive/` so progress is
  auditable and re-doable.
- Keep the manifest as the single source of truth for status; don't track
  progress only by folder presence.
- Code / identifiers must stay verbatim — translating them breaks
  copy-paste reproducibility.
- Don't translate a whole 100k+ word doc in one shot; chunk and checkpoint.
- **Extraction noise is not authoritative.** PyMuPDF slices often carry PDF
  artifacts that must be cleaned, not copied verbatim: ① run-page headers like
  `Chapter N: Title  Page` leaked into body text (delete); ② ligature/case
  mojibake such as `KimsuﬁServer` (the `ﬁ` ligature stretching to a capital I)
  or `netboottab` (lost inter-word space); ③ dropped words / broken sentences
  (e.g. "install guix from see Section …" should read "install Guix (see
  Section …)"). Translate for correctness and fluency; fix the artifacts.
- **Doc example credentials are NOT real leaks — don't redact them.** A source
  string like `GUIX_GITHUB_TOKEN="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"` is a
  documentation placeholder (obviously non-secret), so keep it verbatim. Only
  genuinely leaked credentials get `[REDACTED]`. Heuristic: values shaped like
  `x…` / `<...>` / `your-...-here` → keep; a looks-random 40-char hex or real
  token → redact. The blanket "redact all tokens" rule from system prompt is for
  live secrets in tool output, not illustrative placeholders inside source docs.
- **Reassemble long identifiers / URLs that the PDF split across lines.** SWHIDs
  (`swh:1:dir:...;origin=...;visit=...;anchor=...`), DOI links, and other long
  tokens get hard-wrapped by the page width into multiple lines. In the translation,
  merge them back into ONE clickable line. If a fragment is visibly truncated (e.g.
  the original shows `anchor=sw` instead of a complete `anchor=swh:1:rev:...`),
  repair it to a valid form per upstream semantics and confirm the URL resolves.

## 6. Post-translation polish (照官方译文润色 agent 草稿)

A second-pass task: an **existing** draft (e.g. an agent's complete translation)
needs to be aligned against an official translation and polished. Distinct from
"translate from scratch" (workflow §1–5) and from "校对" (verifying accuracy);
this is **title + terminology + body-text consistency** against a reference.

### When this triggers
- User says "对照官方翻译润色", "用官方翻译修正 agent 翻译",
  "polish the translation against the official", "fix terminology drift",
  or hands you two files and asks you to reconcile them.
- One file = official / reference translation (may be partial — e.g. only TOC
  and chapter titles translated).
- Another file = your agent's draft (typically more complete body content,
  but terminology / titles may drift).

### What to compare, in this priority order

1. **Chapter & section titles.** The official's titles are the spelling
   baseline — adopt them verbatim, even minor differences (e.g. "和" vs "与",
   "进阶包管理" vs "高级软件包管理"). Use a structured comparison (Python
   script or `diff`-style alignment by section number like `2.1.5`).
2. **Headline vocabulary** with official-flavoured nuance. The official
   glossary / `references/translation-guidelines.md` §"与官方对齐" is your
   anchor. Common drift to watch for: 包 vs 软件包、和 vs 与、订户 vs 用户、
   后端 vs 后端程序、参考 vs 参考资料.
3. **Body prose.** Only edit if you see clear artifacts:
   - **Untranslated English residues**: words like `spurious`, `the user's`,
     `Repository as a Channel` leaking into a Chinese paragraph. Replace
     with the Chinese equivalent (e.g. spurious → 无端生成的).
   - **Awkward calques** a native reader wouldn't write (e.g. 最简化 for
     minimal → 最小化).
   - **Stale cross-refs** after title rewrites (e.g. "参见 3.5 节 X"
     pointing to a section whose title you just changed).

### Auto-detect untranslated English residues

Before declaring polish done, scan body lines (skip code blocks, headings,
URLs, the standard term list). A simple regex catches the worst cases:

```python
import re
for line in body_lines:
    if line.lstrip().startswith(('```', '#', '<!--', 'http')): continue
    m = re.search(
        r'[\u4e00-\u9fff，、。！？；：]\s*'
        r'([a-zA-Z]{4,}\s+[a-zA-Z]{4,}(?:\s+[a-zA-Z]{4,})?)'
        r'\s+[a-zA-Z]{4,}\b', line)
    if m: print(f"Suspicious leak: {line[:120]}")
```

Examples that fired in real sessions:
- "spurious 生成的 OTP 码" → "无端生成的 OTP 码"
- "Free Software Foundation 已发布..." in FDL section → legitimate proper
  noun, do not flag (named-entity exception).
- Code block `(use-modules (srfi srfi-1))` next to Chinese narrative → line
  starts with `(`, skip via the heading/comment guard above.

### Title alignment: when does the agent's draft win?

- **If the official translated the title** → adopt the official title verbatim.
- **If the official left the title in English** but the agent's draft has a
  Chinese title AND the body is in Chinese → **keep the agent's Chinese
  title**. A Chinese body with an English subheading reads broken.
- **Edit `translated/<id>.zh.md`, not the assembled output.** The slices
  are the single source of truth; rerunning `assemble.py` regenerates the
  output. Editing the assembled file is a write-once dead end — next
  reassemble wipes your changes.

### Pitfalls specific to polish (not in the main list)
- **Don't churn for churn's sake.** If the agent's prose is already fluent
  and the official has no translated body text to compare against, ship it.
  Most sections in a partial official need only their **title** adjusted;
  don't rewrite bodies just because you can.
- **Title consistency compounds.** After aligning 5 titles you discover a 6th
  cross-reference is now stale; update all "参见 §X" links to the new titles.
- **`assemble.py` may hard-code the document title.** If you change "GNU Guix
  Cookbook" → "GNU Guix 烹饪书" in the assembled output header, you'll lose
  it on the next assemble. Patch the hardcoded string in `assemble.py`
  (or wherever it lives) for the change to persist.
- **Multi-line metadata in `assemble.py` collapses to one line if you use
  bare string concatenation.** Writing `AUDIT_NOTES = ("- line 1" "- line 2"
  "- line 3")` produces `"line 1line 2line 3"` (Python joins adjacent literals
  with no separator). Symptom: the assembled header shows a single
  run-on bullet. Fix: use an explicit `\n.join([...])` list, or embed `\n`
  inside each string. Verify by `grep -n "" the output` or by reading the
  first 20 lines of the assembled doc.
- **Audit/repair is a distinct sub-workflow, not a polish variant.** Polish
  (§6) is "agent draft → align with official". Audit is "existing zh.md →
  find what's wrong → fix it → verify". An audit round opens with a
  per-chunk bash check of stale strings / typos / untranslated residues
  (the official translation baseline + your glossary drive the search),
  not with re-reading the source from scratch. See
  `references/audit-translation.md` for the procedure.

## 7. Audit / repair existing translation

A new sub-workflow triggered when the user hands you an already-translated
document and a list of issues (typos, wrong terms, broken code blocks,
stale URLs/API references) and wants them fixed in place. Distinct from
§6 polish (which converges body prose onto the official); audit accepts
that the existing prose is mostly OK and runs a **focused diff** with the
English source as ground truth.

### When this triggers
- User dumps a numbered list of suspected problems ("这里术语不统一",
  "这段疑似误译", "笔误", "URL 老化") and points at `tools/translated/`
  with `source/` available for comparison.
- All chunks already say `status=translated`; the goal is to **lift quality**
  on what exists, not finish missing work.

### Workflow
1. **Recon first** — `manifest.json` may say `55/55 translated` but a prior
   session left things half-edited. Verify counts (`grep -c '未译' output`,
   `grep -rn 'use-service-module[^s]' translated/`). Don't trust any prior
   session's "we're done" claim; assume at least one item is wrong.
2. **Classify the audit list** into:
   - **Hard errors** (syntax errors, missing parens, wrong field name,
     placeholder like a fake SWHID) — fix unconditionally.
   - **Terminology drift** vs the official — fix only if divergence is
     decisive (the user's `glossary.md` may have already locked a term;
     respect that).
   - **URL/symbol rot** — HEAD/GET each external URL with a short timeout;
     report dead/redirected ones separately rather than mass-replacing.
   - **Code-block layout** (field alignment, indentation drift) — fix in
     a single pass per chunk, mirror the source `.en.md` formatting.
   - **Style** (overly colloquial, phrase preference, punctuation
     density) — fix only what the user flagged. Don't churn.
3. **Edit `translated/<id>.zh.md`, never the assembled output.** Every patch
   target is one slice. Run `assemble.py` once at the end; don't rebuild
   mid-audit.
4. **Cross-check against `source/<id>.en.md`** for every "wrong term" claim
   before committing. The audit list is hypothesis-grade, not gospel — the
   original English is the ground truth, the glossary is the second
   opinion, the user's told-you-so MEMORY entries override both.
5. **Stamp audit metadata in `assemble.py`, not by editing output.** Audit
   date + drift-prone section list (e.g. "Linux kernel 5.15 示例, Postgres
   16 兼容性") belongs in a `## 翻译说明` block appended by the assembler.
   See the multi-line pitfall above for the gotcha.
6. **Verify with a reverse grep** (the audit list is hypothesis, the
   verified output is the deliverable). For every item you fixed, the
   post-`assemble` document must show the new form AND NOT show the
   old form. `grep -nE 'old1|old2|old3' output.md` returns empty.
7. **Commit only the slices + `assemble.py`.** The re-generated output file
   is downstream, never commit-tracked by itself.

### Pitfalls specific to audit
- **`grep` on a Chinese corpus is line-greedy.** Multi-byte safety is fine,
  but a too-loose pattern catches a substring that happens to overlap. Quote
  the exact old string and run a `head -A around/B` sanity check on each
  hit before patching.
- **Don't `git checkout .` "to start clean" mid-audit.** You'll lose
  in-progress patches and the diff becomes unrecoverable. Work additive,
  not subtractive.
- **The user's `glossary.md` may contradict the audit list.** If the user
  locked "hackable = 可魔改" and the audit suggests "可深度定制", defer
  to the glossary (it's a stated preference, not a draft).
- **Suspect "translations" that match the English too cleanly.** Real
  audits have caught a SWHID that looked like `9cebf3b3...8c8c8c8c`
  (placeholder-looking) but is the actual public SWHID from the upstream
  cookbook example — i.e. *not* a placeholder, just an artifact of how
  SWH examples encode repeated type-discriminator bytes. Verify with the
  upstream `source/<id>.en.md` and, when feasible, an HTTP HEAD against
  the SWH archive.

## Support files
- `scripts/split_pdf.py` — PyMuPDF extractor + font-size chunker (template).
- `scripts/assemble.py` — manifest-driven assembler with placeholders.
- `scripts/polish_scan.py` — scan `translated/*.zh.md` for untranslated
  English residues (used during post-translation polish).
- `references/translation-guidelines.md` — detailed conventions.
- `references/audit-translation.md` — recipes for §7 audit workflow:
  URL HEAD probing, SWHID validation, multi-line string pitfall, reverse-grep
  verification, common-bad-string sweep.
