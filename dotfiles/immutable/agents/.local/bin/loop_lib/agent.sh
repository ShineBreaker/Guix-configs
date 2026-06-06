# SPDX-FileCopyrightText: 2026 brokenshine <brokenshine@users.noreply.codeberg.org>
# SPDX-License-Identifier: MIT
#
# agent.sh — adapter 加载 + 进程管理
# 负责加载 adapter JSON、构造命令、spawn agent、提取 output

# spawn_agent <adapter_name> <prompt_file> <cwd>
# 启动 agent 进程，将 stdout 输出给调用方
spawn_agent() {
	_sa_name="$1"
	_sa_prompt="$2"
	_sa_cwd="$3"

	# 确保 adapter 已加载
	if [ -z "$ADAPTER_BIN" ]; then
		load_adapter "$_sa_name"
	fi

	_sa_cmd="$(_build_agent_cmd "$_sa_prompt" "$_sa_cwd")"
	cd "$_sa_cwd" && eval "$_sa_cmd"
}

# extract_output <type> <output_file>
# 根据类型调用对应提取器脚本
extract_output() {
	_eo_type="$1"
	_eo_file="$2"
	# 类型名到脚本名的映射（有些类型名含 -text 后缀但脚本不带）
	case "$_eo_type" in
	jsonl-last-assistant-text) _eo_script="$EXTRACT_DIR/jsonl-last-assistant.sh" ;;
	jsonl-last-text)          _eo_script="$EXTRACT_DIR/jsonl-last-text.sh" ;;
	claude-code-print)        _eo_script="$EXTRACT_DIR/claude-code-print.sh" ;;
	text)                     _eo_script="$EXTRACT_DIR/text.sh" ;;
	*)                        _eo_script="$EXTRACT_DIR/${_eo_type}.sh" ;;
	esac
	if [ ! -x "$_eo_script" ]; then
		_eo_script="$EXTRACT_DIR/text.sh"
	fi
	"$_eo_script" "$_eo_file"
}

# check_completion <output_file> <marker> [tail_chars]
# 检查输出文件尾部是否包含完成标记
check_completion() {
	_cc_file="$1"
	_cc_marker="$2"
	_cc_tail="${3:-4000}"
	if [ ! -f "$_cc_file" ]; then return 1; fi
	tail -c "$_cc_tail" "$_cc_file" 2>/dev/null | grep -qF "$_cc_marker"
}

# _build_agent_cmd <prompt_file> <cwd>
# 根据 adapter 配置构造在 shell 中执行的命令字符串
# 注意：此函数也在 loopctl 中使用（已定义），这里仅在 spawn_agent 内部使用时作为 fallback

# load_adapter <name>
# 读 adapters/<name>.json，导出为 shell 变量
# 导出变量：
#   ADAPTER_NAME, ADAPTER_BIN, ADAPTER_BIN_CHECK,
#   ADAPTER_INPUT_METHOD, ADAPTER_INPUT_FLAG, ADAPTER_OUTPUT_FORMAT,
#   ADAPTER_TIMEOUT, ADAPTER_EXTRACT_TYPE, ADAPTER_MARKER,
#   ADAPTER_MARKER_TAIL, ADAPTER_SESSION_DIR_FLAG, ADAPTER_RESUME_FLAG,
#   ADAPTER_ARGS_TEMPLATE, ADAPTER_ENV_JSON, ADAPTER_SMOKE_TEST
load_adapter() {
	_la_name="$1"
	_la_file="$ADAPTERS_DIR/${_la_name}.json"
	if [ ! -f "$_la_file" ]; then
		die "Adapter '$_la_name' not found ($_la_file)" 4
	fi

	ADAPTER_NAME="$(json_get "$_la_file" "name")"
	ADAPTER_BIN="$(json_get "$_la_file" "bin")"
	ADAPTER_INPUT_METHOD="$(json_get "$_la_file" "input_method")"
	ADAPTER_INPUT_FLAG="$(json_get "$_la_file" "input_flag")"
	ADAPTER_OUTPUT_FORMAT="$(json_get "$_la_file" "output_format")"
	ADAPTER_EXTRACT_TYPE="$(json_get "$_la_file" "type")"
	ADAPTER_MARKER="$(json_get "$_la_file" "marker")"
	ADAPTER_MARKER_TAIL="$(json_get "$_la_file" "marker_scan_tail_chars")"
	ADAPTER_TIMEOUT="$(json_get "$_la_file" "timeout_sec")"
	ADAPTER_SESSION_DIR_FLAG="$(json_get "$_la_file" "session_dir_flag")"
	ADAPTER_RESUME_FLAG="$(json_get "$_la_file" "resume_flag")"
	ADAPTER_SMOKE_TEST="$(json_get "$_la_file" "smoke_test_prompt")"

	# 从 run 嵌套对象读取
	if [ -z "$ADAPTER_INPUT_METHOD" ]; then
		ADAPTER_INPUT_METHOD="$(json_get_nested "$_la_file" "run" "input_method")"
	fi
	if [ -z "$ADAPTER_INPUT_FLAG" ]; then
		ADAPTER_INPUT_FLAG="$(json_get_nested "$_la_file" "run" "input_flag")"
	fi
	if [ -z "$ADAPTER_OUTPUT_FORMAT" ]; then
		ADAPTER_OUTPUT_FORMAT="$(json_get_nested "$_la_file" "run" "output_format")"
	fi
	if [ -z "$ADAPTER_TIMEOUT" ] || [ "$ADAPTER_TIMEOUT" = "" ]; then
		ADAPTER_TIMEOUT="$(json_get_nested "$_la_file" "run" "timeout_sec")"
	fi

	# 从 extract 嵌套对象读取
	if [ -z "$ADAPTER_EXTRACT_TYPE" ]; then
		ADAPTER_EXTRACT_TYPE="$(json_get_nested "$_la_file" "extract" "type")"
	fi
	if [ -z "$ADAPTER_MARKER" ]; then
		ADAPTER_MARKER="$(json_get_nested "$_la_file" "completion" "marker")"
	fi
	if [ -z "$ADAPTER_MARKER_TAIL" ] || [ "$ADAPTER_MARKER_TAIL" = "" ]; then
		ADAPTER_MARKER_TAIL="$(json_get_nested "$_la_file" "completion" "marker_scan_tail_chars")"
	fi

	# 从 session 嵌套对象读取
	if [ -z "$ADAPTER_SESSION_DIR_FLAG" ]; then
		ADAPTER_SESSION_DIR_FLAG="$(json_get_nested "$_la_file" "session" "session_dir_flag")"
	fi
	if [ -z "$ADAPTER_RESUME_FLAG" ]; then
		ADAPTER_RESUME_FLAG="$(json_get_nested "$_la_file" "session" "resume_flag")"
	fi

	# 从 examples 嵌套对象读取
	if [ -z "$ADAPTER_SMOKE_TEST" ]; then
		ADAPTER_SMOKE_TEST="$(json_get_nested "$_la_file" "examples" "smoke_test_prompt")"
	fi

	# 默认值
	: "${ADAPTER_TIMEOUT:=300}"
	: "${ADAPTER_MARKER:=<promise>COMPLETE</promise>}"
	: "${ADAPTER_MARKER_TAIL:=4000}"
	: "${ADAPTER_INPUT_METHOD:=stdin}"
	: "${ADAPTER_OUTPUT_FORMAT:=text}"
	: "${ADAPTER_EXTRACT_TYPE:=text}"

	# 读取 args_template（简化处理：提取数组为空格分隔字符串）
	ADAPTER_ARGS_TEMPLATE="$(extract_args_template "$_la_file")"

	export ADAPTER_NAME ADAPTER_BIN ADAPTER_INPUT_METHOD ADAPTER_INPUT_FLAG \
		ADAPTER_OUTPUT_FORMAT ADAPTER_TIMEOUT ADAPTER_EXTRACT_TYPE \
		ADAPTER_MARKER ADAPTER_MARKER_TAIL ADAPTER_SESSION_DIR_FLAG \
		ADAPTER_RESUME_FLAG ADAPTER_ARGS_TEMPLATE ADAPTER_SMOKE_TEST
}

# extract_args_template <file>
# 从 adapter JSON 提取 run.args_template 数组为空格分隔字符串
# 处理单行和多行 JSON
extract_args_template() {
	_eat_file="$1"
	awk '
        /"args_template"/ {
            # 检查 ] 是否在同一行
            if ($0 ~ /\]/) {
                # 单行数组
                gsub(/.*"args_template"[[:space:]]*:[[:space:]]*\[/, "")
                gsub(/\].*$/, "")
                gsub(/^[[:space:]]+|[[:space:]]+$/, "")
                if (length($0) == 0) exit
                n = split($0, a, ",")
                for (i = 1; i <= n; i++) {
                    gsub(/^[[:space:]]*"/, "", a[i])
                    gsub(/"[[:space:]]*$/, "", a[i])
                    gsub(/^[[:space:]]*/, "", a[i])
                    if (a[i] != "") printf "%s ", a[i]
                }
                exit
            }
            found = 1
            next
        }
        found && /\]/ { exit }
        found && /"/ {
            gsub(/^[[:space:]]*"/, "")
            gsub(/".*$/, "")
            printf "%s ", $0
        }
    ' "$_eat_file" | sed 's/ $//'
}
