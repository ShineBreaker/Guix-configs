#!/usr/bin/env python3
"""Assemble translated chunks into one markdown file from manifest.json.

Usage: python3 assemble.py
Run from the workspace root (folder containing manifest.json).
Un-translated chunks emit a placeholder comment so the file is always openable.

manifest.json shape:
  { "src": "...", "total": N,
    "chunks": [ {"id","title","level","pages","source","status","translated"} ] }
"""
import json, os, re

ROOT = os.path.dirname(os.path.abspath(__file__))
MANIFEST = os.path.join(ROOT, "manifest.json")
OUT = os.path.join(os.path.dirname(ROOT), "guix-cookbook.zh.md")

HEADER = (
    "# GNU Guix Cookbook（中文翻译）\n\n"
    "> 原文：GNU Guix Cookbook — Tutorials and examples for GNU Guix\n\n"
    "> 本文件由 `guix-cookbook-translation/assemble.py` 自动汇编。\n\n"
)

def clean_header(path):
    """Read a translated chunk but drop its <!-- ... --> status header."""
    with open(path, encoding="utf-8") as f:
        txt = f.read()
    return re.sub(r"^<!--.*?-->\s*", "", txt, count=1, flags=re.S)

def main():
    man = json.load(open(MANIFEST, encoding="utf-8"))
    out = [HEADER]
    done = 0
    for c in man["chunks"]:
        if c["status"] == "translated" and c.get("translated"):
            p = os.path.join(ROOT, c["translated"])
            if os.path.exists(p):
                out.append(clean_header(p).strip())
                out.append("\n")
                done += 1
        else:
            title = c["title"].replace("  ", " ").strip()
            out.append(f"\n<!-- [未译] {title} (id={c['id']}) -->\n")
    with open(OUT, "w", encoding="utf-8") as f:
        f.write("\n".join(out))
    print(f"已汇编 {done}/{man['total']} 切片 -> {OUT}")

if __name__ == "__main__":
    main()
