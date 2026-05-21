#!/usr/bin/env bash
# subagent-wrapper.sh — tmux pane 内的 subagent 执行包装
# 用法: subagent-wrapper.sh <run-id> <agent-name> <task-file> [--model <m>] [--thinking <l>] [--cwd <d>]

set -euo pipefail

RUN_ID="${1:?missing run-id}"
AGENT_NAME="${2:?missing agent-name}"
TASK_FILE="${3:?missing task-file}"
shift 3

MODEL=""
THINKING=""
CWD=""

while [[ $# -gt 0 ]]; do
	case "$1" in
	--model)
		MODEL="$2"
		shift 2
		;;
	--thinking)
		THINKING="$2"
		shift 2
		;;
	--cwd)
		CWD="$2"
		shift 2
		;;
	*) shift ;;
	esac
done

XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"

RUN_DIR="$XDG_CACHE_HOME/pi/subagents/$RUN_ID"
AGENTS_DIR="$XDG_CONFIG_HOME/pi/agents"

status_file="$RUN_DIR/status.json"
result_file="$RUN_DIR/result.md"

die() {
	echo '{"status":"failed","exitCode":'${2:-1}',"finishedAt":'$(date +%s000)',"error":"'"$1"'"}' >"$status_file"
	exit "${2:-1}"
}

# 解析 agent .md 的 frontmatter
parse_agent_md() {
	local agent_file="$AGENTS_DIR/$AGENT_NAME.md"
	if [[ ! -f "$agent_file" ]]; then
		die "agent file not found: $agent_file" 1
	fi

	local in_fm=false
	local line
	while IFS= read -r line || [[ -n "$line" ]]; do
		if [[ "$line" =~ ^--- ]]; then
			if $in_fm; then
				break
			else
				in_fm=true
				continue
			fi
		fi
		if $in_fm; then
			if [[ "$line" =~ ^model: ]]; then
				local fm_model="${line#model: }"
				fm_model="${fm_model# }"
				[[ -z "$MODEL" && -n "$fm_model" ]] && MODEL="$fm_model"
			fi
			if [[ "$line" =~ ^thinking: ]]; then
				local fm_thinking="${line#thinking: }"
				fm_thinking="${fm_thinking# }"
				[[ -z "$THINKING" && -n "$fm_thinking" ]] && THINKING="$fm_thinking"
			fi
		fi
	done <"$agent_file"

	# 提取 body（frontmatter 之后的内容）作为系统提示
	local body
	body="$(sed -n '/^---$/,/^---$/!p' "$agent_file" | tail -n +1)"
	# 去掉首尾空行
	body="$(echo "$body" | sed -e '/./,$!d' -e ':a' -e '/^\n*$/{$d;N;ba' -e '}')"

	AGENT_SYSTEM_PROMPT="$body"
}

parse_agent_md

# 读取任务文件
TASK_TEXT="$(cat "$TASK_FILE")" || die "failed to read task file" 1

# 构造 pi 命令参数
PI_ARGS=(--mode json -p --no-session)

if [[ -n "$MODEL" ]]; then
	PI_ARGS+=(--model "$MODEL")
fi
if [[ -n "$THINKING" ]]; then
	PI_ARGS+=(--thinking "$THINKING")
fi

# 处理系统提示：较长时写入临时文件
AGENT_SYSTEM_PROMPT="${AGENT_SYSTEM_PROMPT:-}"
if [[ -n "$AGENT_SYSTEM_PROMPT" ]]; then
	if [[ ${#AGENT_SYSTEM_PROMPT} -gt 8000 ]]; then
		TMP_PROMPT="$(mktemp /tmp/pi-subagent-prompt-XXXXXX.md)"
		echo "$AGENT_SYSTEM_PROMPT" >"$TMP_PROMPT"
		PI_ARGS+=(--append-system-prompt "$TMP_PROMPT")
	else
		PI_ARGS+=(--append-system-prompt "$AGENT_SYSTEM_PROMPT")
	fi
fi

PI_ARGS+=("Task: $TASK_TEXT")

# 运行子 pi，捕获 JSON 输出
STARTED_AT="$(date +%s000)"

run_pi() {
	local pi_cmd="pi"
	if command -v pi &>/dev/null; then
		pi_cmd="pi"
	elif [[ -x "$HOME/.local/bin/pi" ]]; then
		pi_cmd="$HOME/.local/bin/pi"
	else
		die "pi command not found" 127
	fi

	if [[ -n "$CWD" ]]; then
		cd "$CWD"
	fi

	"$pi_cmd" "${PI_ARGS[@]}"
}

# 解析 JSON 流提取最后一条 assistant 文本（使用 python3 脚本正确处理 JSON 转义）
extract_result() {
	local script_dir
	script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
	"$script_dir/extract-pi-result.py"
}

EXIT_CODE=0
run_pi 2>"$RUN_DIR/stderr.log" | extract_result >"$result_file" || EXIT_CODE=$?

FINISHED_AT="$(date +%s000)"

# 写入最终 status.json
if [[ $EXIT_CODE -eq 0 ]]; then
	FINAL_STATUS="completed"
else
	FINAL_STATUS="failed"
fi

cat >"$status_file" <<STATUS_EOF
{"status":"$FINAL_STATUS","exitCode":$EXIT_CODE,"startedAt":$STARTED_AT,"finishedAt":$FINISHED_AT}
STATUS_EOF

# 清理临时文件
if [[ -n "${TMP_PROMPT:-}" && -f "$TMP_PROMPT" ]]; then
	rm -f "$TMP_PROMPT"
fi

exit $EXIT_CODE
