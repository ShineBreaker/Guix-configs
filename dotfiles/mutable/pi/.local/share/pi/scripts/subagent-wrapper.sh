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
PROMPT_FILE=""

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
	--prompt-file)
		PROMPT_FILE="$2"
		shift 2
		;;
	*) shift ;;
	esac
done

XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"

RUN_DIR="$XDG_CACHE_HOME/pi/subagents/$RUN_ID"

# agent .md 候选目录（多路径回退，与 TS 端 resolveAgentFile 策略一致）：
#   1. 插件内置 atelier/context/agents（自包含 agent 定义）
#   2. 用户自定义 ~/.config/pi/agents（兼容旧路径）
PLUGIN_AGENTS_DIR="$XDG_CONFIG_HOME/pi/extensions/atelier/context/agents"
USER_AGENTS_DIR="$XDG_CONFIG_HOME/pi/agents"

# 按优先级查找 agent .md 文件，输出第一个存在的路径
resolve_agent_file() {
	for d in "$PLUGIN_AGENTS_DIR" "$USER_AGENTS_DIR"; do
		if [[ -f "$d/$AGENT_NAME.md" ]]; then
			echo "$d/$AGENT_NAME.md"
			return 0
		fi
	done
	return 1
}

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
	c_yellow=$'\033[33m'
else
	c_reset=""
	c_bold=""
	c_dim=""
	c_cyan=""
	c_green=""
	c_red=""
	c_yellow=""
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
# ── 安全网：保证 status.json 必有终态，避免父进程 waitForCompletion 永久轮询卡死 ──
# 当 wrapper 因 set -e 中途 abort / 未捕获错误退出（没走到 write_status）时，
# EXIT trap 兜底把仍为 running 的 status 写成 failed。（pipe hang 已由下方“落盘再 extract”修复。）
finalize() {
	set +e
	if [[ -f "$status_file" ]] && grep -Eq '"status":[[:space:]]*"running"' "$status_file" 2>/dev/null; then
		write_status "failed" "${EXIT_CODE:-1}" "${STARTED_AT:-}" "$(date +%s000)" \
			"wrapper 在未写终态时退出（EXIT 安全网兜底）" 2>/dev/null || true
	fi
}
trap finalize EXIT
trap 'EXIT_CODE=130; exit 130' INT
trap 'EXIT_CODE=143; exit 143' TERM
trap 'EXIT_CODE=129; exit 129' HUP

# 解析 agent .md 的 frontmatter（仅提取 tools）
parse_agent_md() {
	local agent_file
	if ! agent_file="$(resolve_agent_file)"; then
		die "agent file not found: $AGENT_NAME.md (searched: $PLUGIN_AGENTS_DIR, $USER_AGENTS_DIR)" 1
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

	# 如果调用方传了 --prompt-file（atelier launcher 预先生成的
	# 清理后的 prompt），优先使用它；否则从 agent .md 提取 body
	# （仍含 HTML 注释标记，LLM 会忽略）
	if [[ -n "$PROMPT_FILE" && -f "$PROMPT_FILE" ]]; then
		AGENT_SYSTEM_PROMPT="$(cat "$PROMPT_FILE")"
	else
		local body
		body="$(sed -n '/^---$/,/^---$/!p' "$agent_file" | tail -n +1)"
		# 去掉首尾空行
		body="$(echo "$body" | sed -e '/./,$!d' -e ':a' -e '/^\n*$/{$d;N;ba' -e '}')"

		AGENT_SYSTEM_PROMPT="$body"
	fi
}

# 从 subagents.json 加载模型配置（如果 --model 未被调用方显式指定）
load_subagents_config() {
	local config_file="$XDG_CONFIG_HOME/pi/subagents.json"
	if [[ -z "$MODEL" && -f "$config_file" ]]; then
		local agent_model
		agent_model="$(
			python3 - "$config_file" "$AGENT_NAME" <<'PY'
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
	IFS=',' read -ra IMG_PATHS <<<"$IMAGES"
	for img_path in "${IMG_PATHS[@]}"; do
		img_path="${img_path# }" # 去前导空格
		img_path="${img_path% }" # 去尾部空格
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
# pi 的 stdout 落到文件（避开 pipe-EOF hang：pipe 需所有写端关闭，pi 的子孙若继承 stdout fd
# 不关则 pipe 永不 EOF；普通文件 EOF 按大小判定，与是否仍 open 无关）。
PI_STDOUT_FILE="$RUN_DIR/pi-stdout.jsonl"
# 实时 pane 美化视图（已恢复）：后台 tail -F 该文件 | extract_result，extract 的 stderr=pane
# （实时流，与旧版一致），stdout→/dev/null。tail 读普通文件 → 无 pipe-EOF 问题。
# wrapper 只 wait pi，不等后台流；pi 退出后 SIGKILL 后台流（SIGKILL 不可被阻塞的 pty 写拦截，
# 故 runaway 也卡不住 wrapper；extract 死后 tail 收 SIGPIPE 自退）。
printf '%b  ▶ subagent 运行中（实时 pane 视图已恢复；wrapper 只等 pi，runaway 不阻塞）%b\n' "$c_dim" "$c_reset" >&2
run_pi >"$PI_STDOUT_FILE" 2>"$RUN_DIR/stderr.log" &
PI_PID=$!
tail -n +1 -F "$PI_STDOUT_FILE" 2>/dev/null | extract_result >/dev/null &
LIVE_PID=$!
PI_EXIT=0
wait "$PI_PID" || PI_EXIT=$?
kill -KILL "$LIVE_PID" 2>/dev/null || true
wait "$LIVE_PID" 2>/dev/null || true
# 对完整文件做权威 extract（result.md + meta；stderr→/dev/null 不重复刷屏）
EXTRACT_EXIT=0
extract_result <"$PI_STDOUT_FILE" >"$result_file" 2>/dev/null || EXTRACT_EXIT=$?
if [[ $PI_EXIT -ne 0 ]]; then
	EXIT_CODE=$PI_EXIT
elif [[ $EXTRACT_EXIT -ne 0 ]]; then
	EXIT_CODE=$EXTRACT_EXIT
else
	EXIT_CODE=0
fi
printf '%b  ■ subagent 结束：exitCode=%s（0=completed）%b\n' "$c_dim" "$EXIT_CODE" "$c_reset" >&2

FINISHED_AT="$(date +%s000)"

# 写入最终 status.json
if [[ $EXIT_CODE -eq 0 ]]; then
	FINAL_STATUS="completed"
	ERROR_MESSAGE=""
else
	FINAL_STATUS="failed"
	ERROR_MESSAGE="$(
		python3 - "$meta_file" "$RUN_DIR/stderr.log" <<'PY'
import json
import sys
from pathlib import Path
try:
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
        try:
            message = stderr.read_text(encoding="utf-8", errors="replace").strip()[-2000:]
        except Exception:
            message = ""
    print(message)
except Exception:
    # 任何意外都不能让 wrapper 在 set -e 下 abort（否则 status 卡在 running）
    print("")
PY
	)"
fi

write_status "$FINAL_STATUS" "$EXIT_CODE" "$STARTED_AT" "$FINISHED_AT" "$ERROR_MESSAGE"

# PR-7：验证 result.md 顶部是否是 Return Header。若缺，写 stderr 警告（不阻塞返回）。
# atelier 侧的 monitor.ts 仍能 parse → 返回 null → 标 return_status="unknown"。
# wrapper 层只做轻量提示，便于 tmux pane 内肉眼诊断。
if [[ -f "$result_file" ]]; then
	first_line="$(head -n 1 "$result_file" 2>/dev/null || true)"
	if [[ "$first_line" != *"**"*"Status"*"**"*":"* ]]; then
		printf '%b[atelier:wrapper]%b result.md 缺 Return Header（首行非 **Status**:）。\n' "$c_yellow" "$c_reset" >&2 || true
	fi
else
	printf '%b[atelier:wrapper]%b result_file 不存在：%s\n' "$c_yellow" "$c_reset" "$result_file" >&2 || true
fi

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
