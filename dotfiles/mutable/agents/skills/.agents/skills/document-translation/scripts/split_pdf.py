#!/usr/bin/env python3
"""Template: extract a PDF into font-size-clustered markdown chunks.

Adapt PATHS, the id/title map, and the font-size thresholds to your doc.
Key lessons (see SKILL.md):
  - Detect headings by FONT SIZE, not by the PDF's embedded TOC (unreliable).
  - Use page.get_text("dict") to find heading boundaries, then extract body
    with text+clip to preserve code indentation. Naive "text" flattens it.
  - Expand ligatures (fi/fl) and normalize whitespace.
"""
import fitz  # python-pymupdf (guix install python-pymupdf)

SRC_PDF = "/path/to/source.pdf"
OUT_DIR = "/path/to/workspace/source"

# Font-size thresholds (sample your doc first; a cookbook: H1~17.2, H2~14.3, H3~13.1)
H1 = 16.5   # >= this => chapter (level 1)
H2 = 14.0   # >= this => section (level 2)
H3 = 12.8   # >= this => subsection (level 3)

def analyze_sizes(doc):
    """Sample all font sizes to pick thresholds."""
    from collections import Counter
    c = Counter()
    for p in doc:
        for b in p.get_text("dict")["blocks"]:
            for l in b.get("lines", []):
                for s in l["spans"]:
                    c[round(s["size"], 1)] += 1
    return c.most_common(20)

def main():
    doc = fitz.open(SRC_PDF)
    # 1) find chapter/section starts by scanning for large-font spans
    # 2) for each such boundary, extract the span's text as title + the
    #    body from that point until the next boundary, using text+clip.
    # 3) write <id>.en.md with the status header comment.
    # (Concrete boundary logic is doc-specific; keep this as a scaffold.)
    raise NotImplementedError("fill in boundary detection for your doc")

if __name__ == "__main__":
    main()
