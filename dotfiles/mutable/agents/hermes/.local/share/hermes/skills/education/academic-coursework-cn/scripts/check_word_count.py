#!/usr/bin/env python3
"""中文课程作业字数核验脚本。

用法：
    python3 scripts/check_word_count.py <file> [start_marker] [end_marker]

示例：
    python3 scripts/check_word_count.py handbook.md "社会实践简介" "附录 A"
    python3 scripts/check_word_count.py handbook.md  # 统计全文
"""

import re
import sys
from pathlib import Path


def count(text: str) -> dict:
    """统计三类字数。"""
    clean = re.sub(r"\s+", "", text)
    return {
        "chars_total": len(clean),
        "chinese_chars": sum(1 for c in clean if "\u4e00" <= c <= "\u9fff"),
        "chinese_with_punct": sum(
            1
            for c in clean
            if "\u4e00" <= c <= "\u9fff" or c in "，。、；：？！""''【】（）《》—…·"
        ),
    }


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 1

    file_path = Path(sys.argv[1])
    if not file_path.exists():
        print(f"文件不存在: {file_path}")
        return 1

    text = file_path.read_text(encoding="utf-8")

    # 区间裁剪
    if len(sys.argv) >= 4:
        start_marker = sys.argv[2]
        end_marker = sys.argv[3]
        i = text.find(start_marker)
        j = text.find(end_marker)
        if i < 0 or j < 0 or j <= i:
            print(f"未找到标记: {start_marker!r} 或 {end_marker!r}")
            return 1
        text = text[i:j]
        print(f"区间: {start_marker!r} ... {end_marker!r}")
        print()

    stats = count(text)
    print(f"字符数（去空白）: {stats['chars_total']}")
    print(f"汉字数（学校通常核这个）: {stats['chinese_chars']}")
    print(f"汉字+中文标点: {stats['chinese_with_punct']}")
    print()

    # 区间定位建议
    cn = stats["chinese_chars"]
    if cn < 800:
        print("⚠  偏短（< 800 汉字），建议扩写")
    elif cn < 1500:
        print("○ 中短篇（800-1500），适合短报告")
    elif cn <= 5000:
        print(f"✓ 中长篇（{cn}），落在常见 1500-5000 字区间内")
    elif cn <= 8000:
        print(f"○ 偏长（{cn}），如方案上限是 5000 字需删减")
    else:
        print(f"⚠  超长（{cn}），强烈建议精简")

    return 0


if __name__ == "__main__":
    sys.exit(main())