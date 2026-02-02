#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Guix 配置文件生成器
将使用 load 和 include 的配置文件内联展开为完整的配置文件
输出到 ./tmp 目录供 Guix 使用

用法:
    python3 configen.py          # 生成所有配置文件
    python3 configen.py init      # 只生成安装配置
    python3 configen.py system   # 只生成系统配置
    python3 configen.py home     # 只生成 home 配置
"""

import os
import re
import sys
from pathlib import Path
from datetime import datetime

# 追踪已加载的文件，避免重复加载
loaded_files = set()

def load_file_content(file_path):
    """加载文件内容"""
    full_path = os.path.abspath(file_path)

    if full_path in loaded_files:
        return ""

    if not os.path.exists(full_path):
        print(f"警告: 文件不存在: {full_path}", file=sys.stderr)
        return ""

    loaded_files.add(full_path)

    with open(full_path, 'r', encoding='utf-8') as f:
        return f.read()

def process_content(content, base_dir):
    """处理文件内容，展开 load 和 include 语句"""
    result = content
    pos = 0

    # 先处理 load 语句
    while True:
        # 查找 (load "./path/file")
        load_match = re.search(r'\(load\s+"\.\/([^"]+)"\)', result[pos:])
        if not load_match:
            break

        relative_path = load_match.group(1)
        full_path = os.path.join(base_dir, relative_path)
        file_content = load_file_content(full_path)

        # 计算匹配位置
        match_start = pos + load_match.start()
        match_end = pos + load_match.end()

        # 检查这一行是否只有这个语句
        line_start = result.rfind('\n', 0, match_start) + 1
        line_end = result.find('\n', match_end)
        if line_end == -1:
            line_end = len(result)

        line_before = result[line_start:match_start].strip()
        line_after = result[match_end:line_end].strip()

        # 如果是独立语句，替换为文件内容；否则跳过（保持原样）
        if not line_before and not line_after:
            if file_content:
                replacement = f"""\n\n;\n; ====== 来自 {relative_path} ======\n;\n\n{process_content(file_content, os.path.dirname(full_path))}\n\n"""
                result = result[:line_start] + replacement + result[line_end:]
                pos = line_start + len(replacement)
            else:
                result = result[:line_start] + f";\n; 警告: 无法加载 {relative_path}\n;\n\n" + result[line_end:]
                pos = line_start
        else:
            pos = match_end

    # 重置位置，处理 include 语句
    pos = 0
    while True:
        # 查找 (include "./path/file")
        include_match = re.search(r'\(include\s+"\.\/([^"]+)"\)', result[pos:])
        if not include_match:
            break

        relative_path = include_match.group(1)
        full_path = os.path.join(base_dir, relative_path)
        file_content = load_file_content(full_path)

        # 计算匹配位置
        match_start = pos + include_match.start()
        match_end = pos + include_match.end()

        # 替换 include 语句为文件内容
        if file_content:
            replacement = f"""\n;\n; ====== 来自 {relative_path} ======\n;\n{process_content(file_content, os.path.dirname(full_path))}\n"""
            result = result[:match_start] + replacement + result[match_end:]
            pos = match_start + len(replacement)
        else:
            result = result[:match_start] + f"; 警告: 无法加载 {relative_path}" + result[match_end:]
            pos = match_start

    return result

def remove_remaining_loads(content):
    """删除所有剩余的 load 语句"""
    # 删除所有 (load "xxx") 语句
    result = re.sub(r'^\s*\(load\s+"[^"]+"\)\s*$', '', content, flags=re.MULTILINE)
    return result

def generate_complete_config(input_path, output_path):
    """生成完整配置文件"""
    print(f"正在生成完整配置文件: {output_path}")

    # 重置已加载文件列表
    loaded_files.clear()

    # 读取输入文件
    content = load_file_content(input_path)
    base_dir = os.path.dirname(os.path.abspath(input_path))

    # 处理内容
    processed_content = process_content(content, base_dir)

    # 删除所有剩余的 load 语句
    processed_content = remove_remaining_loads(processed_content)

    # 添加头部注释
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    header = ";;; 自动生成的完整配置文件\n"
    header += f";;; 原始文件: {input_path}\n"
    header += f";;; 生成时间: {timestamp}\n"
    header += "\n"

    # 写入输出文件
    with open(output_path, 'w', encoding='utf-8') as f:
        f.write(header)
        f.write(processed_content)
        f.write('\n')

    print(f"✓ 成功生成: {output_path}")

def main():
    """主函数"""
    # 获取脚本所在目录（现在脚本在根目录）
    script_path = os.path.abspath(__file__)
    repo_root = os.path.dirname(script_path)
    configs_dir = os.path.join(repo_root, "configs")

    # 创建 tmp 目录
    tmp_dir = os.path.join(repo_root, "tmp")
    os.makedirs(tmp_dir, exist_ok=True)

    # 定义输入和输出文件
    files = {
        'init': {
            'input': os.path.join(configs_dir, "init-config.scm"),
            'output': os.path.join(tmp_dir, "init-config.scm"),
            'desc': '安装配置'
        },
        'system': {
            'input': os.path.join(configs_dir, "system-config.scm"),
            'output': os.path.join(tmp_dir, "system-config.scm"),
            'desc': '系统配置'
        },
        'home': {
            'input': os.path.join(configs_dir, "home-config.scm"),
            'output': os.path.join(tmp_dir, "home-config.scm"),
            'desc': 'Home 配置'
        }
    }

    # 解析命令行参数
    target = "all" if len(sys.argv) < 2 else sys.argv[1].lower()

    print("=" * 40)
    print("Guix 配置文件生成器")
    print("=" * 40)
    print(f"配置目录: {configs_dir}")
    print(f"输出目录: {tmp_dir}\n")

    # 根据目标生成配置文件
    if target in files:
        generate_complete_config(files[target]['input'], files[target]['output'])
    else:
        # 生成所有配置文件
        for name, file_info in files.items():
            generate_complete_config(file_info['input'], file_info['output'])
            if name != 'home':  # 不是最后一个，添加空行
                print()
            loaded_files.clear()  # 重置已加载文件列表

    print()
    print("=" * 40)
    print("所有配置文件生成完成！")
    print("=" * 40)

if __name__ == "__main__":
    main()
