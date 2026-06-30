# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT
"""HTML 模板 — 从 skeleton.html 加载 + string.Template 占位替换。

骨架源文件是 `skeleton.html`（与本文件同目录），包含 ${css} / ${js_core} 等
命名占位符，由调用方通过 Template.substitute 注入实际内容。

不持有任何 HTML 字符串 —— 所有骨架文本在 .html 文件中。
"""

from pathlib import Path
from string import Template

_SKELETON = (Path(__file__).parent / "skeleton.html").read_text(encoding="utf-8")
TEMPLATE = Template(_SKELETON)
