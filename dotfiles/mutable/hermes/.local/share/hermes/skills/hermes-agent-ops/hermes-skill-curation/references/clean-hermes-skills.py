#!/usr/bin/env python3
"""hermes-skill-curation 的 trash-based 清理脚本(XDG trash 范式)。

用法:
  python3 clean-hermes-skills.py --dry-run    # 预览
  python3 clean-hermes-skills.py --apply      # 真正执行

逻辑:
  1. rglob 所有 SKILL.md,拿真实 name(路径倒数第二段,处理 mlops/ 嵌套)
  2. 用 KEEP 集合 - existing = to_delete
  3. 先 chmod -R u+w ~/.local/share/hermes/skills/(read-only 0555 破解)
  4. shutil.move 到 ~/.local/share/hermes/Trash/files/(注意是 hermes 自己的 Trash,不是 ~/.local/share/Trash/)
  5. 写 .trashinfo 供恢复

要改 KEEP 集合,直接编辑脚本顶部 KEEP_NAMES。
"""
import os
import shutil
import datetime
import pathlib
import sys

SKILLS_ROOT = pathlib.Path.home() / ".local/share/hermes/skills"
TRASH_FILES = SKILLS_ROOT.parent / "Trash/files"
TRASH_INFO = SKILLS_ROOT.parent / "Trash/info"

# 决策保留集合 — 每次精简按用户答复调整
KEEP_NAMES = {
    # 视觉/设计
    "architecture-diagram", "claude-design", "popular-web-designs", "sketch",
    # 音乐/媒体
    "gif-search", "heartmula", "songsee", "songwriting-and-ai-music", "youtube-content",
    # PPT/文档
    "nano-pdf", "ocr-and-documents", "powerpoint",
    # 工具/Agent
    "claude-code", "dogfood", "hermes-agent",
}


def discover_existing():
    """rglob SKILL.md,返回 {name: [(category, full_path), ...]} 映射。
    处理 mlops/{evaluation,inference,models} 嵌套。
    """
    out = {}
    for skill_md in SKILLS_ROOT.rglob("SKILL.md"):
        parts = skill_md.relative_to(SKILLS_ROOT).parts
        if len(parts) < 2:
            continue
        name = parts[-2]  # 总是倒数第二段
        out.setdefault(name, []).append(skill_md.parent)
    # 顶层 category 下的 skill(元组形式)
    for top in SKILLS_ROOT.iterdir():
        if top.is_dir() and (top / "SKILL.md").exists() and top.name not in {
            "evaluation", "inference", "models"
        }:
            out.setdefault(top.name, []).append(top)
    return out


def main():
    if "--apply" not in sys.argv and "--dry-run" not in sys.argv:
        print("用法: --dry-run 预览 / --apply 执行")
        sys.exit(1)

    existing = discover_existing()
    to_delete = sorted(set(existing) - KEEP_NAMES)
    to_keep = sorted(set(existing) & KEEP_NAMES)
    not_on_disk = sorted(KEEP_NAMES - set(existing))

    print(f"磁盘上真实存在的 skill: {len(existing)}")
    print(f"决策保留: {len(KEEP_NAMES)} (磁盘上 {len(to_keep)}, 不在磁盘 {len(not_on_disk)})")
    print(f"待删除: {len(to_delete)}\n")

    print("== 保留(实际在磁盘上) ==")
    for n in to_keep:
        print(f"  + {n}")
    if not_on_disk:
        print("\n== 保留清单中磁盘上不存在的(不操作) ==")
        for n in not_on_disk:
            print(f"  - {n}")
    print("\n== 待删除 ==")
    for n in to_delete:
        print(f"  - {n}")

    if "--dry-run" in sys.argv:
        print("\n[dry-run] 不实际移动")
        sys.exit(0)

    # --- apply ---
    # 先 chmod -R u+w
    print("\n[chmod] chmod -R u+w ~/.local/share/hermes/skills/")
    os.system(f"chmod -R u+w {SKILLS_ROOT}")

    TRASH_FILES.mkdir(parents=True, exist_ok=True)
    TRASH_INFO.mkdir(parents=True, exist_ok=True)

    moved, skipped, failed = [], [], []
    for name in to_delete:
        for src in existing.get(name, []):
            if not os.access(src, os.W_OK):
                skipped.append((src, "read-only after chmod"))
                continue
            ts = datetime.datetime.now().strftime("%Y%m%d%H%M%S")
            dest = TRASH_FILES / f"{ts}-{src.name}"
            i = 1
            while dest.exists():
                dest = TRASH_FILES / f"{ts}-{i}-{src.name}"
                i += 1
            info = TRASH_INFO / f"{dest.name}.trashinfo"
            try:
                info.write_text(
                    f"[Trash Info]\nPath={src}\n"
                    f"DeletionDate={datetime.datetime.now().isoformat()}\n"
                )
                shutil.move(str(src), str(dest))
                moved.append((src, dest))
            except Exception as e:
                failed.append((src, str(e)))

    print(f"\n== 结果 ==")
    print(f"已移到 trash: {len(moved)}")
    print(f"跳过(read-only): {len(skipped)}")
    print(f"失败: {len(failed)}")
    for s, w in skipped:
        print(f"  SKIP {s} ({w})")
    for s, e in failed:
        print(f"  FAIL {s} ({e})")


if __name__ == "__main__":
    main()
