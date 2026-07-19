"""Inbox → experiences/ 归档子命令 (PLAN §2.3 Emacs Knowledge 下沉)。

把 `inbox.org` 中一个或多个 heading 子树归档为结构化经验卡片:
  - 路径: experiences/<category>/<YYYYMMDD-HHMMSS>-<slug>.org
  - slug: 由 heading 文本清洗而来(与 Emacs 历史实现字面等价)
  - 默认完成后重建 JSON 索引(消除 Emacs 端 reindex 补刀)
  - 可选从 inbox.org 删除已归档条目(--prune)

设计原则:
  - 单一真相源:slug 算法、路径规则、PROPERTIES 字段全部在 CLI
  - 输入:stdin JSON,数组每项 {"heading": str, "body": str}
  - body 是已剥离 PROPERTIES/ID 的纯文本(由调用方准备)
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from ag_lib.core import KBContext


def slugify_heading(heading: str, max_len: int = 60) -> str:
    """把 inbox heading 转 slug,与 Emacs 历史 archive-inbox-entry 算法等价。

    步骤:
      1. 去 [[link][text]] → text
      2. [^A-Za-z0-9_-]+ → -
      3. 折叠重复 -
      4. 去首尾 -
      5. 空时返回 "entry" 占位(调用方拼时间戳)
      6. 截断到 max_len,断词时去尾 -

    与 Emacs archive-inbox-entry 的 replace-regexp-in-string 链字面等价。
    """
    if not heading:
        return "entry"
    # 1. org-link 去壳: [[target][text]] → text,[[target]] → target
    s = re.sub(r"\[\[([^\]]+)\]\[([^\]]+)\]\]", r"\2", heading)
    s = re.sub(r"\[\[([^\]]+)\]\]", r"\1", s)
    # 2. 非 [A-Za-z0-9_-] → -
    s = re.sub(r"[^A-Za-z0-9_-]+", "-", s)
    # 3. 折叠重复 -
    s = re.sub(r"-+", "-", s)
    # 4. 去首尾 -
    s = s.strip("-")
    # 5. 空占位
    if not s:
        return "entry"
    # 6. 截断
    if len(s) > max_len:
        s = s[:max_len].rstrip("-")
    return s


def _build_archived_card(
    heading: str,
    body: str,
    ts_id: str,
    ts_human: str,
    category: str,
    reason: str | None,
) -> str:
    """组装归档卡片的 Org 文本。

    与 cmd_add 的 PROPERTIES 块结构对齐,但 ENTRY_TYPE 留空
    (归档来源是 inbox 草稿,不是结构化经验)。
    """
    title = heading.strip() or f"迁移自 inbox {ts_id}"
    lines = [
        f"* TODO {title}",
        ":PROPERTIES:",
        f":ID:       {ts_id}",
        f":CREATED:  [{ts_human}]",
        f":CATEGORY: {category}",
        ":TYPE:     workflow",
        ":STATUS:   todo",
        ":END:",
        "",
    ]
    if reason:
        lines.append(f"Archive reason: {reason}")
        lines.append("")
    if body and body.strip():
        lines.append(body.rstrip("\n"))
        lines.append("")
    return "\n".join(lines) + "\n"


def _prune_inbox(inbox_path: Path, pruned_headings: list[str]) -> int:
    """从 inbox.org 删除指定 heading 子树。

    通过精确匹配 `^** [...] <heading>$` 行定位,删除该 heading 与下一个同级
    heading 之间的全部内容。返回实际删除的 heading 数。

    heading 列表为已归档的 heading 文本(去 * 前缀)。
    """
    if not inbox_path.exists() or not pruned_headings:
        return 0
    content = inbox_path.read_text(encoding="utf-8")
    lines = content.split("\n")
    # 把 heading 文本转成匹配集(忽略首尾空白)
    targets = {h.strip() for h in pruned_headings if h and h.strip()}
    if not targets:
        return 0

    output: list[str] = []
    skip_until_level: int | None = None  # 当前在删除子树,跳到同级或更浅 heading
    pruned_count = 0

    for line in lines:
        # heading 行: * / ** / *** ...
        m = re.match(r"^(\*+)\s+(.*)$", line)
        if m:
            level = len(m.group(1))
            text = m.group(2).strip()
            if skip_until_level is not None:
                if level <= skip_until_level:
                    # 退出删除模式
                    skip_until_level = None
                    if text in targets:
                        # 进入新删除
                        skip_until_level = level
                        pruned_count += 1
                        continue
                    # 保留当前 heading
                    output.append(line)
                    continue
                else:
                    # 更深的 heading,继续删除
                    continue
            else:
                if text in targets:
                    skip_until_level = level
                    pruned_count += 1
                    continue
                output.append(line)
                continue
        # 非 heading 行
        if skip_until_level is not None:
            continue
        output.append(line)

    if pruned_count > 0:
        # 清理尾部多余空行
        while len(output) >= 2 and output[-1] == "" and output[-2] == "":
            output.pop()
        inbox_path.write_text("\n".join(output) + "\n", encoding="utf-8")
    return pruned_count


def cmd_inbox_archive(args: argparse.Namespace, ctx: "KBContext | None" = None) -> None:
    """把 stdin JSON 描述的 inbox 条目归档到 experiences/<category>/。

    stdin JSON: 数组,每项 {"heading": str, "body": str}。
    参数:
      --category:   必填,目标 category(路径分隔符/.. 被拒)
      --reason:     可选,写入卡片顶部 Archive reason 注释
      --no-reindex: 默认完成后重建 index;批量场景可关
      --prune:      从 inbox.org 删除已归档条目(默认 False,保留以备回查)
      --stdin:      显式从 stdin 读(默认即从 stdin 读,保留以与 cmd_add 对齐)

    输出:每条归档的文件路径,最后一行打印 reindex 结果(若未 --no-reindex)。
    """
    from ag_lib.core import (  # 局部 import 避免循环
        ensure_dirs,
        timestamp_id,
        now,
        _load_index,
        _save_index,
        _rebuild_index,
        _upsert_card,
        die,
        default_context as _default_context,
    )

    ctx = ctx or _default_context()

    category = args.category
    if not category:
        die("必须指定 --category")
    if "/" in category or "\\" in category or ".." in category:
        die(f"类别名不能包含路径分隔符或 '..': {category}")

    ensure_dirs(ctx)

    # 读 stdin
    raw = sys.stdin.read() if (getattr(args, "stdin", False) or True) else ""
    try:
        entries = json.loads(raw) if raw.strip() else []
    except json.JSONDecodeError as e:
        die(f"stdin 不是合法 JSON: {e}")
    if not isinstance(entries, list):
        die("stdin JSON 必须是数组")
    if not entries:
        print("(no entries)")
        return

    reason = getattr(args, "reason", None)
    pruned_headings: list[str] = []

    for entry in entries:
        if not isinstance(entry, dict):
            print(f"跳过非对象条目: {entry!r}", file=sys.stderr)
            continue
        heading = entry.get("heading") or ""
        body = entry.get("body") or ""
        ts_id = timestamp_id()
        slug = slugify_heading(heading)
        filename = f"{ts_id}-{slug}.org"
        target = ctx.experiences / category / filename
        target.parent.mkdir(parents=True, exist_ok=True)
        # 防止意外覆盖:文件已存在时加 .N 后缀
        counter = 1
        while target.exists():
            target = ctx.experiences / category / f"{ts_id}-{slug}.{counter}.org"
            counter += 1
        ts_human = now()
        card_text = _build_archived_card(heading, body, ts_id, ts_human, category, reason)
        target.write_text(card_text, encoding="utf-8")
        # 增量更新索引(为单卡片 upsert,与 cmd_add 一致)
        index = _load_index(ctx)
        _upsert_card(index, target, ctx)
        _save_index(index, ctx)
        print(str(target))
        if heading.strip():
            pruned_headings.append(heading)

    # 全量 reindex(默认):消除 Emacs 端 reindex 补刀。
    # _rebuild_index 是幂等扫盘,与 cmd_curate step 5 行为一致。
    if not getattr(args, "no_reindex", False):
        idx = _rebuild_index(ctx)
        _save_index(idx, ctx)
        print(f"reindex: {idx['total']} cards")

    # 可选从 inbox 删除已归档条目
    if getattr(args, "prune", False) and pruned_headings:
        pruned = _prune_inbox(ctx.inbox, pruned_headings)
        print(f"pruned from inbox: {pruned}")
