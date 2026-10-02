#!/usr/bin/env bash
# doc-format.sh — 文档格式化编排：doc-punct 管标点，prettier 管 Markdown 结构
# 文档：docs/scripts/doc-format.md
set -euo pipefail

die() { printf '%s: %s\n' "doc-format:" "$1" >&2; exit "${2:-1}"; }

usage() {
	cat <<'EOF'
按仓库文档规范格式化 Markdown：doc-punct.py 规范中文标点与中英间距，
prettier 统一 Markdown 结构（表格列宽、列表缩进、末尾换行等）。

  doc-format.sh                处理全部仓库自有文档
  doc-format.sh FILE...        处理指定文件
  doc-format.sh --check        只报告待处理项，有改动则退出 1

不带 FILE 时经 doc-punct.py --list 取清单——那份清单同时是 vendored 与
agent skills 的排除边界（doc-punct.py 的 EXCLUDE），不在本脚本复制一份。
EOF
}

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd -- "$REPO_ROOT"
DOC_PUNCT="$REPO_ROOT/tools/doc-punct.py"
[[ -f "$DOC_PUNCT" ]] || die "找不到 $DOC_PUNCT"

check=0
declare -a given=()
for arg in "$@"; do
	case "$arg" in
	--check) check=1 ;;
	-h | --help)
		usage
		exit 0
		;;
	-*)
		usage >&2
		die "未知选项：$arg" 64
		;;
	*) given+=("$arg") ;;
	esac
done

# CLAUDE.md 是指向 AGENTS.md 的软链：按 realpath 去重，既避免同一文件处理两遍，
# 也绕开 prettier 对「显式指定的软链」直接报错退出的行为。
declare -a files=()
declare -A seen=()
add() {
	local r
	r="$(realpath -m -- "$1")"
	[[ -f "$r" ]] || die "文件不存在：$1"
	if [[ -n "${seen[$r]:-}" ]]; then return 0; fi
	seen["$r"]=1
	files+=("${r#"$REPO_ROOT"/}")
}

if ((${#given[@]} == 0)); then
	while IFS= read -r f; do
		[[ -n "$f" ]] && add "$f"
	done < <(python3 "$DOC_PUNCT" --list)
else
	for f in "${given[@]}"; do add "$f"; done
fi

((${#files[@]} > 0)) || die "没有可处理的文档"

# 两级顺序不可颠倒：doc-punct 改标点会改变表格单元的显示宽度，prettier 必须
# 在其后按最终宽度对齐列宽，否则第一遍跑完仍有表格待对齐，要跑第二遍才收敛。
declare -a md=()
for f in "${files[@]}"; do
	if [[ "$f" == *.md ]]; then md+=("$f"); fi
done

rc=0

printf '== 1/2 标点与中英间距（doc-punct.py）==\n'
if ((check)); then
	python3 "$DOC_PUNCT" --check "${files[@]}" || rc=1
else
	python3 "$DOC_PUNCT" "${files[@]}"
fi

if ((${#md[@]} > 0)); then
	command -v prettier >/dev/null ||
		die "找不到 prettier（配置包里是 prettier-bin）；只跑标点：python3 tools/doc-punct.py"
	printf '\n== 2/2 Markdown 结构（prettier）==\n'
	# --prose-wrap preserve 与 .prettierrc.json 重复是有意的：仓库规范禁止把正文
	# 折行，而 prettier 默认按 printWidth 重排正文，必须在调用点钉死。
	if ((check)); then
		prettier --prose-wrap preserve --check "${md[@]}" || rc=1
	else
		prettier --prose-wrap preserve --write "${md[@]}"
	fi
fi

if ((check)) && ((rc == 0)); then
	printf '\n全部文档已符合规范\n'
fi
exit "$rc"