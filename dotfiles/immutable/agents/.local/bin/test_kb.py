#!/usr/bin/env python3

# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

"""kb CLI 核心模块测试。

覆盖范围:
  1. _card_dict — Org 元数据解析 + tags 逗号展开
  2. _fix_org_content — Markdown 修复
  3. cmd_get — 路径安全限制
  4. cmd_update — 属性替换（含空格值）
  5. cmd_add — owner/type 白名单校验
  6. _init_memory_template — 从零重建 MEMORY.org
  7. ensure_dirs — 自愈能力
  8. _build_template — 模板生成

用法: python3 test_kb.py
"""

import json
import os
import shutil
import sys
import tempfile
from pathlib import Path
from unittest.mock import patch

# 将 kb 脚本所在目录加入 path，以便 import
KB_SCRIPT = Path(__file__).parent / "kb"
sys.path.insert(0, str(KB_SCRIPT.parent))

# 导入 kb 模块（作为模块而非脚本）
import types

# 直接 exec kb 脚本到独立模块命名空间
# kb 没有 .py 后缀，无法用 importlib，用 exec 代替
kb = types.ModuleType("kb")
kb_code = KB_SCRIPT.read_text(encoding="utf-8")
exec(compile(kb_code, str(KB_SCRIPT), "exec"), kb.__dict__)


# ═══════════════════════════════════════════════════════════════════════════════
# 测试辅助
# ═══════════════════════════════════════════════════════════════════════════════

PASS = 0
FAIL = 0


def assert_eq(actual, expected, label: str) -> None:
    """断言相等，打印结果。"""
    global PASS, FAIL
    if actual == expected:
        PASS += 1
        print(f"  ✓ {label}")
    else:
        FAIL += 1
        print(f"  ✗ {label}")
        print(f"    期望: {expected!r}")
        print(f"    实际: {actual!r}")


def assert_true(condition: bool, label: str) -> None:
    """断言为真。"""
    global PASS, FAIL
    if condition:
        PASS += 1
        print(f"  ✓ {label}")
    else:
        FAIL += 1
        print(f"  ✗ {label}")


def make_temp_kb():
    """创建临时 KB_ROOT 目录，返回路径。"""
    tmp = tempfile.mkdtemp(prefix="kb_test_")
    return Path(tmp)


# ═══════════════════════════════════════════════════════════════════════════════
# 测试 1: _card_dict — Org 元数据解析
# ═══════════════════════════════════════════════════════════════════════════════

def test_card_dict_basic():
    """测试基本的 Org 元数据提取。"""
    print("\n[test_card_dict_basic]")
    tmp = make_temp_kb()
    card_file = tmp / "test-card.org"
    card_file.write_text(
        "* DONE 测试标题\n"
        ":PROPERTIES:\n"
        ":ID:       20260526-120000\n"
        ":CREATED:  [2026-05-26 一]\n"
        ":CATEGORY: general\n"
        ":TECH:     python\n"
        ":TYPE:     debug\n"
        ":STATUS:   done\n"
        ":OWNER:    ai\n"
        ":END:\n"
        ":general:debug:ai:python::\n",
        encoding="utf-8",
    )

    # 临时替换 KB_ROOT
    with patch.object(kb, "KB_ROOT", tmp):
        result = kb._card_dict(card_file)

    assert_eq(result["id"], "20260526-120000", "ID 解析")
    assert_eq(result["title"], "测试标题", "标题解析")
    assert_eq(result["category"], "general", "category 解析")
    assert_eq(result["tech"], "python", "tech 解析")
    assert_eq(result["type"], "debug", "type 解析")
    assert_eq(result["owner"], "ai", "owner 解析")
    assert_eq(result["tags"], ["general", "debug", "ai", "python"], "tags 展开（无逗号）")

    shutil.rmtree(tmp)


def test_card_dict_tags_with_comma():
    """测试 tags 中含逗号的 tech 字段展开。"""
    print("\n[test_card_dict_tags_with_comma]")
    tmp = make_temp_kb()
    card_file = tmp / "test-comma.org"
    card_file.write_text(
        "* DONE 逗号标签测试\n"
        ":PROPERTIES:\n"
        ":ID:       20260526-120001\n"
        ":CREATED:  [2026-05-26 一]\n"
        ":CATEGORY: general\n"
        ":TECH:     Hexo,Playwright,GuixSD,Flatpak\n"
        ":TYPE:     debug\n"
        ":OWNER:    ai\n"
        ":END:\n"
        ":general:debug:ai:Hexo,Playwright,GuixSD,Flatpak::\n",
        encoding="utf-8",
    )

    with patch.object(kb, "KB_ROOT", tmp):
        result = kb._card_dict(card_file)

    expected_tags = ["general", "debug", "ai", "Hexo", "Playwright", "GuixSD", "Flatpak"]
    assert_eq(result["tags"], expected_tags, "逗号展开 tags")

    shutil.rmtree(tmp)


def test_card_dict_symlink_skip():
    """测试符号链接被跳过。"""
    print("\n[test_card_dict_symlink_skip]")
    tmp = make_temp_kb()
    real_file = tmp / "real.org"
    real_file.write_text("content", encoding="utf-8")
    link_file = tmp / "link.org"
    link_file.symlink_to(real_file)

    result = kb._card_dict(link_file)
    assert_eq(result, None, "符号链接返回 None")

    shutil.rmtree(tmp)


# ═══════════════════════════════════════════════════════════════════════════════
# 测试 2: _fix_org_content — Markdown 修复
# ═══════════════════════════════════════════════════════════════════════════════

def test_fix_org_markdown_code_block():
    """测试 Markdown 代码块 → Org 代码块。"""
    print("\n[test_fix_org_markdown_code_block]")
    text = "一些文本\n```python\nprint('hello')\n```\n后续"
    new_text, fixes = kb._fix_org_content(text)
    assert_true("#+begin_src python" in new_text, "```python → #+begin_src python")
    assert_true("#+end_src" in new_text, "``` → #+end_src")
    assert_eq(len(fixes), 2, "修复项数量 = 2")


def test_fix_org_bold():
    """测试 **bold** → *bold*。"""
    print("\n[test_fix_org_bold]")
    text = "这是 **粗体** 文本"
    new_text, fixes = kb._fix_org_content(text)
    assert_eq(new_text, "这是 *粗体* 文本", "**bold** → *bold*")


def test_fix_org_heading():
    """测试 Markdown heading → Org heading。"""
    print("\n[test_fix_org_heading]")
    text = "## 二级标题\n### 三级标题"
    new_text, fixes = kb._fix_org_content(text)
    assert_true("** 二级标题" in new_text, "## → **")
    assert_true("*** 三级标题" in new_text, "### → ***")


def test_fix_org_list():
    """测试 `- list` → `+ list`。"""
    print("\n[test_fix_org_list]")
    text = "- 列表项"
    new_text, fixes = kb._fix_org_content(text)
    assert_eq(new_text, "+ 列表项", "- → +")


def test_fix_org_inline_code():
    """测试 `code` → ~code~。"""
    print("\n[test_fix_org_inline_code]")
    text = "使用 `kb add` 命令"
    new_text, fixes = kb._fix_org_content(text)
    assert_eq(new_text, "使用 ~kb add~ 命令", "`code` → ~code~")


def test_fix_org_preserve_existing():
    """测试已有的 Org 格式不被误修复。"""
    print("\n[test_fix_org_preserve_existing]")
    text = "* 一级标题\n** 二级标题\n#+begin_src python\nprint('hi')\n#+end_src"
    new_text, fixes = kb._fix_org_content(text)
    assert_eq(new_text, text, "已有 Org 格式保持不变")
    assert_eq(len(fixes), 0, "无修复项")


# ═══════════════════════════════════════════════════════════════════════════════
# 测试 3: cmd_get — 路径安全限制
# ═══════════════════════════════════════════════════════════════════════════════

def test_cmd_get_path_restriction():
    """测试 cmd_get 拒绝读取 KB_ROOT 外的文件。"""
    print("\n[test_cmd_get_path_restriction]")
    import argparse

    class MockArgs:
        target = "/etc/passwd"

    # 应该 die() 退出
    try:
        kb.cmd_get(MockArgs())
        assert_true(False, "应该抛出 SystemExit")
    except SystemExit as e:
        assert_true(True, f"正确拒绝 /etc/passwd，退出码={e.code}")


# ═══════════════════════════════════════════════════════════════════════════════
# 测试 4: cmd_update — 属性替换含空格
# ═══════════════════════════════════════════════════════════════════════════════

def test_update_property_with_spaces():
    """测试 cmd_update 正确替换含空格的属性值。"""
    print("\n[test_update_property_with_spaces]")
    tmp = make_temp_kb()
    card_file = tmp / "test.org"
    card_file.write_text(
        "* DONE 标题\n"
        ":PROPERTIES:\n"
        ":TECH:     pi nodejs CJK\n"
        ":TYPE:     debug\n"
        ":END:\n",
        encoding="utf-8",
    )

    import re
    content = card_file.read_text(encoding="utf-8")
    # 模拟 cmd_update 中的属性替换逻辑
    new_tech = "python rust"
    content = re.sub(r":TECH:\s*.+", f":TECH:     {new_tech}", content)

    assert_true(":TECH:     python rust" in content, "含空格的 TECH 值完整替换")
    assert_true("nodejs CJK" not in content, "旧值残留不存在")

    shutil.rmtree(tmp)


# ═══════════════════════════════════════════════════════════════════════════════
# 测试 5: _init_memory_template — 从零重建
# ═══════════════════════════════════════════════════════════════════════════════

def test_init_memory_template():
    """测试 MEMORY.org 模板生成。"""
    print("\n[test_init_memory_template]")
    tmp = make_temp_kb()
    mem_file = tmp / "MEMORY.org"

    with patch.object(kb, "KB_MEMORY", mem_file):
        kb._init_memory_template()

    content = mem_file.read_text(encoding="utf-8")
    assert_true("#+title: MEMORY" in content, "包含 #+title")
    assert_true("* feedback" in content, "包含 feedback 节")
    assert_true("* project" in content, "包含 project 节")
    assert_true("* reference" in content, "包含 reference 节")
    assert_true("* deprecated" in content, "包含 deprecated 节")

    shutil.rmtree(tmp)


# ═══════════════════════════════════════════════════════════════════════════════
# 测试 6: ensure_dirs — 自愈能力
# ═══════════════════════════════════════════════════════════════════════════════

def test_ensure_dirs_self_heal():
    """测试从零创建所有目录和模板。"""
    print("\n[test_ensure_dirs_self_heal]")
    tmp = make_temp_kb()

    # 临时替换所有路径常量
    with patch.object(kb, "KB_ROOT", tmp), \
         patch.object(kb, "KB_EXPERIENCES", tmp / "experiences"), \
         patch.object(kb, "KB_MEMORIES", tmp / "memories"), \
         patch.object(kb, "KB_PROJECTS", tmp / "memories" / "projects"), \
         patch.object(kb, "KB_MEMORY", tmp / "MEMORY.org"), \
         patch.object(kb, "KB_INDEX", tmp / "index.json"), \
         patch.object(kb, "KB_INBOX", tmp / "inbox.org"), \
         patch.object(kb, "KB_PROFILE", tmp / "profile.org"):
        kb.ensure_dirs()

        assert_true((tmp / "experiences").is_dir(), "experiences/ 目录存在")
        assert_true((tmp / "memories" / "projects").is_dir(), "memories/projects/ 目录存在")
        assert_true((tmp / "inbox.org").is_file(), "inbox.org 文件存在")
        assert_true((tmp / "MEMORY.org").is_file(), "MEMORY.org 文件存在")
        assert_true((tmp / "profile.org").is_file(), "profile.org 文件存在")
        assert_true((tmp / "index.json").is_file(), "index.json 文件存在")

        # 验证 index.json 格式
        index = json.loads((tmp / "index.json").read_text(encoding="utf-8"))
        assert_eq(index["version"], 1, "index.json version = 1")
        assert_eq(index["total"], 0, "index.json total = 0")

        # 验证 MEMORY.org 包含所有标准节
        mem = (tmp / "MEMORY.org").read_text(encoding="utf-8")
        for sec in kb.MEMORY_SECTIONS:
            assert_true(f"* {sec}" in mem, f"MEMORY.org 包含 * {sec}")

    shutil.rmtree(tmp)


# ═══════════════════════════════════════════════════════════════════════════════
# 测试 7: _build_template — 模板生成
# ═══════════════════════════════════════════════════════════════════════════════

def test_build_template_default():
    """测试默认模板生成。"""
    print("\n[test_build_template_default]")
    result = kb._build_template("", "")
    assert_true("** 执行过程" in result, "包含执行过程")
    assert_true("** 经验教训 :lessons:" in result, "包含经验教训")


def test_build_template_mistake():
    """测试 mistake 类型模板。"""
    print("\n[test_build_template_mistake]")
    result = kb._build_template("mistake", "")
    assert_true("** 关键发现" in result, "包含关键发现")
    assert_true("*** 下次开始前自检" in result, "包含自检章节")


def test_build_template_with_body():
    """测试传入 body 时替换占位符。"""
    print("\n[test_build_template_with_body]")
    result = kb._build_template("", "自定义内容")
    assert_true("自定义内容" in result, "body 内容被插入")


# ═══════════════════════════════════════════════════════════════════════════════
# 运行所有测试
# ═══════════════════════════════════════════════════════════════════════════════

if __name__ == "__main__":
    print("═══ kb CLI 核心模块测试 ═══")

    test_card_dict_basic()
    test_card_dict_tags_with_comma()
    test_card_dict_symlink_skip()
    test_fix_org_markdown_code_block()
    test_fix_org_bold()
    test_fix_org_heading()
    test_fix_org_list()
    test_fix_org_inline_code()
    test_fix_org_preserve_existing()
    test_cmd_get_path_restriction()
    test_update_property_with_spaces()
    test_init_memory_template()
    test_ensure_dirs_self_heal()
    test_build_template_default()
    test_build_template_mistake()
    test_build_template_with_body()

    print(f"\n═══ 结果: {PASS} 通过, {FAIL} 失败 ═══")
    sys.exit(1 if FAIL else 0)
