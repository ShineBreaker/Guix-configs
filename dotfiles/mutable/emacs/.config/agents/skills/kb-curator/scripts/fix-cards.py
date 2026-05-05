#!/usr/bin/env python3
"""修复经验卡片格式问题"""

import re
import sys
from pathlib import Path

def fix_card(filepath):
    """修复单个卡片"""
    content = filepath.read_text()
    original = content
    
    # 1. 删除空的章节 (难点与坑点、经验教训、相关链接、AI 建议)
    empty_sections = [
        r'\*\* 难点与坑点 :difficulties:\s*\n',
        r'\*\* 经验教训 :lessons:\s*\n',
        r'\*\* 相关链接\s*\n\s*\n',
        r'\*\* AI 建议 :ai_notes:\s*\n\s*\n',
    ]
    for pattern in empty_sections:
        content = re.sub(pattern, '', content)
    
    # 2. 删除执行过程中重复的"任务描述"
    # 如果在 "** 执行过程" 后面紧跟着 "** 任务描述"，删除它
    content = re.sub(
        r'(\*\* 执行过程\s*\n)\s*\*\* 任务描述\s*\n',
        r'\1',
        content
    )
    
    # 3. 将 *** 三级标题改为列表
    # *** 问题 -> - 问题：
    # *** 根因 -> - 根因：
    # 等等
    triple_star_patterns = [
        (r'\*\*\* 问题\s*\n', '- 问题：'),
        (r'\*\*\* 根因\s*\n', '- 根因：'),
        (r'\*\*\* 诊断方法\s*\n', '- 诊断方法：'),
        (r'\*\*\* 修复\s*\n', '- 修复：'),
        (r'\*\*\* 关键教训\s*\n', '- 关键教训：'),
        (r'\*\*\* 根因链\s*\n', '- 根因链：'),
        (r'\*\*\* 修复方案\s*\n', '- 修复方案：'),
        (r'\*\*\* 文件位置\s*\n', '- 文件位置：'),
        (r'\*\*\* 预编译二进制列表\s*\n', '- 预编译二进制列表：'),
        (r'\*\*\* FHS 依赖的具体表现\s*\n', '- FHS 依赖的具体表现：'),
        (r'\*\*\* 典型报错\s*\n', '- 典型报错：'),
    ]
    for pattern, replacement in triple_star_patterns:
        content = re.sub(pattern, replacement, content)
    
    # 4. 删除多余的空行（超过2个连续空行）
    content = re.sub(r'\n{3,}', '\n\n', content)
    
    if content != original:
        filepath.write_text(content)
        return True
    return False

def main():
    experiences_dir = Path.home() / 'Documents' / 'Org' / 'experiences'
    fixed = []
    
    for org_file in experiences_dir.glob('*.org'):
        if fix_card(org_file):
            fixed.append(org_file.name)
    
    print(f"修复了 {len(fixed)} 个文件：")
    for name in fixed:
        print(f"  - {name}")
    
    if not fixed:
        print("没有需要修复的文件")
    
    return 0

if __name__ == '__main__':
    sys.exit(main())
