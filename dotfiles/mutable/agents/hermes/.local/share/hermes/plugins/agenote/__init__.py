# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
# SPDX-License-Identifier: MIT
"""Hermes plugin for agenote — 对位 pi 的 agenote-hooks 扩展。

提供：
- pre_llm_call 钩子：检测任务完成信号，注入 agenote-review 评估提示
- /agenote-summarize：手动触发经验总结
- /agenote-health：显示 KB 健康度
- /agenote-curate：执行策展（健康+去重+归档+权重重分配）

信号清单与写入流程由 agenote-{base,curator,review} skill 提供，本插件只做
事件触发 + 命令快捷入口，避免与 skill 重复维护。
"""

from __future__ import annotations

import os
import subprocess
import time
from pathlib import Path
from typing import Any

# ── 完成信号（与 pi-agenote/index.ts 保持一致）─────────────────────
COMPLETION_SIGNALS = [
    "可以用了",
    "一切正常",
    "都没问题",
    "都正常",
    "搞定",
    "完成",
    "做完了",
    "测试通过",
    "就这些",
    "先这样",
    "暂时够了",
    "就这样",
    "没了",
    "done.",
    "done!",
    "looks good",
    "ship it",
]

HOOK_MARKER = "<agenote-hook>"
DEBOUNCE_MS = 5 * 60 * 1000  # 5 分钟冷却

_last_trigger_ms: float = 0.0

# agenote CLI 解析：Guix 路径优先，fallback 到 PATH
_AGENOTE_BIN = "agenote"


def _resolve_agenote_bin() -> str:
    for cand in [
        str(Path.home() / ".guix-home/profile/bin/agenote"),
        str(Path.home() / ".local/bin/agenote"),
    ]:
        if Path(cand).exists() and os.access(cand, os.X_OK):
            return cand
    return _AGENOTE_BIN


_RESOLVED_BIN: str | None = None


def _bin() -> str:
    global _RESOLVED_BIN
    if _RESOLVED_BIN is None:
        _RESOLVED_BIN = _resolve_agenote_bin()
    return _RESOLVED_BIN


def _run_agenote(*args: str, timeout: int = 30) -> str:
    """运行 agenote CLI，返回 stdout；失败返回错误描述。"""
    try:
        result = subprocess.run(
            [_bin(), *args],
            capture_output=True,
            text=True,
            timeout=timeout,
            env={**os.environ, "AGENOTE_AGENT": "hermes"},
        )
        out = (result.stdout or "").strip()
        err = (result.stderr or "").strip()
        if result.returncode != 0:
            detail = err or out or f"exit {result.returncode}"
            return f"(agenote {' '.join(args)} 失败: {detail})"
        return out or "(无输出)"
    except subprocess.TimeoutExpired:
        return f"(agenote {' '.join(args)} 超时 {timeout}s)"
    except FileNotFoundError:
        return "(agenote 命令未找到，请先安装 agenote CLI)"
    except Exception as exc:
        return f"(agenote 执行异常: {exc})"


def build_review_prompt(reason: str) -> str:
    return "\n".join(
        [
            f"<agenote-hook>{reason}，请按 agenote-review skill 流程评估本次对话：",
            "（注意：这有可能是误报，如果当前任务没有完成的话，请忽略）",
            "1. 是否有可记录的经验信号（bug/踩坑/更优方案/用户纠正/项目决策）？",
            "2. 如有 → 通过 bash 调用 agenote CLI 写入（agenote add / agenote memory --add 等）",
            "3. 本轮用到的资料留痕：已有卡片 agenote touch，联网新知识 agenote add（type=note）",
            "4. 如无 → 明确回复'本次无可记录经验'</agenote-hook>",
        ]
    )


def _should_skip(user_text: str) -> bool:
    """子注入或空文本跳过。"""
    if not user_text:
        return True
    if HOOK_MARKER in user_text:
        return True
    return False


def _has_completion_signal(text_lower: str) -> bool:
    for sig in COMPLETION_SIGNALS:
        if sig.lower() in text_lower:
            return True
    return False


# ── pre_llm_call hook ────────────────────────────────────────────
def _pre_llm_call(
    session_id: str = "",
    user_message: str = "",
    platform: str = "",
    **_: Any,
) -> dict[str, str] | None:
    """检测用户消息中的完成信号，命中时注入 review 提示。"""
    global _last_trigger_ms

    # 子 agent / cron 会话不触发（避免污染 handoff / 定时任务噪音）
    if platform in ("subagent", "cron"):
        return None

    text = user_message if isinstance(user_message, str) else str(user_message or "")
    if _should_skip(text):
        return None

    lower = text.lower()
    if not _has_completion_signal(lower):
        return None

    now_ms = time.time() * 1000
    if now_ms - _last_trigger_ms < DEBOUNCE_MS:
        return None
    _last_trigger_ms = now_ms

    prompt = build_review_prompt("检测到任务完成信号")
    return {"context": prompt}


# ── slash command handlers ───────────────────────────────────────

def _make_summarize_handler(ctx: Any):
    def handler(raw_args: str) -> str:
        prompt = build_review_prompt("用户手动触发经验总结")
        injected = False
        try:
            injected = bool(ctx.inject_message(prompt))
        except Exception:
            injected = False
        if injected:
            return "已注入 agenote-review 评估提示到下一轮对话。"
        return prompt

    return handler


def _handle_health(raw_args: str) -> str:
    return _run_agenote("health", timeout=30)


def _handle_curate(raw_args: str) -> str:
    # 重操作，给 120s，与 pi-agenote 对齐
    out = _run_agenote("curate", timeout=120)
    # curate 后追加 health 摘要便于确认
    health = _run_agenote("health", timeout=15)
    return f"{out}\n\n---\n{health}"


def register(ctx: Any) -> None:
    ctx.register_hook("pre_llm_call", _pre_llm_call)

    ctx.register_command(
        "agenote-summarize",
        _make_summarize_handler(ctx),
        description="在当前会话触发 agenote 经验总结 + 留痕",
        args_hint="",
    )
    ctx.register_command(
        "agenote-health",
        _handle_health,
        description="显示 agenote 健康度报告",
        args_hint="",
    )
    ctx.register_command(
        "agenote-curate",
        _handle_curate,
        description="执行 agenote 策展（健康+去重+归档+权重重分配）",
        args_hint="",
    )
