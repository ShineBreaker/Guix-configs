#!/usr/bin/env python3
"""提取 OpenCode / Crush / Codex / Claude Code 对话记录，输出为 Org-mode 文件。

用法:
    extract-conversations.py [--date YYYY-MM-DD] [--output DIR] [--source {opencode,crush,codex,claude,all}]

日期逻辑:
    默认提取「昨天」的对话。
    若当前时间 < 04:00，则时间范围延至今日 04:00（将凌晨工作算入昨天）。
    可用 --date 指定任意日期。
"""

import argparse
import json
import os
import sqlite3
import sys
from datetime import datetime, timedelta
from pathlib import Path

# ── 数据源配置 ──────────────────────────────────────────────
OPENCODE_DB = os.path.expanduser("~/.local/share/opencode/opencode-stable.db")
CRUSH_GLOBAL_DB = os.path.expanduser("~/.config/crush/.crush/crush.db")
CLAUDE_TRANSCRIPTS_DIR = os.path.expanduser("~/.claude/transcripts")
CLAUDE_HISTORY = os.path.expanduser("~/.claude/history.jsonl")

CRUSH_SEARCH_ROOTS = [
    os.path.expanduser("~/Documents"),
    os.path.expanduser("~/Documents/Repo"),
    os.path.expanduser("~/Documents/Org"),
    os.path.expanduser("~/.emacs.d"),
    "/data/Documents",
]

CODEX_SEARCH_ROOTS = [
    os.path.expanduser("~/Documents"),
    os.path.expanduser("~/Documents/Repo"),
    os.path.expanduser("~/Documents/Org"),
    os.path.expanduser("~/Projects"),
    "/data/Documents",
]


def find_crush_dbs() -> list[str]:
    """扫描所有项目级 Crush 数据库（去重）。"""
    found = {CRUSH_GLOBAL_DB}
    for root in CRUSH_SEARCH_ROOTS:
        if not os.path.exists(root):
            continue
        for dirpath, _, filenames in os.walk(root):
            if ".crush" in dirpath and "crush.db" in filenames:
                db_path = os.path.join(dirpath, "crush.db")
                found.add(db_path)
    return [p for p in found if "/nix/store/" not in p and "/Trash/" not in p]


def find_codex_dbs() -> list[str]:
    """扫描所有项目级 Codex session 目录。返回 .codex 目录路径列表。"""
    found: set[str] = set()
    # 全局 codex 目录
    global_codex = os.path.expanduser("~/.codex")
    if os.path.isdir(global_codex):
        found.add(global_codex)
    for root in CODEX_SEARCH_ROOTS:
        if not os.path.exists(root):
            continue
        for dirpath, dirnames, _ in os.walk(root):
            if ".codex" in dirnames:
                codex_dir = os.path.join(dirpath, ".codex")
                if os.path.isdir(codex_dir):
                    found.add(codex_dir)
    return [p for p in found if "/nix/store/" not in p and "/Trash/" not in p]


def safe_filename(title: str, maxlen: int = 60) -> str:
    """将标题转为安全的文件名片段。"""
    return (
        "".join(c if c.isalnum() or c in " _-" else "-" for c in title)
        [:maxlen]
        .strip()
        .replace(" ", "-")
    )


# ── 日期范围 ────────────────────────────────────────────────
def compute_date_range(target_date: str | None) -> tuple[datetime, datetime]:
    """返回 (range_start, range_end)。"""
    now = datetime.now()
    if target_date:
        td = datetime.strptime(target_date, "%Y-%m-%d").date()
    else:
        td = (now - timedelta(days=1)).date()

    range_start = datetime.combine(td, datetime.min.time())
    if now.hour < 4 and target_date is None:
        range_end = datetime.combine(now.date(), datetime.min.time().replace(hour=4))
    else:
        range_end = datetime.combine(td + timedelta(days=1), datetime.min.time())
    return range_start, range_end


# ── OpenCode 提取 ──────────────────────────────────────────
def extract_opencode(range_start: datetime, range_end: datetime) -> list[dict]:
    """从 OpenCode 数据库提取对话。"""
    if not os.path.exists(OPENCODE_DB):
        return []

    conn = sqlite3.connect(f"file:{OPENCODE_DB}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row

    ts_start = int(range_start.timestamp() * 1000)
    ts_end = int(range_end.timestamp() * 1000)

    sessions = conn.execute(
        """
        SELECT s.id, s.title, s.directory, s.time_created, s.time_updated
        FROM session s
        WHERE s.time_created >= ? AND s.time_created < ?
           OR (s.time_updated >= ? AND s.time_updated < ?)
        ORDER BY s.time_created
        """,
        (ts_start, ts_end, ts_start, ts_end),
    ).fetchall()

    results: list[dict] = []
    for sess in sessions:
        messages = conn.execute(
            """
            SELECT m.id, m.time_created, m.data
            FROM message m
            WHERE m.session_id = ?
            ORDER BY m.time_created
            """,
            (sess["id"],),
        ).fetchall()

        conversation_parts: list[dict] = []
        for msg in messages:
            msg_data: dict = json.loads(msg["data"])
            role: str = msg_data.get("role", "unknown")
            model: str = msg_data.get("modelID", "")
            agent: str = msg_data.get("agent", msg_data.get("mode", ""))

            parts = conn.execute(
                """
                SELECT data FROM part
                WHERE message_id = ? ORDER BY time_created
                """,
                (msg["id"],),
            ).fetchall()

            msg_parts: list[dict] = []
            for p in parts:
                pd: dict = json.loads(p["data"])
                ptype: str = pd.get("type", "")
                if ptype == "text":
                    msg_parts.append({"type": "text", "content": pd.get("text", "")})
                elif ptype == "reasoning":
                    msg_parts.append({"type": "reasoning", "content": pd.get("text", "")})
                elif ptype == "tool":
                    state: dict = pd.get("state", {})
                    inp: dict = state.get("input", {})
                    out = state.get("output", "")
                    msg_parts.append({
                        "type": "tool",
                        "tool": pd.get("tool", ""),
                        "input": inp,
                        "output": out if isinstance(out, str) else json.dumps(out, ensure_ascii=False)[:2000],
                    })
                elif ptype == "patch":
                    msg_parts.append({"type": "patch", "files": pd.get("files", [])})

            conversation_parts.append({
                "role": role,
                "model": model,
                "agent": agent,
                "parts": msg_parts,
                "time_created": msg["time_created"],
            })

        results.append({
            "source": "opencode",
            "id": sess["id"],
            "title": sess["title"],
            "directory": sess["directory"],
            "time_created": sess["time_created"],
            "time_updated": sess["time_updated"],
            "messages": conversation_parts,
        })

    conn.close()
    return results


# ── Crush 提取 ─────────────────────────────────────────────
def extract_crush(range_start: datetime, range_end: datetime) -> list[dict]:
    """从所有 Crush 数据库提取对话。"""
    dbs = find_crush_dbs()
    results: list[dict] = []
    seen_ids: set[str] = set()

    ts_start = int(range_start.timestamp())
    ts_end = int(range_end.timestamp())

    for db_path in dbs:
        if not os.path.exists(db_path):
            continue
        try:
            conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
            conn.row_factory = sqlite3.Row

            project_dir = ""
            if ".config/crush" in db_path:
                project_dir = "(global)"
            else:
                candidate = os.path.dirname(os.path.dirname(db_path))
                if os.path.isdir(candidate):
                    project_dir = candidate

            sessions = conn.execute(
                """
                SELECT id, title, created_at, updated_at
                FROM sessions
                WHERE created_at >= ? AND created_at < ?
                   OR (updated_at >= ? AND updated_at < ?)
                """,
                (ts_start, ts_end, ts_start, ts_end),
            ).fetchall()

            for sess in sessions:
                sid: str = sess["id"]
                if sid in seen_ids:
                    continue
                seen_ids.add(sid)

                messages = conn.execute(
                    """
                    SELECT id, role, parts, model, created_at
                    FROM messages
                    WHERE session_id = ?
                    ORDER BY created_at
                    """,
                    (sid,),
                ).fetchall()

                conversation_parts: list[dict] = []
                for msg in messages:
                    parts_raw: list = json.loads(msg["parts"]) if msg["parts"] else []
                    msg_parts: list[dict] = []
                    for p in parts_raw:
                        ptype: str = p.get("type", "")
                        pdata: dict = p.get("data", {})
                        if ptype == "text":
                            text = pdata.get("text", p.get("text", ""))
                            msg_parts.append({"type": "text", "content": text})
                        elif ptype in ("tool_call", "tool"):
                            tool_name = pdata.get("name", p.get("tool", "unknown"))
                            raw_input = pdata.get("input", {})
                            if isinstance(raw_input, str):
                                try:
                                    raw_input = json.loads(raw_input)
                                except (json.JSONDecodeError, TypeError):
                                    pass
                            msg_parts.append({
                                "type": "tool",
                                "tool": tool_name,
                                "input": raw_input,
                            })
                        elif ptype in ("tool_result", "tool-result"):
                            content = pdata.get("content", pdata.get("output", ""))
                            msg_parts.append({
                                "type": "tool-result",
                                "content": content if isinstance(content, str) else json.dumps(content, ensure_ascii=False)[:2000],
                            })
                        elif ptype == "reasoning":
                            thinking = pdata.get("thinking", pdata.get("text", ""))
                            msg_parts.append({"type": "reasoning", "content": thinking})
                    conversation_parts.append({
                        "role": msg["role"],
                        "model": msg["model"] or "",
                        "parts": msg_parts,
                        "time_created": msg["created_at"],
                    })

                results.append({
                    "source": "crush",
                    "db_path": db_path,
                    "project_dir": project_dir,
                    "id": sid,
                    "title": sess["title"],
                    "time_created": sess["created_at"],
                    "time_updated": sess["updated_at"],
                    "messages": conversation_parts,
                })
            conn.close()
        except Exception:
            continue

    return results


# ── Claude Code 提取 ──────────────────────────────────────
def extract_claude(range_start: datetime, range_end: datetime) -> list[dict]:
    """从 Claude Code transcripts 目录提取对话。"""
    if not os.path.isdir(CLAUDE_TRANSCRIPTS_DIR):
        return []

    # 从 history.jsonl 建立 session_id → title 映射
    session_titles: dict[str, str] = {}
    session_projects: dict[str, str] = {}
    session_first_ts: dict[str, str] = {}
    if os.path.exists(CLAUDE_HISTORY):
        try:
            with open(CLAUDE_HISTORY) as f:
                for line in f:
                    try:
                        entry = json.loads(line)
                    except json.JSONDecodeError:
                        continue
                    sid = entry.get("sessionId", "")
                    if sid and sid not in session_titles:
                        session_titles[sid] = entry.get("display", "Untitled")
                        session_projects[sid] = entry.get("project", "")
                        session_first_ts[sid] = entry.get("timestamp", 0)
        except Exception:
            pass

    results: list[dict] = []
    ts_start_ms = int(range_start.timestamp() * 1000)
    ts_end_ms = int(range_end.timestamp() * 1000)

    for fpath in sorted(Path(CLAUDE_TRANSCRIPTS_DIR).glob("*.jsonl")):
        # 从文件名提取 session ID（格式: ses_<hex>_<base64>.jsonl）
        fname = fpath.name
        # 提取 base64 部分之前的 hex session id
        prefix = fname.replace("ses_", "").split("_")[0] if fname.startswith("ses_") else ""

        # 读取第一条 user 消息获取时间戳和标题
        first_ts = None
        first_title = "Untitled"
        has_messages_in_range = False
        messages_raw: list[dict] = []

        try:
            with open(fpath) as f:
                for line in f:
                    try:
                        msg = json.loads(line)
                    except json.JSONDecodeError:
                        continue
                    ts_str = msg.get("timestamp", "")
                    ts = _parse_iso_timestamp(ts_str)
                    if ts:
                        if first_ts is None:
                            first_ts = ts
                        ts_ms = int(ts.timestamp() * 1000)
                        if ts_start_ms <= ts_ms < ts_end_ms:
                            has_messages_in_range = True

                    if msg.get("type") == "user" and first_title == "Untitled":
                        content = msg.get("content", "")
                        if content:
                            first_title = content[:80].replace("\n", " ").strip()

                    messages_raw.append(msg)
        except Exception:
            continue

        if not has_messages_in_range:
            continue

        # 用 history.jsonl 的标题覆盖（更准确）
        sid_candidate = _find_session_id_for_transcript(fname, session_titles)
        title = session_titles.get(sid_candidate, first_title)
        project = session_projects.get(sid_candidate, "")

        # 转换消息格式
        conversation_parts: list[dict] = []
        for msg in messages_raw:
            mtype = msg.get("type", "")
            ts = _parse_iso_timestamp(msg.get("timestamp", ""))
            ts_unix = int(ts.timestamp()) if ts else 0

            if mtype == "user":
                conversation_parts.append({
                    "role": "user",
                    "model": "",
                    "parts": [{"type": "text", "content": msg.get("content", "")}],
                    "time_created": ts_unix,
                })
            elif mtype == "tool_use":
                conversation_parts.append({
                    "role": "assistant",
                    "model": "",
                    "parts": [{
                        "type": "tool",
                        "tool": msg.get("tool_name", "unknown"),
                        "input": msg.get("tool_input", {}),
                        "output": "",
                    }],
                    "time_created": ts_unix,
                })
            elif mtype == "tool_result":
                output = msg.get("tool_output", "")
                if isinstance(output, dict):
                    output = output.get("output", json.dumps(output, ensure_ascii=False))
                conversation_parts.append({
                    "role": "tool",
                    "model": "",
                    "parts": [{
                        "type": "tool-result",
                        "content": str(output)[:2000] if output else "",
                    }],
                    "time_created": ts_unix,
                })

        results.append({
            "source": "claude",
            "id": sid_candidate or prefix,
            "title": title,
            "project": project,
            "time_created": int(first_ts.timestamp()) if first_ts else 0,
            "time_updated": int(first_ts.timestamp()) if first_ts else 0,
            "messages": conversation_parts,
        })

    return results


def _parse_iso_timestamp(ts_str: str) -> datetime | None:
    """解析 ISO 8601 时间戳字符串。"""
    if not ts_str:
        return None
    try:
        # 处理 "2026-04-13T10:58:46.700Z"
        ts_str = ts_str.replace("Z", "+00:00")
        return datetime.fromisoformat(ts_str).replace(tzinfo=None)
    except (ValueError, TypeError):
        pass
    try:
        # 处理毫秒级 Unix 时间戳（数字字符串）
        ts_int = int(ts_str)
        return datetime.fromtimestamp(ts_int / 1000)
    except (ValueError, TypeError):
        pass
    return None


def _find_session_id_for_transcript(fname: str, session_titles: dict[str, str]) -> str:
    """通过模糊匹配找到 transcript 文件对应的 session ID。
    
    transcript 文件名格式: ses_<hex>_<base64>.jsonl
    history.jsonl 中 sessionId 是 UUID。
    尝试多种匹配策略。
    """
    # 策略1：前缀匹配（hex 部分可能是 sessionId 的前缀）
    prefix = fname.replace("ses_", "").split("_")[0] if fname.startswith("ses_") else ""
    for sid in session_titles:
        if sid.startswith(prefix):
            return sid
    # 策略2：直接检查文件名是否包含 sessionId
    for sid in session_titles:
        # sessionId 中的 - 可能在文件名中被移除
        sid_compact = sid.replace("-", "")
        if sid_compact[:12] in fname:
            return sid
    return prefix or fname


# ── Codex 提取 ────────────────────────────────────────────
def extract_codex(range_start: datetime, range_end: datetime) -> list[dict]:
    """从所有 Codex 项目目录提取对话。"""
    codex_dirs = find_codex_dbs()
    results: list[dict] = []
    seen_ids: set[str] = set()

    ts_start = range_start
    ts_end = range_end

    for codex_dir in codex_dirs:
        sessions_dir = os.path.join(codex_dir, "sessions")
        if not os.path.isdir(sessions_dir):
            continue

        # 加载 history.jsonl 建立 session_id → title/project 映射
        history_path = os.path.join(codex_dir, "history.jsonl")
        session_titles: dict[str, str] = {}
        project_dir = os.path.dirname(codex_dir) if codex_dir != os.path.expanduser("~/.codex") else "(global)"
        if os.path.exists(history_path):
            try:
                with open(history_path) as f:
                    for line in f:
                        try:
                            entry = json.loads(line)
                        except json.JSONDecodeError:
                            continue
                        sid = entry.get("session_id", "")
                        if sid and sid not in session_titles:
                            session_titles[sid] = entry.get("text", "Untitled")[:80].replace("\n", " ").strip()
            except Exception:
                pass

        # 遍历 sessions/YYYY/MM/DD/*.jsonl
        for session_file in sorted(Path(sessions_dir).rglob("*.jsonl")):
            fname = session_file.name
            # 文件名格式: rollout-YYYY-MM-DDTHH-MM-SS-<UUID>.jsonl
            # UUID 是 8-4-4-4-12 格式，共 5 段
            sid = ""
            if fname.startswith("rollout-"):
                parts = fname.replace("rollout-", "").split("-")
                # 日期+时间占用前 6 段: YYYY, MM, DDTHH, MM, SS, UUID[0..7]
                # UUID 的 5 段在 parts[6] 到 parts[10]
                if len(parts) >= 11:
                    uuid_parts = parts[6:11]
                    uuid_parts[-1] = uuid_parts[-1].replace(".jsonl", "")
                    sid = "-".join(uuid_parts)

            if sid in seen_ids:
                continue
            seen_ids.add(sid)

            # 检查文件修改时间是否在范围内
            mtime = datetime.fromtimestamp(session_file.stat().st_mtime)
            is_in_range = False
            messages_raw: list[dict] = []

            try:
                with open(session_file) as f:
                    for line in f:
                        try:
                            msg = json.loads(line)
                        except json.JSONDecodeError:
                            continue
                        ts_str = msg.get("timestamp", "")
                        ts = _parse_iso_timestamp(ts_str)
                        if ts and ts_start <= ts < ts_end:
                            is_in_range = True
                        messages_raw.append(msg)
            except Exception:
                continue

            if not is_in_range:
                # 回退：用文件修改时间判断
                if not (ts_start <= mtime < ts_end):
                    continue

            # 提取 session meta
            first_ts = None
            cwd = ""
            for msg in messages_raw:
                if msg.get("type") == "session_meta":
                    payload = msg.get("payload", {})
                    first_ts = _parse_iso_timestamp(payload.get("timestamp", ""))
                    cwd = payload.get("cwd", "")
                    break

            title = session_titles.get(sid, "Untitled")

            # 转换消息
            conversation_parts: list[dict] = _parse_codex_messages(messages_raw)

            results.append({
                "source": "codex",
                "id": sid,
                "title": title,
                "directory": cwd or project_dir,
                "project_dir": project_dir,
                "time_created": int(first_ts.timestamp()) if first_ts else int(mtime.timestamp()),
                "time_updated": int(mtime.timestamp()),
                "messages": conversation_parts,
            })

    return results


def _parse_codex_messages(messages_raw: list[dict]) -> list[dict]:
    """将 Codex JSONL 消息转换为统一格式。"""
    result: list[dict] = []
    for msg in messages_raw:
        mtype = msg.get("type", "")
        ts = _parse_iso_timestamp(msg.get("timestamp", ""))
        ts_unix = int(ts.timestamp()) if ts else 0

        if mtype == "response_item":
            payload = msg.get("payload", {})
            role = payload.get("role", "")
            if role not in ("user", "assistant"):
                continue
            content = payload.get("content", [])
            if isinstance(content, str):
                content = [{"type": "text", "text": content}]

            parts: list[dict] = []
            for block in content:
                btype = block.get("type", "")
                if btype in ("input_text", "output_text"):
                    parts.append({"type": "text", "content": block.get("text", "")})
                elif btype == "function_call":
                    parts.append({
                        "type": "tool",
                        "tool": block.get("name", block.get("function_name", "unknown")),
                        "input": json.loads(block.get("arguments", "{}")) if isinstance(block.get("arguments"), str) else block.get("arguments", {}),
                        "output": "",
                    })
                elif btype == "reasoning":
                    parts.append({"type": "reasoning", "content": block.get("text", block.get("summary", ""))})

            if parts:
                result.append({
                    "role": role,
                    "model": "",
                    "parts": parts,
                    "time_created": ts_unix,
                })

    return result


# ── Org-mode 格式化 ────────────────────────────────────────
def format_org(session: dict) -> str:
    """将一个 session 格式化为 Org-mode 文本。"""
    source: str = session["source"]
    title: str = session.get("title", "Untitled")
    project: str = session.get("project_dir", session.get("directory", ""))
    ts = session.get("time_created", 0)

    if source == "opencode":
        ts_sec = ts / 1000
    else:
        ts_sec = ts

    dt = datetime.fromtimestamp(ts_sec)
    id_stamp = dt.strftime("%Y%m%d-%H%M%S")

    lines: list[str] = []
    lines.append(f"* {title}")
    lines.append(":PROPERTIES:")
    lines.append(f":ID:       {id_stamp}-{session['id'][:8]}")
    lines.append(f":CREATED:  [{dt.strftime('%Y-%m-%d %a %H:%M')}]")
    lines.append(f":SOURCE:   {source}")
    lines.append(f":PROJECT:  {project}")
    lines.append(":END:")
    lines.append("")

    for msg in session.get("messages", []):
        role: str = msg["role"]
        model: str = msg.get("model", "")
        agent: str = msg.get("agent", "")

        if role == "tool":
            # tool_result message — 跳过，输出合并到上一个 tool
            for part in msg.get("parts", []):
                if part.get("type") == "tool-result":
                    content = part.get("content", "").strip()
                    if content:
                        lines.append("#+RESULTS:")
                        lines.append("#+BEGIN_SRC")
                        lines.append(content[:1500])
                        lines.append("#+END_SRC")
                        lines.append("")
            continue

        role_label = "User" if role == "user" else ("Assistant" if role == "assistant" else role)

        header_parts: list[str] = [role_label]
        if agent:
            header_parts.append(f"@{agent}")
        if model:
            header_parts.append(f"({model})")
        header = " ".join(header_parts)

        lines.append(f"** {header}")
        lines.append("")

        for part in msg.get("parts", []):
            ptype: str = part.get("type", "")
            if ptype == "text":
                content = part.get("content", "").strip()
                if content:
                    lines.append(content)
                    lines.append("")
            elif ptype == "reasoning":
                content = part.get("content", "").strip()
                if content:
                    lines.append("#+BEGIN_QUOTE")
                    lines.append(content)
                    lines.append("#+END_QUOTE")
                    lines.append("")
            elif ptype == "tool":
                tool_name: str = part.get("tool", "unknown")
                inp = part.get("input", {})
                out: str = part.get("output", "")
                cmd = ""
                if isinstance(inp, dict):
                    cmd = inp.get("command", inp.get("description", json.dumps(inp, ensure_ascii=False)[:200]))
                lines.append(f"*** tool: {tool_name}")
                lines.append("#+BEGIN_SRC")
                lines.append(str(cmd).strip())
                lines.append("#+END_SRC")
                if out:
                    lines.append("#+RESULTS:")
                    lines.append("#+BEGIN_SRC")
                    lines.append(out.strip()[:1500])
                    lines.append("#+END_SRC")
                lines.append("")
            elif ptype == "tool-result":
                content = part.get("content", "").strip()
                if content:
                    lines.append("#+RESULTS:")
                    lines.append("#+BEGIN_SRC")
                    lines.append(content[:1500])
                    lines.append("#+END_SRC")
                    lines.append("")
            elif ptype == "patch":
                files = part.get("files", [])
                if files:
                    lines.append(f"*** patch: {', '.join(str(f) for f in files)}")
                    lines.append("")

    return "\n".join(lines)


# ── 主逻辑 ──────────────────────────────────────────────────
def main() -> None:
    parser = argparse.ArgumentParser(description="提取 OpenCode/Crush/Codex/Claude 对话记录")
    parser.add_argument("--date", "-d", help="目标日期 (YYYY-MM-DD)，默认昨天")
    parser.add_argument("--output", "-o", default=None, help="输出目录")
    parser.add_argument(
        "--source", "-s",
        choices=["opencode", "crush", "codex", "claude", "all"],
        default="all",
        help="数据源 (默认: all)",
    )
    args = parser.parse_args()

    range_start, range_end = compute_date_range(args.date)
    target_label = range_start.strftime("%Y-%m-%d")

    output_dir = args.output or os.path.join(os.getcwd(), "conversations", target_label)
    os.makedirs(output_dir, exist_ok=True)

    sessions: list[dict] = []
    if args.source in ("opencode", "all"):
        print("提取 OpenCode...")
        sessions.extend(extract_opencode(range_start, range_end))
    if args.source in ("crush", "all"):
        print("提取 Crush...")
        sessions.extend(extract_crush(range_start, range_end))
    if args.source in ("claude", "all"):
        print("提取 Claude Code...")
        sessions.extend(extract_claude(range_start, range_end))
    if args.source in ("codex", "all"):
        print("提取 Codex...")
        sessions.extend(extract_codex(range_start, range_end))

    if not sessions:
        print(f"未找到 {target_label} 的对话记录。")
        sys.exit(0)

    sessions.sort(key=lambda s: s.get("time_created", 0))

    written = 0
    for sess in sessions:
        org_content = format_org(sess)
        source: str = sess["source"]
        title: str = sess.get("title", "Untitled")
        sname = safe_filename(title)

        ts = sess.get("time_created", 0)
        ts_sec = ts / 1000 if source == "opencode" else ts
        dt = datetime.fromtimestamp(ts_sec)
        filename = f"{dt.strftime('%Y%m%d-%H%M%S')}-{source}-{sname}.org"
        filepath = os.path.join(output_dir, filename)

        with open(filepath, "w", encoding="utf-8") as f:
            f.write(org_content)
        written += 1
        print(f"  [{source}] {dt.strftime('%H:%M')} {title}")

    print(f"\n提取完成: {written} 个对话 -> {output_dir}")


if __name__ == "__main__":
    main()
