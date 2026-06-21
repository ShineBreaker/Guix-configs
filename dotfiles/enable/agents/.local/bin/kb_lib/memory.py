# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

"""kb_memory — 知识库记忆系统：MEMORY.org 查阅（只读）"""

import argparse
import os
import re
from datetime import datetime
from pathlib import Path

from kb_lib.core import (
    KB_MEMORY,
    KB_ROOT,
    STALE_DAYS,
    die,
    ensure_dirs,
    today,
    now,
    _init_memory_template,
)


def _parse_memory_sections(content: str) -> dict[str, list[tuple[int, int, str]]]:
    """解析 MEMORY.org 的 `*` 顶级节。返回 {节名: [(起始行号, 结束行号, 节文本)]}。"""
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


def _find_section_end(lines: list[str], section_start: int) -> int:
    """找到指定 `*` 节的最后一行（下一个 `*` 节之前）。"""
    for i in range(section_start + 1, len(lines)):
        if re.match(r"^\*\s+", lines[i]):
            return i
    return len(lines)


# ═══════════════════════════════════════════════════════════════════════════════
# 子命令: memory — 查阅记忆系统（只读）
# ═══════════════════════════════════════════════════════════════════════════════


def cmd_memory(args: argparse.Namespace) -> None:
    """查阅 MEMORY.org 中的反馈、项目和参考记忆（只读）。"""
    ensure_dirs()

    # --get：输出 MEMORY.org 全文或指定节
    if getattr(args, "get", False):
        if not KB_MEMORY.exists():
            print("(记忆文件不存在)")
            return
        text = KB_MEMORY.read_text(encoding="utf-8")
        mem_type = getattr(args, "type", None)
        if mem_type:
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

    # --stale：列出陈旧记忆
    if getattr(args, "stale", False):
        _memory_stale()
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

    proj_entries = []
    for sec_name, entries in sections.items():
        if "project" in sec_name.lower():
            for _s, _e, content in entries:
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
        return

    if identifier == ".":
        identifier = os.getcwd()

    matched = None
    for entry_title, props in proj_entries:
        if entry_title.strip() == identifier.strip():
            matched = props
            break

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
        return

    file_path = matched.get("FILE", matched.get("PATH", ""))
    proj_path = (
        KB_ROOT / file_path if not Path(file_path).is_absolute() else Path(file_path)
    )
    if proj_path.exists():
        print(proj_path.read_text(encoding="utf-8"), end="")
    else:
        print(f"项目文件不存在: {file_path}")
