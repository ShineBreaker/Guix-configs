#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

# context-select.sh — zcode / omp / crush / hermes 四方共享的上下文注入决策核（单一真相源）
#
# 注入内容分层（源：~/.config/agents/context/）：
#   00-core.md   跨领域通用原则，恒注入
#   INDEX.md     领域路由表（带红线摘要），恒注入；crush 等无门控端靠它指引手动拉取
#   domains/*.md 领域专用原则，按门控注入
#
# 消费者（适配器只做协议转换，判定语义集中于此）：
#   - zcode   dotfiles/mutable/agents/zcode/.zcode/hooks/session-start.sh（SessionStart）
#   - omp     dotfiles/mutable/agents/omp/.config/omp/extensions/global-context/index.ts（before_agent_start）
#   - hermes  dotfiles/mutable/agents/hermes/.local/share/hermes/plugins/global-context/__init__.py
#   - crush   无 hook 机制：context_paths 静态声明恒注入集，由 --check 校验引用不烂
#
# CLI（stdout 一行一个绝对路径；select/list 模式退出码恒 0，--check 失败退出 1）：
#   context-select.sh [--platform zcode|omp|crush|hermes] [--cwd DIR] [--explain]
#   context-select.sh --list-all
#   context-select.sh --check
#
# 环境变量 CONTEXT_DIR：覆盖 context 目录（默认 $XDG_CONFIG_HOME/agents/context），
# 供 blue home 部署前用仓库源树验证。
#
# 门控语义（多条件用 + 叠加，全部满足才注入）：
#   always              全平台恒注入
#   git                 --cwd 在 git 仓库内（向上 ≤8 层找 .git）
#   platform:p1,p2,...  仅列出的平台注入
# 新增领域三步联动（--check 校验一致性）：domains/ 加文件 + 映射表加行 + INDEX.md 加条目。

set -uo pipefail

CTX_BASE="${XDG_CONFIG_HOME:-$HOME/.config}/agents"
CTX_DIR="${CONTEXT_DIR:-$CTX_BASE/context}"

# ─── 注入映射表（有序：恒注入在前，域文件在后）───────────────────────────────
INJECT_MAP=(
	"00-core.md|always"
	"INDEX.md|always"
	"domains/coding.md|git"
)

in_git_repo() { # $1=起点目录
	local d="${1:-$PWD}"
	d="$(realpath -ms "$d" 2>/dev/null || printf '%s' "$d")"
	for _ in 1 2 3 4 5 6 7 8; do
		[[ -e "$d/.git" ]] && return 0
		[[ "$d" == "/" || -z "$d" ]] && return 1
		d="$(dirname "$d")"
	done
	return 1
}

passes() { # $1=gate $2=platform $3=cwd
	local part
	for part in ${1//+/ }; do
		case "$part" in
		always) ;;
		git) in_git_repo "$3" || return 1 ;;
		platform:*) [[ ",${part#platform:}," == *",$2,"* ]] || return 1 ;;
		*) return 1 ;;
		esac
	done
	return 0
}

explain() { printf '  %s %s（%s）\n' "$1" "$2" "$3" >&2; }

select_files() { # $1=platform $2=cwd $3=explain(0/1)
	local entry file gate
	for entry in "${INJECT_MAP[@]}"; do
		file="${entry%%|*}" gate="${entry#*|}"
		if passes "$gate" "$1" "$2"; then
			printf '%s\n' "$CTX_DIR/$file"
			if [[ "$3" == 1 ]]; then explain '✓' "$file" "$gate"; fi
		else
			if [[ "$3" == 1 ]]; then explain '－' "$file" "$gate 未满足"; fi
		fi
	done
	return 0
}

list_all() { # 映射表全集（不做门控判定）；消费者用它注册 section 集，渲染时再以 select 结果门控
	local entry
	for entry in "${INJECT_MAP[@]}"; do
		printf '%s\n' "$CTX_DIR/${entry%%|*}"
	done
}

# ─── 一致性自检 ───────────────────────────────────────────────────────────────
# 抓两类历史事故：文件改名/移动后引用断链（crush 曾断供）、加域文件忘登记三步联动。

index_domains() { # INDEX.md 的 `## <name> —` 条目集合
	awk '/^## [a-z0-9-]+ —/ { s = $0; sub(/^## /, "", s); sub(/ —.*/, "", s); print s }' \
		"$CTX_DIR/INDEX.md" 2>/dev/null
}

check() {
	local fail=0 entry file name
	local -A seen=()

	# 1. 映射表引用的文件存在
	for entry in "${INJECT_MAP[@]}"; do
		file="${entry%%|*}"
		if [[ ! -f "$CTX_DIR/$file" ]]; then
			echo "✗ 映射表引用的文件不存在：$CTX_DIR/$file"
			fail=1
		fi
		[[ "$file" == domains/* ]] && seen["$(basename "$file" .md)"]=1
	done

	# 2. domains/ 目录实际文件 == 映射表登记集合（加文件忘登记 → 永不注入，静默漏）
	local -A disk=()
	for file in "$CTX_DIR"/domains/*.md; do
		[[ -f "$file" ]] || continue
		name="$(basename "$file" .md)"
		disk["$name"]=1
		if [[ -z "${seen[$name]:-}" ]]; then
			echo "✗ domains/$name.md 未登记进 context-select.sh 映射表（永不注入）；登记或删除"
			fail=1
		fi
	done
	for name in "${!seen[@]}"; do
		if [[ -z "${disk[$name]:-}" ]]; then
			echo "✗ 映射表登记的 domains/$name.md 在目录中不存在"
			fail=1
		fi
	done

	# 3. INDEX.md 条目集合 == domains/ 文件集合，且条目给出文件路径
	if [[ -f "$CTX_DIR/INDEX.md" ]]; then
		local -A idx=()
		while IFS= read -r name; do
			[[ -n "$name" ]] || continue
			idx["$name"]=1
			if ! grep -q "文件：.*domains/$name\.md" "$CTX_DIR/INDEX.md"; then
				echo "✗ INDEX.md 条目「$name」缺「文件：…domains/$name.md」行"
				fail=1
			fi
		done < <(index_domains)
		for name in "${!disk[@]}"; do
			[[ -z "${idx[$name]:-}" ]] && {
				echo "✗ domains/$name.md 未收录进 INDEX.md"
				fail=1
			}
		done
		for name in "${!idx[@]}"; do
			[[ -z "${disk[$name]:-}" ]] && {
				echo "✗ INDEX.md 条目「$name」无对应 domains/$name.md"
				fail=1
			}
		done
	else
		echo "✗ $CTX_DIR/INDEX.md 不存在"
		fail=1
	fi

	# 4. crush：context_paths 引用存在，且覆盖恒注入集（basename 比较，~ 已展开）
	local crush_json="${XDG_CONFIG_HOME:-$HOME/.config}/crush/crush.json"
	if [[ -f "$crush_json" ]]; then
		local p target found_core=0 found_index=0
		while IFS= read -r p; do
			[[ -z "$p" ]] && continue
			target="${p/#\~/$HOME}"
			[[ -f "$target" ]] || {
				echo "✗ crush context_paths 指向不存在的文件：$p"
				fail=1
			}
			case "$(basename "$target")" in
			00-core.md) found_core=1 ;;
			INDEX.md) found_index=1 ;;
			esac
		done < <(jq -r '.options.context_paths[]?' "$crush_json" 2>/dev/null)
		[[ $found_core -eq 1 && $found_index -eq 1 ]] || {
			echo "✗ crush context_paths 未覆盖恒注入集（00-core.md / INDEX.md）"
			fail=1
		}
	else
		echo "－ crush 配置不可读（$crush_json），跳过 crush 校验"
	fi

	# 5. omp：配置存在于扩展查找路径（配置根）且启用
	local omp_json="${XDG_CONFIG_HOME:-$HOME/.config}/omp/global-context.json"
	if [[ -f "$omp_json" ]]; then
		[[ "$(jq -r '.enabled' "$omp_json" 2>/dev/null)" == "true" ]] ||
			echo "－ omp global-context 已禁用（enabled != true）"
	else
		echo "✗ omp 配置不在扩展查找路径：$omp_json"
		fail=1
	fi

	# 6. hermes：插件存在（分类判定已内嵌，无需校验清单文件）
	local hermes_plugin="${HERMES_HOME:-$HOME/.local/share/hermes}/plugins/global-context/__init__.py"
	[[ -f "$hermes_plugin" ]] || echo "－ hermes global-context 插件未部署，跳过"

	[[ $fail -eq 0 ]] && echo "✓ context 注入体系一致性检查通过（$CTX_DIR）"
	return $fail
}

# ─── 入口 ─────────────────────────────────────────────────────────────────────

PLATFORM="generic" CWD="$PWD" EXPLAIN=0 MODE="select"
while [[ $# -gt 0 ]]; do
	case "$1" in
	--platform)
		PLATFORM="${2:-}"
		shift 2
		;;
	--cwd)
		CWD="${2:-}"
		shift 2
		;;
	--explain)
		EXPLAIN=1
		shift
		;;
	--list-all)
		MODE="list-all"
		shift
		;;
	--check)
		MODE="check"
		shift
		;;
	*)
		printf 'usage: %s [--platform P] [--cwd DIR] [--explain] | --list-all | --check\n' "$0" >&2
		exit 64
		;;
	esac
done

case "$MODE" in
check) check ;;
list-all) list_all ;;
*) select_files "$PLATFORM" "$CWD" "$EXPLAIN" ;;
esac
