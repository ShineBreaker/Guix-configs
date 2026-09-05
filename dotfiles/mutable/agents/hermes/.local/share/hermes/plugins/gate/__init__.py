# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT
"""hermes gate — 权限边界插件（对位 omp pi-gate）。

判定语义全部在 ~/.config/agents/gate-core.sh（决策核，规则源为两级
anchors.json 的 ratchet 合并）。本插件只做 hermes 协议转换：
  - BLOCK / SENSITIVE  → {"action": "block", "message": ...}
  - REWRITTEN          → {"action": "modify", "args": {"command": ...}}（terminal）
  - RM_HINT/NOTES/REDIRECT/HINT → 经 transform_tool_result 把 gate_hint 追加进
    工具结果（对位 zcode additionalContext；hermes 无原生非阻塞提示通道）

与 pi-gate 的两处语义差异：
  - hermes 的 pre_tool_call 回调抛异常是 fail-open（放行），sudo 保底必须
    写在回调内部 try/except 里返回 block 指令，不能靠异常兜底
  - gate-core 缺失/执行失败时无日志文件可写（omp 有 .load-errors.log），
    仅 stderr 留痕

工具映射：terminal→bash 模式（command）；write_file/patch→edit 模式
（path + 内容走 stdin）。姊妹适配器见 zcode/.zcode/hooks 与
immutable agents/.config/crush/hooks。
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any

GATE_CORE = Path.home() / ".config" / "agents" / "gate-core.sh"
# 须低于 hermes hook 回调默认 30s 超时（超时侧框架 fail-closed）
_CORE_TIMEOUT = 8

# 待追加提示：pre_tool_call 阶段攒下，transform_tool_result 阶段消费
_PENDING_HINTS: dict[str, list[str]] = {}


def _cwd_from(args: dict) -> str:
    # pre_tool_call payload 不含 cwd：terminal 的 workdir > TERMINAL_CWD > 进程 cwd
    workdir = args.get("workdir")
    if isinstance(workdir, str) and workdir:
        return workdir
    return os.environ.get("TERMINAL_CWD") or os.getcwd()


def _run_core(mode_args: list[str], cwd: str, stdin_text: str = "") -> dict | None:
    """调决策核并解析行协议（每行 `TYPE<TAB>payload`）；异常返回 None。"""
    try:
        res = subprocess.run(
            ["bash", str(GATE_CORE), *mode_args],
            input=stdin_text,
            capture_output=True,
            text=True,
            timeout=_CORE_TIMEOUT,
            env={**os.environ, "GATE_CWD": cwd},
        )
    except Exception as exc:
        print(f"[gate] gate-core 调用异常: {exc}", file=sys.stderr)
        return None
    if res.returncode != 0:
        print(
            f"[gate] gate-core exit {res.returncode}: {res.stderr.strip()}",
            file=sys.stderr,
        )
        return None
    verdict: dict[str, Any] = {
        "block": None,
        "sensitive": False,
        "rewritten": None,
        "hints": [],
    }
    for line in res.stdout.split("\n"):
        if not line:
            continue
        type_, _, payload = line.partition("\t")
        if type_ == "BLOCK":
            verdict["block"] = payload
            return verdict
        if type_ == "SENSITIVE":
            verdict["block"] = payload
            verdict["sensitive"] = True
            return verdict
        if type_ == "REWRITTEN":
            verdict["rewritten"] = payload
        elif type_ in ("RM_HINT", "NOTES", "REDIRECT", "HINT"):
            if payload:
                verdict["hints"].append(payload)
        # AUTO_ALLOW：走默认流程即可
    return verdict


def _sudo_fallback(tool_name: str, args: dict) -> dict | None:
    """决策核异常时的保底：agent 任何场景都不需要提权。"""
    if tool_name == "terminal" and "sudo" in str(args.get("command", "")):
        return {
            "action": "block",
            "message": "🚫 冻结命令「sudo」禁止执行（gate-core 异常，保底拦截）。",
        }
    return None


def _gate_bash(args: dict, cwd: str, tool_call_id: str) -> dict | None:
    cmd = str(args.get("command", ""))
    if not cmd:
        return None
    verdict = _run_core(["bash", cmd], cwd)
    if verdict is None:
        return _sudo_fallback("terminal", args)
    if verdict["block"]:
        return {"action": "block", "message": verdict["block"]}
    if verdict["hints"]:
        _PENDING_HINTS[tool_call_id] = verdict["hints"]
    if verdict["rewritten"]:
        return {"action": "modify", "args": {"command": verdict["rewritten"]}}
    return None


def _edit_content(args: dict) -> str:
    # write_file：全量内容；patch：old/new 拼接（对齐 pi-gate 的 edits 拼接）；
    # V4A 结构化 patch 形态退化为序列化全量
    if "content" in args:
        return str(args.get("content", ""))
    text = "\n".join(
        p
        for p in (str(args.get("old_string", "")), str(args.get("new_string", "")))
        if p
    )
    return text or str(args.get("patch", ""))


def _gate_edit(args: dict, cwd: str) -> dict | None:
    path = str(args.get("path", ""))
    if not path:
        return None
    verdict = _run_core(["edit", path], cwd, _edit_content(args))
    if verdict is None:
        return None
    if verdict["block"]:
        return {"action": "block", "message": verdict["block"]}
    return None


def _pre_tool_call(
    tool_name: str = "",
    args: dict | None = None,
    tool_call_id: str = "",
    **_: Any,
) -> dict | None:
    args = args if isinstance(args, dict) else {}
    try:
        cwd = _cwd_from(args)
        if tool_name == "terminal":
            return _gate_bash(args, cwd, tool_call_id)
        if tool_name in ("write_file", "patch"):
            return _gate_edit(args, cwd)
        return None
    except Exception as exc:
        print(f"[gate] 回调异常: {exc}", file=sys.stderr)
        return _sudo_fallback(tool_name, args)


def _transform_tool_result(
    tool_name: str = "",
    tool_call_id: str = "",
    result: str = "",
    **_: Any,
) -> str | None:
    hints = _PENDING_HINTS.pop(tool_call_id, None)
    if not hints:
        return None
    note = "; ".join(hints)
    try:
        parsed = json.loads(result)
        if isinstance(parsed, dict):
            parsed["gate_hint"] = note
            return json.dumps(parsed, ensure_ascii=False)
    except (ValueError, TypeError):
        pass
    return f"{result}\n\n[gate] {note}"


def register(ctx: Any) -> None:
    ctx.register_hook("pre_tool_call", _pre_tool_call)
    ctx.register_hook("transform_tool_result", _transform_tool_result)
