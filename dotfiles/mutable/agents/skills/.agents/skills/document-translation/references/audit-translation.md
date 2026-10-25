# Audit & Repair an Existing Translation

Concrete recipes for fixing a translated document that already lives at
`tools/translated/<id>.zh.md` against a review list. Pair with the
workflow at the bottom of the parent SKILL.md §7.

## Recon: which slices actually need work

Don't trust a prior session's claim of "55/55 translated". Spawn these
checks before reading any audit list:

```python
import json, os
from pathlib import Path

base = Path("tools")
man = json.load(open(base / "manifest.json"))
translated_ids = sorted({c["id"] for c in man["chunks"] if c["status"] == "translated"})
on_disk = sorted({p.stem.replace(".zh","") for p in (base / "translated").glob("*.zh.md")})
print("manifest says translated:", len(translated_ids))
print("on disk:", len(on_disk))
print("orphan on disk:", set(on_disk) - set(translated_ids))
print("manifest says done but missing:", set(translated_ids) - set(on_disk))
```

The two sets should be identical. `orphan on disk > 0` usually means a
prior session translated a slice but never advanced `manifest.json`
(consult §4 in the parent skill on reconcile).

## Sweep for known-bad strings

After you have a hypothesis list, fan out the search across the whole
`translated/` corpus in one pass. Each line is a single `search_files`
call. Common offender categories:

| Category | Patterns (case-sensitive unless noted) |
|---|---|
| Syntax errors | `(use-service-module[^s]` (should be `modules`) |
| Stale 标题 | `Scheme 急就`, `客制化` |
| 误译 | `虚拟化项目` (likely `dummy project` not virtualization) |
| 叠字 | `的的`, `了了`, `的的的` |
| 中英混排 | `spurious\ 生成`, `wireguard\ VPN` (laptop doc wireguard → WireGuard) |
| Stale hostname | `https://ftpmirror\.gnu\.org`, `https://libgit2\.github\.com` |
| 残留占位 | `TODO REVIEW`, `XXX` (after deliberate removal) |
| Dead URL chars | `^https://\``, `https://[^ ]+\`` (markdown tail) |

`search_files(target="content")` with `path="tools/translated"` returns
path-grouped matches — one call surfaces every slice that needs touching.

## URL HEAD probe

For URL-validity audits, run a single Python pass with a generous timeout
and ignore unicode decode errors (Chinese closing punctuation gets
accidentally merged into URLs by `search_files`):

```python
import urllib.request, urllib.error, ssl
ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

def probe(u, timeout=8):
    req = urllib.request.Request(u, method="HEAD",
        headers={"User-Agent": "hermes-audit/1.0"})
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=ctx) as r:
            return r.status
    except urllib.error.HTTPError as e: return e.code
    except Exception: return None

# Build clean candidate list (not 96 of them; dedupe + strip markdown tails)
import re, json
urls = set()
for md in Path("tools/translated").glob("*.zh.md"):
    txt = md.read_text(encoding="utf-8")
    for m in re.finditer(r'https?://[^\s<>"\)\]\,;]+', txt):
        u = m.group(0).rstrip("。，；,;`').")
        if '.onion' in u or 'localhost' in u: continue
        if re.match(r'https?://\d+\.\d+\.\d+\.\d+', u): continue
        urls.add(u)

# HEAD each, GROUP BY status
from collections import defaultdict
buckets = defaultdict(list)
for u in sorted(urls):
    code = probe(u)
    buckets[code].append(u)
for c in sorted(buckets, key=lambda x: (x is None, x)):
    print(f"--- {c} ---")
    for u in buckets[c][:5]: print(" ", u)
    if len(buckets[c]) > 5: print(f"  ... and {len(buckets[c])-5} more")
```

Notable codes:
- **200 OK** — URL live
- **301/302 redirect** — usually fine; check the Location header for typos
- **403** — often legit (CDN anti-bot: fsf.org, linode.com,
  www.postgresql.org selects pages). Don't mass-flag.
- **404** — real rot. Fix it.
- **URLError / `ERR:*`** — DNS or unreachable. Confirm by `GET` if HEAD
  was suspicious (some servers reject HEAD for safety).
- **Anubis/JS challenge page** — domain resolves and trusts the URL
  format; cannot fetch but trust the URL.

## Field-shape comparison: zh vs en

For each slice with an audit claim like "frankly translated terms",
diff the relevant section textually against `tools/source/<id>.en.md`:

```python
def grep_pair(zh_id, en_id, pattern):
    zh = open(f"tools/translated/{zh_id}.zh.md").read()
    en = open(f"tools/source/{en_id}.en.md").read()
    for label, txt in [("EN", en), ("ZH", zh)]:
        for ln, line in enumerate(txt.splitlines(), 1):
            if pattern in line:
                print(f"{label}:{ln}: {line[:140]}")
```

Most audit claims about "wrong translation" can be closed by:
- Reading the surrounding English in `source/`
- Reading the official zh_CN version (when available, often in
  `Documents/GNU Guix 烹饪书.md` or similar offline copy)
- Checking `glossary.md` for any locked term

## SWHID / long-id validation

When an audit claims "this SWHID looks fake", don't trust the heuristics
(yes, real SWHID example values can look like placeholder octets
`8c8c8c8c`). Verify:

```python
import urllib.request, ssl
ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE
url = "https://archive.softwareheritage.org/swh:1:dir:<rest of SWHID>"
code, _ = probe(url, timeout=15)
# 200 with anti-bot challenge page = URL is well-formed and accepted
# 404 = SWHID is unknown to archive
```

Then **compare upstream** `source/<id>.en.md` to see if the same
placeholder-looking ID is verbatim in the English original. If yes, it's
the cookbook's deliberate example, not a translation bug — keep it.

## Multi-line string pitfall in `assemble.py`

If you add a `## 翻译说明` block to the assembler preamble, **never**
write:

```python
NOTES = ("- line 1"
         "- line 2"
         "- line 3")          # joins to "- line 1- line 2- line 3"
```

Use `"\n".join([...])` so each item is on its own line. Symptom in the
output file: all bullets concatenated to one paragraph. Verify by
`grep -A6 "翻译说明" output.md` returning the multi-line bullet list,
not a single run-on.

## Diff after every batch

After patching a batch and running `python3 tools/assemble.py`, run the
**reverse grep**: for each old string you wanted gone, confirm the
assembled output has zero matches.

```python
ex_stings = ["Scheme 急就", "客制化", "wireguard VPN", "spurious"]
for s in ex_stings:
    n = sum(1 for _ in open("guix-cookbook.zh.md", encoding="utf-8")
            if s in _)
    print(f"{n}  {s!r}")
```

`n == 0` for all of them is the acceptance signal. This is the same
reverse-grep pattern as §4.1 in the parent skill, but applied to the
audit fixes specifically.

## What NOT to do

- Don't `find -delete` translated files "to start clean" — you lose
  signal and break the assemble pipeline's expectations.
- Don't bulk-replace based on a single Chinese-EN paper — many audit
  suggestions are wrong; verify each against `source/`.
- Don't edit the assembled output. The reassemble wipes it.
- Don't commit the reassembled output file; commit the slices +
  `assemble.py`. The output regenerates.
- Don't add a new audit round unless the user asks for it. Polishing
  one fix at a time keeps the diff scannable.
