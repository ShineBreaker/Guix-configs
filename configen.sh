#!/usr/bin/env bash
# configen.sh - Guix 配置文件生成器 (Bash版)
# 用法:
# ./configen.sh # 生成所有配置文件
# ./configen.sh init # 只生成安装配置
# ./configen.sh system # 只生成系统配置
# ./configen.sh home # 只生成 home 配置
set -e

# 获取脚本所在目录的绝对路径
SCRIPT_PATH=$(realpath "${BASH_SOURCE[0]}")
REPO_ROOT=$(dirname "$SCRIPT_PATH")
CONFIGS_DIR="$REPO_ROOT/configs"
TMP_DIR="$REPO_ROOT/tmp"

# 确保 tmp 目录存在
mkdir -p "$TMP_DIR"

# 定义关联数组来追踪已加载的文件
declare -A LOADED_FILES

# -----------------------------------------------------------------------------
# 核心处理函数
# -----------------------------------------------------------------------------

# 递归处理文件内容
process_content() {
    local file_path="$1"

    # 获取文件的绝对路径
    local full_path
    full_path=$(realpath "$file_path" 2>/dev/null || echo "")

    # 检查文件是否存在
    if [[ -z "$full_path" || ! -f "$full_path" ]]; then
        echo "; 警告: 文件不存在: $file_path" >&2
        echo "; 警告: 无法加载 $file_path"
        return
    fi

    # 检查是否已加载（去重）
    if [[ -n "${LOADED_FILES[$full_path]}" ]]; then
        return
    fi

    # 标记为已加载
    LOADED_FILES["$full_path"]=1

    # 获取当前文件所在的目录，用于解析相对路径
    local base_dir
    base_dir=$(dirname "$full_path")

    # 逐行读取文件
    while IFS= read -r line || [[ -n "$line" ]]; do
        # 只匹配 (load "./xxx")，忽略 include
        if [[ "$line" =~ ^[[:space:]]*\(load[[:space:]]+\"./([^\"]+)\"[[:space:]]*\)[[:space:]]*$ ]]; then
            local relative_path="${BASH_REMATCH[1]}"
            local target_path="$base_dir/$relative_path"

            # 输出注释分隔符
            echo ""
            echo ";"
            echo "; ====== 来自 $relative_path ======"
            echo ";"

            # 递归调用
            process_content "$target_path"

            echo ""
        else
            # 普通行直接输出（保留 include 行）
            echo "$line"
        fi
    done < "$full_path"
}

# 生成单个配置文件
generate_config() {
    local input_name="$1"
    local output_name="$2"
    local desc="$3"

    local input_path="$CONFIGS_DIR/$input_name"
    local output_path="$TMP_DIR/$output_name"

    echo "正在生成完整配置文件: $output_path ($desc)"

    # 重置已加载文件列表
    LOADED_FILES=()

    # 准备头部信息
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")

    local header=";;; 自动生成的完整配置文件
;;; 原始文件: $input_path
;;; 生成时间: $timestamp
"
    # 生成内容并写入临时文件
    {
        echo -e "$header"
        process_content "$input_path"
    } > "$output_path"

    # 清理遗留的 load 语句 - 更宽松的正则，匹配各种空格情况
    # 删除包含 (load "...") 的行，无论前后有什么
    if [[ "$(uname)" == "Darwin" ]]; then
        sed -i '' -E '/^[[:space:]]*\(load[[:space:]]+".*"\)[[:space:]]*$/d' "$output_path"
    else
        sed -i -E '/^[[:space:]]*\(load[[:space:]]+".*"\)[[:space:]]*$/d' "$output_path"
    fi

    echo "✓ 成功生成: $output_path"
}

# -----------------------------------------------------------------------------
# 主程序逻辑
# -----------------------------------------------------------------------------

main() {
    local target="${1:-all}"
    target=$(echo "$target" | tr '[:upper:]' '[:lower:]')

    echo "========================================"
    echo "          Guix 配置文件生成器"
    echo "========================================"
    echo "配置目录: $CONFIGS_DIR"
    echo "输出目录: $TMP_DIR"
    echo ""

    if [[ "$target" == "init" || "$target" == "all" ]]; then
        generate_config "init-config.scm" "init-config.scm" "安装配置"
    fi

    if [[ "$target" == "system" || "$target" == "all" ]]; then
        [[ "$target" == "all" ]] && echo ""
        generate_config "system-config.scm" "system-config.scm" "系统配置"
    fi

    if [[ "$target" == "home" || "$target" == "all" ]]; then
        [[ "$target" == "all" ]] && echo ""
        generate_config "home-config.scm" "home-config.scm" "Home 配置"
    fi

    echo ""
    echo "========================================"
    echo "         所有配置文件生成完成！"
    echo "========================================"
}

# 执行主函数
main "$@"
