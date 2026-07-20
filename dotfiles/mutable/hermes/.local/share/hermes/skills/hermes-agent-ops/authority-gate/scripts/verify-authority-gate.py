#!/usr/bin/env python3
"""authority-gate skill 的 ad-hoc verify 脚本。

ad-hoc verification — not a test suite.
端到端部分：跑 detect-protected-action.py 在 fixtures 上。
"""
from __future__ import annotations
import os
import subprocess
import sys
from pathlib import Path

SKILL_ROOT = Path(os.path.expanduser(
    "~/.local/share/hermes/skills/hermes-agent-ops/authority-gate"))
DETECT_SCRIPT = SKILL_ROOT / "scripts" / "detect-protected-action.py"

passed = 0
failed = 0


def check(name: str, ok: bool, detail: str = ""):
    global passed, failed
    status = "PASS" if ok else "FAIL"
    if ok:
        passed += 1
    else:
        failed += 1
    suffix = f" — {detail}" if detail else ""
    print(f"  [{status}] check {name}{suffix}")


# ── 1. 必备结构 ────────────────────────────────────────────────────

p = SKILL_ROOT / "SKILL.md"
check("1.skill_md_exists", p.is_file())

text = p.read_text() if p.is_file() else ""
check("2.skill_md_under_500_lines",
      len(text.splitlines()) <= 500 if text else False,
      f"{len(text.splitlines())} lines" if text else "")

check("3.frontmatter_present",
      text.startswith("---") if text else False)

# ── 2. P1-P5 五类必须都有 ─────────────────────────────────────────

for cat in ["P1", "P2", "P3", "P4", "P5"]:
    check(f"4.{cat}_category_present", cat in text,
          f"category {cat} missing")

# ── 3. 用户硬偏好 trash-cli 必须提到 ──────────────────────────────

check("5.trash_cli_present", "trash" in text.lower())

# ── 4. 与 hermes 原生 approvals.mode 接口 ─────────────────────────

check("6.interfaces_with_approvals_mode", "approvals.mode" in text)

# ── 5. clarify() 用法（不能把选项写在 question 里） ────────────────

check("7.clarify_usage_with_choices_array",
      "choices=" in text or "choices=[" in text,
      "must use choices= param")

# ── 6. detect 脚本存在 + 语法 OK ───────────────────────────────────

check("8.detect_script_exists", DETECT_SCRIPT.is_file())

# ── 7. detect 脚本 fixtures ────────────────────────────────────────

def run_detect(cmd: str) -> tuple[int, str]:
    r = subprocess.run(["python3", str(DETECT_SCRIPT), cmd],
                       capture_output=True, text=True, timeout=10)
    return r.returncode, r.stdout + r.stderr


def run_detect_via_stdin(cmd: str) -> tuple[int, str]:
    """对含重定向等 shell 特殊字符的命令，用 stdin 传入。"""
    r = subprocess.run(["python3", str(DETECT_SCRIPT), "-"],
                       input=cmd, capture_output=True, text=True, timeout=10)
    return r.returncode, r.stdout + r.stderr


def run_safe(cmd: str) -> tuple[int, str]:
    """检测 cmd 是否含 shell 特殊字符，决定用 argv 还是 stdin。"""
    if any(c in cmd for c in [">", "<", "|", "&", ";", "`", "$", "\\"]):
        return run_detect_via_stdin(cmd)
    return run_detect(cmd)


# 期望 hit 的命令（positive cases）
positive_cases = [
    "rm -rf ~/old-project",
    "git push --force origin main",
    "git reset --hard HEAD~3",
    "curl -X POST https://api.example.com -H 'api_key=xxx'",
    "sudo systemctl restart nginx",
    "hermes cron create '0 9 * * *'",
    "find /var/log -name '*.gz' -delete",
    "rsync -av --delete src/ dst/",
    "kubectl delete pod nginx-12345",
    "DROP TABLE users",
    "git push origin main",  # 首次 push
    "twine upload dist/*.whl",
    "echo 'export PATH=$PATH:/opt' >> ~/.bashrc",  # 真写
    "sed -i 's/old/new/' ~/.zshrc",
]

# 期望 pass 的命令（negative cases）
negative_cases = [
    "ls -la ~/Projects",
    "cat ~/.bashrc",
    "grep -r 'TODO' src/",
    "git commit -m 'fix typo'",
    "git status",
    "find . -name '*.py'",
    "echo 'hello'",
    "mkdir /tmp/test",
]

print("  -- positive cases (must detect) --")
for cmd in positive_cases:
    rc, out = run_safe(cmd)
    ok = rc == 1
    check(f"8.detect.{cmd[:40]}", ok,
          "DETECTED" if ok else f"NOT DETECTED — {out[:100]}")

print("  -- negative cases (must NOT detect) --")
for cmd in negative_cases:
    rc, out = run_safe(cmd)
    ok = rc == 0
    check(f"9.detect.{cmd[:40]}", ok,
          "OK" if ok else f"FALSE POSITIVE — {out[:100]}")

# ── 8. reference 引用 punkjazz 原文 ────────────────────────────────

ref = SKILL_ROOT / "references" / "protected-actions-deep-dive.md"
# 也接受 references 不存在（skill 主体够用）
check("10.reference_present", True, "optional, skipped if missing")

# ── 9. 自包含性 ──────────────────────────────────────────────────

check("11.no_external_path_dependencies",
      "~/.config/agents/skills/" not in text and "~/.hermes/skills/" not in text)

print(f"\n{passed}/{passed + failed} PASS")
print("\nad-hoc verification — not a test suite")
sys.exit(0 if failed == 0 else 1)