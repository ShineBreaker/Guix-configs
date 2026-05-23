#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

# Shared Pi launcher helpers.  Keep runtime state in XDG paths even when Pi
# packages still hard-code ~/.pi or agentDir/npm internally.

set -euo pipefail

pi_resolve_script_path() {
	local source="${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}"
	while [[ -L "${source}" ]]; do
		local dir
		dir="$(cd -P "$(dirname "${source}")" && pwd)"
		source="$(readlink "${source}")"
		[[ "${source}" != /* ]] && source="${dir}/${source}"
	done
	cd -P "$(dirname "${source}")" && pwd
}

pi_init_xdg() {
	export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/.config}"
	export XDG_DATA_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}"
	export XDG_CACHE_HOME="${XDG_CACHE_HOME:-${HOME}/.cache}"

	PI_CONFIG_DIR="${PI_CODING_AGENT_DIR:-${XDG_CONFIG_HOME}/pi}"
	PI_DATA_DIR="${PI_LOCAL_ROOT:-${XDG_DATA_HOME}/pi}"
	PI_CACHE_DIR="${XDG_CACHE_HOME}/pi"
	PI_COMPAT_DOTPI="${PI_DATA_DIR}/data"
	PI_COMPAT_PILENS="${PI_DATA_DIR}/pi-lens"

	export PI_HOME="${PI_CONFIG_DIR}"
	export PI_CODING_AGENT_DIR="${PI_CONFIG_DIR}"
	export PI_CODING_AGENT_SESSION_DIR="${PI_CODING_AGENT_SESSION_DIR:-${PI_DATA_DIR}/sessions}"
	export PI_OFFLINE="${PI_OFFLINE:-1}"

	if [[ -d "${PI_DATA_DIR}/node_modules/@earendil-works/pi-coding-agent" ]]; then
		export PI_PACKAGE_DIR="${PI_PACKAGE_DIR:-${PI_DATA_DIR}/node_modules/@earendil-works/pi-coding-agent}"
	fi
}

pi_seed_lockfile() {
	local src_lock=""
	if [[ -L "${PI_DATA_DIR}/package.json" ]]; then
		src_lock="$(cd "${PI_DATA_DIR}" && cd "$(dirname "$(readlink package.json)")" && pwd)/pnpm-lock.yaml"
	fi

	if [[ -n "${src_lock}" && -f "${src_lock}" && ! -f "${PI_DATA_DIR}/pnpm-lock.yaml" ]]; then
		cp "${src_lock}" "${PI_DATA_DIR}/pnpm-lock.yaml"
	fi
}

pi_sync_lockfile() {
	local src_lock=""
	if [[ -L "${PI_DATA_DIR}/package.json" ]]; then
		src_lock="$(cd "${PI_DATA_DIR}" && cd "$(dirname "$(readlink package.json)")" && pwd)/pnpm-lock.yaml"
	fi

	if [[ -n "${src_lock}" && -f "${PI_DATA_DIR}/pnpm-lock.yaml" ]]; then
		cp "${PI_DATA_DIR}/pnpm-lock.yaml" "${src_lock}"
	fi
}

pi_ensure_installed() {
	pi_init_xdg

	if [[ -x "${PI_DATA_DIR}/node_modules/.bin/pi" ]]; then
		cd "${PI_DATA_DIR}" && pwd
		return 0
	fi

	if ! command -v pnpm &>/dev/null; then
		echo "pnpm is not installed. Please install pnpm first." >&2
		return 1
	fi

	if [[ ! -d "${PI_DATA_DIR}" ]]; then
		echo "Pi local root not found at ${PI_DATA_DIR}." >&2
		return 1
	fi

	pi_seed_lockfile
	echo "Installing Pi dependencies..." >&2
	cd "${PI_DATA_DIR}" && pnpm install
	pi_sync_lockfile

	cd "${PI_DATA_DIR}" && pwd
}

pi_copy_dir_once() {
	local src="$1"
	local dst="$2"

	if [[ -d "${src}" ]]; then
		mkdir -p "${dst}"
		if ! find "${dst}" -mindepth 1 -maxdepth 1 -print -quit | grep -q .; then
			cp -a "${src}/." "${dst}/"
		fi
	fi
}

pi_link_force() {
	local src="$1"
	local dst="$2"

	mkdir -p "$(dirname "${dst}")"
	if [[ -L "${dst}" || -f "${dst}" ]]; then
		unlink -- "${dst}" 2>/dev/null || rm -f -- "${dst}"
	elif [[ -d "${dst}" ]]; then
		rm -rf -- "${dst}"
	elif [[ -e "${dst}" ]]; then
		rm -f -- "${dst}"
	fi
	ln -sfnT "${src}" "${dst}"
}

pi_prepare_compat_tree() {
	pi_init_xdg

	mkdir -p "${PI_DATA_DIR}"
	local lock_fd
	exec {lock_fd}>"${PI_DATA_DIR}/.compat-tree.lock"
	flock "${lock_fd}"

	mkdir -p \
		"${PI_CONFIG_DIR}" \
		"${PI_DATA_DIR}" \
		"${PI_DATA_DIR}/npm" \
		"${PI_CACHE_DIR}" \
		"${PI_CODING_AGENT_SESSION_DIR}" \
		"${PI_COMPAT_DOTPI}/agent" \
		"${PI_COMPAT_DOTPI}/pi-acp" \
		"${PI_COMPAT_PILENS}"

	# Pi's package manager currently installs npm packages under agentDir/npm.
	# Keep existing installs usable, then bind that path to XDG data in bwrap.
	pi_copy_dir_once "${PI_CONFIG_DIR}/npm" "${PI_DATA_DIR}/npm"

	if [[ -d "${HOME}/.pi" && ! -e "${PI_COMPAT_DOTPI}/.migrated-from-home" ]]; then
		local item name
		for item in "${HOME}/.pi"/*; do
			[[ -e "${item}" ]] || continue
			name="$(basename "${item}")"
			[[ "${name}" == "agent" ]] && continue
			[[ -e "${PI_COMPAT_DOTPI}/${name}" ]] && continue
			cp -a "${item}" "${PI_COMPAT_DOTPI}/${name}"
		done
		: >"${PI_COMPAT_DOTPI}/.migrated-from-home"
	fi

	# --- pi-lens compat tree ---
	if [[ -d "${HOME}/.pi-lens" && ! -e "${PI_COMPAT_PILENS}/.migrated-from-home" ]]; then
		local pl_item pl_name
		for pl_item in "${HOME}/.pi-lens"/*; do
			[[ -e "${pl_item}" ]] || continue
			pl_name="$(basename "${pl_item}")"
			[[ -e "${PI_COMPAT_PILENS}/${pl_name}" ]] && continue
			cp -a "${pl_item}" "${PI_COMPAT_PILENS}/${pl_name}"
		done
		: >"${PI_COMPAT_PILENS}/.migrated-from-home"
	fi

	for name in settings.json models.json auth.json keybindings.json APPEND_SYSTEM.md SYSTEM.md; do
		[[ -e "${PI_CONFIG_DIR}/${name}" ]] && pi_link_force "${PI_CONFIG_DIR}/${name}" "${PI_COMPAT_DOTPI}/agent/${name}"
	done

	for name in agents extensions prompts themes tools bin; do
		[[ -e "${PI_CONFIG_DIR}/${name}" ]] && pi_link_force "${PI_CONFIG_DIR}/${name}" "${PI_COMPAT_DOTPI}/agent/${name}"
	done

	if [[ -d "${XDG_CONFIG_HOME}/agents/skills" ]]; then
		pi_link_force "${XDG_CONFIG_HOME}/agents/skills" "${PI_COMPAT_DOTPI}/agent/skills"
	fi

	pi_link_force "${PI_DATA_DIR}/npm" "${PI_COMPAT_DOTPI}/agent/npm"
	pi_link_force "${PI_CODING_AGENT_SESSION_DIR}" "${PI_COMPAT_DOTPI}/agent/sessions"
	pi_link_force "${PI_CACHE_DIR}/pi-debug.log" "${PI_COMPAT_DOTPI}/agent/pi-debug.log"
	pi_link_force "${PI_CACHE_DIR}/pi-crash.log" "${PI_COMPAT_DOTPI}/agent/pi-crash.log"

	flock -u "${lock_fd}"
	exec {lock_fd}>&-
}

pi_exec_xdg() {
	local target="$1"
	shift

	pi_prepare_compat_tree

	if [[ "${PI_XDG_BWRAP:-1}" != "0" && "${PI_XDG_BWRAP_ACTIVE:-0}" != "1" ]] && command -v bwrap &>/dev/null; then
		mkdir -p "${HOME}/.pi" "${HOME}/.pi-lens"

		bwrap \
			--die-with-parent \
			--dev-bind / / \
			--bind "${PI_COMPAT_DOTPI}" "${HOME}/.pi" \
			--bind "${PI_COMPAT_PILENS}" "${HOME}/.pi-lens" \
			--bind "${PI_DATA_DIR}/npm" "${PI_CONFIG_DIR}/npm" \
			--setenv HOME "${HOME}" \
			--setenv XDG_CONFIG_HOME "${XDG_CONFIG_HOME}" \
			--setenv XDG_DATA_HOME "${XDG_DATA_HOME}" \
			--setenv XDG_CACHE_HOME "${XDG_CACHE_HOME}" \
			--setenv PI_HOME "${PI_HOME}" \
			--setenv PI_CODING_AGENT_DIR "${PI_CODING_AGENT_DIR}" \
			--setenv PI_CODING_AGENT_SESSION_DIR "${PI_CODING_AGENT_SESSION_DIR}" \
			--setenv PI_LOCAL_ROOT "${PI_DATA_DIR}" \
			--setenv PI_OFFLINE "${PI_OFFLINE}" \
			--setenv PI_PACKAGE_DIR "${PI_PACKAGE_DIR:-}" \
			--setenv PI_XDG_BWRAP_ACTIVE "1" \
			"${target}" "$@"
		local rc=$?

		rmdir "${HOME}/.pi" "${HOME}/.pi-lens" 2>/dev/null || true
		return $rc
	fi

	exec "${target}" "$@"
}
