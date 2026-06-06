# SPDX-FileCopyrightText: 2026 brokenshine <brokenshine@users.noreply.codeberg.org>
# SPDX-License-Identifier: MIT
#
# common.sh — 公共常量和工具函数
# 被 loopctl 和其他 lib/*.sh source

# 路径常量
# LIB_DIR: loop_lib/ 所在目录（由 loopctl 通过 _LOOPCTL_LIB_DIR 传入）
LIB_DIR="${_LOOPCTL_LIB_DIR:?loop_lib path not set (must be sourced from loopctl)}"

# 配置目录：adapters/docs 通过 XDG_CONFIG_HOME 派生
LOOPCTL_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/loopctl"
ADAPTERS_DIR="$LOOPCTL_CONFIG_DIR/adapters"

# 模板和提取器随 loop_lib 一起部署
TEMPLATES_DIR="$LIB_DIR/templates"
EXTRACT_DIR="$LIB_DIR/extract"

# 运行时数据目录：state/checkpoints 通过 XDG_DATA_HOME 派生
LOOPCTL_DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/loopctl"
ACTIVE_DIR="$LOOPCTL_DATA_DIR/active"
CHECKPOINTS_DIR="$LOOPCTL_DATA_DIR/checkpoints"
DONE_DIR="$LOOPCTL_DATA_DIR/done"
FAILED_DIR="$LOOPCTL_DATA_DIR/failed"
ARCHIVE_DIR="$LOOPCTL_DATA_DIR/archive"

# 错误退出
die() {
	log_error "$1" >&2
	exit "${2:-1}"
}

# 确保所有运行时目录存在
ensure_dirs() {
	mkdir -p "$ACTIVE_DIR" "$CHECKPOINTS_DIR" "$DONE_DIR" "$FAILED_DIR" "$ARCHIVE_DIR"
}

# 检查命令是否可用
has_cmd() {
	command -v "$1" >/dev/null 2>&1
}

# ISO 8601 时间戳
iso_now() {
	date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%SZ"
}

# 简单 JSON 解析：提取顶层字段值
# 用法: json_get <file> <key>
# 返回值（字符串）或空（未找到）
# 限制：只处理顶层 key-value，值不含嵌套对象
json_get() {
	_jg_file="$1"
	_jg_key="$2"
	# 匹配 "key": "value" 或 "key": number 或 "key": null
	sed -n "s/^[[:space:]]*\"${_jg_key}\"[[:space:]]*:[[:space:]]*//p" "$_jg_file" |
		sed -e 's/^[[:space:]]*"//' -e 's/"[[:space:]]*,\{0,1\}[[:space:]]*$//' \
			-e 's/^[[:space:]]*//' -e 's/,[[:space:]]*$//'
}

# 提取嵌套一级的字段值
# 用法: json_get_nested <file> <parent> <key>
# 处理单行和多行嵌套 JSON
json_get_nested() {
	_jg_file="$1"
	_jg_parent="$2"
	_jg_key="$3"
	awk -v parent="\"$_jg_parent\"" -v key="\"$_jg_key\"" '
    # 单行处理：parent 和 key 在同一行
    $0 ~ parent && $0 ~ key {
        pidx = index($0, parent)
        if (pidx > 0) {
            rest = substr($0, pidx + length(parent))
            kidx = index(rest, key)
            if (kidx > 0) {
                val_part = substr(rest, kidx + length(key))
                gsub(/^[[:space:]]*:[[:space:]]*/, "", val_part)
                if (substr(val_part, 1, 1) == "\"") {
                    gsub(/^"/, "", val_part)
                    gsub(/".*$/, "", val_part)
                } else {
                    gsub(/[,}].*$/, "", val_part)
                    gsub(/^[[:space:]]*/, "", val_part)
                    gsub(/[[:space:]]+$/, "", val_part)
                }
                print val_part
                exit
            }
        }
    }
    # 多行处理：先进入 parent 块
    $0 ~ parent && $0 ~ /\{/ && !done { in_parent = 1; next }
    in_parent && $0 ~ /\}/ { in_parent = 0; next }
    in_parent && $0 ~ key && !done {
        val_part = $0
        kidx = index(val_part, key)
        if (kidx > 0) {
            val_part = substr(val_part, kidx + length(key))
            gsub(/^[[:space:]]*:[[:space:]]*/, "", val_part)
            if (substr(val_part, 1, 1) == "\"") {
                gsub(/^"/, "", val_part)
                gsub(/".*$/, "", val_part)
            } else {
                gsub(/[,}].*$/, "", val_part)
                gsub(/^[[:space:]]*/, "", val_part)
                gsub(/[[:space:]]+$/, "", val_part)
            }
            print val_part
            done = 1
            exit
        }
    }
    ' "$_jg_file"
}

# 写入/更新顶层字段值
# 用法: json_set <file> <key> <value>
# 前提是文件中已有该 key。
json_set() {
	_js_file="$1"
	_js_key="$2"
	_js_val="$3"
	_js_is_number=false
	case "$_js_val" in
	null | true | false) _js_is_number=true ;;
	*)
		_js_cleaned="$(printf '%s' "$_js_val" | tr -d '0-9')"
		if [ -z "$_js_cleaned" ] && [ -n "$_js_val" ]; then
			_js_is_number=true
		fi
		;;
	esac

	_js_tmp="${_js_file}.tmp$$"
	awk -v key="$_js_key" -v val="$_js_val" -v isnum="$_js_is_number" '
    BEGIN { pattern = "\"" key "\"" }
    $0 ~ pattern {
        if (isnum == "true") {
            sub(/:[[:space:]]*[^,}]*/, ": " val, $0)
        } else {
            # sub() 替换字符串中 & 是特殊字符（代表匹配文本），需先转义
            safe_val = val
            gsub(/&/, "\\\\&", safe_val)
            sub(/:[[:space:]]*"[^"]*"/, ": \"" safe_val "\"", $0)
        }
    }
    { print }
    ' "$_js_file" >"$_js_tmp"
	mv "$_js_tmp" "$_js_file"
}

# 获取数组长度（简单计数逗号+1 方式）
# 用法: json_array_len <file> <key>
json_array_len() {
	_ja_file="$1"
	_ja_key="$2"
	# 提取 "key": [...] 的行，数元素
	awk -v key="\"$_ja_key\"" '
        $0 ~ key " *[[:space:]]*:[[:space:]]*\\[" {
            gsub(/^[^[]*\[/, "")
            gsub(/\].*$/, "")
            if (length($0) == 0) { print 0; exit }
            n = split($0, a, ",")
            print n
            exit
        }
    ' "$_ja_file"
}

# 生成唯一 loop 名的安全 ID
safe_name() {
	echo "$1" | sed 's/[^a-zA-Z0-9_-]/-/g' | sed 's/^-\|-$//' | tr '[:upper:]' '[:lower:]'
}
