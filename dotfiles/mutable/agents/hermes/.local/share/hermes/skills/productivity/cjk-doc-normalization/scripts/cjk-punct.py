#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""中文技术文档标点规范化（zh-tech-doc-style-guide 硬规则）。

只做保守的机械变换：中文语境里的半角标点转全角、破折号排版、汉字与英文
之间补半角空格。代码块、内联代码、URL、org 链接与块名一律原样保留。

用法：
    python3 cjk-punct.py --self-test        # 先跑自检（必须通过）
    python3 cjk-punct.py --check            # 全仓只报告不改（先跑这个）
    python3 cjk-punct.py --check FILE...    # 只报告不改
    python3 cjk-punct.py FILE...            # 写入指定文件

不带 FILE 时扫描 CWD 下的仓库自有文档，排除 vendored / skills / scratch。
每处改动都打印上下文，便于人工复核。

自检覆盖 §2 的 CJK-vs-English 边界：每条 fixture 都是一个真实会踩的误伤。
若要扩展规则，先在 _self_check() 里加断言，再改 convert()。
"""

from __future__ import annotations

import argparse
import glob
import os
import re
import sys

HAN = r"一-鿿"            # 只含汉字：全角标点不该触发补空格规则
PUNCT_CJK = r"　-〿＀-￯"  # 全角标点与符号

# 仓库自有文档：排除 vendored、agent skills、session scratch
EXCLUDE = ("/fcitx5/rime/others/", "/.local/share/hermes/skills/",
           "/.config/agents/skills/", "/.agents/workfile/",
           "/.zcode/plans/", "/.config/emacs/.agents/workfile/")


def protected_spans(line: str) -> list[tuple[int, int]]:
    """不该改动的字符区间：行内代码、org 等宽/波浪、链接、URL、块名。"""
    spans: list[tuple[int, int]] = []
    for pat in (r"`[^`]*`",                        # 行内代码
                r"=+[^=\s][^=]*=+",                 # org 等宽
                r"~[^~\s][^~]*~",                   # org 波浪
                r"\[\[[^\]]*\]\]\[[^\]]*\]",        # org 链接
                r"\[\[[^\]]*\]\]",                  # org 裸链接
                r"https?://\S+",
                r"\{\{[^{}]*\}\}",
                r"(?m)^\s*#\+[\w-]+:",              # org 关键字行
                r"^\s*#:[^:\s]+:.*$",                # org 旧式块名整行
                r"(?m)^\s*#\+begin_",               # org 块起始行
                r"(?m)^\s*#\+end_"):                 # org 块结束行
        for m in re.finditer(pat, line):
            spans.append((m.start(), m.end()))
    return spans


def convert(line: str) -> tuple[str, list[str]]:
    """单行变换。返回 (新行, 改动说明)。"""
    orig = line
    notes: list[str] = []
    spans = protected_spans(line)
    out = list(line)
    n = len(line)

    def free(i: int) -> bool:
        return not any(s <= i < e for s, e in spans)

    if not re.search(f"[{HAN}]", line):
        return line, []                  # 纯英文行，整行不动

    # 1) 半角标点 → 全角。判据是「标点分隔的是不是中文」，不是「本行中文多不多」：
    #    中文句子常夹整段英文代码片段，靠行级占比会误伤 (a,b) 这类英文内容。
    for i, ch in enumerate(line):
        if ch not in ",;:?!()" or not free(i):
            continue
        prev = line[i - 1] if i > 0 else ""
        nxt = line[i + 1] if i + 1 < n else ""
        # 「主:次」这类字段格式说明是技术内容，不是中文句法
        if ch == ":" and re.match(f"[A-Za-z{HAN}]", prev) and re.match(f"[A-Za-z{HAN}]", nxt):
            continue
        # 括号：zh-style-guide 规定「内含任何中文用全角，内全英文用半角」。
        # 按内容判，不按整行判。
        if ch in "()":
            if ch == "(":
                close = line.find(")", i)
                inner = line[i + 1:close] if close > i else ""
            else:
                open_at = line.rfind("(", 0, i)
                inner = line[open_at + 1:i] if open_at >= 0 else ""
            if not re.search(f"[{HAN}]", inner):
                continue
            out[i] = "（" if ch == "(" else "）"
            notes.append(f"半角 {ch!r} → 全角｜{orig.strip()[:56]}")
            continue
        if ch in ",;":
            if re.match(f"[{HAN}]", prev) or re.match(f"[{HAN}]", nxt):
                out[i] = "，" if ch == "," else "；"
                notes.append(f"半角 {ch!r} → 全角｜{orig.strip()[:56]}")
            continue
        prev_cjk = bool(re.match(f"[{HAN}{PUNCT_CJK}]", prev)) or prev in ")]】」』*"
        nxt_cjk = bool(re.match(f"[{HAN}]", nxt))
        if prev_cjk or nxt_cjk:
            out[i] = {",": "，", ";": "；", ":": "：",
                      "?": "？", "!": "！"}[ch]
            notes.append(f"半角 {ch!r} → 全角｜{orig.strip()[:56]}")

    # 1b) 全角标点后不留半角空格：`**标签**: X` → `**标签**：X`
    line = "".join(out)
    for m in re.finditer(r"([，；：？！])\s+(?=\S)", line):
        if free(m.start()):
            line = line[:m.end() - 1] + line[m.end():]
    out = list(line)

    # 2) 英文省略号 → 中文省略号。版本号、省略范围、表格截断标记不动。
    for m in re.finditer(r"\.\.\.", line):
        if not free(m.start()) or line.lstrip().startswith("|"):
            continue
        before = line[max(0, m.start() - 1)] or " "
        after = line[m.end()] if m.end() < n else " "
        if re.match(r"[0-9A-Za-z]", before) or re.match(r"[0-9A-Za-z]", after):
            continue
        if re.search(r"\S\.\.\.$", line) or "……" in line:
            continue
        for k in range(m.start(), m.end()):
            out[k] = "…"
        notes.append(f"'...' → '……'｜{orig.strip()[:56]}")

    # 3) 破折号「——」前后不空格。单个一字线「—」是连接号，留空格是正确排版。
    line = "".join(out)
    for m in re.finditer(r" ?—— ?", line):
        dash = m.start() + (1 if m.group(0).startswith(" ") else 0)
        if free(dash) and m.group(0) != "——":
            line = line[:m.start()] + "——" + line[m.end():]
            notes.append(f"破折号去空格｜{orig.strip()[:56]}")
    out = list(line)

    # 4) 汉字与 ASCII 字母/数字之间补半角空格。表格行、行首标记、
    #    配置项名（[connection] 后接汉字）、紧凑枚举（0=NM默认）处跳过。
    for m in re.finditer(f"([{HAN}])([A-Za-z0-9])|([A-Za-z0-9])([{HAN}])", line):
        i = m.start()
        if not free(i) or not free(i + 1):
            continue
        if line.lstrip().startswith("|"):
            continue
        if re.search(r"(\*+|\#+|\[|=|~|\(|（|>|-)$", line[:i]):
            continue
        tail = line[m.start(2) + 1 if m.group(2) else m.start(4) + 1:]
        if re.match(r"[\s)\]）】」』|，,。；：、？！…]", tail):
            continue
        if re.search(r"\[[\w.\-]+\]$", line[:i]):
            continue
        if re.search(r"=\s*[A-Za-z0-9._-]+$", line[:i]):
            continue
        out.insert(i + 1, " ")
        notes.append(f"中英补空格｜{line[i:i + 8]!r}")
        line = "".join(out)
        spans = protected_spans(line)

    return "".join(out), notes


def scan(text: str, org: bool) -> tuple[str, list[str]]:
    """逐行处理，跳过所有块内内容（代码块、org 各种块）。"""
    out_lines: list[str] = []
    all_notes: list[str] = []
    fence: str | None = None          # None = 不在块内
    for line in text.split("\n"):
        s = line.strip()
        if fence is not None:                      # 块内原样保留
            out_lines.append(line)
            if s.lower().startswith(fence):
                fence = None
            continue
        low = s.lower()
        if s.startswith("```") or s.startswith("~~~"):
            fence = s[:3]
        elif org and low.startswith("#+begin_"):
            fence = "#+end_"
        if fence is not None:
            out_lines.append(line)
            continue
        new, notes = convert(line)
        out_lines.append(new)
        all_notes.extend(notes)
    return "\n".join(out_lines), all_notes


def _self_check() -> None:
    """自检：代码块/org 块/行内代码必须原样；文档正文按规则变换。"""
    cases = [
        ("中文,后面", "中文，后面", "半角逗号转全角"),
        ("中文:说明", "中文：说明", "半角冒号转全角"),
        ("- **桌面**(变体):`xfce`", "- **桌面**（变体）：`xfce`", "粗体标签后的括号与冒号"),
        ("见 §2 (最常见坏法)", "见 §2 （最常见坏法）", "括号内含中文转全角"),
        ("见 §2 (only english)", "见 §2 (only english)", "括号内纯英文保持半角"),
        ("`a,b` 是代码(c,d)", "`a,b` 是代码(c,d)", "英文括注保持半角"),
        ("单一二进制(`age-encryption.org`),无配置",
         "单一二进制(`age-encryption.org`)，无配置", "中文句夹整段英文"),
        ("a,b,c 全是英文", "a,b,c 全是英文", "英文列表不动"),
        ("This line is pure english, no CJK", "This line is pure english, no CJK", "纯英文行不动"),
        ("`a,b` 和 c,d", "`a,b` 和 c,d", "行内代码内不动"),
        ("参见 https://x.cn/a,b 链接", "参见 https://x.cn/a,b 链接", "URL 内不动"),
        ("版本 v1.2.3 发布", "版本 v1.2.3 发布", "版本号不动"),
        ("| a | b... |", "| a | b... |", "表格截断省略号不动"),
        ("概念 —— 说明", "概念——说明", "破折号去空格"),
        ("概念—说明", "概念—说明", "连接号不动"),
        ("使用 blue 命令", "使用 blue 命令", "已有空格不重复加"),
        ("改 config.org 文件", "改 config.org 文件", "等宽标记内不动"),
        ("在 NM `[connection]` 段写默认", "在 NM `[connection]` 段写默认", "配置项名后不加空格"),
        ("0=NM默认 2=disable省电", "0=NM默认 2=disable省电", "紧凑枚举不加空格"),
        ("主:次 root", "主:次 root", "mountinfo 字段格式不动"),
    ]
    src = "\n".join(a for a, _, _ in cases)
    want = "\n".join(b for _, b, _ in cases)
    got, notes = scan(src, org=False)
    assert got == want, f"\n期望:\n{want}\n\n实得:\n{got}"
    assert notes, "自检用例没触发任何规则"

    # org 块名与代码块必须逐字节不变
    org_src = ("#:NAME: 块: 值\n"
               "#+begin_src scheme\n"
               "中文,原样,保持:same\n"
               "中文 —— 原样\n"
               "#+end_src\n"
               "正文,转全角\n")
    org_want = ("#:NAME: 块: 值\n"
                "#+begin_src scheme\n"
                "中文,原样,保持:same\n"
                "中文 —— 原样\n"
                "#+end_src\n"
                "正文，转全角\n")
    org_got, _ = scan(org_src, org=True)
    assert org_got == org_want, f"\norg 块被改动:\n{org_got}"
    print(f"自检通过（{len(cases) + 1} 条）")


def own_files(root: str) -> list[str]:
    files: list[str] = []
    for pat in ("**/*.md", "**/*.org", "README*"):
        for p in glob.glob(os.path.join(root, pat), recursive=True):
            rel = p[len(root):]
            if any(x in rel for x in EXCLUDE) or "/.git/" in rel:
                continue
            files.append(p)
    return sorted(files)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="*")
    ap.add_argument("--check", action="store_true", help="只报告不改")
    ap.add_argument("--self-test", action="store_true", help="跑自检后退出")
    args = ap.parse_args()
    if args.self_test:
        _self_check()
        return 0

    root = os.getcwd()
    files = args.files or own_files(root)

    total = 0
    for path in files:
        if not os.path.exists(path):
            print(f"跳过（不存在）：{path}", file=sys.stderr)
            continue
        raw = open(path, encoding="utf-8").read()
        new, notes = scan(raw, path.endswith(".org"))
        if new == raw:
            continue
        total += len(notes)
        print(f"\n=== {os.path.relpath(path, root)}  ({len(notes)} 处) ===")
        for x in dict.fromkeys(notes):
            print(f"  {x}")
        if not args.check:
            open(path, "w", encoding="utf-8").write(new)
    print(f"\n合计 {total} 处{'（未写入，--check 模式）' if args.check else '，已写入'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
