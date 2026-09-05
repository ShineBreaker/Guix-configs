# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT
"""hermes global-context — 全局上下文注入（对位 omp global-context）。

注入清单由 context-select.sh（四端共享决策核，单一真相源）按 platform=hermes
与 session cwd 判定：00-core.md 与 INDEX.md 恒注入，git 仓库内附加
domains/coding.md。本插件只做协议转换，不维护 always/gitGated 之类的
文件分类清单。

hermes 无 before_agent_start hook，改用 ctx.register_system_prompt_section
（每 session 冻结渲染一次；单节 4000 / 全进程总 8000 字符由框架硬限，空节
自动跳过）：注册集合来自 selector `--list-all`（映射表全集，与进程启动
目录无关），每文件注册一节；render 时按当次 session cwd 调 selector 的
select 结果门控，文件不在当次清单内即返回空串。subagent / cron 平台整体
不注入（hermes 框架语义：子任务上下文自包含，硬防护由 gate 插件的运行时
拦截承担）。

selector 不可用 / 无输出时 fallback：恒注入 contextDir（CONTEXT_DIR 或
$XDG_CONFIG_HOME/agents/context，与 selector 内定逻辑一致）下存在的
00-core.md 与 INDEX.md 两件，保证 blue home 部署前插件不空转。
调用 selector 只以 stdout 为契约（忽略 returncode）。

配置 $HERMES_HOME/global-context.json（缺省/解析失败用内置默认）：
  {enabled, maxBytesPerFile}
"""

from __future__ import annotations

import functools
import json
import os
import subprocess
from pathlib import Path
from typing import Any, Callable

_DEFAULTS: dict[str, Any] = {
    "enabled": True,
    "maxBytesPerFile": 65536,
}

_SKIP_PLATFORMS = ("subagent", "cron")
_SELECTOR_TIMEOUT_S = 10
_FALLBACK_FILES = ("00-core.md", "INDEX.md")  # 恒注入集，与 selector 映射表一致


def _hermes_home() -> Path:
    env = os.environ.get("HERMES_HOME")
    if env:
        return Path(env)
    return Path.home() / ".local" / "share" / "hermes"


def _load_config() -> dict[str, Any]:
    cfg = dict(_DEFAULTS)
    try:
        raw = json.loads(
            (_hermes_home() / "global-context.json").read_text(encoding="utf-8")
        )
    except (OSError, ValueError):
        return cfg
    if isinstance(raw, dict):
        cfg.update({k: raw[k] for k in _DEFAULTS if k in raw})
    return cfg


def _fallback_context_dir() -> Path:
    env = os.environ.get("CONTEXT_DIR")
    if env:
        return Path(env)
    xdg = os.environ.get("XDG_CONFIG_HOME") or str(Path.home() / ".config")
    return Path(xdg) / "agents" / "context"


def _fallback_paths() -> list[Path]:
    base = _fallback_context_dir()
    return [base / name for name in _FALLBACK_FILES if (base / name).is_file()]


def _selector_path() -> str:
    return os.environ.get("CONTEXT_SELECT_BIN") or str(
        Path.home() / ".config" / "agents" / "context-select.sh"
    )


def _run_selector(args: list[str]) -> list[Path] | None:
    """跑 selector，返回 stdout 路径清单；selector 缺失/失败/无输出返回 None。"""
    try:
        proc = subprocess.run(
            [_selector_path(), *args],
            capture_output=True,
            text=True,
            timeout=_SELECTOR_TIMEOUT_S,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    paths = [Path(line) for line in proc.stdout.splitlines() if line.strip()]
    return paths or None


@functools.lru_cache(maxsize=32)  # render 每节各查一次，按 cwd 去重 spawn
def _selected_paths(cwd: str) -> list[Path]:
    """本 session 应注入的文件清单：selector 决策，失败/无输出时 fallback 恒注入两件。"""
    return _run_selector(
        ["--platform", "hermes", "--cwd", cwd or os.getcwd()]
    ) or _fallback_paths()


def _all_paths() -> list[Path]:
    """注册全集（selector 映射表全量，不做门控），保证与进程启动目录无关。"""
    return _run_selector(["--list-all"]) or _fallback_paths()


def _make_section(cfg: dict[str, Any], path: Path) -> Callable[[dict[str, str]], str]:
    def render(session_info: dict[str, str]) -> str:
        if session_info.get("platform") in _SKIP_PLATFORMS:
            return ""
        if path not in _selected_paths(session_info.get("cwd", "")):
            return ""
        try:
            if path.stat().st_size > cfg["maxBytesPerFile"]:
                return ""
            content = path.read_text(encoding="utf-8")
        except OSError:
            return ""
        if not content.strip():
            return ""
        return f'<global_context_file path="{path}">\n{content}\n</global_context_file>'

    return render


# ── /global-context 命令：显示注入清单（对位 omp 版状态查询）────────────────


def _handle_global_context(raw_args: str) -> str:
    cfg = _load_config()
    lines = [
        f"状态: {'✅ 已启用' if cfg['enabled'] else '❌ 已禁用'}",
        f"selector: {_selector_path()}（--platform hermes，决策与 zcode/omp/crush 共享）",
        f"单文件预算: {cfg['maxBytesPerFile']} B",
    ]
    paths = _selected_paths(os.getcwd())
    if not paths:
        lines.append("清单: （空——selector 无输出且 fallback 恒注入文件不存在）")
    for p in paths:
        size = f" ({p.stat().st_size} B)" if p.is_file() else ""
        lines.append(f"  {'✅' if p.is_file() else '❌'} {p}{size}")
    lines.append("subagent/cron 平台不注入；注入判定由 context-select.sh 按 session cwd 决策")
    return "\n".join(lines)


def register(ctx: Any) -> None:
    cfg = _load_config()
    if not cfg["enabled"]:
        return
    for path in _all_paths():
        # section id 限 [a-z0-9._-]
        stem = path.stem.replace("_", "-").lower()
        ctx.register_system_prompt_section(
            f"global-context-{stem}", _make_section(cfg, path)
        )
    ctx.register_command(
        "global-context",
        _handle_global_context,
        description="显示 global-context 注入的上下文文件清单",
        args_hint="",
    )
