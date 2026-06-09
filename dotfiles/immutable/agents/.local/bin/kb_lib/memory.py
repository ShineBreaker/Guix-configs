# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

"""kb_memory — 知识库记忆系统：MEMORY.org 管理、项目记忆、模式管理"""

import argparse
import os
import re
import sys
from datetime import datetime
from pathlib import Path

from kb_lib.core import (
    KB_MEMORY,
    KB_MEMORIES,
    KB_PROJECTS,
    KB_ROOT,
    STALE_DAYS,
    MEMORY_ARCHIVE_DAYS,
    KB_MEMORY_ARCHIVE,
    die,
    ensure_dirs,
    today,
    now,
    _init_memory_template,
)


def _parse_memory_sections(content: str) -> dict[str, list[tuple[int, int, str]]]:
    """解析 MEMORY.org 的 `*` 顶级节。

    返回 {节名: [(起始行号, 结束行号, 节文本)]}，行号从 0 开始。
    """
    lines = content.split("\n")
    sections: dict[str, list[tuple[int, int, str]]] = {}
    cur_name = None
    cur_start = 0
    for i, line in enumerate(lines):
        m = re.match(r"^\*\s+(.+)", line)
        if m:
            if cur_name is not None:
                sections.setdefault(cur_name, []).append(
                    (cur_start, i, "\n".join(lines[cur_start:i]))
                )
            cur_name = m.group(1).strip()
            cur_start = i
    if cur_name is not None:
        sections.setdefault(cur_name, []).append(
            (cur_start, len(lines), "\n".join(lines[cur_start:]))
        )
    return sections


def _next_memory_id(section_content: str, prefix: str) -> str:
    """扫描已有 F/R 序号，返回下一个（如 F015）。"""
    existing = re.findall(rf"^\*\* {prefix}(\d+)", section_content, re.MULTILINE)
    if not existing:
        return f"{prefix}001"
    max_id = max(int(n) for n in existing)
    return f"{prefix}{max_id + 1:03d}"


def _find_section_end(lines: list[str], section_start: int) -> int:
    """找到指定 `*` 节的最后一行（下一个 `*` 节之前）。"""
    for i in range(section_start + 1, len(lines)):
        if re.match(r"^\*\s+", lines[i]):
            return i
    return len(lines)


# ═══════════════════════════════════════════════════════════════════════════════
# 子命令: memory — 管理记忆系统
# ═══════════════════════════════════════════════════════════════════════════════


def cmd_memory(args: argparse.Namespace) -> None:
    """管理 MEMORY.org 中的反馈、项目和参考记忆。"""
    ensure_dirs()

    # --get：输出 MEMORY.org 全文或指定节
    if getattr(args, "get", False):
        if not KB_MEMORY.exists():
            print("(记忆文件不存在)")
            return
        text = KB_MEMORY.read_text(encoding="utf-8")
        mem_type = getattr(args, "type", None)
        if mem_type:
            # 只输出指定节的内容
            sections = _parse_memory_sections(text)
            for sec_name, entries in sections.items():
                if mem_type in sec_name.lower():
                    for _start, _end, sec_content in entries:
                        print(sec_content, end="")
                    return
            print(f"(未找到 {mem_type} 节)")
        else:
            print(text, end="")
        return

    # --touch：更新时间戳
    if getattr(args, "touch", None):
        _memory_touch(args.touch)
        return

    # --archive：归档到 deprecated 节
    if getattr(args, "archive", None):
        _memory_archive(args.archive)
        return

    # --archive-to-file：归档到 MEMORY-ARCHIVE.org
    if getattr(args, "archive_to_file", None):
        _memory_archive_to_file(args.archive_to_file)
        return

    # --auto-archive-days + --stale：自动归档 stale feedback
    if getattr(args, "stale", False) and getattr(args, "auto_archive_days", 0) > 0:
        _memory_auto_archive_stale(args.auto_archive_days)
        return

    # --project-touch：更新项目 LAST_ACTIVE
    if getattr(args, "project_touch", None):
        _memory_project_touch(args.project_touch)
        return

    # --stale：列出陈旧记忆
    if getattr(args, "stale", False):
        _memory_stale()
        return

    # --add：添加记忆（优先于 --project 检索）
    if getattr(args, "add", False):
        _memory_add(args)
        return

    # --auto-update：自动更新项目记忆元数据
    if getattr(args, "auto_update", False):
        if not getattr(args, "project", None):
            die("--auto-update 需要与 --project 联合使用")
        _memory_project_auto_update(args.project)
        return

    # --project：按项目名或路径检索
    if getattr(args, "project", None):
        _memory_project(args.project)
        return

    # 默认：列出所有记忆概览
    _memory_overview(args)


def _memory_overview(args: argparse.Namespace) -> None:
    """列出所有记忆概览或按类型过滤。"""
    if not KB_MEMORY.exists():
        print("(记忆文件不存在)")
        return

    text = KB_MEMORY.read_text(encoding="utf-8")
    sections = _parse_memory_sections(text)

    mem_type = getattr(args, "type", None)
    if mem_type:
        # 映射类型到节名
        type_to_section = {
            "feedback": "feedback",
            "project": "project",
            "reference": "reference",
        }
        section_name = type_to_section.get(mem_type)
        if not section_name:
            die(f"未知记忆类型: {mem_type}")
        for sec_name, entries in sections.items():
            if section_name in sec_name.lower():
                for _start, _end, content in entries:
                    # 列出 ** 二级标题
                    for line in content.split("\n"):
                        m = re.match(r"^\*\*\s+(.+)", line)
                        if m:
                            print(m.group(1))
                return
        print(f"(未找到 {mem_type} 条目)")
        return

    # 无过滤：概览统计
    print("═══ MEMORY 概览 ═══")
    for sec_name, entries in sections.items():
        total = 0
        for _s, _e, content in entries:
            total += len(re.findall(r"^\*\* ", content, re.MULTILINE))
        print(f"  {sec_name}: {total} 条")


def _memory_add(args: argparse.Namespace) -> None:
    """添加记忆条目。"""
    mem_type = getattr(args, "type", None) or "feedback"
    title = getattr(args, "title", "") or ""
    use_stdin = getattr(args, "stdin", False)
    project_name = getattr(args, "project", None)

    body = ""
    if use_stdin and not sys.stdin.isatty():
        body = sys.stdin.read()

    if not title:
        # 从 stdin 内容第一行生成 title
        if body:
            first_line = body.strip().split("\n")[0].strip()
            title = first_line[:80] if first_line else "(无标题)"
        else:
            die("添加记忆需要 --title")

    if mem_type == "project":
        _memory_add_project(title, body, project_name)
        return

    if not KB_MEMORY.exists():
        _init_memory_template()

    text = KB_MEMORY.read_text(encoding="utf-8")
    lines = text.split("\n")
    sections = _parse_memory_sections(text)

    type_to_section = {
        "feedback": "feedback",
        "reference": "reference",
    }
    section_name = type_to_section.get(mem_type)
    if not section_name:
        die(f"未知记忆类型: {mem_type}")

    # 找到目标节
    target_section = None
    for sec_name, entries in sections.items():
        if section_name in sec_name.lower():
            target_section = entries[0]
            break

    prefix = "F" if mem_type == "feedback" else "R"

    if target_section:
        _start, _end, sec_content = target_section
        new_id = _next_memory_id(sec_content, prefix)
        insert_line = _find_section_end(lines, _start)
    else:
        # 节不存在，创建
        new_id = f"{prefix}001"
        # 在文件末尾追加新节
        insert_line = len(lines)
        # 先添加节标题
        section_header = f"\n* {section_name}"
        lines.append(section_header)
        insert_line = len(lines)

    # 构建条目
    entry_lines = [f"\n** {new_id} {title}"]
    entry_lines.append("   :PROPERTIES:")
    entry_lines.append(f"   :CREATED:  [{today()}]")
    entry_lines.append(f"   :UPDATED:  [{today()}]")
    if mem_type == "feedback" and getattr(args, "ref", None):
        entry_lines.append(f"   :REF:      {args.ref}")
    entry_lines.append("   :END:")
    if body.strip():
        entry_lines.append(f"   {body.strip()}")

    entry_text = "\n".join(entry_lines) + "\n"
    lines.insert(insert_line, entry_text)

    KB_MEMORY.write_text("\n".join(lines), encoding="utf-8")
    print(f"已添加 {mem_type} 记忆: {new_id} {title}")


def _memory_add_project(title: str, body: str, project_name: str | None) -> None:
    """添加 project 记忆到 memories/projects/<name>.org。"""
    if not project_name:
        die("添加 project 记忆需要 --project <项目名>")

    KB_PROJECTS.mkdir(parents=True, exist_ok=True)
    proj_file = KB_PROJECTS / f"{project_name}.org"

    if not proj_file.exists():
        proj_file.write_text(
            f"#+title: {project_name}\n#+date: [{today()}]\n\n",
            encoding="utf-8",
        )

    # 追加条目到项目文件
    proj_text = proj_file.read_text(encoding="utf-8")
    proj_lines = proj_text.split("\n")

    entry_lines = [f"\n** {title}"]
    entry_lines.append("   :PROPERTIES:")
    entry_lines.append(f"   :CREATED:  [{today()}]")
    entry_lines.append(f"   :UPDATED:  [{today()}]")
    entry_lines.append("   :END:")
    if body.strip():
        entry_lines.append(f"   {body.strip()}")
    entry_lines.append("")

    proj_lines.extend(entry_lines)
    proj_file.write_text("\n".join(proj_lines), encoding="utf-8")

    # 同步更新 MEMORY.org 索引
    _memory_sync_project_index(project_name, proj_file)

    print(f"已添加 project 记忆: {title} → {project_name}")


def _memory_sync_project_index(name: str, proj_file: Path) -> None:
    """同步项目到 MEMORY.org 的 * project 节索引。"""
    if not KB_MEMORY.exists():
        _init_memory_template()

    text = KB_MEMORY.read_text(encoding="utf-8")

    # 检查是否已存在索引
    if f"** {name}" in text:
        return

    lines = text.split("\n")
    sections = _parse_memory_sections(text)

    # 找到或创建 * project 节
    proj_section = None
    for sec_name, entries in sections.items():
        if "project" in sec_name.lower():
            proj_section = entries[0]
            break

    if proj_section:
        insert_line = _find_section_end(lines, proj_section[0])
    else:
        # 追加新节
        insert_line = len(lines)
        lines.append("")
        lines.append("* project")
        insert_line = len(lines)

    index_entry = (
        f"\n** {name}\n"
        f"   :PROPERTIES:\n"
        f"   :PATH:     {proj_file}\n"
        f"   :FILE:     {proj_file}\n"
        f"   :UPDATED:  [{today()}]\n"
        f"   :END:\n"
    )
    lines.insert(insert_line, index_entry)
    KB_MEMORY.write_text("\n".join(lines), encoding="utf-8")


def _memory_touch(entry_id: str) -> None:
    """更新指定条目的 UPDATED 时间戳。"""
    if not KB_MEMORY.exists():
        die("记忆文件不存在")

    text = KB_MEMORY.read_text(encoding="utf-8")
    lines = text.split("\n")

    # 找到条目位置
    found = False
    for i, line in enumerate(lines):
        if re.match(rf"^\*\* {re.escape(entry_id)}\b", line):
            found = True
            # 向下查找 :UPDATED: 属性行
            for j in range(i + 1, min(i + 10, len(lines))):
                if ":UPDATED:" in lines[j]:
                    lines[j] = re.sub(
                        r":UPDATED:\s*\[\d{4}-\d{2}-\d{2}\]",
                        f":UPDATED:  [{today()}]",
                        lines[j],
                    )
                    break
                if ":END:" in lines[j]:
                    break
            break

    if not found:
        die(f"未找到条目: {entry_id}")

    KB_MEMORY.write_text("\n".join(lines), encoding="utf-8")
    print(f"已更新 {entry_id} 时间戳 → {today()}")


def _memory_archive(entry_id: str) -> None:
    """将指定条目移入 * deprecated 节。"""
    if not KB_MEMORY.exists():
        die("记忆文件不存在")

    text = KB_MEMORY.read_text(encoding="utf-8")
    lines = text.split("\n")

    # 找到条目起始行
    entry_start = None
    for i, line in enumerate(lines):
        if re.match(rf"^\*\* {re.escape(entry_id)}\b", line):
            entry_start = i
            break

    if entry_start is None:
        die(f"未找到条目: {entry_id}")

    # 找到条目结束行（下一个 ** 或 * 之前）
    entry_end = entry_start + 1
    while entry_end < len(lines):
        if re.match(r"^\*\*?\s+", lines[entry_end]):
            break
        entry_end += 1

    # 提取条目文本
    entry_lines = lines[entry_start:entry_end]

    # 从原位置删除
    del lines[entry_start:entry_end]

    # 找到或创建 * deprecated 节
    sections = _parse_memory_sections("\n".join(lines))
    dep_section = None
    for sec_name, entries in sections.items():
        if "deprecated" in sec_name.lower():
            dep_section = entries[0]
            break

    if dep_section:
        insert_line = _find_section_end(lines, dep_section[0])
    else:
        # 追加 deprecated 节
        lines.append("")
        lines.append("* deprecated")
        insert_line = len(lines)

    # 插入到 deprecated 节末尾
    for k, el in enumerate(entry_lines):
        lines.insert(insert_line + k, el)

    KB_MEMORY.write_text("\n".join(lines), encoding="utf-8")
    print(f"已归档 {entry_id} → deprecated")


def _memory_stale() -> None:
    """列出超过 STALE_DAYS 天未更新的条目。"""
    if not KB_MEMORY.exists():
        print("(记忆文件不存在)")
        return

    text = KB_MEMORY.read_text(encoding="utf-8")
    lines = text.split("\n")
    stale_count = 0

    for i, line in enumerate(lines):
        if not re.match(r"^\*\* ", line):
            continue
        # 向下查找 UPDATED
        for j in range(i + 1, min(i + 10, len(lines))):
            m = re.match(r"\s*:UPDATED:\s*\[(\d{4}-\d{2}-\d{2})\]", lines[j])
            if m:
                try:
                    updated = datetime.strptime(m.group(1), "%Y-%m-%d")
                    if (datetime.now() - updated).days > STALE_DAYS:
                        print(f"  {line.strip()} (更新于 {m.group(1)})")
                        stale_count += 1
                except ValueError:
                    pass
                break
            if ":END:" in lines[j]:
                break

    if stale_count == 0:
        print("无陈旧记忆")
    else:
        print(f"\n共 {stale_count} 条 >{STALE_DAYS} 天未更新")


def _memory_project(identifier: str) -> None:
    """按项目名或路径检索项目记忆。"""
    if not KB_MEMORY.exists():
        print("(记忆文件不存在)")
        return

    text = KB_MEMORY.read_text(encoding="utf-8")
    sections = _parse_memory_sections(text)

    # 收集所有项目条目
    proj_entries = []
    for sec_name, entries in sections.items():
        if "project" in sec_name.lower():
            for _s, _e, content in entries:
                # 解析 ** 条目及其属性
                entry_lines_list = content.split("\n")
                cur_entry = None
                cur_props: dict[str, str] = {}
                for el in entry_lines_list:
                    m_entry = re.match(r"^\*\*\s+(.+)", el)
                    if m_entry:
                        if cur_entry:
                            proj_entries.append((cur_entry, cur_props))
                        cur_entry = m_entry.group(1)
                        cur_props = {}
                    else:
                        pm = re.match(r"\s*:(\w+):\s*(.+)", el)
                        if pm and cur_entry:
                            cur_props[pm.group(1)] = pm.group(2).strip()
                if cur_entry:
                    proj_entries.append((cur_entry, cur_props))
            break

    if not proj_entries:
        print("未找到匹配项目。")
        sys.exit(1)

    # 处理 "." → 用 PWD
    if identifier == ".":
        identifier = os.getcwd()

    # 尝试匹配：1) 项目名  2) 路径前缀
    matched = None

    # 按项目名匹配
    for entry_title, props in proj_entries:
        if entry_title.strip() == identifier.strip():
            matched = props
            break

    # 按路径前缀匹配
    if not matched:
        try:
            id_path = str(Path(identifier).expanduser().resolve())
        except (OSError, RuntimeError):
            id_path = identifier

        for entry_title, props in proj_entries:
            path_val = props.get("PATH", props.get("FILE", ""))
            if path_val:
                try:
                    resolved = str(Path(path_val).expanduser().resolve())
                    if resolved.startswith(id_path) or id_path.startswith(resolved):
                        matched = props
                        break
                except (OSError, RuntimeError):
                    if path_val == identifier:
                        matched = props
                        break

    if not matched:
        known = ", ".join(e[0] for e in proj_entries)
        print(f"未找到匹配项目。已知项目：{known}")
        sys.exit(1)

    # 读取并输出项目文件内容
    file_path = matched.get("FILE", matched.get("PATH", ""))
    proj_path = (
        KB_ROOT / file_path if not Path(file_path).is_absolute() else Path(file_path)
    )
    if proj_path.exists():
        print(proj_path.read_text(encoding="utf-8"), end="")
    else:
        print(f"项目文件不存在: {file_path}")
        sys.exit(1)


# ═══════════════════════════════════════════════════════════════════════════════
# 0.9 增强: MEMORY 归档分离 — 支持归档到 MEMORY-ARCHIVE.org
# ═══════════════════════════════════════════════════════════════════════════════


def _memory_archive_to_file(entry_id: str) -> None:
    """将 feedback 条目从 MEMORY.org 移到 MEMORY-ARCHIVE.org。

    project 和 reference 类型不自动归档到文件。
    """
    if not KB_MEMORY.exists():
        die("记忆文件不存在")

    text = KB_MEMORY.read_text(encoding="utf-8")
    lines = text.split("\n")

    # 找到条目
    entry_start = None
    for i, line in enumerate(lines):
        if re.match(rf"^\*\* {re.escape(entry_id)}\b", line):
            entry_start = i
            break

    if entry_start is None:
        die(f"未找到条目: {entry_id}")

    # 找到条目结束行
    entry_end = entry_start + 1
    while entry_end < len(lines):
        if re.match(r"^\*\*?\s+", lines[entry_end]):
            break
        entry_end += 1

    # 提取条目文本
    entry_text = "\n".join(lines[entry_start:entry_end])

    # 添加 ARCHIVED_AT 属性
    if ":ARCHIVED_AT:" not in entry_text:
        entry_text = entry_text.replace(":END:", f":ARCHIVED_AT: [{now()}]\n:END:", 1)

    # 从 MEMORY.org 删除
    del lines[entry_start:entry_end]
    # 清理多余空行
    while entry_start < len(lines) and lines[entry_start].strip() == "":
        del lines[entry_start]
    KB_MEMORY.write_text("\n".join(lines), encoding="utf-8")

    # 追加到 MEMORY-ARCHIVE.org
    archive = KB_MEMORY_ARCHIVE
    if not archive.exists():
        archive.write_text(
            f"#+title: MEMORY-ARCHIVE\n#+date: [{now()}]\n\n* archived\n",
            encoding="utf-8",
        )

    archive_text = archive.read_text(encoding="utf-8")
    # 找到或创建 * archived 节
    if "* archived" in archive_text:
        archive_text = archive_text.rstrip("\n") + f"\n\n{entry_text}\n"
    else:
        archive_text = archive_text.rstrip("\n") + f"\n\n* archived\n\n{entry_text}\n"

    archive.write_text(archive_text, encoding="utf-8")
    print(f"已归档到 MEMORY-ARCHIVE.org: {entry_id}")


def _memory_auto_archive_stale(days: int = 0) -> None:
    """自动归档超过指定天数的 stale feedback 条目。"""
    threshold = days or MEMORY_ARCHIVE_DAYS
    if not KB_MEMORY.exists():
        print("(记忆文件不存在)")
        return

    text = KB_MEMORY.read_text(encoding="utf-8")
    lines = text.split("\n")
    count = 0

    # 找到 feedback 节中的 stale 条目
    entries_to_archive = []
    for i, line in enumerate(lines):
        m = re.match(r"^\*\* (F\d+)", line)
        if not m:
            continue
        entry_id = m.group(1)
        # 查找 UPDATED
        for j in range(i + 1, min(i + 10, len(lines))):
            um = re.match(r"\s*:UPDATED:\s*\[(\d{4}-\d{2}-\d{2})\]", lines[j])
            if um:
                try:
                    updated = datetime.strptime(um.group(1), "%Y-%m-%d")
                    if (datetime.now() - updated).days > threshold:
                        entries_to_archive.append(entry_id)
                except ValueError:
                    pass
                break
            if ":END:" in lines[j]:
                break

    for entry_id in entries_to_archive:
        try:
            _memory_archive_to_file(entry_id)
            count += 1
        except SystemExit:
            continue

    print(f"自动归档完成: {count} 条 feedback 记忆 (>{threshold}天未更新)")


# ═══════════════════════════════════════════════════════════════════════════════
# 0.10 增强: 项目记忆元数据 — LAST_ACTIVE, LAST_CURATED, STATUS
# ═══════════════════════════════════════════════════════════════════════════════


def _memory_project_touch(project_name: str) -> None:
    """更新项目记忆的 LAST_ACTIVE 时间戳。"""
    if not KB_MEMORY.exists():
        die("记忆文件不存在")

    text = KB_MEMORY.read_text(encoding="utf-8")
    lines = text.split("\n")

    # 找到项目条目
    found = False
    for i, line in enumerate(lines):
        m = re.match(rf"^\*\* {re.escape(project_name)}\b", line)
        if m:
            found = True
            # 向下查找并更新/添加 LAST_ACTIVE
            for j in range(i + 1, min(i + 10, len(lines))):
                if ":LAST_ACTIVE:" in lines[j]:
                    lines[j] = re.sub(
                        r":LAST_ACTIVE:\s*\[.+?\]",
                        f":LAST_ACTIVE: [{today()}]",
                        lines[j],
                    )
                    break
                if ":END:" in lines[j]:
                    # 插入 LAST_ACTIVE
                    lines.insert(j, f"   :LAST_ACTIVE: [{today()}]")
                    break
            break

    if not found:
        die(f"未找到项目: {project_name}")

    KB_MEMORY.write_text("\n".join(lines), encoding="utf-8")

    print(f"已更新项目 {project_name} LAST_ACTIVE → {today()}")


def _memory_set_property(lines, start, key, value):
    """设置条目 PROPERTIES 中的属性(更新或插入)。原地修改 lines。"""
    for j in range(start + 1, min(start + 15, len(lines))):
        if ":" + key + ":" in lines[j]:
            lines[j] = re.sub(
                r"(:\w+:)(\s+).*$",
                lambda m: m.group(1) + m.group(2) + value,
                lines[j],
            )
            return
        if lines[j].strip() == ":END:":
            lines.insert(j, "   :" + key + ":  " + value)
            return


def _memory_project_auto_update(name):
    """自动更新项目记忆元数据: LAST_ACTIVE, STATUS, LAST_CURATED。"""

    if not KB_MEMORY.exists():
        die("记忆文件不存在")

    text = KB_MEMORY.read_text(encoding="utf-8")
    lns = text.split("\n")

    # 找到项目条目
    entry_start = None
    for i, l in enumerate(lns):
        m = re.match(rf"^\*\* {re.escape(name)}\b", l)
        if m:
            entry_start = i
            break

    if entry_start is None:
        die(f"未找到项目: {name}")

    # 扫描已有属性
    props = {}
    for j in range(entry_start + 1, min(entry_start + 15, len(lns))):
        if lns[j].strip() == ":END:":
            break
        pm = re.match(r"\s*:(\w+):\s*(.+)", lns[j])
        if pm:
            props[pm.group(1)] = pm.group(2).strip()

    summary = [f"项目: {name}"]

    # 1. 验证 PATH 存在性 -> STATUS
    path_val = props.get("PATH", "")
    if path_val:
        proj_path = Path(path_val).expanduser()
        if not proj_path.exists():
            _memory_set_property(lns, entry_start, "STATUS", "dormant")
            summary.append(f"  STATUS -> dormant (PATH 不存在: {path_val})")
    else:
        summary.append("  未设置 PATH 属性")

    # 2. 检查 UPDATED 日期 > 60 天
    updated_str = props.get("UPDATED", "")
    if updated_str:
        try:
            # UPDATED 值格式为 [2026-05-26]，去掉方括号再解析
            date_str = updated_str.strip("[]")
            updated_date = datetime.strptime(date_str, "%Y-%m-%d").date()
            delta = (datetime.now().date() - updated_date).days
            if delta > 60:
                summary.append(f"  上次更新距今 {delta} 天 (>60)，建议策展")
            else:
                summary.append(f"  距上次更新 {delta} 天，尚在窗口内")
        except ValueError:
            summary.append(f"  无法解析 UPDATED 日期: {updated_str}")
    else:
        summary.append("  未设置 UPDATED 属性")

    # 3. 更新 LAST_ACTIVE
    _memory_set_property(lns, entry_start, "LAST_ACTIVE", f"[{today()}]")
    summary.append(f"  LAST_ACTIVE -> [{today()}]")

    # 4. 更新项目记忆文件的 LAST_CURATED
    file_val = props.get("FILE", "")
    if file_val:
        proj_file = (
            KB_ROOT / file_val if not Path(file_val).is_absolute() else Path(file_val)
        )
        if proj_file.exists():
            proj_text = proj_file.read_text(encoding="utf-8")
            if ":PROPERTIES:" in proj_text[:100]:
                # PROPERTIES 抽屉格式
                proj_lns = proj_text.split("\n")
                _memory_set_property(proj_lns, 0, "LAST_CURATED", f"[{today()}]")
                proj_file.write_text("\n".join(proj_lns), encoding="utf-8")
            else:
                # #+ 元数据格式: 更新或追加
                if "#+LAST_CURATED:" in proj_text:
                    proj_text = re.sub(
                        r"#\+LAST_CURATED:.*",
                        f"#+LAST_CURATED: [{today()}]",
                        proj_text,
                    )
                else:
                    # 在第一个 #+ 属性块末尾追加
                    plines = proj_text.split("\n")
                    insert_pt = 0
                    for k, pl in enumerate(plines):
                        if pl.startswith("#+"):
                            insert_pt = k + 1
                        else:
                            break
                    plines.insert(insert_pt, f"#+LAST_CURATED: [{today()}]")
                    proj_text = "\n".join(plines)
                proj_file.write_text(proj_text, encoding="utf-8")
            summary.append(f"  {file_val} LAST_CURATED -> [{today()}]")
        else:
            summary.append(f"  项目记忆文件不存在: {file_val}")

    # 写入 MEMORY.org
    KB_MEMORY.write_text("\n".join(lns), encoding="utf-8")

    # 输出摘要
    print("\n".join(summary))
