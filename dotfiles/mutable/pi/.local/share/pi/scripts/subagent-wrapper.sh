#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

# subagent-wrapper.sh — tmux pane 内的 subagent 执行包装
# 用法: subagent-wrapper.sh <run-id> <agent-name> <task-file> [--model <m>] [--cwd <d>] [--tools <list>]

set -euo pipefail

RUN_ID="${1:?missing run-id}"
AGENT_NAME="${2:?missing agent-name}"
TASK_FILE="${3:?missing task-file}"
shift 3

MODEL=""
CWD=""
TOOLS=""
IMAGES=""

while [[ $# -gt 0 ]]; do
	case "$1" in
	--model)
		MODEL="$2"
		shift 2
		;;
	--cwd)
		CWD="$2"
		shift 2
		;;
	--tools)
		TOOLS="$2"
		shift 2
		;;
	--image)
		IMAGES="$2"
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

# 标记当前进程为 subagent，供扩展 hook 检测递归
export PI_SUBAGENT=1

status_file="$RUN_DIR/status.json"
result_file="$RUN_DIR/result.md"
meta_file="$RUN_DIR/result.json"
session_dir="$RUN_DIR/sessions"

if [[ -t 2 && -z "${NO_COLOR:-}" ]]; then
	c_reset=$'\033[0m'
	c_bold=$'\033[1m'
	c_dim=$'\033[2m'
	c_cyan=$'\033[36m'
	c_green=$'\033[32m'
	c_red=$'\033[31m'
else
	c_reset=""
	c_bold=""
	c_dim=""
	c_cyan=""
	c_green=""
	c_red=""
fi

write_status() {
	local status="$1"
	local exit_code="$2"
	local started_at="${3:-}"
	local finished_at="${4:-$(date +%s000)}"
	local error="${5:-}"

	python3 - "$status_file" "$status" "$exit_code" "$started_at" "$finished_at" "$error" <<'PY'
import json
import sys

path, status, exit_code, started_at, finished_at, error = sys.argv[1:7]
payload = {
    "status": status,
    "exitCode": int(exit_code),
    "finishedAt": int(finished_at),
}
if started_at:
    payload["startedAt"] = int(started_at)
if error:
    payload["error"] = error
with open(path, "w", encoding="utf-8") as fh:
    json.dump(payload, fh, ensure_ascii=False)
PY
}

die() {
	write_status "failed" "${2:-1}" "" "" "$1"
	exit "${2:-1}"
}

# 解析 agent .md 的 frontmatter（仅提取 tools）
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
			if [[ "$line" =~ ^tools: ]]; then
				local fm_tools="${line#tools: }"
				fm_tools="${fm_tools# }"
				[[ -z "$TOOLS" && -n "$fm_tools" ]] && TOOLS="$fm_tools"
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

# 从 subagents.json 加载模型配置（如果 --model 未被调用方显式指定）
load_subagents_config() {
	local config_file="$XDG_CONFIG_HOME/pi/subagents.json"
	if [[ -z "$MODEL" && -f "$config_file" ]]; then
		local agent_model
		agent_model="$(python3 - "$config_file" "$AGENT_NAME" <<'PY'
import json
import sys

config_path, agent_name = sys.argv[1:3]
try:
    data = json.load(open(config_path, encoding="utf-8"))
    agent_cfg = data.get("agents", {}).get(agent_name, {})
    model = agent_cfg.get("model", "")
    if model:
        print(model)
except Exception:
    pass
PY
)"
		[[ -n "$agent_model" ]] && MODEL="$agent_model"
	fi
}

parse_agent_md
load_subagents_config

# 读取任务文件
TASK_TEXT="$(cat "$TASK_FILE")" || die "failed to read task file" 1
TOOLS="$(printf '%s' "$TOOLS" | sed -e 's/[[:space:]]*,[[:space:]]*/,/g' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
mkdir -p "$session_dir"

# 构造 pi 命令参数
PI_ARGS=(--mode json -p --session-dir "$session_dir")

if [[ -n "$MODEL" ]]; then
	PI_ARGS+=(--model "$MODEL")
fi
if [[ -n "$TOOLS" ]]; then
	PI_ARGS+=(--tools "$TOOLS")
else
	PI_ARGS+=(--tools "read,grep,find,ls")
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

# 附加图片文件（pi @file 语法）
if [[ -n "$IMAGES" ]]; then
	# 逗号分隔的多图片路径
	IFS=',' read -ra IMG_PATHS <<< "$IMAGES"
	for img_path in "${IMG_PATHS[@]}"; do
		img_path="${img_path# }"  # 去前导空格
		img_path="${img_path% }"  # 去尾部空格
		if [[ -f "$img_path" ]]; then
			PI_ARGS+=("@$img_path")
		else
			echo "warning: image file not found: $img_path" >&2
		fi
	done
fi

PI_ARGS+=("Task: $TASK_TEXT")

# 运行子 pi，捕获 JSON 输出
STARTED_AT="$(date +%s000)"

run_pi() {
	local pi_cmd="pi"
	if [[ -x "$HOME/.local/bin/pi" ]]; then
		pi_cmd="$HOME/.local/bin/pi"
	elif command -v pi &>/dev/null; then
		pi_cmd="pi"
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
	"$script_dir/extract-pi-result.py" --meta "$meta_file"
}

EXIT_CODE=0
{
	printf '%bsubagent%b %s  %b%s%b\n' "$c_cyan$c_bold" "$c_reset" "$AGENT_NAME" "$c_dim" "$RUN_ID" "$c_reset"
	printf '  cwd:   %s\n' "${CWD:-$PWD}"
	printf '  model: %s\n' "${MODEL:-default}"
	printf '  tools: %s\n\n' "${TOOLS:-read,grep,find,ls}"
} >&2
run_pi 2>"$RUN_DIR/stderr.log" | extract_result >"$result_file" || EXIT_CODE=$?

FINISHED_AT="$(date +%s000)"

# 写入最终 status.json
if [[ $EXIT_CODE -eq 0 ]]; then
	FINAL_STATUS="completed"
	ERROR_MESSAGE=""
else
	FINAL_STATUS="failed"
	ERROR_MESSAGE="$(python3 - "$meta_file" "$RUN_DIR/stderr.log" <<'PY'
import json
import sys
from pathlib import Path

meta = Path(sys.argv[1])
stderr = Path(sys.argv[2])
message = ""
if meta.exists():
    try:
        payload = json.loads(meta.read_text(encoding="utf-8"))
        message = payload.get("errorMessage") or ""
    except Exception:
        pass
if not message and stderr.exists():
    message = stderr.read_text(encoding="utf-8").strip()[-2000:]
print(message)
PY
)"
fi

write_status "$FINAL_STATUS" "$EXIT_CODE" "$STARTED_AT" "$FINISHED_AT" "$ERROR_MESSAGE"

# 清理临时文件
if [[ -n "${TMP_PROMPT:-}" && -f "$TMP_PROMPT" ]]; then
	rm -f "$TMP_PROMPT"
fi

if [[ -n "${TMUX:-}" && "${PI_SUBAGENT_KEEP_PANE:-0}" == "1" ]]; then
	if [[ "$FINAL_STATUS" == "completed" ]]; then
		status_color="$c_green"
	else
		status_color="$c_red"
	fi
	{
		printf '\n%bsubagent%b %s %b%s%b\n' "$c_cyan$c_bold" "$c_reset" "$AGENT_NAME" "$status_color$c_bold" "$FINAL_STATUS" "$c_reset"
		printf '  result:  %s\n' "$result_file"
		printf '  session: %s\n' "$session_dir"
		printf '  %bpane kept open because PI_SUBAGENT_KEEP_PANE=1.%b\n' "$c_dim" "$c_reset"
	} >&2
	exec "${SHELL:-bash}" -i
fi

exit $EXIT_CODE
