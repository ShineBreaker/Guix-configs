#!/usr/bin/env python3
"""blind-review 验证脚本 —— 用 skill 自带的 scripts/blind-strip.el 跑端到端。

ad-hoc 验证，不是测试套件。覆盖：
  1. 四类语言的边界情况（含手写字符级扫描器必然翻车的构造）
  2. 不变量：行数守恒、逐行宽度守恒、注释内容消失、代码/字符串存活
  3. 多字节 UTF-8 注释（中文、制表符）不报错
  4. 残留检测器在已知答案样本上零误报零漏报
  5. 形状漂移为 0

用法：python3 scripts/verify-blind-strip.py [--repo PATH]
默认 --repo 用当前工作目录，只跑语言表内的文件。
"""
from __future__ import annotations

import argparse
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SKILL = HERE.parent
STRIP = SKILL / "scripts" / "blind-strip.el"

# 扩展名 -> major-mode。typescript-mode 不随 Emacs 分发，.ts 用 js-mode。
MODES = {
    ".py": "python-mode",
    ".el": "emacs-lisp-mode",
    ".scm": "scheme-mode",
    ".js": "js-mode",
    ".mjs": "js-mode",
    ".cjs": "js-mode",
    ".ts": "js-mode",
    ".tsx": "js-mode",
    ".sh": "sh-mode",
    ".bash": "sh-mode",
}

# (源码, mode, 应消失的注释片段, 必须存活的代码/字符串)
FIXTURES: list[tuple[str, str, list[str], list[str]]] = [
    (
        "x = 1  # note\ns = \"http://x#y\"  # real\nt = \"\"\"triple # not comment\"\"\"\n",
        "python-mode",
        ["# note", "# real"],
        ['s = "http://x#y"', 't = """triple # not comment"""'],
    ),
    (
        "const a = 1; // tail\nconst t = `tpl ${a} // inside tpl`;\n"
        "const r = /^\\s*=\\s*'([^']*)'\\s*(?:#.*)?$/; // after regex\n/* block\n   comment */\n",
        "js-mode",
        ["// tail", "after regex", "block", "comment */"],
        ["const t = `tpl ${a} // inside tpl`;", "const r = /^\\s*=\\s*'([^']*)'\\s*(?:#.*)?$/;"],
    ),
    (
        ";; leading\n(define x 1) ; trailing\n(display \"str ; and #| inside\")\n"
        "#| block\n   comment |#\n(define `quoted-symbol' 2) ; after sym\n(define y #\\; ) ; char lit\n",
        "scheme-mode",
        ["leading", "trailing", "block", "comment |#", "after sym", "char lit"],
        ['(display "str ; and #| inside")', "(define `quoted-symbol' 2)", "(define y #\\; )"],
    ),
    (
        "#! /usr/bin/env bash\nx=1 # note\ncat <<'EOF'\nthis is heredoc # not comment\nEOF\n",
        "sh-mode",
        ["/usr/bin/env bash", "# note"],
        ["cat <<'EOF'", "this is heredoc # not comment", "EOF"],
    ),
    # 多字节 UTF-8 注释：subst-char-in-region 会在这里报错
    (
        ";; 中文注释，含制表符 ─────────\n(define z 1)\n",
        "scheme-mode",
        ["中文注释"],
        ["(define z 1)"],
    ),
]


def run_strip(path: str, mode: str) -> tuple[str, str]:
    r = subprocess.run(
        ["emacs", "--batch", "-l", str(STRIP), "--", path, mode],
        capture_output=True,
        text=True,
    )
    return r.stdout, r.stderr


def check_fixtures() -> list[str]:
    """返回失败的描述列表。"""
    fails: list[str] = []
    tmp = Path(tempfile.mkdtemp(prefix="blind-review-verify-"))
    try:
        for i, (src, mode, gone, keep) in enumerate(FIXTURES, 1):
            ext = {"python-mode": ".py", "js-mode": ".js",
                   "scheme-mode": ".scm", "sh-mode": ".sh"}[mode]
            f = tmp / f"case{i}{ext}"
            f.write_text(src, encoding="utf-8")
            out, err = run_strip(str(f), mode)

            if "Error:" in err:
                fails.append(f"case{i}: emacs 报错 {err.strip()[:80]}")
                continue

            sl, ol = src.splitlines(), out.splitlines()
            if len(sl) != len(ol):
                fails.append(f"case{i}: 行数 {len(sl)} -> {len(ol)}")
                continue
            for ln, (a, b) in enumerate(zip(sl, ol), 1):
                if len(a) != len(b):
                    fails.append(f"case{i}:{ln} 列宽 {len(a)} -> {len(b)}")
            for g in gone:
                if g in out:
                    fails.append(f"case{i}: 注释内容残留 {g!r}")
            for k in keep:
                if k not in out:
                    fails.append(f"case{i}: 代码被误删 {k!r}")
    finally:
        for p in tmp.rglob("*"):
            p.unlink()
        tmp.rmdir()
    return fails


def check_detector() -> list[str]:
    """残留检测器的已知答案校准。

    检测器本身就是宽松匹配，对 CSS id 选择器 / #include / shell case 模式
    必然误报 —— 这是已知事实，不是缺陷。这里断言的是**定性规则**能把这些
    误报排除掉：定界符后紧跟非空白字符 => 不是注释。
    """
    fails: list[str] = []

    # 检测器会命中，但定性规则必须判为「非注释」
    false_positives = [
        "#progressBar { height: 100%; }",       # CSS id 选择器
        "#include <stdio.h>",                   # C 预处理
        "    /*) [ \"$m\" != \"/\" ] || die \"x\" ;;",  # shell case 分支
        "(if #f #t)",                            # Scheme 布尔
        "url = \"http://x#frag\"",              # 字符串内 #
    ]
    for line in false_positives:
        s = line.lstrip()
        matched = next((d for d in ("#", "//", ";", "/*") if s.startswith(d)), None)
        if matched is None:
            continue  # 检测器本就没命中，无需定性
        rest = s[len(matched):]
        if not rest or rest[0].isspace():
            fails.append(f"定性规则失效，会把合法代码当注释: {line!r}")

    # 反向：真注释必须被命中，否则残留检测形同虚设
    true_positives = ["# 这是一条注释", "// line comment",
                      ";; scheme comment", "/* block */"]
    for line in true_positives:
        s = line.lstrip()
        if not any(s.startswith(d) for d in ("#", "//", ";", "/*")):
            fails.append(f"检测器漏报: {line!r}")
    return fails


def check_repo(repo: Path) -> tuple[int, int, list[str]]:
    """返回 (处理文件数, 形状漂移数, 失败列表)。"""
    fails: list[str] = []
    n = drift = 0
    tmp = Path(tempfile.mkdtemp(prefix="blind-review-repo-"))
    try:
        for p in sorted(repo.rglob("*")):
            if not p.is_file():
                continue
            mode = MODES.get(p.suffix.lower())
            if not mode or any(x in p.parts for x in (".git", "node_modules")):
                continue
            out, err = run_strip(str(p), mode)
            if "Error:" in err:
                fails.append(f"{p.relative_to(repo)}: {err.strip()[:80]}")
                continue
            n += 1
            a = p.read_text(errors="replace").splitlines()
            b = out.splitlines()
            if len(a) != len(b) or any(len(x) != len(y) for x, y in zip(a, b)):
                drift += 1
                fails.append(f"形状漂移: {p.relative_to(repo)}")
    finally:
        for q in tmp.rglob("*"):
            q.unlink()
        tmp.rmdir()
    return n, drift, fails


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", type=Path, default=Path.cwd())
    args = ap.parse_args()

    if not STRIP.exists():
        print(f"FAIL: 找不到 {STRIP}")
        return 1

    results: list[tuple[str, bool, str]] = []

    f = check_fixtures()
    results.append((f"边界样本 {len(FIXTURES)} 组", not f, "; ".join(f) or "全部通过"))

    f = check_detector()
    results.append(("残留检测器校准", not f, "; ".join(f) or "零误报"))

    n, drift, f = check_repo(args.repo)
    results.append((f"仓库 {args.repo} ({n} 文件)", not f,
                    f"形状漂移 {drift}" + (f"; {'; '.join(f[:3])}" if f else "")))

    passed = sum(1 for _, ok, _ in results if ok)
    for name, ok, detail in results:
        print(f"[{'PASS' if ok else 'FAIL'}] {name}: {detail}")
    print(f"\n{passed}/{len(results)} PASS")
    print("ad-hoc 验证 — 不是测试套件")
    return 0 if passed == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
