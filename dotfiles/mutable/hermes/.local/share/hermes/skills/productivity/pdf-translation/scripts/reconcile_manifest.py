#!/usr/bin/env python3
"""续译前对账：比对 manifest.json 状态与实际文件，修复中断会话留下的漂移。

场景：上一轮会话写完 translated/<id>.zh.md 后、在「更新 manifest + 把原文移入
archive/」之前中断，导致 manifest 仍标 pending、untranslated/ 原文未归档。本脚本
检测这种孤儿译文并回填状态。

用法：
  python3 reconcile_manifest.py [WORKSPACE] [--repair] [--backup]

  WORKSPACE   工作区目录（默认当前目录）。需含 manifest.json，以及
              source/ untranslated/ translated/ archive/ 四子目录。
  默认（无 --repair）：只报告，绝不修改任何文件。
  --repair     回填：把 pending 且有 .zh.md 的 chunk 标为 translated，并把
              untranslated/<id>.en.md 移入 archive/（archive 已有则删 untranslated 副本）。
  --backup     修复前先备份 manifest.json 为 manifest.json.bak。
"""
import argparse, json, os, shutil, sys


def main():
    ap = argparse.ArgumentParser(description="Reconcile pdf-translation manifest vs files")
    ap.add_argument("workspace", nargs="?", default=".")
    ap.add_argument("--repair", action="store_true", help="回填漂移状态（默认只报告）")
    ap.add_argument("--backup", action="store_true", help="修复前备份 manifest.json")
    args = ap.parse_args()

    base = os.path.abspath(args.workspace)
    man_path = os.path.join(base, "manifest.json")
    if not os.path.exists(man_path):
        print(f"错误：找不到 {man_path}", file=sys.stderr)
        sys.exit(1)

    man = json.load(open(man_path, encoding="utf-8"))
    chunks = man.get("chunks", [])

    reports = []  # (id, kind, detail)
    backfill = []  # chunk dicts to mark translated
    archive_moves = []  # (src, dst)

    for c in chunks:
        cid = c["id"]
        status = c.get("status")
        zh = os.path.join(base, "translated", f"{cid}.zh.md")
        un = os.path.join(base, "untranslated", f"{cid}.en.md")
        arch = os.path.join(base, "archive", f"{cid}.en.md")
        has_zh = os.path.exists(zh)
        has_un = os.path.exists(un)
        has_arch = os.path.exists(arch)

        if status == "translated":
            if not has_zh:
                reports.append((cid, "BAD", "manifest=translated 但 translated/ 无 .zh.md"))
            if has_un:
                reports.append((cid, "BAD", "manifest=translated 但 untranslated/ 仍有原文（未归档）"))
            if not has_arch:
                reports.append((cid, "WARN", "manifest=translated 但 archive/ 无归档原文"))
        elif status == "pending":
            if has_zh:
                reports.append((cid, "DRIFT", "manifest=pending 但 translated/ 已有 .zh.md（漏登记）"))
                backfill.append(c)
                if has_un:
                    if has_arch:
                        archive_moves.append((un, None))  # 删 untranslated 副本
                    else:
                        archive_moves.append((un, arch))
            if not has_un and not has_arch and not has_zh:
                reports.append((cid, "WARN", "pending 且 untranslated/ 与 archive/ 均无原文（两处皆缺）"))

    # 汇总
    print(f"工作区: {base}")
    print(f"切片总数: {len(chunks)}")
    n_trans = sum(1 for c in chunks if c.get("status") == "translated")
    n_pend = sum(1 for c in chunks if c.get("status") == "pending")
    print(f"manifest 标记: translated={n_trans} pending={n_pend}")
    print(f"实际文件: translated/*.zh.md={len([f for f in os.listdir(os.path.join(base,'translated')) if f.endswith('.zh.md')])}")
    print()
    if not reports:
        print("✅ 状态一致，无需修复。")
        return
    for cid, kind, msg in reports:
        print(f"  [{kind}] {cid}: {msg}")

    if not args.repair:
        print("\n（默认只报告。加 --repair 可回填 DRIFT 项并归档原文。）")
        return

    # 执行修复
    if args.backup:
        shutil.copy2(man_path, man_path + ".bak")
    for c in backfill:
        c["status"] = "translated"
        c["translated"] = f"translated/{c['id']}.zh.md"
    for src, dst in archive_moves:
        if dst is None:
            os.remove(src)
        else:
            shutil.move(src, dst)
    json.dump(man, open(man_path, "w", encoding="utf-8"), indent=2, ensure_ascii=False)

    print(f"\n✅ 已修复: 回填 {len(backfill)} 个译文状态, 归档/清理原文 {len(archive_moves)} 个。")
    print("建议接着跑 assemble.py 确认拼接无误。")


if __name__ == "__main__":
    main()
