#!/usr/bin/env bash
# symlink-to-file.sh - 递归将符号链接转换为实际文件
# 用法: ./symlink-to-file.sh [目标目录] [--dry-run]

set -euo pipefail

DRY_RUN=false
TARGET_DIR="."

# 解析参数
for arg in "$@"; do
    case "$arg" in
        --dry-run|-n) DRY_RUN=true ;;
        *) TARGET_DIR="$arg" ;;
    esac
done

if [[ ! -d "$TARGET_DIR" ]]; then
    echo "错误: '$TARGET_DIR' 不是有效目录" >&2
    exit 1
fi

echo "扫描目录: $TARGET_DIR"
[[ "$DRY_RUN" == true ]] && echo "** 演习模式 (dry-run)，不会实际修改 **"

# 统计计数器
count=0
failed=0

# 使用 -print0 处理特殊文件名（空格、换行等）
while IFS= read -r -d '' link_path; do
    # 跳过指向目录的链接（只处理文件）
    if [[ -d "$link_path" ]]; then
        echo "跳过目录链接: $link_path"
        continue
    fi

    # 检查链接是否有效
    if [[ ! -e "$link_path" ]]; then
        echo "警告: 跳过损坏的链接: $link_path" >&2
        ((failed++)) || true
        continue
    fi

    # 获取真实文件路径
    real_path=$(readlink -f "$link_path" 2>/dev/null || realpath "$link_path")

    # 获取原文件权限
    perms=$(stat -c %a "$link_path" 2>/dev/null || stat -f %Lp "$link_path")

    echo "处理: $link_path -> $real_path"

    if [[ "$DRY_RUN" == false ]]; then
        # 创建临时文件（同一文件系统，避免跨设备移动）
        tmp_file=$(mktemp "$(dirname "$link_path")/.tmp.XXXXXX")

        # 使用 cat 复制内容（如你所要求）
        if cat "$link_path" > "$tmp_file"; then
            # 删除符号链接
            rm "$link_path"

            # 重命名为原文件名
            mv "$tmp_file" "$link_path"

            # 恢复权限
            chmod "$perms" "$link_path" 2>/dev/null || true

            ((++count))
        else
            echo "错误: 无法读取 $link_path" >&2
            rm -f "$tmp_file"
            ((++failed))
        fi
    else
        ((++count))
    fi

done < <(find "$TARGET_DIR" -type l -print0)

echo ""
echo "完成: 处理了 $count 个符号链接"
if (( failed > 0 )); then
    echo "失败: $failed 个"
fi
