# SPDX-FileCopyrightText: 2026 brokenshine <brokenshine@users.noreply.codeberg.org>
# SPDX-License-Identifier: MIT
#
# adapter-cmds.sh — adapter 子命令实现
# 被 loopctl source

cmd_adapter_list() {
	log_info "Available adapters:"
	_found=0
	for _f in "$ADAPTERS_DIR"/*.json; do
		[ -f "$_f" ] || continue
		_name="$(basename "$_f" .json)"
		_bin="$(json_get "$_f" "bin")"
		if [ "$_name" = "_TEMPLATE" ]; then
			continue
		fi
		_found=1
		if has_cmd "$_bin"; then
			log_success "  $_name (bin: $_bin — available)"
		else
			log_warn "  $_name (bin: $_bin — NOT FOUND)"
		fi
	done
	if [ "$_found" -eq 0 ]; then
		log_warn "  (no adapters found)"
	fi
}

cmd_adapter_show() {
	_cas_name="$1"
	_cas_file="$ADAPTERS_DIR/${_cas_name}.json"
	if [ ! -f "$_cas_file" ]; then
		die "Adapter '$_cas_name' not found" 4
	fi
	cat "$_cas_file"
	echo ""
	_bin="$(json_get "$_cas_file" "bin")"
	if has_cmd "$_bin"; then
		log_success "bin '$_bin' is available"
	else
		log_error "bin '$_bin' is NOT available"
	fi
}

cmd_adapter_add() {
	_caa_name="$1"
	if [ -z "$_caa_name" ]; then
		die "Usage: loopctl adapter add <name>" 1
	fi
	_caa_file="$ADAPTERS_DIR/${_caa_name}.json"
	if [ -f "$_caa_file" ]; then
		die "Adapter '$_caa_name' already exists" 2
	fi

	printf "CLI binary name: "
	read -r _caa_bin
	printf "Fixed args (space-separated, or empty): "
	read -r _caa_args
	printf "Input method (stdin/arg/file) [stdin]: "
	read -r _caa_input
	printf "Input flag (e.g. --prompt-file, or empty): "
	read -r _caa_flag
	printf "Extract type (text/jsonl-last-assistant-text/jsonl-last-text/claude-code-print) [text]: "
	read -r _caa_extract

	: "${_caa_input:=stdin}"
	: "${_caa_extract:=text}"

	_caa_args_json="[]"
	if [ -n "$_caa_args" ]; then
		_caa_args_json="["
		_caa_first=1
		for _arg in $_caa_args; do
			if [ "$_caa_first" -eq 1 ]; then
				_caa_args_json="${_caa_args_json}\"$_arg\""
				_caa_first=0
			else
				_caa_args_json="${_caa_args_json}, \"$_arg\""
			fi
		done
		_caa_args_json="${_caa_args_json}]"
	fi

	_caa_flag_json="null"
	if [ -n "$_caa_flag" ]; then
		_caa_flag_json="\"$_caa_flag\""
	fi

	cat >"$_caa_file" <<ADAPTER_EOF
{
  "name": "${_caa_name}",
  "version": "1.0",
  "description": "Auto-generated adapter for ${_caa_name}",

  "bin": "${_caa_bin}",
  "bin_check": ["${_caa_bin}", "--version"],
  "bin_min_version": "",

  "run": {
    "args_template": ${_caa_args_json},
    "input_method": "${_caa_input}",
    "input_flag": ${_caa_flag_json},
    "output_format": "text",
    "working_dir": "project_root",
    "timeout_sec": 300
  },

  "extract": {
    "type": "${_caa_extract}"
  },

  "session": {
    "supported": false,
    "fresh_per_step": true,
    "session_dir_flag": null,
    "resume_flag": null
  },

  "completion": {
    "marker": "<promise>COMPLETE</promise>",
    "marker_scan_tail_chars": 4000,
    "native_command": null
  },

  "env": {},

  "extra_args": [],

  "examples": {
    "smoke_test_prompt": "Reply with exactly: OK"
  }
}
ADAPTER_EOF

	log_success "Created $_caa_file"
}

cmd_adapter_test() {
	_cat_name="$1"
	if [ -z "$_cat_name" ]; then
		die "Usage: loopctl adapter test <name>" 1
	fi
	_cat_file="$ADAPTERS_DIR/${_cat_name}.json"
	if [ ! -f "$_cat_file" ]; then
		die "Adapter '$_cat_name' not found" 4
	fi

	load_adapter "$_cat_name"

	log_info "Testing adapter '$_cat_name' (bin=$ADAPTER_BIN)..."
	if ! has_cmd "$ADAPTER_BIN"; then
		die "Binary '$ADAPTER_BIN' not found in PATH" 6
	fi
	log_success "Binary found"

	_cat_prompt="$(mktemp)"
	_cat_smoke="${ADAPTER_SMOKE_TEST:-Reply with exactly: OK}"
	echo "$_cat_smoke" >"$_cat_prompt"

	log_info "Spawning agent with smoke test prompt..."
	_cat_output="$(mktemp)"

	_cat_cwd="$(pwd)"
	if spawn_agent "$_cat_name" "$_cat_prompt" "$_cat_cwd" >"$_cat_output" 2>&1; then
		log_success "Agent exited successfully"
	else
		_cat_rc=$?
		log_error "Agent exited with code $_cat_rc"
		echo "--- Output ---"
		cat "$_cat_output"
		rm -f "$_cat_prompt" "$_cat_output"
		return "$_cat_rc"
	fi

	_cat_extracted="$(extract_output "$ADAPTER_EXTRACT_TYPE" "$_cat_output")"
	if [ -n "$_cat_extracted" ]; then
		log_success "Extracted output (${#_cat_extracted} chars)"
		echo "--- Extracted ---"
		echo "$_cat_extracted" | head -5
	else
		log_warn "No output extracted"
	fi

	if check_completion "$_cat_output" "$ADAPTER_MARKER" "$ADAPTER_MARKER_TAIL"; then
		log_success "Completion marker detected"
	else
		log_warn "Completion marker NOT detected (expected for smoke test)"
	fi

	rm -f "$_cat_prompt" "$_cat_output"
	log_success "Adapter test complete"
}
