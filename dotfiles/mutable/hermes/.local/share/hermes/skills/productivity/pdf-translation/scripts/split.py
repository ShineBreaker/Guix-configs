#!/usr/bin/env python3
"""长 PDF → 增量翻译切片器。按字号定位标题（H1/H2 开新切片），正文用坐标裁剪提取以保留缩进。
用法：python3 split.py <pdf_path> <workdir>
阈值（字号/页码过滤）按具体 PDF 调整。"""
import fitz, re, json, os, sys, unicodedata

PDF = sys.argv[1] if len(sys.argv) > 1 else "guix-cookbook.pdf"
BASE = sys.argv[2] if len(sys.argv) > 2 else "translation"
for d in ["source", "untranslated", "translated", "archive"]:
    os.makedirs(os.path.join(BASE, d), exist_ok=True)

doc = fitz.open(PDF)
H1_FS, H2_FS = 17.2, 14.3   # 按实际聚类调整
TOC_END_PAGE = 6            # 目录到此页为止，之后才算正文标题

def is_heading(pg0, fs, txt):
    if pg0 + 1 < TOC_END_PAGE:
        return False
    if fs < H2_FS:
        return False
    t = txt.strip()
    if pg0 + 1 >= 117 and not re.match(r"concept\s+index", t, re.I):
        return False
    if len(t) <= 2 and t.isalpha() and pg0 + 1 >= 116:
        return False
    return True

headings = []
for pi in range(doc.page_count):
    d = doc[pi].get_text("dict")
    for b in d["blocks"]:
        if "lines" not in b:
            continue
        txt = " ".join(s["text"] for l in b["lines"] for s in l["spans"]).strip()
        maxfs = max((s["size"] for l in b["lines"] for s in l["spans"]), default=0)
        if is_heading(pi, maxfs, txt):
            r = b["bbox"]
            headings.append((pi, round(r[1],1), round(r[3],1), maxfs, txt, tuple(round(v,1) for v in r)))
headings.sort(key=lambda h: (h[0], h[1]))

def slugify(s):
    s = unicodedata.normalize("NFKC", s)
    s = re.sub(r"^Appendix\s+[A-Z]\s*", "appendix-", s, flags=re.I)
    s = re.sub(r"^Concept\s+Index", "concept-index", s, flags=re.I)
    s = re.sub(r"[^a-z0-9]+", "-", s.lower())
    return re.sub(r"-+", "-", s).strip("-")

def heading_id(t):
    t = t.strip()
    m = re.match(r"^(Appendix\s+[A-Z]|Concept\s+Index|\d+(?:\.\d+)*)\b\s*(.*)$", t, re.I)
    if m:
        pre, rest = m.group(1), m.group(2).strip()
        if pre.lower().startswith("appendix"): return "A-" + slugify(rest), 1
        if pre.lower().startswith("concept"):   return "concept-index", 1
        num = pre; level = num.count(".") + 1
        return f"{num}-{slugify(rest)}", level
    return slugify(t), 1

slices = []
for i, (pg0, ytop, ybot, fs, txt, rect) in enumerate(headings):
    hid, level = heading_id(txt)
    nxt = headings[i+1] if i+1 < len(headings) else None
    nxt_pg = nxt[0] if nxt else doc.page_count - 1
    nxt_ytop = nxt[1] if nxt else None
    parts = []
    p = pg0
    while p <= nxt_pg:
        page = doc[p]; W, H = page.rect.width, page.rect.height
        if p == pg0 and p == nxt_pg:   clip = fitz.Rect(0, ybot, W, nxt_ytop)
        elif p == pg0:                 clip = fitz.Rect(0, ybot, W, H)
        elif p == nxt_pg:              clip = fitz.Rect(0, 0, W, nxt_ytop) if nxt_ytop is not None else None
        else:                          clip = None
        seg = unicodedata.normalize("NFKC", page.get_text("text", clip=clip))
        if seg.strip(): parts.append(seg.strip())
        p += 1
    slices.append({"id": hid, "title": txt.strip(), "level": level,
                   "page_start": pg0+1, "page_end": (nxt_pg if nxt else doc.page_count-1)+1,
                   "body": "\n\n".join(parts)})

# 合并 FDL 附录页内同 L1 切片
merged = []
for s in slices:
    if merged and s["page_start"] >= 109 and s["level"] == 1 and merged[-1]["page_start"] >= 109 and s["id"] != "concept-index":
        merged[-1]["body"] += "\n\n" + s["body"]; merged[-1]["page_end"] = s["page_end"]
    else:
        merged.append(s)
slices = merged

manifest = {"src": PDF, "total": len(slices), "chunks": []}
for s in slices:
    fn = f"{s['id']}.en.md"
    hdr = f"<!-- id={s['id']} | title={s['title']} | pages={s['page_start']}-{s['page_end']} | level={s['level']} | status=pending -->\n"
    with open(os.path.join(BASE, "source", fn), "w", encoding="utf-8") as f: f.write(hdr + s["body"].strip() + "\n")
    with open(os.path.join(BASE, "untranslated", fn), "w", encoding="utf-8") as f: f.write(hdr + s["body"].strip() + "\n")
    manifest["chunks"].append({"id": s["id"], "title": s["title"], "level": s["level"],
                               "pages": [s["page_start"], s["page_end"]], "source": f"source/{fn}",
                               "status": "pending", "translated": None})
with open(os.path.join(BASE, "manifest.json"), "w", encoding="utf-8") as f:
    json.dump(manifest, f, ensure_ascii=False, indent=2)
print(f"切片总数: {len(slices)}  ->  {BASE}/")
