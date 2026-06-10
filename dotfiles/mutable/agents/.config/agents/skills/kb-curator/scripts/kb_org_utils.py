#!/usr/bin/env python3

# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

"""共享 Org 解析工具函数。

供 analyze_kb.py 和 find_gaps.py 共用的 Org 元数据解析和日期处理逻辑。
避免策展脚本之间的代码重复。
"""

import re
from datetime import datetime
from pathlib import Path


def parse_org_metadata(filepath: str, quality_check: bool = False) -> dict | None:
    """从 Org 文件头部提取元数据。

    参数:
        filepath: Org 文件路径
        quality_check: 是否同时进行质量检查（仅 analyze_kb 需要）

    返回:
        元数据字典，文件不可读时返回 None。
        quality_check=True 时额外包含 quality_issues 和 line_count。
    """
    meta: dict = {"file": filepath}
    if quality_check:
        meta["quality_issues"] = []

    try:
        with open(filepath, encoding="utf-8") as f:
            content = f.read()
    except Exception:
        return None

    # ── 提取 PROPERTIES 块 ───────────────────────────────────────────
    props_match = re.search(r":PROPERTIES:(.*?):END:", content, re.DOTALL)
    if not props_match:
        if quality_check:
            meta["quality_issues"].append("missing_properties")
        # 仍然尝试提取标题
        title_match = re.search(r"^\* DONE (.+)", content, re.MULTILINE)
        meta["title"] = title_match.group(1).strip() if title_match else "unknown"
        return meta

    props = props_match.group(1)

    def get_prop(key: str) -> str | None:
        m = re.search(rf":{key}:\s*(.+)", props)
        return m.group(1).strip() if m else None

    meta["id"] = get_prop("ID")
    meta["created"] = get_prop("CREATED")
    meta["category"] = get_prop("CATEGORY") or "unknown"
    meta["tech"] = get_prop("TECH") or ""
    meta["type"] = get_prop("TYPE") or "unknown"
    meta["status"] = get_prop("STATUS") or "unknown"
    meta["owner"] = get_prop("OWNER") or "unknown"

    # ── 提取标题 ─────────────────────────────────────────────────────
    title_match = re.search(r"^\* (?:DONE|TODO) (.+)", content, re.MULTILINE)
    meta["title"] = title_match.group(1).strip() if title_match else "unknown"

    # ── 质量检查（仅 analyze_kb 调用时启用）─────────────────────────
    if quality_check:
        if not meta["id"]:
            meta["quality_issues"].append("missing_id")
        if not meta["created"]:
            meta["quality_issues"].append("missing_created")
        if meta["category"] == "unknown":
            meta["quality_issues"].append("missing_category")
        if not meta["tech"]:
            meta["quality_issues"].append("missing_tech")

        # 检查章节完整性
        has_task_desc = bool(re.search(r"^\*\* 任务描述", content, re.MULTILINE))
        has_execution = bool(re.search(r"^\*\* 执行过程", content, re.MULTILINE))
        has_findings = bool(
            re.search(r"^\*{2,3} (关键发现|难点与坑点|经验教训)", content, re.MULTILINE)
        )

        if not has_task_desc:
            meta["quality_issues"].append("missing_task_description")
        if not has_execution:
            meta["quality_issues"].append("missing_execution_process")
        if not has_findings:
            meta["quality_issues"].append("missing_findings")

        # 检查 Markdown 格式污染
        if "```" in content:
            meta["quality_issues"].append("markdown_code_blocks")
        if re.search(r"(?<!\*)\*\*(?!\*)", content) and "** " not in content:
            meta["quality_issues"].append("markdown_bold")

        # 统计内容长度
        meta["line_count"] = len(content.splitlines())

    return meta


def parse_date(date_str: str | None) -> datetime | None:
    """解析 Org 日期字符串。

    支持格式: [2026-04-23 四 23:02] 或 [2026-04-23 四]
    提取 YYYY-MM-DD 部分并转换为 datetime 对象。
    """
    if not date_str:
        return None
    m = re.search(r"(\d{4}-\d{2}-\d{2})", date_str)
    if m:
        try:
            return datetime.strptime(m.group(1), "%Y-%m-%d")
        except ValueError:
            pass
    return None
