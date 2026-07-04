# SPDX-FileCopyrightText: 2026 brokenshine <brokenshine@users.noreply.codeberg.org>
# SPDX-License-Identifier: MIT
#
# prompt.sh — continuation prompt 渲染
# 极简原则：continuation < 500 字，只含任务摘要 + checkpoint 路径 + 进展摘要

# render_continuation <name>
# 读 state.json → 渲染 continuation → 写入 session_dir/iter-NN.prompt.md
# 返回值：生成的 prompt 文件路径
render_continuation() {
	_rc_name="$1"

	_rc_iteration="$(state_read "$_rc_name" "iteration")"
	_rc_next_iter="$((_rc_iteration + 1))"
	_rc_max_iter="$(state_read "$_rc_name" "max_iterations")"
	_rc_agent="$(state_read "$_rc_name" "agent")"
	_rc_task="$(state_read "$_rc_name" "task")"
	_rc_cwd="$(state_read "$_rc_name" "cwd")"
	_rc_marker="$(state_read "$_rc_name" "completion_marker")"
	_rc_checkpoint="$(state_read "$_rc_name" "last_checkpoint")"

	# session_dir 默认在 XDG_CACHE_HOME 下
	_rc_session_dir="${XDG_CACHE_HOME:-$HOME/.cache}/loops/${_rc_name}"
	mkdir -p "$_rc_session_dir"

	_rc_prompt_file="$_rc_session_dir/iter-$(printf '%03d' "$_rc_next_iter").prompt.md"

	# 读模板
	_rc_tmpl="$TEMPLATES_DIR/continuation.md.tmpl"
	if [ ! -f "$_rc_tmpl" ]; then
		die "Continuation template not found: $_rc_tmpl" 5
	fi

	# 构造 checkpoint 相对提示
	if [ -n "$_rc_checkpoint" ] && [ -f "$_rc_checkpoint" ]; then
		_rc_checkpoint_hint="$_rc_checkpoint"
	else
		_rc_checkpoint_hint="(none — 这是第一轮)"
	fi

	# 进展摘要：git diff --stat（静默失败）
	_rc_git_summary=""
	if [ -d "$_rc_cwd/.git" ]; then
		_rc_git_summary="$(cd "$_rc_cwd" && git diff --stat HEAD 2>/dev/null | tail -1)" || _rc_git_summary=""
	fi

	# 上一轮输出尾部（200 字符）
	_rc_output_tail=""
	_rc_last_output="$(state_read "$_rc_name" "last_iteration_output")"
	if [ -n "$_rc_last_output" ] && [ -f "$_rc_last_output" ]; then
		_rc_output_tail="$(tail -c 200 "$_rc_last_output" 2>/dev/null)" || _rc_output_tail=""
	fi

	# 渲染模板：用 awk 替换变量（安全，不受特殊字符影响）
	awk -v loop_name="$_rc_name" \
		-v iteration="$_rc_next_iter" \
		-v max_iter="$_rc_max_iter" \
		-v agent="$_rc_agent" \
		-v task="$_rc_task" \
		-v checkpoint="$_rc_checkpoint_hint" \
		-v marker="$_rc_marker" \
		-v git_summary="$_rc_git_summary" \
		-v output_tail="$_rc_output_tail" '
    {
        gsub(/\$\{LOOP_NAME\}/, loop_name)
        gsub(/\$\{ITERATION\}/, iteration)
        gsub(/\$\{MAX_ITERATIONS\}/, max_iter)
        gsub(/\$\{AGENT\}/, agent)
        gsub(/\$\{TASK\}/, task)
        gsub(/\$\{CHECKPOINT\}/, checkpoint)
        gsub(/\$\{MARKER\}/, marker)
        gsub(/\$\{GIT_SUMMARY\}/, git_summary)
        gsub(/\$\{OUTPUT_TAIL\}/, output_tail)
        print
    }
    ' "$_rc_tmpl" >"$_rc_prompt_file"

	echo "$_rc_prompt_file"
}
