---
name: doc-audit
description: "Audit and simplify documentation across a multi-file codebase. Use when the user says '遍历文档检查是否反映最新状态' / '简化 AGENTS.md' / '文档校对' / '检查文档一致性' / '清理冗余文档'. Covers three axes — existence (do claimed paths/packages/files exist?), consistency (do docs agree with each other and with actual code?), and redundancy (can content be pointerized?). Produces a structured audit report with every fix traced to ground truth."
version: 0.1.0
license: MIT
metadata:
  hermes:
    tags: [doc-review, doc-simplification, cross-doc-consistency, agents-md, audit]
    related_skills: [doc-engineering, skill-authoring]
---

# Document Audit

Systematic audit + simplification of documentation across a codebase.
Three axes, one report, every fix traced to ground truth.

## 1. When to fire

- User says "遍历文档 / 检查文档是否还在 / 文档校对 / 简化 X / 文档一致性"
- User opens a session involving docs that haven't been verified in >30 days
- After adding/removing files, packages, or adapters that multiple docs reference

## 2. Three-axis audit protocol

### 2.1 Existence (存在性)

For every file path, package name, adapter name, or CLI command claimed in a doc:

```bash
# Verify file exists
search_files pattern=<claimed-path> target=files

# Verify package exists (Guix)
guix search <package-name>

# Verify adapter/config exists
find <config-dir> -name "<name>.*"
```

**Common failures**:
- Doc lists `nftables.conf` / `zed.json` but `source/files/` doesn't have them
- Doc lists `pi.json` adapter but `adapters/` only has `omp.json`
- Doc references a `pi` package under `dotfiles/mutable/` but no such directory exists

### 2.2 Consistency (一致性)

For every entity described in multiple docs, verify they agree:

| Check | Method |
| ----- | ------ |
| Desktop environment | `docs/iso-build.md` §2.6 vs §1.2 — which DE does the actual ISO use? |
| Display manager | Same doc, D5 row says "sddm" but §1.2 says "lightdm" |
| Service operations | D6 says "add kmscon" but §3.7 says "delete kmscon" |
| Adapter names | `docs/loopctl.md` lists `pi.json` but actual dir has `omp.json` |

**Rule**: When docs disagree, the actual code/config is ground truth. Patch the doc, not the code.

### 2.3 Redundancy (冗余性)

For every paragraph in an AGENTS.md, ask: "Can an AI get this from another source?"

| If... | Then... |
| ----- | ------- |
| A scheme code block repeats a config that has its own doc | Replace with pointer to that doc |
| A paragraph summarizes another AGENTS.md | Replace with pointer to that AGENTS.md |
| A description is an oral summary of a code block in `source/config.org` | Replace with pointer to the code block |

## 3. AGENTS.md simplification rules

### 3.1 What to keep

- Task routing tables (the core value of AGENTS.md)
- `<critical>` hard constraints
- `<!-- structor:begin -->...<!-- /structor -->` marker pairs
- Pointers to other docs (these ARE the content)

### 3.2 What to delete

- Full scheme code blocks that repeat `source/config.org` declarations
- Detailed descriptions of systems that have their own AGENTS.md (Emacs, agents, etc.)
- Dead references to files/packages/adapters that no longer exist
- Duplicate paragraphs that overlap with sibling docs

### 3.3 Replacement pattern

```
Before:
```scheme
(service home-dotfiles-service-type
  (home-dotfiles-configuration
   (directories '("../dotfiles/immutable"))
   ...))
```

After:
"详细配置（directories / layout / packages / excluded）见 `dotfiles/AGENTS.md`。"
```

## 4. 80-column hard wrap cleanup

**Rule**: Markdown source files do NOT enforce 80-column line breaks. GUI renderers show no visual benefit, and hard wraps make `patch` fuzzy matching harder and source files harder to edit.

**Detection**:
```bash
search_files pattern="^.{80,}$" target=content file_glob="*.md"
```

**Fix**: Merge hard-wrapped lines back into natural paragraphs. Preserve tables, code blocks, lists, and structured content.

## 5. Audit report format

Produce a structured report with three sections:

### 5.1 Fact fixes
| File | Line | Error | Fix | Evidence |
| ---- | ---- | ----- | --- | -------- |

### 5.2 Redundancy cleanup
| File | Removed | Replaced with |
| ---- | ------- | ------------- |

### 5.3 Consistency fixes
| Documents | Disagreement | Ground truth | Unified to |
| --------- | ------------ | ------------ | ---------- |

## 6. Pitfalls

- **Don't trust doc-copy verbatim.** A doc may already be wrong. Verify against actual files/code.
- **Don't delete structor markers.** They are auto-maintained by `blue structor`.
- **Don't delete routing tables.** They are the core value of AGENTS.md.
- **Don't patch code to match docs.** When docs disagree with code, the code wins.
- **Don't use `clarify` for "which doc to edit".** The user's ask is clear: audit all docs and fix them.

## 7. Verification

After all fixes:
1. Re-run existence checks on all modified docs
2. Re-run consistency checks across all doc pairs
3. Confirm no structor markers were damaged
4. Confirm routing tables are intact

## References

- `references/doc-audit-protocol.md` — extended protocol with real-session examples (2026-07-27)
