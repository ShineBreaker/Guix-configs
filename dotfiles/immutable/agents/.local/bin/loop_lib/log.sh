# SPDX-FileCopyrightText: 2026 brokenshine <brokenshine@users.noreply.codeberg.org>
# SPDX-License-Identifier: MIT
#
# log.sh — 彩色日志函数
# 支持 NO_COLOR 环境变量关闭颜色

_log_color() {
	if [ "${NO_COLOR:-}" = "" ] && [ -t 2 ]; then
		printf '\033[%sm' "$1"
	fi
}

_log_reset() {
	if [ "${NO_COLOR:-}" = "" ] && [ -t 2 ]; then
		printf '\033[0m'
	fi
}

log_info() {
	_log_color "36"
	printf '[INFO] '
	_log_reset
	printf '%s\n' "$*"
}

log_warn() {
	_log_color "33"
	printf '[WARN] '
	_log_reset
	printf '%s\n' "$*"
}

log_error() {
	_log_color "31"
	printf '[ERROR] '
	_log_reset
	printf '%s\n' "$*"
}

log_success() {
	_log_color "32"
	printf '[OK] '
	_log_reset
	printf '%s\n' "$*"
}

log_debug() {
	if [ "${LOOPCTL_DEBUG:-}" = "1" ]; then
		_log_color "90"
		printf '[DEBUG] '
		_log_reset
		printf '%s\n' "$*"
	fi
}
