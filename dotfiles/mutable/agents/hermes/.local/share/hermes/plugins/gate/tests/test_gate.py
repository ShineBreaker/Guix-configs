# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT
"""gate 插件测试：fake 核行协议矩阵 + 决策核缺失保底 + 真实核冒烟。

跑法（hermes venv python，零第三方依赖）：
  ~/.local/share/hermes/hermes-agent/venv/bin/python -m unittest \
      discover -s <本目录> -t <本目录>
"""

import importlib.util
import tempfile
import unittest
from pathlib import Path
from unittest import mock

_PLUGIN_DIR = Path(__file__).resolve().parents[1]
# 真实部署位决策核（集成冒烟用；由 immutable agents 包部署）
_REAL_CORE = Path.home() / ".config" / "agents" / "gate-core.sh"

# fake 核：记录 mode/arg/GATE_CWD/stdin 到 $FAKE_LOG，原样输出 $FAKE_OUT
_FAKE_CORE = """#!/usr/bin/env bash
printf '%s\\n' "$1" "$2" "$GATE_CWD" > "$FAKE_LOG"
cat >> "$FAKE_LOG"
printf '%s' "$FAKE_OUT"
"""


def _load_plugin():
    spec = importlib.util.spec_from_file_location(
        "gate_under_test", _PLUGIN_DIR / "__init__.py"
    )
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class GateUnitTests(unittest.TestCase):
    """fake 核驱动：行协议 → hermes 指令的转换矩阵。"""

    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.tmp = Path(tmp.name)
        self.gate = _load_plugin()  # 每用例独立模块实例，隔离 _PENDING_HINTS
        core = self.tmp / "fake-core.sh"
        core.write_text(_FAKE_CORE)
        core.chmod(0o755)
        self.gate.GATE_CORE = core
        self.log = self.tmp / "core.log"
        self.env = {"FAKE_LOG": str(self.log), "FAKE_OUT": ""}

    def _pre(self, tool, args, tid="t1"):
        with mock.patch.dict("os.environ", self.env):
            return self.gate._pre_tool_call(tool_name=tool, args=args, tool_call_id=tid)

    def _transform(self, result, tid="t1"):
        with mock.patch.dict("os.environ", self.env):
            return self.gate._transform_tool_result(
                tool_name="terminal", tool_call_id=tid, result=result
            )

    def _log_lines(self):
        return self.log.read_text().splitlines()

    # ── 行协议矩阵 ──────────────────────────────────────────────────────

    def test_block(self):
        self.env["FAKE_OUT"] = "BLOCK\t冻结命令禁止执行"
        verdict = self._pre("terminal", {"command": "some-cmd"})
        self.assertEqual(verdict, {"action": "block", "message": "冻结命令禁止执行"})

    def test_sensitive_blocks(self):
        self.env["FAKE_OUT"] = "SENSITIVE\t检测到 API key"
        verdict = self._pre("terminal", {"command": "curl x"})
        self.assertEqual(verdict["action"], "block")
        self.assertEqual(verdict["message"], "检测到 API key")

    def test_rewritten_modifies_command(self):
        self.env["FAKE_OUT"] = "AUTO_ALLOW\nREWRITTEN\trewritten-cmd"
        verdict = self._pre("terminal", {"command": "orig-cmd"})
        self.assertEqual(
            verdict, {"action": "modify", "args": {"command": "rewritten-cmd"}}
        )

    def test_rewritten_with_notes(self):
        self.env["FAKE_OUT"] = "REWRITTEN\trewritten-cmd\nNOTES\t改写说明"
        verdict = self._pre("terminal", {"command": "orig-cmd"}, tid="t9")
        self.assertEqual(verdict["action"], "modify")
        # modify 与 hints 并存：hints 等 transform 消费
        out = self._transform('{"output": "ok"}', tid="t9")
        self.assertIn("gate_hint", out)
        self.assertIn("改写说明", out)

    def test_hints_appended_to_json_result(self):
        self.env["FAKE_OUT"] = "RM_HINT\trm 提示\nNOTES\t备注说明"
        self.assertIsNone(self._pre("terminal", {"command": "ls"}, tid="t2"))
        out = self._transform('{"output": "done"}', tid="t2")
        parsed = __import__("json").loads(out)
        self.assertEqual(parsed["gate_hint"], "rm 提示; 备注说明")
        self.assertEqual(parsed["output"], "done")

    def test_hints_appended_to_plain_text_result(self):
        self.env["FAKE_OUT"] = "HINT\t提示内容"
        self._pre("terminal", {"command": "ls"}, tid="t3")
        out = self._transform("plain result", tid="t3")
        self.assertTrue(out.startswith("plain result"))
        self.assertIn("[gate] 提示内容", out)

    def test_transform_without_pending_returns_none(self):
        self.assertIsNone(self._transform('{"output": "ok"}', tid="never"))

    def test_allows_pass_through(self):
        self.env["FAKE_OUT"] = "AUTO_ALLOW"
        self.assertIsNone(self._pre("terminal", {"command": "echo hi"}))

    # ── 决策核缺失 / 异常：sudo 保底，其余放行 ─────────────────────────

    def test_missing_core_sudo_fallback(self):
        self.gate.GATE_CORE = self.tmp / "nonexistent.sh"
        verdict = self._pre("terminal", {"command": "sudo ls"})
        self.assertEqual(verdict["action"], "block")
        self.assertIn("sudo", verdict["message"])

    def test_missing_core_normal_passes(self):
        self.gate.GATE_CORE = self.tmp / "nonexistent.sh"
        self.assertIsNone(self._pre("terminal", {"command": "echo hi"}))
        self.assertIsNone(self._pre("write_file", {"path": "/tmp/x", "content": "y"}))

    # ── 工具路由与参数提取 ──────────────────────────────────────────────

    def test_unrelated_tool_skips_core(self):
        self.env["FAKE_OUT"] = "BLOCK\t不应到达"
        self.assertIsNone(self._pre("read_file", {"path": "/tmp/x"}))
        self.assertFalse(self.log.exists())

    def test_empty_command_skips_core(self):
        self.assertIsNone(self._pre("terminal", {"command": ""}))
        self.assertFalse(self.log.exists())

    def test_cwd_prefers_workdir(self):
        self.env["FAKE_OUT"] = "AUTO_ALLOW"
        self._pre("terminal", {"command": "ls", "workdir": "/tmp/wd"})
        self.assertEqual(self._log_lines()[2], "/tmp/wd")

    def test_cwd_falls_back_to_terminal_cwd_env(self):
        self.env["FAKE_OUT"] = "AUTO_ALLOW"
        self.env["TERMINAL_CWD"] = "/tmp/from-env"
        self._pre("terminal", {"command": "ls"})
        self.assertEqual(self._log_lines()[2], "/tmp/from-env")

    def test_bash_mode_invocation(self):
        self.env["FAKE_OUT"] = "AUTO_ALLOW"
        self._pre("terminal", {"command": "the-cmd"})
        lines = self._log_lines()
        self.assertEqual(lines[0], "bash")
        self.assertEqual(lines[1], "the-cmd")

    def test_write_file_edit_mode(self):
        self.env["FAKE_OUT"] = "AUTO_ALLOW"
        self._pre("write_file", {"path": "/tmp/f.txt", "content": "body"})
        lines = self._log_lines()
        self.assertEqual(lines[0], "edit")
        self.assertEqual(lines[1], "/tmp/f.txt")
        self.assertEqual(lines[3], "body")

    def test_patch_content_concatenates_old_new(self):
        self.env["FAKE_OUT"] = "AUTO_ALLOW"
        self._pre(
            "patch",
            {"path": "/tmp/f.txt", "old_string": "old", "new_string": "new"},
        )
        stdin_part = self._log_lines()[3:]
        self.assertEqual(stdin_part, ["old", "new"])

    def test_patch_v4a_serialized(self):
        self.env["FAKE_OUT"] = "AUTO_ALLOW"
        self._pre("patch", {"path": "/tmp/f.txt", "patch": {"diffs": 1}})
        self.assertIn("diffs", "\n".join(self._log_lines()[3:]))


class GatePauseTests(unittest.TestCase):
    """人工总开关：存在即放行并附提示，且不调决策核。"""

    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.tmp = Path(tmp.name)
        self.gate = _load_plugin()
        core = self.tmp / "fake-core.sh"
        core.write_text(_FAKE_CORE)
        core.chmod(0o755)
        self.gate.GATE_CORE = core
        self.log = self.tmp / "core.log"
        # 假核恒回 BLOCK：若暂停态仍调核，用例必然失败
        self.env = {"FAKE_LOG": str(self.log), "FAKE_OUT": "BLOCK\t不应到达"}
        self.pause = self.tmp / "gate.off"

    def _pre(self, tool, args, tid):
        with mock.patch.dict("os.environ", self.env):
            return self.gate._pre_tool_call(tool_name=tool, args=args, tool_call_id=tid)

    def test_paused_bash_skips_core_and_emits_hint(self):
        self.pause.touch()
        self.gate.GATE_PAUSE_FILE = self.pause
        self.assertIsNone(self._pre("terminal", {"command": "su" "do -i"}, "p1"))
        self.assertFalse(self.log.exists(), "暂停态不应调用决策核")
        with mock.patch.dict("os.environ", self.env):
            out = self.gate._transform_tool_result(
                tool_name="terminal", tool_call_id="p1", result='{"output": "ok"}'
            )
        self.assertIn("暂停", out)
        self.assertIn("ok", out)

    def test_paused_edit_skips_core(self):
        self.pause.touch()
        self.gate.GATE_PAUSE_FILE = self.pause
        self.assertIsNone(
            self._pre("write_file", {"path": "/tmp/x", "content": "y"}, "p2")
        )
        self.assertFalse(self.log.exists(), "暂停态不应调用决策核")

    def test_pause_absent_blocks_normally(self):
        self.gate.GATE_PAUSE_FILE = self.tmp / "absent.off"
        verdict = self._pre("terminal", {"command": "su" "do -i"}, "p3")
        self.assertEqual(verdict["action"], "block")

    def test_pause_file_is_a_directory_not_pause(self):
        # is_file() 语义：同名目录不算暂停
        d = self.tmp / "dir.off"
        d.mkdir()
        self.gate.GATE_PAUSE_FILE = d
        verdict = self._pre("terminal", {"command": "su" "do -i"}, "p4")
        self.assertEqual(verdict["action"], "block")


class GateIntegrationTests(unittest.TestCase):
    """真实 PluginManager + 真实 gate-core.sh 冒烟（部署形态复验）。"""

    def _load_with_manager(self):
        import hermes_cli.plugins as hp

        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        home = Path(tmp.name)
        plugins_dir = home / "plugins" / "gate"
        plugins_dir.parent.mkdir()
        plugins_dir.symlink_to(_PLUGIN_DIR, target_is_directory=True)
        (home / "config.yaml").write_text("plugins:\n  enabled:\n    - gate\n")
        with mock.patch.dict("os.environ", {"HERMES_HOME": str(home)}):
            mgr = hp.PluginManager()
            mgr.discover_and_load()
        loaded = [p for p in mgr._plugins.values() if p.manifest.name == "gate"]
        self.assertTrue(loaded, "gate 插件未被加载（检查 config.yaml enabled）")
        return mgr

    def test_real_core_blocks_frozen_sudo(self):
        if not _REAL_CORE.exists():
            self.skipTest("真实 gate-core.sh 未部署")
        mgr = self._load_with_manager()
        results = mgr.invoke_hook(
            "pre_tool_call",
            tool_name="terminal",
            args={"command": "sudo -i"},
            tool_call_id="t",
        )
        self.assertTrue(
            any(r and r.get("action") == "block" for r in results),
            f"真实核未拦截 sudo: {results}",
        )

    def test_real_core_allows_normal_command(self):
        if not _REAL_CORE.exists():
            self.skipTest("真实 gate-core.sh 未部署")
        mgr = self._load_with_manager()
        results = mgr.invoke_hook(
            "pre_tool_call",
            tool_name="terminal",
            args={"command": "printf hello"},
            tool_call_id="t",
        )
        self.assertFalse(
            any(r and r.get("action") == "block" for r in results),
            f"普通命令被误拦: {results}",
        )


if __name__ == "__main__":
    unittest.main()
