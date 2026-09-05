# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT
"""global-context 插件测试：selector 决策注入 + fallback + 平台跳过 + 渲染链路。

selector 以 monkeypatch CONTEXT_SELECT_BIN 指向 fixture 脚本的方式 mock；
fallback 覆盖 selector 缺失（OSError）与无输出两类。零第三方依赖。

跑法：
  python3 -m pytest <本目录> -q
  # 或（hermes venv python）
  ~/.local/share/hermes/hermes-agent/venv/bin/python -m unittest \\
      discover -s <本目录> -t <本目录>
"""

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

_PLUGIN_DIR = Path(__file__).resolve().parents[1]

try:  # integration 类依赖 hermes 框架，缺 venv 时跳过
    import hermes_cli.plugins as _hp  # noqa: F401

    _HAS_HERMES_CLI = True
except ImportError:
    _HAS_HERMES_CLI = False

# fixture selector：模拟 context-select.sh。--list-all 输出映射表全集（无视
# git）；select 模式 git 判定向上找 .git ≤8 层，stdout 一行一个绝对路径
# （platform 参数仅透传语义，fixture 忽略）
FIXTURE_SELECTOR = """#!/usr/bin/env python3
import os
import sys

args = sys.argv[1:]
base = os.environ.get("CONTEXT_DIR", "")
core = os.path.join(base, "00-core.md")
index = os.path.join(base, "INDEX.md")
coding = os.path.join(base, "domains", "coding.md")
if "--list-all" in args:
    print(core)
    print(index)
    print(coding)
    raise SystemExit(0)
cwd = args[args.index("--cwd") + 1] if "--cwd" in args else ""
print(core)
print(index)
d = os.path.abspath(cwd or os.getcwd())
for _ in range(8):
    if os.path.exists(os.path.join(d, ".git")):
        print(coding)
        break
    parent = os.path.dirname(d)
    if parent == d:
        break
    d = parent
"""

# 真实 selector 的 select 模式退出码是最后一个 explain 分支的值（EXPLAIN
# 关闭时恒 1）：exit 非 0 但 stdout 有清单，消费端必须仍采用输出。
EXIT1_SELECTOR = FIXTURE_SELECTOR + "raise SystemExit(1)\n"

# 坏 selector：非零退出且无输出 → 应 fallback
FAILING_SELECTOR = "#!/bin/sh\nexit 3\n"

# 坏 selector：正常退出但输出不存在的文件 → render 空串
GHOST_SELECTOR = """#!/usr/bin/env python3
import os
print(os.path.join(os.environ.get("CONTEXT_DIR", ""), "99-ghost.md"))
"""


def _load_plugin():
    spec = importlib.util.spec_from_file_location(
        "global_context_under_test", _PLUGIN_DIR / "__init__.py"
    )
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class _FakeCtx:
    def __init__(self):
        self.sections = []
        self.commands = []

    def register_system_prompt_section(self, section_id, content, **kw):
        self.sections.append((section_id, content))

    def register_command(self, name, handler, description="", args_hint=""):
        self.commands.append(name)


class GlobalContextUnitTests(unittest.TestCase):
    """selector 决策矩阵 + fallback + register 注册形态。"""

    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.tmp = Path(tmp.name)
        self.ctx_dir = self.tmp / "context"
        (self.ctx_dir / "domains").mkdir(parents=True)
        for rel, body in (
            ("00-core.md", "CONTENT-CORE"),
            ("INDEX.md", "CONTENT-INDEX"),
            ("domains/coding.md", "CONTENT-CODING"),
        ):
            (self.ctx_dir / rel).write_text(body)
        self.selector = self.tmp / "fixture-context-select"
        self.selector.write_text(FIXTURE_SELECTOR)
        self.selector.chmod(0o755)
        self.home = self.tmp / "hermes-home"
        self.home.mkdir()
        self.git_cwd = self.tmp / "repo"
        (self.git_cwd / ".git").mkdir(parents=True)
        self.plain_cwd = self.tmp / "plain"
        self.plain_cwd.mkdir()
        self._env = {
            "CONTEXT_SELECT_BIN": str(self.selector),
            "CONTEXT_DIR": str(self.ctx_dir),
            "HERMES_HOME": str(self.home),
        }

    def _write_config(self, **cfg):
        (self.home / "global-context.json").write_text(json.dumps(cfg))

    def _load_and_register(self, register_cwd=None, **env_overrides):
        mod = _load_plugin()
        ctx = _FakeCtx()
        self._env.update(env_overrides)
        # 注册集合来自 selector --list-all（与进程 cwd 无关）；门控在 render
        with mock.patch.dict("os.environ", self._env):
            if register_cwd is not None:
                with mock.patch(
                    "os.getcwd", return_value=str(register_cwd)
                ):
                    mod.register(ctx)
            else:
                mod.register(ctx)
        return mod, ctx

    def _render(self, ctx, section_id, platform="cli", cwd=""):
        for sid, content in ctx.sections:
            if sid == section_id:
                # render 时 selector 子进程需要与注册时同一 CONTEXT_DIR
                with mock.patch.dict("os.environ", self._env):
                    return content({"platform": platform, "cwd": cwd})
        raise AssertionError(f"section {section_id} 未注册")

    # ── selector 决策注入 ─────────────────────────────────────────────

    def test_git_cwd_registers_and_renders_all_three(self):
        _, ctx = self._load_and_register(register_cwd=self.git_cwd)
        self.assertEqual(
            [sid for sid, _ in ctx.sections],
            [
                "global-context-00-core",
                "global-context-index",
                "global-context-coding",
            ],
        )
        for sid, body in (
            ("global-context-00-core", "CONTENT-CORE"),
            ("global-context-index", "CONTENT-INDEX"),
            ("global-context-coding", "CONTENT-CODING"),
        ):
            out = self._render(ctx, sid, cwd=str(self.git_cwd))
            self.assertIn(body, out)
            self.assertIn('<global_context_file path="', out)

    def test_plain_cwd_skips_git_gated_section(self):
        _, ctx = self._load_and_register(register_cwd=self.git_cwd)
        self.assertEqual(
            self._render(ctx, "global-context-coding", cwd=str(self.plain_cwd)),
            "",
        )
        self.assertIn(
            "CONTENT-CORE",
            self._render(ctx, "global-context-00-core", cwd=str(self.plain_cwd)),
        )
        self.assertIn(
            "CONTENT-INDEX",
            self._render(ctx, "global-context-index", cwd=str(self.plain_cwd)),
        )

    def test_selector_nonzero_exit_with_output_still_used(self):
        # 对齐真实 selector：exit 1 但 stdout 有清单，不能误走 fallback
        _, ctx = self._load_and_register(
            register_cwd=self.git_cwd,
            CONTEXT_SELECT_BIN=self._write_fixture(
                "exit1-selector", EXIT1_SELECTOR
            ),
        )
        self.assertEqual(len(ctx.sections), 3)
        self.assertIn(
            "CONTENT-CODING",
            self._render(ctx, "global-context-coding", cwd=str(self.git_cwd)),
        )

    def test_subagent_and_cron_platforms_skip_all(self):
        _, ctx = self._load_and_register(register_cwd=self.git_cwd)
        for sid, _ in ctx.sections:
            for platform in ("subagent", "cron"):
                self.assertEqual(
                    self._render(ctx, sid, platform=platform, cwd=str(self.git_cwd)),
                    "",
                )

    def test_oversized_file_skipped(self):
        self._write_config(enabled=True, maxBytesPerFile=4)
        _, ctx = self._load_and_register(register_cwd=self.git_cwd)
        for sid, _ in ctx.sections:
            self.assertEqual(
                self._render(ctx, sid, cwd=str(self.git_cwd)),
                "",
            )

    def test_selector_output_of_missing_file_renders_empty(self):
        _, ctx = self._load_and_register(
            register_cwd=self.git_cwd,
            CONTEXT_SELECT_BIN=self._write_fixture(
                "ghost-selector", GHOST_SELECTOR
            ),
        )
        self.assertEqual(
            self._render(ctx, "global-context-99-ghost", cwd=str(self.git_cwd)),
            "",
        )

    # ── fallback（selector 缺失 / 失败 / 无输出）──────────────────────

    def test_fallback_when_selector_missing(self):
        _, ctx = self._load_and_register(
            register_cwd=self.git_cwd,
            CONTEXT_SELECT_BIN=str(self.tmp / "no-such-selector"),
        )
        self.assertEqual(
            [sid for sid, _ in ctx.sections],
            ["global-context-00-core", "global-context-index"],
        )
        self.assertIn(
            "CONTENT-CORE",
            self._render(ctx, "global-context-00-core", cwd=str(self.plain_cwd)),
        )

    def test_fallback_when_selector_fails_without_output(self):
        _, ctx = self._load_and_register(
            register_cwd=self.git_cwd,
            CONTEXT_SELECT_BIN=self._write_fixture(
                "failing-selector", FAILING_SELECTOR
            ),
        )
        self.assertEqual(
            [sid for sid, _ in ctx.sections],
            ["global-context-00-core", "global-context-index"],
        )
        self.assertIn(
            "CONTENT-INDEX",
            self._render(ctx, "global-context-index", cwd=str(self.plain_cwd)),
        )

    def test_fallback_respects_context_dir_override(self):
        empty_ctx = self.tmp / "empty-context"
        empty_ctx.mkdir()
        _, ctx = self._load_and_register(
            register_cwd=self.git_cwd,
            CONTEXT_SELECT_BIN=str(self.tmp / "no-such-selector"),
            CONTEXT_DIR=str(empty_ctx),
        )
        # fallback 恒注入文件在空 context 目录下不存在 → 无节，命令仍注册
        self.assertEqual(ctx.sections, [])
        self.assertEqual(ctx.commands, ["global-context"])

    # ── register 形态与配置 ───────────────────────────────────────────

    def test_register_command_always_registered_when_enabled(self):
        _, ctx = self._load_and_register(register_cwd=self.git_cwd)
        self.assertEqual(ctx.commands, ["global-context"])

    def test_register_skipped_when_disabled(self):
        self._write_config(enabled=False)
        _, ctx = self._load_and_register(register_cwd=self.git_cwd)
        self.assertEqual(ctx.sections, [])
        self.assertEqual(ctx.commands, [])

    def test_defaults_when_no_config_file(self):
        mod = _load_plugin()
        with mock.patch.dict("os.environ", {"HERMES_HOME": str(self.home)}):
            cfg = mod._load_config()
        self.assertTrue(cfg["enabled"])
        self.assertEqual(cfg["maxBytesPerFile"], 65536)
        self.assertNotIn("contextDir", cfg)
        self.assertNotIn("always", cfg)
        self.assertNotIn("gitGated", cfg)

    def test_legacy_config_keys_ignored(self):
        self._write_config(
            enabled=True,
            maxBytesPerFile=1024,
            contextDir="/no/where",
            always=["01-style.md"],
            gitGated=["04-git.md"],
        )
        mod = _load_plugin()
        with mock.patch.dict("os.environ", {"HERMES_HOME": str(self.home)}):
            cfg = mod._load_config()
        self.assertEqual(cfg["maxBytesPerFile"], 1024)
        self.assertNotIn("contextDir", cfg)
        self.assertNotIn("always", cfg)
        self.assertNotIn("gitGated", cfg)

    # ── 辅助 ──────────────────────────────────────────────────────────

    def _write_fixture(self, name: str, body: str) -> str:
        p = self.tmp / name
        p.write_text(body)
        p.chmod(0o755)
        return str(p)


@unittest.skipUnless(_HAS_HERMES_CLI, "hermes_cli 不可用（无 hermes venv）")
class GlobalContextRenderIntegrationTests(unittest.TestCase):
    """真实 PluginManager 渲染链路：空节跳过 + frame 形态。"""

    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.tmp = Path(tmp.name)
        ctx_dir = self.tmp / "context"
        (ctx_dir / "domains").mkdir(parents=True)
        (ctx_dir / "00-core.md").write_text("CONTENT-CORE")
        (ctx_dir / "INDEX.md").write_text("CONTENT-INDEX")
        (ctx_dir / "domains" / "coding.md").write_text("CONTENT-CODING")
        selector = self.tmp / "fixture-context-select"
        selector.write_text(FIXTURE_SELECTOR)
        selector.chmod(0o755)
        self.home = self.tmp / "hermes-home"
        (self.home / "plugins" / "global-context").mkdir(parents=True)
        (self.home / "global-context.json").write_text(
            json.dumps({"enabled": True, "maxBytesPerFile": 65536})
        )
        for f in ("__init__.py", "plugin.yaml"):
            (self.home / "plugins" / "global-context" / f).symlink_to(
                _PLUGIN_DIR / f
            )
        (self.home / "config.yaml").write_text(
            "plugins:\n  enabled:\n    - global-context\n"
        )
        self.env = {
            "HERMES_HOME": str(self.home),
            "CONTEXT_SELECT_BIN": str(selector),
            "CONTEXT_DIR": str(ctx_dir),
        }
        self.git_cwd = self.tmp / "repo"
        (self.git_cwd / ".git").mkdir(parents=True)

    def _render_ids(self, platform="cli", cwd="/tmp"):
        with mock.patch.dict("os.environ", self.env), mock.patch(
            "os.getcwd", return_value=str(self.git_cwd)
        ):
            mgr = _hp.PluginManager()
            mgr.discover_and_load()
            rendered = mgr.render_system_prompt_sections(
                {
                    "session_id": "s",
                    "model": "m",
                    "provider": "p",
                    "platform": platform,
                    "profile_name": "default",
                    "cwd": cwd,
                }
            )
        return [r.id for r in rendered]

    def test_git_repo_renders_all_sections(self):
        # 框架契约：sections 按 id 字典序渲染（非注册顺序）
        self.assertEqual(
            self._render_ids(cwd=str(self.git_cwd)),
            [
                "global-context-00-core",
                "global-context-coding",
                "global-context-index",
            ],
        )

    def test_plain_cwd_skips_git_gated_section(self):
        self.assertEqual(
            self._render_ids(cwd=str(self.tmp)),
            ["global-context-00-core", "global-context-index"],
        )

    def test_subagent_platform_renders_nothing(self):
        self.assertEqual(
            self._render_ids(platform="subagent", cwd=str(self.git_cwd)), []
        )


if __name__ == "__main__":
    unittest.main()
