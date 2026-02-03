#!/usr/bin/env bash
# configen.sh - Guix 配置文件生成器 (Bash版)

set -e

SCRIPT_PATH=$(realpath "${BASH_SOURCE[0]}")
REPO_ROOT=$(dirname "$SCRIPT_PATH")
CONFIGS_DIR="$REPO_ROOT/configs"
CONFIGEN_DIR="$CONFIGS_DIR/main"
TMP_DIR="$REPO_ROOT/tmp"

mkdir -p "$TMP_DIR"

declare -A LOADED_FILES

# -----------------------------------------------------------------------------
# 核心处理函数
# -----------------------------------------------------------------------------

process_content() {
    local file_path="$1"
    local load_root="${2:-}"

    local full_path
    full_path=$(realpath "$file_path" 2>/dev/null || echo "")

    if [[ -z "$full_path" || ! -f "$full_path" ]]; then
        echo "; 警告: 文件不存在: $file_path" >&2
        echo "; 警告: 无法加载 $file_path"
        return
    fi

    if [[ -n "${LOADED_FILES[$full_path]}" ]]; then
        return
    fi

    LOADED_FILES["$full_path"]=1

    local base_dir
    base_dir=$(dirname "$full_path")

    if [[ -z "$load_root" ]]; then
        load_root="$base_dir"
    fi

    while IFS= read -r line || [[ -n "$line" ]]; do
        # 匹配 (load "./xxx") 或 (load "../xxx")，捕获路径部分
        if [[ "$line" =~ ^[[:space:]]*\(load[[:space:]]+\"(\.\.?/[^\"]+)\"[[:space:]]*\)[[:space:]]*$ ]]; then
            local relative_path="${BASH_REMATCH[1]}"

            # 如果路径以 ./ 开头，相对于 load_root
            # 如果路径以 ../ 开头，相对于当前文件所在目录（base_dir）
            local target_path
            if [[ "$relative_path" == ./* ]]; then
                target_path="$load_root/${relative_path#./}"
            else
                target_path="$base_dir/$relative_path"
            fi

            # 规范化路径（处理 ../）
            target_path=$(realpath -m "$target_path")

            echo ""
            echo ";"
            echo "; ====== 来自 $relative_path ======"
            echo ";"

            # 递归时保持 load_root 不变
            process_content "$target_path" "$load_root"

            echo ""
        else
            echo "$line"
        fi
    done < "$full_path"
}

generate_config() {
    local input_name="$1"
    local output_name="$2"
    local desc="$3"

    local input_path="$CONFIGEN_DIR/$input_name"
    local output_path="$TMP_DIR/$output_name"

    echo "正在生成完整配置文件: $output_path ($desc)"

    LOADED_FILES=()

    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")

    local header=";;; 自动生成的完整配置文件
;;; 原始文件: $input_path
;;; 生成时间: $timestamp
"
    {
        echo -e "$header"
        process_content "$input_path" "$CONFIGS_DIR"
    } > "$output_path"

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
    echo "入口目录: $CONFIGEN_DIR"
    echo "模块目录: $CONFIGS_DIR"
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

main "$@"
