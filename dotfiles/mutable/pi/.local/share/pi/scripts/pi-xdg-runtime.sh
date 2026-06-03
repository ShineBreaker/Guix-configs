#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

# Shared Pi launcher helpers.  Pi now honours PI_HOME / PI_CODING_AGENT_DIR /
# PI_LOCAL_ROOT, so runtime state lives entirely under XDG paths.

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
		# Skip if the source lock already resolves to the same file (stow
		# symlinks point the runtime path straight into the source repo, so
		# pnpm install would write through to it directly).
		if [[ "${src_lock}" -ef "${PI_DATA_DIR}/pnpm-lock.yaml" ]]; then
			return 0
		fi
		cp "${src_lock}" "${PI_DATA_DIR}/pnpm-lock.yaml"
	fi
}

pi_sync_lockfile() {
	local src_lock=""
	if [[ -L "${PI_DATA_DIR}/package.json" ]]; then
		src_lock="$(cd "${PI_DATA_DIR}" && cd "$(dirname "$(readlink package.json)")" && pwd)/pnpm-lock.yaml"
	fi

	if [[ -z "${src_lock}" || ! -f "${PI_DATA_DIR}/pnpm-lock.yaml" ]]; then
		return 0
	fi

	# pnpm update wrote through the symlink straight into the source repo —
	# nothing to copy back.
	if [[ -e "${src_lock}" && "${PI_DATA_DIR}/pnpm-lock.yaml" -ef "${src_lock}" ]]; then
		return 0
	fi

	cp "${PI_DATA_DIR}/pnpm-lock.yaml" "${src_lock}"
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
