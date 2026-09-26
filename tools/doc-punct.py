#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""中文技术文档标点规范化（zh-tech-doc-style-guide 硬规则）。

只做保守的机械变换，逐行处理、逐处报告：
  1)  中文语境里的半角逗号/分号/冒号/问号/叹号/括号 → 全角
  1b) 全角标点两旁不留半角空格
  2)  英文省略号 → 中文省略号（……，两个字符）
  3)  破折号「——」前后不空格
  4)  汉字与 ASCII 字母/数字之间补半角空格
  5)  汉字/中文标点之间的空格（含全角空格）→ 删除
  6)  全角数字/字母 → 半角；数值与单位符号之间补半角空格

代码块、行内代码、URL、org 链接、md 链接/图片、表格行一律原样保留。

用法：
    python3 tools/doc-punct.py --check          # 全仓库只报告不改
    python3 tools/doc-punct.py FILE...          # 写入指定文件
    python3 tools/doc-punct.py --check FILE...  # 只报告不改
    python3 tools/doc-punct.py --self-test      # 跑自检后退出

不带 FILE 时扫描 git 可见的仓库自有文档（排除 vendored、agent skills）。
每处改动都打印上下文，便于人工复核。
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys

HAN = r"一-鿿"  # 只含汉字：全角标点不该触发补空格规则
PUNCT_CJK = r"　-〿＀-￯"  # 全角标点与符号
FULLWIDTH_ALNUM = r"０-９Ａ-Ｚａ-ｚ"  # 全角字母数字段

# 汉字之间 / 汉字与中文标点之间：不允许空格
CJK_PUNCT = "，。：；？！、）】」』"
OPEN_BRACKET = "（【「『"

# 中文语境里要转全角的半角标点（不含句点：句点转全角风险高，留人工）
HALF_TO_FULL = {",": "，", ";": "；", ":": "：", "?": "？", "!": "！"}

# 单位符号：数值与单位之间补空格（zh-style-guide：7 kg、8 MB）
UNIT_RE = re.compile(
    r"(?<=[0-9])((?:B|KB|MB|GB|TB|PB|ms|us|ns|min|Hz|kHz|MHz|GHz|rpm|"
    r"px|pt|dpi|W|kW|V|mV|kV|A|mA|ohm|km|cm|mm|kg|mg|fps|bps|Kbps|Mbps|Gbps))"
    r"(?![A-Za-z])"
)

# 仓库自有文档：排除 vendored（子模块、上游 README）与 agent skills
EXCLUDE = (
    "/.local/share/hermes/skills/",
    "/.config/agents/skills/",
    "/agents/skills/",
    "/.archive/",
    "/fcitx5/rime/",
    "/tools/linux-setup/",
    "/tools/appimage-run/",
)


def protected_spans(line: str) -> list[tuple[int, int]]:
    """不该改动的字符区间：行内代码、org 等宽/波浪、链接、URL、模板变量。"""
    spans: list[tuple[int, int]] = []
    for pat in (
        r"`[^`]*`",  # 行内代码
        r"=+[^=\s][^=]*=+",  # org 等宽
        r"~[^~\s][^~]*~",  # org 波浪
        r"\[\[[^\]]*\]\]\[[^\]]*\]",  # org 链接
        r"\[\[[^\]]*\]\]",  # org 裸链接
        r"!\[[^\]]*\]\([^)]*\)",  # md 图片
        r"\[[^\]]*\]\([^)]*\)",  # md 链接
        r"https?://\S+",
        r"\{\{[^{}]*\}\}",
        r"(?m)^\s*#\+[\w-]+:",  # org 关键字行（#+NAME: / #:tangle …）
        r"^\s*#:[^:\s]+:.*$",  # org 旧式块名整行 #:NAME: …
        r"(?m)^\s*#\+begin_",  # org 块起始行
        r"(?m)^\s*#\+end_",  # org 块结束行
    ):
        for m in re.finditer(pat, line):
            spans.append((m.start(), m.end()))
    return spans


def convert(line: str) -> tuple[str, list[str]]:
    """单行变换。返回 (新行, 改动说明)。

    关键不变量：会改变行长度的规则（删空格、补空格、省略号整体替换）一律
    「重建整行」而非原位 splice——spans 只在行首算一次，原位 splice 会让
    后续 finditer 拿到陈旧坐标，进而吃掉 org 等宽标记或行内代码边界。
    """
    orig = line
    notes: list[str] = []
    n = len(line)
    spans = protected_spans(line)

    def free(i: int) -> bool:
        return 0 <= i < n and not any(s <= i < e for s, e in spans)

    han = len(re.findall(f"[{HAN}]", line))
    if not han:
        return line, []  # 纯英文行，整行不动

    is_table = line.lstrip().startswith("|")

    # 1) 中文语境里的半角逗号/分号/冒号/问号/叹号，以及包住中文的半角括号
    #    → 全角。判定依据是「这一行讲的是中文」，不是「标点旁边有没有汉字」：
    #    中文句子常夹整段英文代码片段（`- **桌面**(变体):`xfce``），
    #    靠邻接汉字判断会漏掉这类。
    out = list(line)
    for i, ch in enumerate(line):
        if ch not in ",;:?!()" or not free(i):
            continue
        prev = line[i - 1] if i > 0 else ""
        nxt = line[i + 1] if i + 1 < n else ""
        # 「主:次」这类字段格式说明是技术内容，不是中文句法
        if (
            ch == ":"
            and re.match(f"[A-Za-z{HAN}]", prev)
            and re.match(f"[A-Za-z{HAN}]", nxt)
        ):
            continue
        # 括号：zh-style-guide 规定「内含任何中文用全角，内全英文用半角」。
        # 按内容判，不按整行判——中文句子里的 (c,d)、(最常见坏法) 都是英文。
        if ch in "()":
            close = line.find(")", i) if ch == "(" else -1
            if ch == ")":
                open_at = line.rfind("(", 0, i)
                inner = line[open_at + 1 : i] if open_at >= 0 else ""
            else:
                inner = line[i + 1 : close] if close > i else ""
            if not re.search(f"[{HAN}]", inner):
                continue
            out[i] = "（" if ch == "(" else "）"
            notes.append(f"半角 {ch!r} → 全角｜{orig.strip()[:56]}")
            continue
        # 逗号/分号：中文句子常夹整段英文（`…([url](x)),无配置`），
        # 标点两侧未必挨着汉字。判据是「这个逗号分隔的是中文」——
        # 一侧是汉字就转，两侧都是英文（`(c,d)`、`a,b,c`）就留半角。
        if ch in ",;":
            if re.match(f"[{HAN}]", prev) or re.match(f"[{HAN}]", nxt):
                out[i] = "，" if ch == "," else "；"
                notes.append(f"半角 {ch!r} → 全角｜{orig.strip()[:56]}")
            continue
        prev_cjk = bool(re.match(f"[{HAN}{PUNCT_CJK}]", prev)) or prev in ")]】」』*"
        nxt_cjk = bool(re.match(f"[{HAN}]", nxt))
        if prev_cjk or nxt_cjk:
            out[i] = HALF_TO_FULL[ch]
            notes.append(f"半角 {ch!r} → 全角｜{orig.strip()[:56]}")

    line = "".join(out)

    # ---- 以下规则全部走「重建」：每步之后重算 spans ----
    #
    # 为什么不复用同一份 spans：重建规则会改变行长（删空格、`...`→`……`
    # 从 3 字符变 2 字符），原下标整体错位，保护区间（org 等宽、行内代码）
    # 会盖到错误的位置——`=(路径 挂载点)=` 里的空格就是这么被吃掉的。
    # 每步重建后立刻重算，用新下标继续。
    spans = protected_spans(line)
    n = len(line)

    def _strip_after_cjk_punct(text: str) -> str:
        """全角标点之后的半角空格删掉：`（ X ）` → `（X）`、`**标签**: X` → `**标签**：X`。

        例外：空格之后紧跟 org 等宽/行内代码/粗体起始标记（`=x=` / `` `x` `` /
        `*x*` / `_x_`）时保留——`： =C-c g s= （状态）` 是 org 文档通行的排版
        惯例，删掉会让全角冒号紧贴标记，可读性更差。
        """
        buf: list[str] = []
        i = 0
        while i < len(text):
            buf.append(text[i])
            if text[i] in "，；：？！" and text[i + 1 : i + 2] == " ":
                j = i + 1
                while text[j : j + 1] == " ":
                    j += 1
                if j < len(text) and text[j] not in "=`~*_":
                    i = j
                    continue
            i += 1
        return "".join(buf)

    def _ellipsis(text: str) -> str:
        """`...` → `……`（两个字符）。前后是字母数字视为版本号/省略范围，不动。"""
        buf: list[str] = []
        i = 0
        while i < len(text):
            if text[i : i + 3] == "..." and free(i):
                before = text[i - 1] if i > 0 else " "
                after = text[i + 3] if i + 3 < len(text) else " "
                if not re.match(r"[0-9A-Za-z]", before) and not re.match(
                    r"[0-9A-Za-z]", after
                ):
                    buf.append("……")
                    i += 3
                    continue
            buf.append(text[i])
            i += 1
        return "".join(buf)

    def _dash(text: str) -> str:
        """破折号「——」前后去空格。单个一字线「—」是连接号，空格是正确排版。"""
        buf: list[str] = []
        i = 0
        while i < len(text):
            if text[i : i + 2] == "——":
                if buf and buf[-1] == " ":
                    buf.pop()
                buf.append("——")
                if text[i + 2 : i + 3] == " ":
                    i += 3
                    continue
                i += 2
                continue
            buf.append(text[i])
            i += 1
        return "".join(buf)

    def _fullwidth_alnum(text: str) -> str:
        """全角数字/字母 → 半角。保护区间（行内代码、org 等宽）内不动。"""
        buf: list[str] = []
        for i, c in enumerate(text):
            if re.match(f"[{FULLWIDTH_ALNUM}]", c) and free(i):
                buf.append(chr(ord(c) - 0xFEE0))
            else:
                buf.append(c)
        return "".join(buf)

    def _unit_space(text: str) -> str:
        """数值与单位符号之间补空格：`8MB` → `8 MB`。保护区间内不动。"""
        out: list[str] = []
        last = 0
        for m in UNIT_RE.finditer(text):
            if not free(m.start(1)):
                continue
            out.append(text[last : m.start(1)])
            out.append(" " + m.group(1))
            last = m.end(1)
        out.append(text[last:])
        return "".join(out)

    def _rebuild(fn, note: str) -> None:
        """跑一个重建规则，并在行内容变化后重算 spans / n。

        所有会改变行长的规则都必须走这里，否则后续 free() 用陈旧下标，
        保护区间会错位（org 等宽、行内代码里的空格就是这么被误删的）。
        """
        nonlocal line, spans, n
        new = fn(line)
        if new != line:
            line = new
            spans = protected_spans(line)
            n = len(line)
            notes.append(note)

    if not is_table:
        _rebuild(_strip_after_cjk_punct, "全角标点后去空格")
        _rebuild(_ellipsis, "'...' → '……'")
        _rebuild(_fullwidth_alnum, "全角数字/字母 → 半角")
        _rebuild(_unit_space, "数值与单位间补空格")

    # 破折号去空格对表格行也适用（表格里的 `概念 —— 说明` 同样要去空格），
    # 但不适用于省略号/全角数字等会改变对齐的规则，故单独放在表格分支之外。
    _rebuild(_dash, "破折号去空格")

    # 4) 汉字与 ASCII 字母/数字之间补半角空格。
    # 5) 汉字/中文标点之间的空格（含全角空格）→ 删除。
    #    表格行跳过：那里的空格由对齐与标记语法决定。
    if not is_table:
        buf: list[str] = []
        i = 0
        m = len(line)
        while i < m:
            c = line[i]
            prev = buf[-1] if buf else ""
            nxt = line[i + 1] if i + 1 < m else ""
            # 5) 全角空格或汉字/中文标点之间的半角空格 → 删。
            #    保护区间（org 等宽、行内代码）内的空格是内容本身，不能删。
            if c in "　 " and prev and nxt and free(i):
                if (
                    re.match(f"[{HAN}]", prev)
                    and re.match(f"[{HAN}]", nxt)
                ) or (
                    re.match(f"[{HAN}]", prev)
                    and re.match(f"[{CJK_PUNCT}]", nxt)
                ) or (
                    re.match(f"[{CJK_PUNCT}]", prev)
                    and re.match(f"[{HAN}]", nxt)
                ) or (
                    re.match(f"[{HAN}{CJK_PUNCT}]", prev)
                    and re.match(f"[{OPEN_BRACKET}]", nxt)
                ):
                    notes.append("汉字间空格 → 删除")
                    i += 1
                    continue
            # 4) 中英之间补空格
            if (
                re.match(f"[{HAN}]", c)
                and re.match(r"[A-Za-z0-9]", nxt)
                and free(i)
                and free(i + 1)
            ):
                tail = line[i + 2 :]
                if not re.match(r"[\s)\]）】」』|，,。；：、？！…]", tail):
                    # 配置项名（[connection] 后接汉字）、枚举值
                    # （0=NM默认 / 2=disable省电）不加
                    if not re.search(r"\[[\w.\-]+\]$", "".join(buf)) and not re.search(
                        r"=\s*[A-Za-z0-9._-]+$", "".join(buf)
                    ):
                        buf.append(c)
                        buf.append(" ")
                        notes.append(f"中英补空格｜{c}{nxt!r}")
                        i += 1
                        continue
            buf.append(c)
            i += 1
        line = "".join(buf)

    return line, notes


def scan(text: str, org: bool) -> tuple[str, list[str]]:
    """逐行处理，跳过所有块内内容（代码块、org 各种块）。"""
    out_lines: list[str] = []
    all_notes: list[str] = []
    fence: str | None = None  # None = 不在块内
    for line in text.split("\n"):
        s = line.strip()
        if fence is not None:  # 块内原样保留
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


def own_files(root: str) -> list[str]:
    """git 可见的仓库自有文档。

    用 git ls-files 而不是 glob：glob 的 `**` 不穿透 `.config` / `.zcode`
    等隐藏目录，会漏掉 agents 上下文、emacs.org、zcode 插件文档等一大批。
    """
    try:
        raw = subprocess.run(
            [
                "git",
                "ls-files",
                "--cached",
                "--others",
                "--exclude-standard",
                "--",
                "*.md",
                "*.org",
            ],
            capture_output=True,
            text=True,
            cwd=root,
            check=True,
        ).stdout
    except (OSError, subprocess.CalledProcessError):
        return []

    files = []
    for rel in raw.split("\n"):
        rel = rel.strip()
        if not rel or rel.startswith("../"):
            continue
        if any(x in rel for x in EXCLUDE):
            continue
        files.append(os.path.join(root, rel))
    return sorted(files)


def _self_check() -> None:
    """自检：代码块、org 块、行内代码必须原样保留；文档正文按规则变换。"""
    cases = [
        # (输入, 期望输出, 说明)
        ("中文,后面", "中文，后面", "半角逗号转全角"),
        ("#:NAME: 块: 值", "#:NAME: 块: 值", "org 块名不转"),
        ("主:次 root", "主:次 root", "mountinfo 字段格式不转"),
        ("| a | b... |", "| a | b... |", "表格截断省略号不动"),
        ("版本 v1.2.3 发布", "版本 v1.2.3 发布", "版本号不动"),
        ("概念 —— 说明", "概念——说明", "破折号去空格"),
        ("概念—说明", "概念—说明", "连接号不动"),
        ("使用 blue 命令", "使用 blue 命令", "已有空格不重复加"),
        ("改 config.org 文件", "改 config.org 文件", "等宽标记内不动"),
        ("安装 guix。", "安装 guix。", "紧邻全角标点不加空格"),
        ("先 blue rebuild 再重启", "先 blue rebuild 再重启", "命令夹中文正常"),
        ("`a,b` 和 c,d", "`a,b` 和 c,d", "行内代码内不动"),
        ("参见 https://x.cn/a,b 链接", "参见 https://x.cn/a,b 链接", "URL 内不动"),
        (
            "在 NM `[connection]` 段写默认",
            "在 NM `[connection]` 段写默认",
            "配置项名后不加空格",
        ),
        (
            "2=disable省电 3=enable省电",
            "2=disable省电 3=enable省电",
            "枚举值紧凑排版不加空格",
        ),
        (
            "- **桌面**(变体):`xfce`",
            "- **桌面**（变体）：`xfce`",
            "粗体标签后的括号与冒号转全角",
        ),
        (
            "- **age**: 单一二进制(见官网),无配置",
            "- **age**：单一二进制（见官网），无配置",
            "标签冒号与中文括号",
        ),
        ("见 §2 (最常见坏法)", "见 §2 （最常见坏法）", "括号内含中文转全角"),
        ("见 §2 (only english)", "见 §2 (only english)", "括号内纯英文保持半角"),
        ("`a,b` 是代码(c,d)", "`a,b` 是代码(c,d)", "英文括注保持半角"),
        (
            "This line is pure english, no CJK",
            "This line is pure english, no CJK",
            "纯英文行不动",
        ),
        ("a,b,c 全是英文", "a,b,c 全是英文", "英文行不动"),
        (
            "单一二进制(`age-encryption.org`),无配置",
            "单一二进制(`age-encryption.org`)，无配置",
            "中文句夹整段英文：括号内纯英文留半角，句内逗号转全角",
        ),
        # ---- 回归用例（本次修复的 bug）----
        ("x 是 ...", "x 是 ……", "省略号转两个字符而非三个"),
        ("中文， ...", "中文，……", "省略号在行尾不再崩"),
        ("![图](docs/a.png) 说明", "![图](docs/a.png) 说明", "md 图片语法不动"),
        ("说明 ，第二", "说明，第二", "全角标点前的空格也删"),
        ("方便 单独调试", "方便单独调试", "汉字之间的空格删除"),
        ("中文　全角", "中文全角", "全角空格删除"),
        ("每２分钟", "每 2分钟", "全角数字转半角并补空格（中文单位不机械补）"),
        ("内存 8MB 磁盘", "内存 8 MB 磁盘", "数值与单位之间补空格"),
        (
            "工具： =spec->pkg= 来自频道； =pkg-bin= 拼路径",
            "工具： =spec->pkg= 来自频道； =pkg-bin= 拼路径",
            "等宽标记前后的空格是 org 排版惯例，保留",
        ),
        (
            "**标签**: `xfce`",
            "**标签**： `xfce`",
            "半角冒号转全角，等宽标记前空格保留",
        ),
        (
            "参见 [配置](dotfiles/mutable/a,b) 说明",
            "参见 [配置](dotfiles/mutable/a,b) 说明",
            "md 链接 URL 内不动",
        ),
        ("| 概念 —— 说明 |", "| 概念——说明 |", "表格内破折号仍去空格"),
    ]
    src = "\n".join(a for a, _, _ in cases)
    want = "\n".join(b for _, b, _ in cases)
    got, notes = scan(src, org=False)
    assert got == want, f"\n期望:\n{want}\n实得:\n{got}"
    assert notes, "自检用例没触发任何规则"

    # org 代码块整块不得被触碰
    org_src = (
        "#+begin_src scheme\n"
        "中文,原样,保持:same\n"
        "中文 —— 原样\n"
        "#+end_src\n"
        "正文,转全角\n"
    )
    org_want = (
        "#+begin_src scheme\n"
        "中文,原样,保持:same\n"
        "中文 —— 原样\n"
        "#+end_src\n"
        "正文，转全角\n"
    )
    org_got, _ = scan(org_src, org=True)
    assert org_got == org_want, f"\norg 块被改动:\n{org_got}"
    print("自检通过")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="*")
    ap.add_argument("--check", action="store_true", help="只报告不改")
    ap.add_argument("--self-test", action="store_true", help="跑自检后退出")
    args = ap.parse_args()
    if args.self_test:
        _self_check()
        return 0

    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
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
    print(
        f"\n合计 {total} 处{'（未写入，--check 模式）' if args.check else '，已写入'}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
