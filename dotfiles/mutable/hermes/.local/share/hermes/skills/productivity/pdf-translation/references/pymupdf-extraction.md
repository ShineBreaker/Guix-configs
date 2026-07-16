# PyMuPDF 提取技术细节

环境：Guix Home，`python-pymupdf`(提供 `fitz`)。正文提取用系统 Python 跑脚本文件，
**不要**用 execute_code —— 它的 sandbox Python 不含 `fitz`。

## 标题层级：用 dict 模式检测字号
```python
import fitz, unicodedata
doc = fitz.open("book.pdf")
blocks = []
for pi in range(doc.page_count):
    d = doc[pi].get_text("dict")
    for b in d["blocks"]:
        if "lines" not in b: continue
        txt = " ".join(s["text"] for l in b["lines"] for s in l["spans"]).strip()
        maxfs = max((s["size"] for l in b["lines"] for s in l["spans"]), default=0)
        if txt:
            blocks.append((pi, round(b["bbox"][1],1), maxfs, txt))
# 聚类字号：17.2=章 14.3=节 13.1=小节 9~10.9=正文（具体值因书而异）
```

## 正文：用坐标裁剪 text+clip（保留缩进）
dict 会把一个代码块的所有 span 拼成一行 → 缩进丢失。**改用 text+clip**：
```python
# headings 已按 (page, y0_top, y1_bottom) 排序
for i, (pg0, ytop, ybot, fs, txt, rect) in enumerate(headings):
    nxt = headings[i+1] if i+1 < len(headings) else None
    nxt_pg  = nxt[0] if nxt else doc.page_count - 1
    nxt_ytop = nxt[1] if nxt else None
    parts = []
    p = pg0
    while p <= nxt_pg:
        page = doc[p]
        W, H = page.rect.width, page.rect.height
        if p == pg0 and p == nxt_pg:
            clip = fitz.Rect(0, ybot, W, nxt_ytop)
        elif p == pg0:
            clip = fitz.Rect(0, ybot, W, H)
        elif p == nxt_pg:
            clip = fitz.Rect(0, 0, W, nxt_ytop) if nxt_ytop is not None else None
        else:
            clip = None
        seg = page.get_text("text", clip=clip)
        seg = unicodedata.normalize("NFKC", seg)   # 展开 ﬁ/ﬂ
        if seg.strip():
            parts.append(seg.strip())
        p += 1
    body = "\n\n".join(parts)
```

## 过滤误判标题
- 索引页（如 page>=117）除 "Concept Index" 本身外，不识别为标题（单字母 A/B/C、或 "2FA" 条目会被字号误判）。
- 长度 ≤ 2 的纯字母块，且位于后部索引区，跳过。
- FDL 附录的 "Addendum" 大标题若落在附录页内，并入同一 L1 切片。

## 边界坑
- 末片无下一标题：`nxt_pg = doc.page_count - 1`，`nxt_ytop = None` 时整页提取（`clip=None`）。
- 同页多个标题：切片正文区间 = [本标题底, 下一标题顶)。
