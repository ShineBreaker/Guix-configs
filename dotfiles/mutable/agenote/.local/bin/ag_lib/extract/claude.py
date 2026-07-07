# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT
"""claude code conversation extractor (JSONL, transcripts/ses_*.jsonl).

Dual-XDG paths (verified, important!):
  CLAUDE_CONFIG_DIR = $XDG_CONFIG_HOME/claude   -- stores config/settings/skills
  transcripts: $XDG_DATA_HOME/claude/transcripts/  -- **NOT under CLAUDE_CONFIG_DIR**
  Old script's assumption ~/.claude/transcripts/ is now empty.

Schema: transcripts/ses_<hex>_<base64>.jsonl, each line {type, timestamp, ...}
  type ∈ user | tool_use | tool_result (no 'assistant' event type!)

  user:        {type, timestamp, content}  — user message (may include system prompts)
  tool_use:    {type, timestamp, tool_name, tool_input}  — assistant's tool call
  tool_result: {type, timestamp, tool_name, tool_input, tool_output}  — result

Pairing: user → tool_use(s) → tool_result(s) grouped into one fact.

Read-only: JSONL read-only.
"""

from __future__ import annotations

import json
import os
from pathlib import Path

from ag_lib.reconcile import ReconciledFact, RECONCILE_DEFAULT_WEIGHT
from ag_lib.extract import resolve_xdg_path, extract_title

# IMPORTANT: transcripts lives under XDG_DATA_HOME, NOT CLAUDE_CONFIG_DIR
CLAUDE_TRANSCRIPTS_DIR = resolve_xdg_path(
    "CLAUDE_TRANSCRIPTS_DIR",
    "$XDG_DATA_HOME/claude/transcripts",
)

# claude 外部源：trust 0.5 → weight 0.6
EXTERNAL_RECONCILE_WEIGHT = round(RECONCILE_DEFAULT_WEIGHT - 0.1, 2)


def _normalize_message(msg) -> str:
    """Extract text from claude message (str, list of parts with type=text/tool_use/tool_result)."""
    if isinstance(msg, str):
        return msg.strip()
    if isinstance(msg, list):
        texts: list[str] = []
        for part in msg:
            if isinstance(part, dict):
                ptype = part.get("type", "")
                if ptype == "text":
                    texts.append(part.get("text", ""))
                elif ptype == "tool_use":
                    tool_name = part.get("name", "unknown")
                    tool_input = json.dumps(
                        part.get("input", {}), ensure_ascii=False
                    )[:300]
                    texts.append(f"[tool_use: {tool_name}] {tool_input}")
                elif ptype == "tool_result":
                    content = part.get("content", "")
                    if isinstance(content, str):
                        texts.append(f"[tool_result] {content[:500]}")
                    else:
                        texts.append(
                            f"[tool_result] {json.dumps(content, ensure_ascii=False)[:500]}"
                        )
            elif isinstance(part, str):
                texts.append(part)
        return "\n".join(t for t in texts if t).strip()
    if isinstance(msg, dict):
        return _normalize_message(msg.get("content", msg.get("text", "")))
    return str(msg).strip()


def _extract_session_file(jsonl_path: Path) -> tuple[list[ReconciledFact], list[str]]:
    """Extract from one ses_*.jsonl file.

    Claude transcript schema (no 'assistant' event type):
      user        → user message (including system prompts)
      tool_use    → assistant's tool call (tool_name + tool_input)
      tool_result → tool execution result

    Pairing strategy: user → tool_use(s) → tool_result(s)
    """
    facts: list[ReconciledFact] = []
    errors: list[str] = []
    session_id = jsonl_path.stem

    events: list[dict] = []
    try:
        with open(jsonl_path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    events.append(json.loads(line))
                except json.JSONDecodeError:
                    continue
    except OSError as e:
        return [], [str(e)]

    # First user message as title
    title = "Untitled"
    for evt in events:
        if evt.get("type") == "user":
            msg = evt.get("message", evt.get("content", ""))
            text = _normalize_message(msg)
            if text:
                title = extract_title(text) or "Untitled"
                break

    # Build facts: user → tool_use(s) → tool_result(s)
    current_user: str | None = None
    tool_calls: list[dict] = []
    tool_results: list[str] = []

    def _flush_pair():
        """Flush accumulated user→tools→results as one fact."""
        nonlocal current_user, tool_calls, tool_results
        if not current_user or not tool_calls:
            current_user = None
            tool_calls = []
            tool_results = []
            return

        # Build assistant content from tool calls
        assistant_parts: list[str] = []
        for tc in tool_calls:
            tool_name = tc.get("tool_name", "unknown")
            tool_input = json.dumps(tc.get("tool_input", {}), ensure_ascii=False)[:300]
            assistant_parts.append(f"[tool_use: {tool_name}] {tool_input}")
        assistant_content = "\n".join(assistant_parts)

        # Append tool results if available
        if tool_results:
            results_text = "\n".join(f"[tool_result] {r[:500]}" for r in tool_results)
            assistant_content += f"\n\n{results_text}"

        ts = tool_calls[0].get("timestamp", "")
        facts.append(
            ReconciledFact(
                id=f'claude:{session_id}:{ts}',
                source="claude",
                native_id=session_id,
                title=title,
                category="general",
                content=f"USER: {current_user[:1000]}\n\nASSISTANT: {assistant_content[:2000]}",
                trust_score=0.5,
                weight=EXTERNAL_RECONCILE_WEIGHT,
                tags=["claude-code"],
                timestamp=ts,
            )
        )
        current_user = None
        tool_calls = []
        tool_results = []

    for evt in events:
        etype = evt.get("type", "")
        if etype == "user":
            # Flush previous pair before starting new one
            _flush_pair()
            msg = evt.get("message", evt.get("content", ""))
            current_user = _normalize_message(msg)
        elif etype == "tool_use":
            tool_calls.append(evt)
        elif etype == "tool_result":
            output = evt.get("tool_output", "")
            if isinstance(output, str):
                tool_results.append(output)
            else:
                tool_results.append(json.dumps(output, ensure_ascii=False))

    # Flush last pair
    _flush_pair()

    return facts, errors


def extract_claude() -> tuple[list[ReconciledFact], list[str]]:
    """Extract from claude transcripts/ (read-only)."""
    all_facts: list[ReconciledFact] = []
    all_errors: list[str] = []
    if not CLAUDE_TRANSCRIPTS_DIR.exists():
        return [], [f"transcripts dir 不存在: {CLAUDE_TRANSCRIPTS_DIR}"]
    for jsonl_path in sorted(CLAUDE_TRANSCRIPTS_DIR.glob("ses_*.jsonl")):
        facts, errors = _extract_session_file(jsonl_path)
        all_facts.extend(facts)
        all_errors.extend(errors)
    return all_facts, all_errors