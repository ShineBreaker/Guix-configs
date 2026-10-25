#!/usr/bin/env python3
"""digest_render.py 结构化卡片解析的回归断言。

改 parse_digest_md / render_item / 卡片结构后跑一次：
    python3 scripts/test_render_struct.py
通过打印 render struct OK，失败抛 AssertionError。
"""
import sys
from pathlib import Path

RENDER_DIR = Path.home() / ".local/share/hermes/scripts/twitter-digest"
sys.path.insert(0, str(RENDER_DIR))
from digest_render import parse_digest_md, render_item  # noqa: E402

MD = """# 日报 2026-10-20

## 要闻

1. 第一条要闻。
2. 第二条要闻。

## 模型与评测

### DeepSeek 发布 V4.1 Flash 1017
> 开源权重模型第一次进总榜前 11。
Artificial Analysis 测得智能指数 45 分。
OpenCode 已切换到 1017。
来源：https://x.com/deepseek_ai/status/1
![img7]

### Mercury 3 上线 OpenRouter
> 扩散模型，1000+ tok/s。
生成速度是 2.5 的 4 倍。
![img2]
"""


def main() -> int:
    title, groups = parse_digest_md(MD)
    assert title == "日报 2026-10-20", title
    assert [g for g, _ in groups] == ["要闻", "模型与评测"], groups

    headlines = groups[0][1]
    assert headlines == ["第一条要闻。", "第二条要闻。"], headlines

    cards = groups[1][1]
    assert all(isinstance(c, dict) for c in cards), cards
    c1 = cards[0]
    assert c1["title"] == "DeepSeek 发布 V4.1 Flash 1017", c1
    assert c1["lines"][0].startswith(">"), c1
    assert any(l.startswith("来源") for l in c1["lines"]), c1

    html = render_item(c1, Path("."), {})
    assert '<h3 class="ctitle">DeepSeek 发布 V4.1 Flash 1017</h3>' in html, html
    assert 'class="cledeg"' in html, html
    assert html.count('<p class="item">') == 2, html
    assert "来源 · https://x.com/deepseek_ai/status/1" in html, html

    # 要闻组混入 ### 卡片：降级成纯标题，不炸 _inline
    _t, gs = parse_digest_md("# T\n\n## 要闻\n\n1. ok\n\n### 混入卡片\n> x\n正文\n")
    assert gs[0][1][0] == "ok", gs
    assert isinstance(gs[0][1][1], dict), gs
    assert "混入卡片" in render_item(gs[0][1][1], Path("."), {})

    # 老格式：一行一条裸文本仍兼容
    _t2, g2 = parse_digest_md("# 日报\n\n## 模型\n\n一行老格式条目\n")
    assert g2[0][1] == ["一行老格式条目"], g2

    print("render struct OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
