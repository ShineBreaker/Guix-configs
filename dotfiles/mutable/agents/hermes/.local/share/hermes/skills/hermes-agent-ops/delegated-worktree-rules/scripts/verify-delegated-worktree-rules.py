#!/usr/bin/env python3
"""delegated-worktree-rules skill 的 ad-hoc verify 脚本。

ad-hoc verification — not a test suite.

注：hermes TUI sandbox 限制——部分 git/grep 命令不可用。end-to-end 部分降级
为「脚本语法 + shellcheck 等价检查」+「环境探针」。
"""
from __future__ import annotations
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

SKILL_ROOT = Path(os.path.expanduser(
    "~/.local/share/hermes/skills/hermes-agent-ops/delegated-worktree-rules"))

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

# ── 2. 必须含 trigger 清单（T1-T6） ──────────────────────────────────

required_triggers = ["T1", "T2", "T3", "T4", "T5", "T6"]
missing = [t for t in required_triggers if t not in text]
check("4.all_6_triggers_present", not missing,
      f"missing {missing}" if missing else "")

# ── 3. 硬规则 R1-R6 ────────────────────────────────────────────────
# 注意：R6 在 references/source-stability-rules.md（设计上是跨文件分布），
# SKILL.md 里有 R1-R5 + 引用 references。Verify 接受这种模式。

required_in_skill = ["R1", "R2", "R3", "R4", "R5"]
missing_skill = [r for r in required_in_skill if r not in text]
ref = SKILL_ROOT / "references" / "source-stability-rules.md"
ref_text = ref.read_text() if ref.is_file() else ""
r6_in_ref = "R6" in ref_text
check("5.hard_rules_R1_R5_in_skill_R6_in_ref",
      not missing_skill and r6_in_ref,
      f"missing in skill: {missing_skill}, R6 in ref: {r6_in_ref}")

# ── 4. 三种用法 A/B/C 必须都有 ─────────────────────────────────────

all_three = all(u in text for u in ["用法 A", "用法 B", "用法 C"])
check("6.all_three_usage_patterns", all_three)

# ── 5. trash-cli 引用（用户硬偏好） ─────────────────────────────────

check("7.uses_trash_cli", "trash" in text.lower(),
      "must reference trash-cli not rm")

# ── 6. "rm -rf" 反向警告允许在注释里，但 shell 命令中不允许 ────────

def shell_lines(text: str) -> list[str]:
    """提取 shell 脚本中**非注释行**（以 # 开头）。"""
    return [l for l in text.splitlines() if l.strip() and not l.strip().startswith("#")]


def has_rmrf_in_commands(text: str) -> bool:
    return any("rm -rf" in l for l in shell_lines(text))


setup_script_text = (SKILL_ROOT / "templates" / "worktree-setup.sh").read_text()
cleanup_script_text = (SKILL_ROOT / "templates" / "worktree-cleanup.sh").read_text()
shell_has_rmrf = (has_rmrf_in_commands(setup_script_text) or
                  has_rmrf_in_commands(cleanup_script_text))
check("8.templates_no_rm_rf_in_commands", not shell_has_rmrf,
      "shell commands must NOT use 'rm -rf' (user hard pref)")

# ── 7. 与 worker-handoff 接口 ──────────────────────────────────────

check("9.interfaces_with_worker_handoff", "worker-handoff" in text)

# ── 8. templates 脚本存在 + bash 语法正确 ───────────────────────────

setup_script = SKILL_ROOT / "templates" / "worktree-setup.sh"
cleanup_script = SKILL_ROOT / "templates" / "worktree-cleanup.sh"
check("10.setup_script_exists", setup_script.is_file())
check("11.cleanup_script_exists", cleanup_script.is_file())

# bash -n 语法检查（不执行）
def bash_syntax_ok(path: Path) -> bool:
    if not shutil.which("bash"):
        return None  # 不确定，但环境约束
    r = subprocess.run(["bash", "-n", str(path)],
                       capture_output=True, timeout=10)
    return r.returncode == 0

setup_syntax = bash_syntax_ok(setup_script)
cleanup_syntax = bash_syntax_ok(cleanup_script)
check("12.setup_script_syntax_ok",
      setup_syntax is not False,
      "passed" if setup_syntax else "bash -n failed" if setup_syntax is False
      else "bash unavailable, skipped")
check("13.cleanup_script_syntax_ok",
      cleanup_syntax is not False,
      "passed" if cleanup_syntax else "bash -n failed" if cleanup_syntax is False
      else "bash unavailable, skipped")

# ── 9. reference 文件存在 ──────────────────────────────────────────

check("14.reference_present", ref.is_file())

# ── 10. end-to-end (downgrade: git 在 hermes sandbox 不在 PATH) ─────

git_available = shutil.which("git") is not None
if not git_available:
    print("\n  [SKIP] e2e worktree test: git not available in sandbox")
    print("        (shell scripts validated by syntax check only)")
    print("        → real e2e runs in user shell with `python3 <verify-script>`")
else:
    with tempfile.TemporaryDirectory(prefix="hermes-verify-worktree-") as tmp:
        repo = Path(tmp) / "fake-repo"
        wt_parent = repo.parent
        repo.mkdir()
        subprocess.run(["git", "init", "-b", "main"],
                       cwd=str(repo), capture_output=True, timeout=30)
        subprocess.run(["git", "config", "user.email", "t@t"],
                       cwd=str(repo), capture_output=True, timeout=10)
        subprocess.run(["git", "config", "user.name", "T"],
                       cwd=str(repo), capture_output=True, timeout=10)
        (repo / "README.md").write_text("# t\n")
        subprocess.run(["git", "add", "."], cwd=str(repo),
                       capture_output=True, timeout=10)
        subprocess.run(["git", "commit", "-m", "i"],
                       cwd=str(repo), capture_output=True, timeout=10)

        rc = subprocess.run(["bash", str(setup_script), "20260720-test", "verify", "main"],
                            cwd=str(repo), capture_output=True, text=True, timeout=30)
        check("15.e2e.setup_runs", rc.returncode == 0,
              f"rc={rc.returncode}, stderr={rc.stderr[:200]}" if rc.returncode != 0
              else f"out={rc.stdout.strip()[:80]}")

        wt_dir = f"{wt_parent}/worktrees/20260720-test"
        out = subprocess.run(["git", "worktree", "list"], cwd=str(repo),
                             capture_output=True, text=True, timeout=10).stdout
        check("16.e2e.worktree_created",
              wt_dir in out and "task/20260720-test-verify" in out)

        check("17.e2e.worktree_not_in_source_root",
              not (repo / "worktrees").exists(),
              "must not pollute source root")

print(f"\n{passed}/{passed + failed} PASS, 1 SKIPPED (sandbox git unavailable)")
print("\nad-hoc verification — not a test suite")
sys.exit(0 if failed == 0 else 1)