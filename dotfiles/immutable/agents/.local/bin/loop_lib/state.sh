# SPDX-FileCopyrightText: 2026 brokenshine <brokenshine@users.noreply.codeberg.org>
# SPDX-License-Identifier: MIT
#
# state.sh — state.json CRUD 函数
# 不依赖 jq，用 POSIX sed/awk 处理固定 schema 的简单 JSON

# state_init <name> <task> <adapter> <cwd> <max_iterations> [model] [marker] [extra_args_json]
# 创建初始 state.json
state_init() {
	_si_name="$1"
	_si_task="$2"
	_si_adapter="$3"
	_si_cwd="$4"
	_si_max_iter="${5:-50}"
	_si_model="${6:-}"
	_si_marker="${7:-<promise>COMPLETE</promise>}"
	_si_extra_args="${8:-[]}"

	_si_state_file="$ACTIVE_DIR/${_si_name}.state.json"
	_si_task_file="$ACTIVE_DIR/${_si_name}.task.md"

	if [ -f "$_si_state_file" ]; then
		die "Loop '$_si_name' already exists (state file: $_si_state_file)" 2
	fi

	# 写任务文件
	cat >"$_si_task_file" <<TASK_EOF
# Loop Task: ${_si_name}

${_si_task}
TASK_EOF

	# 写初始 state.json（用 awk 避免变量注入风险）
	# jstr 函数：转义 \ → \\ 和 " → \"，用于 JSON 字符串值
	# 用 sprintf("%c",34) 生成引号字符，避免在单引号 awk 脚本中嵌套引号
	_si_ts="$(iso_now)"
	awk -v name="$_si_name" \
		-v task="$_si_task" \
		-v task_file="$_si_task_file" \
		-v agent="$_si_adapter" \
		-v cwd="$_si_cwd" \
		-v max_iter="$_si_max_iter" \
		-v marker="$_si_marker" \
		-v ts="$_si_ts" \
		-v model="$_si_model" '
	function jstr(s) {
		gsub(/\\/, "\\\\", s)
		q = sprintf("%c", 34)
		bq = "\\" q
		gsub(q, bq, s)
		return s
	}
	BEGIN {
		printf "{\n"
		printf "  \"schema_version\": 1,\n"
		printf "  \"name\": \"%s\",\n", jstr(name)
		printf "  \"task\": \"%s\",\n", jstr(task)
		printf "  \"task_file\": \"%s\",\n", jstr(task_file)
		printf "  \"agent\": \"%s\",\n", jstr(agent)
		printf "  \"cwd\": \"%s\",\n", jstr(cwd)
		printf "  \"status\": \"active\",\n"
		printf "  \"iteration\": 0,\n"
		printf "  \"max_iterations\": %s,\n", max_iter
		printf "  \"completion_marker\": \"%s\",\n", jstr(marker)
		printf "  \"started_at\": \"%s\",\n", ts
		printf "  \"last_iteration_at\": \"\",\n"
		printf "  \"last_iteration_duration_ms\": 0,\n"
		printf "  \"last_iteration_output\": \"\",\n"
		printf "  \"last_checkpoint\": \"\",\n"
		printf "  \"git\": {\n"
		printf "    \"repo\": \"%s\",\n", jstr(cwd)
		printf "    \"branch_at_start\": \"\",\n"
		printf "    \"branch\": \"\"\n"
		printf "  },\n"
		printf "  \"config\": {\n"
		printf "    \"model\": \"%s\",\n", jstr(model)
		printf "    \"extra_env\": {},\n"
		printf "    \"spawn_mode\": \"foreground\"\n"
		printf "  }\n"
		printf "}\n"
	}' >"$_si_state_file"

	echo "$_si_state_file"
}

# state_read <name> <field>
# 读取 state.json 的顶层字段
state_read() {
	_sr_name="$1"
	_sr_field="$2"
	_sr_file="$(state_get_path "$_sr_name")"
	if [ -z "$_sr_file" ] || [ ! -f "$_sr_file" ]; then
		die "State file for '$_sr_name' not found" 3
	fi
	json_get "$_sr_file" "$_sr_field"
}

# state_read_nested <name> <parent> <field>
state_read_nested() {
	_srn_name="$1"
	_srn_parent="$2"
	_srn_field="$3"
	_srn_file="$(state_get_path "$_srn_name")"
	if [ -z "$_srn_file" ] || [ ! -f "$_srn_file" ]; then
		die "State file for '$_sr_name' not found" 3
	fi
	json_get_nested "$_srn_file" "$_srn_parent" "$_srn_field"
}

# state_update <name> <key> <value>
# 更新 state.json 的顶层字段（要求字段已存在）
state_update() {
	_su_name="$1"
	_su_key="$2"
	_su_val="$3"
	_su_file="$(state_get_path "$_su_name")"
	if [ -z "$_su_file" ] || [ ! -f "$_su_file" ]; then
		die "State file for '$_su_name' not found" 3
	fi
	json_set "$_su_file" "$_su_key" "$_su_val"
}

# state_get_path <name>
# 返回 state.json 路径（优先 active，然后 paused 在 active，然后 done/failed）
state_get_path() {
	_sgp_name="$1"
	# 优先检查 active
	if [ -f "$ACTIVE_DIR/${_sgp_name}.state.json" ]; then
		echo "$ACTIVE_DIR/${_sgp_name}.state.json"
		return
	fi
	# 检查 done
	if [ -f "$DONE_DIR/${_sgp_name}.state.json" ]; then
		echo "$DONE_DIR/${_sgp_name}.state.json"
		return
	fi
	# 检查 failed
	if [ -f "$FAILED_DIR/${_sgp_name}.state.json" ]; then
		echo "$FAILED_DIR/${_sgp_name}.state.json"
		return
	fi
	# 未找到
	return 1
}

# state_get_status <name>
# 快速获取 status 字段
state_get_status() {
	state_read "$1" "status"
}

# state_move <name> <target_dir>
# 移动 state.json（和 task.md）到目标目录
state_move() {
	_sm_name="$1"
	_sm_dir="$2"
	_sm_file="$(state_get_path "$_sm_name")"
	if [ -z "$_sm_file" ]; then
		die "State file for '$_sm_name' not found" 3
	fi
	_sm_cur_dir="$(dirname "$_sm_file")"
	mkdir -p "$_sm_dir"
	mv "$_sm_file" "$_sm_dir/"
	# 同时移动 task.md（如果在同目录）
	if [ -f "${_sm_cur_dir}/${_sm_name}.task.md" ]; then
		mv "${_sm_cur_dir}/${_sm_name}.task.md" "$_sm_dir/"
	fi
}

# state_exists <name>
state_exists() {
	state_get_path "$1" >/dev/null 2>&1
}
