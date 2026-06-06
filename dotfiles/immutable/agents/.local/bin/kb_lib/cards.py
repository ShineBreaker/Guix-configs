# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT
import argparse
import json
import os
import re
import shlex
import sys
from collections import Counter
from datetime import datetime
from pathlib import Path

from kb_lib.core import (  # noqa: E402
    KB_ROOT,
    KB_EXPERIENCES,
    KB_MEMORY,
    KB_PATTERNS,
    KB_INBOX,
    VALID_TYPES,
    VALID_OWNERS,
    VALID_ENTRY_TYPES,
    VALID_STATUSES,
    STALE_DAYS,
    STALE_THRESHOLD_DAYS,
    ARCHIVE_THRESHOLD_DAYS,
    CARD_TEMPLATES,
    ENTRY_BODY_DEFAULTS,
    die,
    now,
    today,
    timestamp_id,
    parse_org_prop,
    read_org_title,
    _card_dict,
    _load_index,
    _save_index,
    _rebuild_index,
    _upsert_card,
    _iter_search_targets,
    _query_terms,
    _line_contains_any,
    _merge_ranges,
    _range_score,
    _build_template,
    ensure_dirs,
    touch_card,
    _resolve_card,
)


def cmd_add(args: argparse.Namespace) -> None:
    """
    创建一张新的经验卡片并写入 experiences/ 目录。

    参数解析后根据 entry_type 自动推断 type 和 owner，
    生成符合 Org mode 格式的卡片文件。
    """
    title = args.title or ""
    category = args.category or "general"
    tech = args.tech or ""
    type_ = args.type or "workflow"
    owner = args.owner or "ai"
    entry_type = args.entry or ""
    summary = args.summary or ""
    use_stdin = args.stdin

    if not title:
        die("必须指定 --title")

    if "/" in category or "\\" in category or ".." in category:
        die(f"类别名不能包含路径分隔符或 '..': {category}")

    if entry_type and entry_type not in VALID_ENTRY_TYPES | {""}:
        die(f"--entry 仅支持: {', '.join(sorted(VALID_ENTRY_TYPES))}")

    # ── 白名单校验：对非标准值打印警告 ─────────────────────────────────────
    if type_ not in VALID_TYPES:
        print(
            f"警告: type '{type_}' 不在标准值中 ({', '.join(sorted(VALID_TYPES))})",
            file=sys.stderr,
        )
    if owner not in VALID_OWNERS:
        print(
            f"警告: owner '{owner}' 不在标准值中 ({', '.join(sorted(VALID_OWNERS))})",
            file=sys.stderr,
        )

    # entry_type 自动推断（仅在用户未显式指定时）
    if entry_type and not args.type:
        if entry_type in ("mistake", "ascended"):
            type_ = "debug"
        elif entry_type == "note":
            type_ = "workflow"

    if entry_type and not args.owner:
        owner = "collab"

    if not tech:
        tech = category

    id_ = timestamp_id()
    ts = now()
    filename = f"{id_}-{type_}-{category}.org"

    # 构建标签行
    tags_parts = [category, type_, owner]
    if tech and tech != category:
        tags_parts.append(tech)
    if entry_type:
        tags_parts.append(entry_type)
    tags_line = ":" + ":".join(tags_parts) + "::"

    filepath = KB_EXPERIENCES / category / filename
    filepath.parent.mkdir(parents=True, exist_ok=True)

    # 读取 stdin 内容
    body = ""
    if use_stdin:
        body = sys.stdin.read()

    # ── 组装 Org 内容 ──────────────────────────────────────────────────────
    lines = []
    lines.append(f"* DONE {title}")
    lines.append(":PROPERTIES:")
    lines.append(f":ID:       {id_}")
    lines.append(f":CREATED:  [{ts}]")
    lines.append(f":CATEGORY: {category}")
    lines.append(f":TECH:     {tech}")
    lines.append(f":TYPE:     {type_}")
    if entry_type:
        lines.append(f":ENTRY_TYPE: {entry_type}")
    lines.append(":STATUS:   done")
    lines.append(f":LAST_USED:   [{ts}]")
    lines.append(f":LAST_VERIFIED: [{ts}]")
    lines.append(":EFFORT:")
    lines.append(f":OWNER:    {owner}")
    lines.append(":END:")
    lines.append(tags_line)
    lines.append("")

    # 如果 stdin 已包含 ** 小节，直接作为完整正文写入
    if use_stdin and re.search(r"^\*\* ", body, re.MULTILINE):
        lines.append(body.rstrip("\n"))
    else:
        lines.append("** 任务描述")
        lines.append(summary or title)
        lines.append("")
        lines.extend(_build_template(entry_type, body))

    filepath.write_text("\n".join(lines) + "\n", encoding="utf-8")

    # 增量更新 JSON 索引
    index = _load_index()
    _upsert_card(index, filepath)
    _save_index(index)

    print(filepath)


def cmd_get(args: argparse.Namespace) -> None:
    """读取指定卡片的完整内容。支持完整路径或 ID 部分匹配。

    安全限制：直接路径必须在 KB_ROOT 内，防止任意文件读取。
    """
    target = args.target
    if not target:
        die("用法: kb get <卡片文件名或ID>")

    p = Path(target)
    # 安全检查：绝对路径必须在 KB_ROOT 内
    if p.is_absolute():
        try:
            p.resolve().relative_to(KB_ROOT.resolve())
        except ValueError:
            die(f"路径超出知识库范围: {target}")
    if p.is_file():
        print(p.read_text(encoding="utf-8"), end="")
        touch_card(p, "LAST_USED")
        return

    # 在 experiences/ 中模糊匹配
    candidates = list(KB_EXPERIENCES.rglob(f"*{target}*"))
    candidates = [c for c in candidates if not c.is_symlink() and c.is_file()]
    if candidates:
        print(candidates[0].read_text(encoding="utf-8"), end="")
        touch_card(candidates[0], "LAST_USED")
        return

    die(f"未找到卡片: {target}")


# ═══════════════════════════════════════════════════════════════════════════════
# 子命令: list — 列出卡片
# ═══════════════════════════════════════════════════════════════════════════════


def cmd_list(args: argparse.Namespace) -> None:
    """列出经验卡片，支持过滤和数量限制。默认显示最近 DEFAULT_LIST_COUNT 条，输出 JSON。"""
    recent = (
        args.recent
        if args.recent is not None
        else (0 if args.all else DEFAULT_LIST_COUNT)
    )
    index = _load_index()
    matched = []
    for c in index["cards"]:
        if args.category and c["category"] != args.category:
            continue
        if args.type and c["type"] != args.type:
            continue
        if args.owner and c["owner"] != args.owner:
            continue
        matched.append(c)
        if recent > 0 and len(matched) >= recent:
            break

    compact = [
        {
            k: c.get(k, "")
            for k in ("id", "title", "category", "type", "tech", "owner", "created")
        }
        for c in matched
    ]
    print(json.dumps(compact, ensure_ascii=False, indent=2))


# ═══════════════════════════════════════════════════════════════════════════════
# 子命令: search — 全文检索
# ═══════════════════════════════════════════════════════════════════════════════


def cmd_search(args: argparse.Namespace) -> None:
    """在 experiences/ 和 patterns.org 中全文检索。"""
    query = args.query
    context = args.context

    if args.regex:
        targets = [str(KB_EXPERIENCES), str(KB_PATTERNS)]
        if shutil.which("rg"):
            cmd = ["rg", "--color=never", "-n", "-C", str(context), query] + targets
        else:
            cmd = ["grep", "-r", "-n", "-C", str(context), query] + targets

        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode == 0:
            print(result.stdout, end="")
        else:
            print(f"未找到匹配: {query}")
        return

    terms = _query_terms(query)
    if not terms:
        die("必须提供搜索关键词")

    normalized_terms = terms if args.case_sensitive else [t.casefold() for t in terms]
    normalized_phrase = query if args.case_sensitive else query.casefold()
    matches = []

    for filepath in _iter_search_targets():
        try:
            content = filepath.read_text(encoding="utf-8")
        except OSError:
            continue

        haystack = content if args.case_sensitive else content.casefold()
        term_hits = [
            term for raw, term in zip(terms, normalized_terms) if term in haystack
        ]
        if not term_hits:
            continue
        if args.all_terms and len(term_hits) != len(terms):
            continue

        occurrence_count = sum(haystack.count(term) for term in term_hits)
        phrase_bonus = 50 if normalized_phrase and normalized_phrase in haystack else 0
        title = read_org_title(content)
        title_haystack = title if args.case_sensitive else title.casefold()
        title_bonus = 25 * sum(1 for term in term_hits if term in title_haystack)
        score = len(term_hits) * 100 + occurrence_count + phrase_bonus + title_bonus

        matches.append(
            {
                "filepath": filepath,
                "content": content,
                "score": score,
                "matched": [
                    raw
                    for raw, term in zip(terms, normalized_terms)
                    if term in haystack
                ],
                "title": title,
            }
        )

    if not matches:
        print(f"未找到匹配: {query}")
        return

    matches.sort(key=lambda item: (-item["score"], str(item["filepath"])))
    limit = max(1, args.limit)
    for idx, match in enumerate(matches[:limit]):
        filepath = match["filepath"]
        rel = (
            filepath.relative_to(KB_ROOT)
            if filepath.is_relative_to(KB_ROOT)
            else filepath
        )
        print(
            f"== {rel} | score={match['score']} | matched={', '.join(match['matched'])} =="
        )
        if match["title"] != "unknown":
            print(f"title: {match['title']}")

        lines = match["content"].splitlines()
        hit_indexes = [
            i
            for i, line in enumerate(lines)
            if _line_contains_any(line, normalized_terms, args.case_sensitive)
        ]
        ranges = _merge_ranges(
            [
                (max(0, i - context), min(len(lines) - 1, i + context))
                for i in hit_indexes
            ]
        )
        selected_ranges = sorted(
            sorted(
                ranges,
                key=lambda r: (
                    -_range_score(
                        lines, r[0], r[1], normalized_terms, args.case_sensitive
                    ),
                    r[0],
                ),
            )[: max(1, args.max_blocks)]
        )
        for start, end in selected_ranges:
            for line_idx in range(start, end + 1):
                sep = ":" if line_idx in hit_indexes else "-"
                print(f"{filepath}{sep}{line_idx + 1}{sep}{lines[line_idx]}")
            if (start, end) != selected_ranges[-1]:
                print("--")
        if idx != min(len(matches), limit) - 1:
            print()


# ═══════════════════════════════════════════════════════════════════════════════
# 子命令: fields — 列出已有字段值
# ═══════════════════════════════════════════════════════════════════════════════


def cmd_fields(args: argparse.Namespace) -> None:
    """
    从 JSON 索引统计已有的 category/tech/type/owner 值及出现次数。
    帮助写入新卡片时优先复用已有标签。
    """
    show = {
        "category": args.category,
        "tech": args.tech,
        "type": args.type_,
        "owner": args.owner,
    }
    if not any(show.values()):
        for k in show:
            show[k] = True

    counters = {k: Counter() for k in show}
    index = _load_index()

    for c in index["cards"]:
        if show["category"] and c.get("category"):
            counters["category"][c["category"]] += 1
        if show["tech"] and c.get("tech"):
            counters["tech"][c["tech"]] += 1
        if show["type"] and c.get("type"):
            counters["type"][c["type"]] += 1
        if show["owner"] and c.get("owner"):
            counters["owner"][c["owner"]] += 1

    labels = {"category": "category", "tech": "tech", "type": "type", "owner": "owner"}
    for key, label in labels.items():
        if show[key]:
            print(f"── {label} ──")
            if not counters[key]:
                print("  (无)")
            else:
                for k, c in sorted(counters[key].items()):
                    print(f"  {k} ({c})")


# ═══════════════════════════════════════════════════════════════════════════════
# 子命令: tags — 按标签检索
# ═══════════════════════════════════════════════════════════════════════════════


def cmd_tags(args: argparse.Namespace) -> None:
    """按标签搜索卡片文件，标签以冒号包裹形式存储在 Org 属性中。"""
    if not args.tags:
        die("用法: kb tags <标签> [标签2 ...]")

    for tag in args.tags:
        print(f"── 标签: {tag} ──")
        if shutil.which("rg"):
            result = subprocess.run(
                ["rg", "--color=never", "-l", f":{tag}:", str(KB_EXPERIENCES)],
                capture_output=True,
                text=True,
            )
        else:
            result = subprocess.run(
                ["grep", "-rl", f":{tag}:", str(KB_EXPERIENCES)],
                capture_output=True,
                text=True,
            )
        if result.returncode == 0 and result.stdout.strip():
            print(result.stdout, end="")
        else:
            print("  (无匹配)")


# ═══════════════════════════════════════════════════════════════════════════════
# MEMORY 系统：内部工具函数
# ═══════════════════════════════════════════════════════════════════════════════


def cmd_inbox(args: argparse.Namespace) -> None:
    """快速捕获一个想法或待办到 inbox.org。"""
    content = args.content
    if not content:
        content = sys.stdin.read()
    if not content.strip():
        die("必须指定内容或通过 stdin 管道输入")

    ensure_dirs()
    ts = now()
    entry = f"\n** [{ts}] {content.strip()}\n"
    with KB_INBOX.open("a", encoding="utf-8") as f:
        f.write(entry)
    print(f"已捕获到 {KB_INBOX}")


# ═══════════════════════════════════════════════════════════════════════════════
# 子命令: stats — 知识库统计
# ═══════════════════════════════════════════════════════════════════════════════


def cmd_stats(args: argparse.Namespace) -> None:
    """输出知识库的统计概览。"""
    ensure_dirs()
    index = _load_index()
    cards = index["cards"]
    total = len(cards)

    cat_counter: Counter = Counter()
    type_counter: Counter = Counter()
    owner_counter: Counter = Counter()
    tech_counter: Counter = Counter()
    dates = []

    for c in cards:
        cat_counter[c.get("category", "unknown")] += 1
        type_counter[c.get("type", "unknown")] += 1
        owner_counter[c.get("owner", "unknown")] += 1
        tech_counter[c.get("tech", "unknown")] += 1
        if c.get("created"):
            dates.append(c["created"])

    print(f"═══ 知识库统计 ═══")
    print(f"总卡片数: {total}")
    if dates:
        print(f"时间范围: {min(dates)} ~ {max(dates)}")
    if KB_PATTERNS.exists():
        pat_text = KB_PATTERNS.read_text(encoding="utf-8")
        pat_count = len(re.findall(r"^\*\* ", pat_text, re.MULTILINE))
        print(f"模式数量: {pat_count}")
    print()

    for label, counter in [
        ("按类别", cat_counter),
        ("按类型", type_counter),
        ("按执行者", owner_counter),
        ("按技术栈", tech_counter),
    ]:
        print(f"── {label} ──")
        for k, v in counter.most_common():
            bar = "█" * v
            print(f"  {k:20s} {v:3d} {bar}")
        print()

    # MEMORY 统计
    if KB_MEMORY.exists():
        mem_text = KB_MEMORY.read_text(encoding="utf-8")
        fb_count = len(re.findall(r"^\*\* F\d+", mem_text, re.MULTILINE))
        ref_count = len(re.findall(r"^\*\* R\d+", mem_text, re.MULTILINE))
        dep_section = (
            mem_text[mem_text.find("* deprecated") :]
            if "* deprecated" in mem_text
            else ""
        )
        dep_count = len(re.findall(r"^\*\* F\d+", dep_section, re.MULTILINE))
        proj_section = ""
        if "* project" in mem_text and "* reference" in mem_text:
            proj_start = mem_text.find("* project")
            proj_end = mem_text.find("* reference")
            if proj_start < proj_end:
                proj_section = mem_text[proj_start:proj_end]
        proj_count = len(
            re.findall(r"^\*\* .+\n\s+:PROPERTIES:", proj_section, re.MULTILINE)
        )
        stale_count = 0
        for m in re.finditer(r":UPDATED:\s*\[(\d{4}-\d{2}-\d{2})\]", mem_text):
            try:
                updated = datetime.strptime(m.group(1), "%Y-%m-%d")
                if (datetime.now() - updated).days > STALE_DAYS:
                    stale_count += 1
            except ValueError:
                pass
        print("── MEMORY ──")
        print(f"  feedback 条目数: {fb_count}")
        print(f"  project 索引数: {proj_count}")
        print(f"  reference 条目数: {ref_count}")
        print(f"  deprecated 条目数: {dep_count}")
        print(f"  stale (>{STALE_DAYS}d): {stale_count}")


# ═══════════════════════════════════════════════════════════════════════════════
# 子命令: connect — 双向链接
# ═══════════════════════════════════════════════════════════════════════════════


def cmd_connect(args: argparse.Namespace) -> None:
    """在两张卡片之间建立双向链接。"""
    id_a = args.id_a
    id_b = args.id_b
    desc = args.desc or ""

    if id_a == id_b:
        die("不能链接同一张卡片")

    file_a = _resolve_card(id_a)
    file_b = _resolve_card(id_b)
    if not file_a:
        die(f"未找到卡片: {id_a}")
    if not file_b:
        die(f"未找到卡片: {id_b}")

    _append_link(file_a, file_b, desc)
    _append_link(file_b, file_a, desc)
    print(f"已建立双向链接: {file_a.name} ↔ {file_b.name}")


def _append_link(filepath: Path, target: Path, desc: str) -> None:
    """在卡片的 ** 相关链接 章节追加链接。"""
    import os as _os

    content = filepath.read_text(encoding="utf-8")
    # 使用从源文件到目标文件的相对路径（Org 按文件位置解析）
    rel_path = _os.path.relpath(target, filepath.parent)
    link = (
        f"  [[file:{rel_path}][{read_org_title(target.read_text(encoding='utf-8'))}]]"
    )
    if desc:
        link += f" — {desc}"

    if "** 相关链接" in content:
        content = content.replace(
            "** 相关链接\n",
            f"** 相关链接\n{link}\n",
            1,
        )
    else:
        content = content.rstrip("\n") + f"\n\n** 相关链接\n{link}\n"

    filepath.write_text(content, encoding="utf-8")


# ═══════════════════════════════════════════════════════════════════════════════
# 子命令: update — 更新卡片
# ═══════════════════════════════════════════════════════════════════════════════


def cmd_update(args: argparse.Namespace) -> None:
    """更新已有卡片的属性或追加内容。

    属性替换使用 .+ 匹配到行尾，避免含空格的属性值被截断。
    """
    target = args.target
    card = _resolve_card(target)
    if not card:
        die(f"未找到卡片: {target}")

    content = card.read_text(encoding="utf-8")

    # ── 更新属性（用 .+ 匹配整行值，避免空格截断）────────────────────────
    if args.status:
        if args.status not in VALID_STATUSES:
            die(f"无效状态: {args.status}（可选: {', '.join(sorted(VALID_STATUSES))}）")
        content = re.sub(r":STATUS:\s*.+", f":STATUS:   {args.status}", content)
        # --status stable 自动更新 LAST_VERIFIED
        if args.status == "stable":
            if ":LAST_VERIFIED:" in content:
                content = re.sub(
                    r":LAST_VERIFIED:\s*\[.+?\]", f":LAST_VERIFIED: [{now()}]", content
                )
            else:
                content = content.replace(
                    ":END:", f":LAST_VERIFIED: [{now()}]\n:END:", 1
                )
    if args.category:
        content = re.sub(r":CATEGORY:\s*.+", f":CATEGORY: {args.category}", content)
    if args.tech:
        content = re.sub(r":TECH:\s*.+", f":TECH:     {args.tech}", content)
    if args.type_:
        content = re.sub(r":TYPE:\s*.+", f":TYPE:     {args.type_}", content)
    if args.owner:
        content = re.sub(r":OWNER:\s*.+", f":OWNER:    {args.owner}", content)

    # 追加内容到指定章节
    if args.append_to and args.append_text:
        section = f"** {args.append_to}"
        if section in content:
            content = content.replace(
                section,
                f"{section}\n{args.append_text}",
                1,
            )
        else:
            content = content.rstrip("\n") + f"\n\n{section}\n{args.append_text}\n"

    # 从 stdin 追加到末尾（在 PROPERTIES 和标签之后）
    if args.stdin:
        extra = sys.stdin.read()
        if extra.strip():
            content = content.rstrip("\n") + f"\n\n{extra.strip()}\n"

    card.write_text(content, encoding="utf-8")
    print(f"已更新: {card}")


# ═══════════════════════════════════════════════════════════════════════════════
# 新命令: touch — 更新时间戳
# ═══════════════════════════════════════════════════════════════════════════════


def cmd_touch(args: argparse.Namespace) -> None:
    """更新卡片的时间戳。"""
    target = args.target
    card = _resolve_card(target)
    if not card:
        die(f"未找到卡片: {target}")

    if args.used_only:
        touch_card(card, "LAST_USED")
        print(f"已更新 LAST_USED: {card.name}")
    else:
        touch_card(card, "LAST_USED")
        touch_card(card, "LAST_VERIFIED")
        print(f"已更新 LAST_USED + LAST_VERIFIED: {card.name}")


# ═══════════════════════════════════════════════════════════════════════════════
# 新命令: merge — 合并卡片
# ═══════════════════════════════════════════════════════════════════════════════


def cmd_merge(args: argparse.Namespace) -> None:
    """将 secondary 卡片合并到 primary 卡片。"""
    primary_id = args.primary
    secondary_ids = args.secondary

    primary = _resolve_card(primary_id)
    if not primary:
        die(f"未找到主卡片: {primary_id}")

    primary_content = primary.read_text(encoding="utf-8")
    merged_from_ids = []

    for sec_id in secondary_ids:
        sec = _resolve_card(sec_id)
        if not sec:
            print(f"警告: 未找到卡片 {sec_id}，跳过", file=sys.stderr)
            continue
        if sec == primary:
            print(f"警告: 跳过自身合并 {sec_id}", file=sys.stderr)
            continue

        sec_content = sec.read_text(encoding="utf-8")
        sec_title = read_org_title(sec_content)
        sec_card_id = parse_org_prop(sec_content, "ID") or sec.stem.split("-")[0]
        merged_from_ids.append(sec_card_id)

        # 追加到 primary
        merge_section = f"\n** 合并来源: {sec_title}\n   :PROPERTIES:\n   :MERGED_FROM: {sec_card_id}\n   :END:\n\n"
        # 提取 secondary 正文
        body_lines = []
        in_props = False
        past_header = False
        for line in sec_content.split("\n"):
            if line.startswith("* DONE") or line.startswith("* TODO"):
                past_header = True
                continue
            if past_header and line.startswith(":PROPERTIES:"):
                in_props = True
                continue
            if in_props:
                if line.startswith(":END:"):
                    in_props = False
                continue
            if past_header and not in_props and re.match(r"^:\w+:", line):
                continue
            if past_header and not in_props:
                body_lines.append(line)
        body = "\n".join(body_lines).strip()
        primary_content = primary_content.rstrip("\n") + f"\n{merge_section}{body}\n"

        # 设置 secondary 为 archived
        sec_new = sec_content
        if ":STATUS:" in sec_new:
            sec_new = re.sub(r":STATUS:\s*.+", ":STATUS:   archived", sec_new)
        else:
            sec_new = sec_new.replace(":END:", ":STATUS:   archived\n:END:", 1)
        if ":MERGED_INTO:" not in sec_new:
            sec_new = sec_new.replace(":END:", f":MERGED_INTO:  {primary_id}\n:END:", 1)
        sec.write_text(sec_new, encoding="utf-8")
        print(f"  已归档: {sec.name}")

    if not merged_from_ids:
        die("没有可合并的卡片")

    # 更新 primary 的 MERGED_FROM
    merged_str = ",".join(merged_from_ids)
    if ":MERGED_FROM:" in primary_content:
        primary_content = re.sub(
            r":MERGED_FROM:\s*.+", f":MERGED_FROM: {merged_str}", primary_content
        )
    else:
        primary_content = primary_content.replace(
            ":END:", f":MERGED_FROM: {merged_str}\n:END:", 1
        )

    primary.write_text(primary_content, encoding="utf-8")

    # 更新索引
    index = _load_index()
    _upsert_card(index, primary)
    _save_index(index)
    print(f"已合并 {len(merged_from_ids)} 张卡片到: {primary.name}")


# ═══════════════════════════════════════════════════════════════════════════════
# 新命令: archive / restore — 归档与恢复
# ═══════════════════════════════════════════════════════════════════════════════


def cmd_archive(args: argparse.Namespace) -> None:
    """归档卡片或自动归档过时卡片。"""
    if getattr(args, "list_cards", False):
        _archive_list(json_output=getattr(args, "json", False))
        return

    if getattr(args, "stale", False):
        _archive_auto_stale()
        return

    # 归档指定卡片
    if not args.id:
        die("请指定卡片 ID 或使用 --stale")
    card = _resolve_card(args.id)
    if not card:
        die(f"未找到卡片: {args.id}")

    content = card.read_text(encoding="utf-8")
    if ":STATUS:" in content:
        content = re.sub(r":STATUS:\s*.+", ":STATUS:   archived", content)
    else:
        content = content.replace(":END:", ":STATUS:   archived\n:END:", 1)
    if ":ARCHIVED_AT:" not in content:
        content = content.replace(":END:", f":ARCHIVED_AT: [{now()}]\n:END:", 1)
    if getattr(args, "reason", None):
        if ":ARCHIVE_REASON:" not in content:
            content = content.replace(
                ":END:", f":ARCHIVE_REASON: {args.reason}\n:END:", 1
            )

    card.write_text(content, encoding="utf-8")
    index = _load_index()
    _upsert_card(index, card)
    _save_index(index)
    print(f"已归档: {card.name}")


def _archive_list(json_output: bool = False) -> None:
    """列出所有归档卡片。"""
    index = _load_index()
    archived = [c for c in index["cards"] if c.get("status") == "archived"]
    if not archived:
        print("无归档卡片")
        return
    if json_output:
        print(json.dumps(archived, ensure_ascii=False, indent=2))
    else:
        for c in archived:
            print(f"  {c['id']}  {c['title'][:60]}")
        print(f"\n共 {len(archived)} 张归档卡片")


def _archive_auto_stale() -> None:
    """自动归档超过阈值天数的 stale 卡片。"""
    index = _load_index()
    count = 0
    for card_info in index["cards"]:
        if card_info.get("status") != "stale":
            continue
        last_verified = card_info.get("last_verified", "")
        if not last_verified:
            continue
        try:
            verified_date = re.sub(r"[\[\]]", "", last_verified).split()[0]
            days = (datetime.now() - datetime.strptime(verified_date, "%Y-%m-%d")).days
        except (ValueError, IndexError):
            continue
        if days > ARCHIVE_THRESHOLD_DAYS:
            card = _resolve_card(card_info["id"])
            if card and card.exists():
                content = card.read_text(encoding="utf-8")
                if ":STATUS:" in content:
                    content = re.sub(r":STATUS:\s*.+", ":STATUS:   archived", content)
                if ":ARCHIVED_AT:" not in content:
                    content = content.replace(
                        ":END:", f":ARCHIVED_AT: [{now()}]\n:END:", 1
                    )
                card.write_text(content, encoding="utf-8")
                _upsert_card(index, card)
                count += 1
                print(f"  自动归档: {card.name} (>{ARCHIVE_THRESHOLD_DAYS}天未验证)")
    if count:
        _save_index(index)
    print(f"自动归档完成: {count} 张卡片")


def cmd_restore(args: argparse.Namespace) -> None:
    """恢复归档卡片。"""
    card = _resolve_card(args.id)
    if not card:
        die(f"未找到卡片: {args.id}")

    new_status = args.status or "stable"
    if new_status not in VALID_STATUSES:
        die(f"无效状态: {new_status}（可选: {', '.join(sorted(VALID_STATUSES))}）")

    content = card.read_text(encoding="utf-8")
    if ":STATUS:" in content:
        content = re.sub(r":STATUS:\s*.+", f":STATUS:   {new_status}", content)
    content = re.sub(r":ARCHIVED_AT:\s*.+\n?", "", content)
    content = re.sub(r":ARCHIVE_REASON:\s*.+\n?", "", content)
    if ":LAST_VERIFIED:" in content:
        content = re.sub(
            r":LAST_VERIFIED:\s*\[.+?\]", f":LAST_VERIFIED: [{now()}]", content
        )
    else:
        content = content.replace(":END:", f":LAST_VERIFIED: [{now()}]\n:END:", 1)

    card.write_text(content, encoding="utf-8")
    index = _load_index()
    _upsert_card(index, card)
    _save_index(index)
    print(f"已恢复为 {new_status}: {card.name}")


# ═══════════════════════════════════════════════════════════════════════════════
# 新命令: deduplicate — 检测重复卡片
# ═══════════════════════════════════════════════════════════════════════════════


def cmd_deduplicate(args: argparse.Namespace) -> None:
    """基于标题相似度和 category/tech 匹配检测重复卡片。"""
    threshold = args.threshold or 0.7
    index = _load_index()
    cards_list = [c for c in index["cards"] if c.get("status") != "archived"]

    def _jaccard(s1: str, s2: str) -> float:
        """标题词级 Jaccard 相似度。"""
        w1 = set(s1.casefold().split())
        w2 = set(s2.casefold().split())
        if not w1 or not w2:
            return 0.0
        return len(w1 & w2) / len(w1 | w2)

    pairs = []
    for i in range(len(cards_list)):
        for j in range(i + 1, len(cards_list)):
            a, b = cards_list[i], cards_list[j]
            sim = _jaccard(a.get("title", ""), b.get("title", ""))
            if a.get("category") == b.get("category"):
                sim += 0.15
            if a.get("tech") and a.get("tech") == b.get("tech"):
                sim += 0.1
            sim = min(sim, 1.0)
            if sim >= threshold:
                pairs.append((a, b, sim))

    if not pairs:
        print("未检测到重复卡片")
        return

    if getattr(args, "json", False):
        output = [
            {
                "id_a": a["id"],
                "id_b": b["id"],
                "similarity": round(s, 2),
                "title_a": a["title"][:60],
                "title_b": b["title"][:60],
            }
            for a, b, s in pairs
        ]
        print(json.dumps(output, ensure_ascii=False, indent=2))
    else:
        for a, b, sim in sorted(pairs, key=lambda x: -x[2]):
            print(f"  [{sim:.0%}] {a['id']}: {a['title'][:50]}")
            print(f"         {b['id']}: {b['title'][:50]}")
        print(f"\n共 {len(pairs)} 对疑似重复 (阈值={threshold:.0%})")

    if getattr(args, "merge", False) and pairs:
        print("\n--merge 模式：请用 kb merge 手动合并")


# ═══════════════════════════════════════════════════════════════════════════════
# 新命令: review — 审查卡片
# ═══════════════════════════════════════════════════════════════════════════════


def cmd_review(args: argparse.Namespace) -> None:
    """审查单张卡片的状态、时效性、关联数和质量。"""
    card = _resolve_card(args.id)
    if not card:
        die(f"未找到卡片: {args.id}")

    content = card.read_text(encoding="utf-8")
    card_id = parse_org_prop(content, "ID") or card.stem.split("-")[0]
    title = read_org_title(content)
    status = parse_org_prop(content, "STATUS") or "done"
    last_verified = parse_org_prop(content, "LAST_VERIFIED")
    created = parse_org_prop(content, "CREATED")

    # 计算时效性
    days_since_verified = None
    if last_verified:
        try:
            vd = re.sub(r"[\[\]]", "", last_verified).split()[0]
            days_since_verified = (
                datetime.now() - datetime.strptime(vd, "%Y-%m-%d")
            ).days
        except (ValueError, IndexError):
            pass

    # 计算关联数
    link_count = len(re.findall(r"\[\[file:", content))

    # 质量检查
    issues = []
    if not parse_org_prop(content, "CATEGORY"):
        issues.append("缺少 CATEGORY")
    if not parse_org_prop(content, "TECH"):
        issues.append("缺少 TECH")
    if link_count == 0:
        issues.append("无关联链接（孤立卡片）")

    # 状态建议
    if status == "done" and days_since_verified is None:
        suggestion = "建议策展后设为 stable"
    elif status == "stale":
        suggestion = "建议验证后设为 stable 或归档"
    elif status == "archived":
        suggestion = "已归档，可恢复或删除"
    else:
        suggestion = "状态良好"

    print(f"=== 卡片审查: {card_id} ===")
    print(f"标题: {title}")
    print(f"状态: {status}")
    print(f"创建: {created or '未知'}")
    print(f"最后验证: {last_verified or '未验证'}")
    if days_since_verified is not None:
        print(f"距上次验证: {days_since_verified} 天")
    print(f"关联数: {link_count}")
    print(f"建议: {suggestion}")
    if issues:
        print("问题:")
        for issue in issues:
            print(f"  ❌ {issue}")
    else:
        print("质量检查: ✅ 全部通过")

    # --fix 模式
    if getattr(args, "fix", False) and issues:
        fixes = []
        if "缺少 CATEGORY" in issues:
            content = re.sub(r":CATEGORY:\s*\n", ":CATEGORY: general\n", content)
            fixes.append("已设置 CATEGORY=general")
        if "缺少 TECH" in issues:
            content = re.sub(r":TECH:\s*\n", ":TECH: general\n", content)
            fixes.append("已设置 TECH=general")
        if fixes:
            card.write_text(content, encoding="utf-8")
            for fix in fixes:
                print(f"  🔧 {fix}")


# ═══════════════════════════════════════════════════════════════════════════════
# 增强: cmd_stats --health
# ═══════════════════════════════════════════════════════════════════════════════


def cmd_health(args: argparse.Namespace) -> None:
    """输出知识库健康度报告。"""
    ensure_dirs()
    index = _load_index()
    cards = index["cards"]
    total = len(cards)

    # 状态分布
    status_counts = Counter(c.get("status", "done") for c in cards)
    done = status_counts.get("done", 0)
    stable = status_counts.get("stable", 0)
    stale = status_counts.get("stale", 0)
    archived = status_counts.get("archived", 0)

    print("=== 知识库健康度报告 ===")
    print(
        f"总卡片: {total} | done: {done} | stable: {stable} | stale: {stale} | archived: {archived}"
    )
    print()

    # 孤立率
    linked_cards = set()
    for f in KB_EXPERIENCES.rglob("*.org"):
        if f.is_symlink():
            continue
        content = f.read_text(encoding="utf-8")
        if "[[file:" in content:
            linked_cards.add(parse_org_prop(content, "ID") or f.stem.split("-")[0])
    isolated = total - len(linked_cards)
    isolated_pct = (isolated / total * 100) if total > 0 else 0
    isolated_icon = "✅" if isolated_pct < 15 else "⚠️" if isolated_pct < 25 else "❌"

    # 过时率
    stale_pct = (stale / total * 100) if total > 0 else 0
    stale_icon = "✅" if stale_pct < 10 else "⚠️" if stale_pct < 20 else "❌"

    # 类型偏斜
    type_counts = Counter(c.get("type", "unknown") for c in cards)
    max_type, max_type_count = (
        type_counts.most_common(1)[0] if type_counts else ("none", 0)
    )
    max_type_pct = (max_type_count / total * 100) if total > 0 else 0
    type_icon = "✅" if max_type_pct < 45 else "⚠️"

    # 薄弱类别
    cat_counts = Counter(c.get("category", "unknown") for c in cards)
    weak_cats = [(cat, cnt) for cat, cnt in cat_counts.items() if cnt < 3]

    print("── 健康指标 ──")
    print(f"  孤立率:     {isolated_pct:.0f}% [阈值 <15%] {isolated_icon}")
    print(f"  过时率:      {stale_pct:.0f}% [阈值 <10%] {stale_icon}")
    print(f"  类型偏斜:   {max_type} {max_type_pct:.0f}% [阈值 <45%] {type_icon}")
    if weak_cats:
        cats_str = ", ".join(f"{cat}({cnt})" for cat, cnt in weak_cats)
        print(f"  薄弱类别:   {cats_str} [阈值 ≥3] ❌")
    else:
        print(f"  薄弱类别:   无 [阈值 ≥3] ✅")

    # MEMORY 统计
    if KB_MEMORY.exists():
        mem_text = KB_MEMORY.read_text(encoding="utf-8")
        fb_count = len(re.findall(r"^\*\* F\d+", mem_text, re.MULTILINE))
        stale_fb = 0
        for m in re.finditer(r":UPDATED:\s*\[(\d{4}-\d{2}-\d{2})\]", mem_text):
            try:
                updated = datetime.strptime(m.group(1), "%Y-%m-%d")
                if (datetime.now() - updated).days > STALE_DAYS:
                    stale_fb += 1
            except ValueError:
                pass
        proj_section = ""
        if "* project" in mem_text and "* reference" in mem_text:
            proj_start = mem_text.find("* project")
            proj_end = mem_text.find("* reference")
            if proj_start < proj_end:
                proj_section = mem_text[proj_start:proj_end]
        proj_count = len(
            re.findall(r"^\*\* .+\n\s+:PROPERTIES:", proj_section, re.MULTILINE)
        )
        fb_icon = "✅" if stale_fb < fb_count // 2 else "⚠️"
        print()
        print("── 记忆 ──")
        print(f"  feedback: {fb_count} (stale: {stale_fb}) {fb_icon}")
        print(f"  project:  {proj_count}")
