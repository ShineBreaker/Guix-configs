#!/usr/bin/env python3
"""核对文本中引用的本地路径是否存在（只读抽查工具）。

用法: python3 ref_check.py <文件1> [<文件2> ...]
提取 ~/... 与 /home/brokenshine/... 形状的引用（排除含通配/占位符的），
报告每个文件的存在/缺失清单，供人工判断卡片/技能文档的时效性。
"""
import os
import pathlib
import re
import sys

HOME = str(pathlib.Path.home())
ref_re = re.compile(r"(?:~/|/home/brokenshine/)[A-Za-z0-9_./+-]+")
skip_chars = set("<>*${}()[]|`'\"")


def refs(text: str):
    out = set()
    for m in ref_re.finditer(text):
        s = m.group(0).rstrip(".,;:)。，；、")
        if any(c in s for c in skip_chars):
            continue
        out.add(s)
    return sorted(out)


def check(s: str) -> bool:
    p = s.replace("~/", HOME + "/", 1) if s.startswith("~/") else s
    return os.path.exists(p)


def main() -> int:
    total_ok = total = 0
    for fn in sys.argv[1:]:
        text = pathlib.Path(fn).read_text(errors="ignore")
        rs = refs(text)
        ok = [r for r in rs if check(r)]
        bad = [r for r in rs if not check(r)]
        total_ok += len(ok)
        total += len(rs)
        print(f"== {fn}: {len(ok)}/{len(rs)} 存在")
        for b in bad:
            print("   MISSING:", b)
    print(f"\n合计: {total_ok}/{total}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
