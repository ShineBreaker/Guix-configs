# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT
"""Hermes plugin for agenote — 知识库集成 + 记忆注入（设计 C4 W2 成品级）。

本插件是 agenote 生态为 hermes 的唯一接入点，承担两块职责：

注入（agenote → 会话，AGENOTE_INJECTION_DESIGN.md §3 C4，追加型三件套）：
- register_system_prompt_section（after_memory 锚点，框架默认位）：会话级简报
  （`--mode session`，3800 字符）。进程内按 KB 指纹缓存——指纹未变零 spawn
  重放；compact 后 hermes 重建系统提示词会重新调 render，此时从缓存返回
  （不返回空，否则重建后的提示词会丢简报）；KB 更新则重跑 CLI 换新快照。
- pre_llm_call（每回合 recall，2000 字符）：追加型三件套——①指纹+query
  未变不重注（含被分数下限滤空的情况）②短 prompt 门槛（镜像 SCHEMA
  recall_min_query=6）③单会话累计预算 24000 字符触顶停 recall；
  SessionStart 语义由 bash 注入器承担（hermes 无该挂点），本插件的会话
  边界 = 进程生命周期 + 状态文件按 session_id 隔离。
- 与既有的任务完成信号检测共存于同一 pre_llm_call：召回正文与评估提示
  各自独立触发，同回合双双命中时以空行拼接成一个 context 注入。
- 状态文件 ~/.cache/agenote/injectors/hermes-<session_id>.json（与 bash 注入器
  同款布局；session_id 缺失退化为 hermes.json 单文件；整目录可清理无副作用）。
- `agenote context` text 零字节（disabled/empty）→ 本回合不注，宿主零感知。

集成（会话 → agenote，既有能力，保持不变）：
- pre_llm_call 钩子：检测任务完成信号，注入 agenote-review 评估提示
- /agenote-summarize：手动触发经验总结
- /agenote-health：显示 KB 健康度
- /agenote-curate：执行策展（健康+去重+归档+权重重分配）

信号清单与写入流程由 agenote-{base,curator,review} skill 提供，本插件只做
事件触发 + 注入通道 + 命令快捷入口，避免与 skill 重复维护。

注入语义开关的真相源在 agenote SCHEMA [injection]/[injection.hosts]（一键全关
AGENOTE_INJECTION_ENABLED=false）；本侧旋钮只有预算/门槛/状态目录三个 env。
真机验收：/context 看 agenote 节 + sidecar 审计（详见 agenote 仓库
injectors/hermes/README.md）。
"""

from __future__ import annotations

import json
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

# ── 注入参数（设计 C4 每宿主预算表；env 覆盖，语义开关在 agenote SCHEMA）──
_BRIEF_BUDGET = int(os.environ.get("AGENOTE_INJECTION_BRIEF_BUDGET") or 3800)
_RECALL_BUDGET = int(os.environ.get("AGENOTE_INJECTION_RECALL_BUDGET") or 2000)
_CUMULATIVE_BUDGET = int(
    os.environ.get("AGENOTE_INJECTION_SESSION_CUMULATIVE_BUDGET") or 24000
)
_MIN_QUERY = int(os.environ.get("AGENOTE_INJECTION_MIN_QUERY") or 6)
_QUERY_MAX_CHARS = 200  # recall query 取 prompt 前 N 字符
_SKIP_PLATFORMS = ("subagent", "cron")

# 会话级简报的进程内缓存：{fp, content}（指纹未变零 spawn；compact 重建安全）
_BRIEF_CACHE: dict[str, str] = {}

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


# ═══════════════════════════════════════════════════════════════════════════════
# 注入：KB 指纹 / 状态文件 / context 调用（与 injectors/lib.sh 同构）
# ═══════════════════════════════════════════════════════════════════════════════


def _kb_domain_root() -> Path:
    """agenote 域根（context 语料所在）：KB_ROOT env > config.toml > 默认。

    与 CLI 同口径的镜像实现（config 只取 paths 两键，解析失败回退默认）；
    context 命令读 agent 域，指纹必须定位到 KB_ROOT/<agenote_dir>/。
    """
    try:
        import tomllib

        cfg = (
            Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")
            / "agenote"
            / "config.toml"
        )
        with open(cfg, "rb") as f:
            paths = tomllib.load(f).get("paths", {})
        kb = os.environ.get("KB_ROOT") or paths.get("kb_root") or ""
        agenote_dir = paths.get("agenote_dir") or "agenote"
        if kb:
            return Path(kb).expanduser() / agenote_dir
    except Exception:
        pass
    if os.environ.get("KB_ROOT"):
        return Path(os.environ["KB_ROOT"]).expanduser() / "agenote"
    return Path.home() / "Documents" / "Org" / "agenote"


def _kb_fingerprint() -> str:
    """MEMORY.org 与 memories/ 的 mtime_ns+size 指纹（设计 D8）；KB 缺失返回空。"""
    root = _kb_domain_root()
    try:
        st = (root / "MEMORY.org").stat()
    except OSError:
        return ""
    fp = f"{st.st_mtime_ns}:{st.st_size}"
    try:
        st_dir = (root / "memories").stat()
        fp += f"|{st_dir.st_mtime_ns}:{st_dir.st_size}"
    except OSError:
        fp += "|-"
    return fp


def _state_dir() -> Path:
    env = os.environ.get("AGENOTE_INJECTOR_STATE_DIR")
    if env:
        return Path(env)
    cache = os.environ.get("XDG_CACHE_HOME") or str(Path.home() / ".cache")
    return Path(cache) / "agenote" / "injectors"


def _state_path(session_id: str) -> Path:
    sid = (session_id or "").strip().replace("/", "_")
    name = f"hermes-{sid}.json" if sid else "hermes.json"
    return _state_dir() / name


def _state_read(path: Path) -> dict[str, Any]:
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def _state_write(path: Path, data: dict[str, Any]) -> None:
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_suffix(".json.tmp")
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False)
        os.replace(tmp, path)
    except OSError:
        pass  # 状态写失败宁可下轮重复注入，也不中断回合


def _context_content(mode: str, budget: int, query: str = "") -> str:
    """调 `agenote context` 取注入正文；任何失败/非 ok/空 → 空串（不注）。"""
    args = [
        "context", "--mode", mode, "--budget", str(budget),
        "--host", "hermes", "--format", "json",
    ]
    if query:
        args += ["--query", query]
    try:
        result = subprocess.run(
            [_bin(), *args],
            capture_output=True,
            text=True,
            timeout=30,
            env={**os.environ, "AGENOTE_AGENT": "hermes"},
        )
        data = json.loads(result.stdout or "")
    except Exception:
        return ""
    if isinstance(data, dict) and data.get("status") == "ok":
        return data.get("content") or ""
    return ""


def build_query(user_text: str, cwd: str = "") -> str | None:
    """prompt 折叠空白取前 200 字符 + cwd basename 伪词；短门槛不过返回 None。

    门槛按 prompt 部分长度判（伪词不计入），与 lib.sh 同语义。
    """
    q_text = " ".join((user_text or "").split())[:_QUERY_MAX_CHARS]
    if len(q_text.strip()) < _MIN_QUERY:
        return None
    pseudo = os.path.basename((cwd or os.getcwd()).rstrip("/"))
    return (q_text + " " + pseudo).strip() if pseudo and pseudo != "." else q_text


def _recall_context(session_id: str, user_text: str) -> str:
    """每回合 recall（追加型三件套①②③）；不注返回空串。"""
    fp = _kb_fingerprint()
    if not fp:
        return ""
    q = build_query(user_text)
    if q is None:  # 三件套②：短 prompt 不值得注入
        return ""
    state_path = _state_path(session_id)
    state = _state_read(state_path)
    key = fp + "::" + q
    if state.get("recall_key") == key:  # 三件套①：指纹+query 未变（含滤空）不重注
        return ""
    cumulative = int(state.get("cumulative") or 0)
    if cumulative >= _CUMULATIVE_BUDGET:  # 三件套③：触顶停 recall
        state["recall_key"] = key
        _state_write(state_path, state)
        return ""
    content = _context_content("recall", _RECALL_BUDGET, q)
    state["recall_key"] = key
    if content:
        state["cumulative"] = cumulative + len(content)
        _state_write(state_path, state)
        return content
    _state_write(state_path, state)  # 滤空也落账：同 query 下轮零 spawn
    return ""


def _render_brief(session_info: dict[str, str]) -> str:
    """会话级简报节（register_system_prompt_section 渲染回调）。

    指纹未变零 spawn 重放；compact 重建时 hermes 重新调 render，从缓存返回
    而非空串——否则重建后的提示词会丢简报。disabled/empty 的空 content 同样
    入缓存（避免每轮 render 反复 spawn），KB 指纹变化时自然失效。
    """
    if session_info.get("platform") in _SKIP_PLATFORMS:
        return ""
    fp = _kb_fingerprint()
    if not fp:
        return ""
    if _BRIEF_CACHE.get("fp") == fp:
        return _BRIEF_CACHE.get("content", "")
    content = _context_content("session", _BRIEF_BUDGET)
    _BRIEF_CACHE["fp"] = fp
    _BRIEF_CACHE["content"] = content
    return content


# ── 完成信号（既有逻辑，保持不变）─────────────────────────────────


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


# ── pre_llm_call hook（召回注入 + 完成信号检测合一）───────────────


def _pre_llm_call(
    session_id: str = "",
    user_message: str = "",
    platform: str = "",
    **_: Any,
) -> dict[str, str] | None:
    """召回记忆注入 + 完成信号检测。两者独立触发，命中合并为一个 context。"""
    global _last_trigger_ms

    # 子 agent / cron 会话不触发（避免污染 handoff / 定时任务噪音；设计 §5-9）
    if platform in _SKIP_PLATFORMS:
        return None

    text = user_message if isinstance(user_message, str) else str(user_message or "")
    if _should_skip(text):
        return None

    parts: list[str] = []

    recall = _recall_context(session_id, text)
    if recall:
        parts.append(recall)

    lower = text.lower()
    if _has_completion_signal(lower):
        now_ms = time.time() * 1000
        if now_ms - _last_trigger_ms >= DEBOUNCE_MS:
            _last_trigger_ms = now_ms
            parts.append(build_review_prompt("检测到任务完成信号"))

    if not parts:
        return None
    return {"context": "\n\n".join(parts)}


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
    # 会话级简报节（after_memory 锚点为框架默认位；单节 4000/总量 8000 由框架
    # 硬限，本插件节预算 3800 留余量）。global-context 插件先例：section 注册
    # 无需在 plugin.yaml 声明。
    ctx.register_system_prompt_section("agenote-context-brief", _render_brief)
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
