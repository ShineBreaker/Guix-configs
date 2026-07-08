#!/usr/bin/env bash
# audit-emacs-config.sh — literal-config 静态审计脚本
#
# 用途:扫描 emacs.org 内联 src 块 + lisp/*.el,产出五类问题清单,供人工判定。
# 用法:bash docs/domain/audit-emacs-config.sh > audit-output.txt
#
# 五类检查项(对应 PLAN §C-1):
#   1. 同名 defun/defvar/defcustom 重复定义(同名 ≥ 2)
#   2. literal/set-key 悬空绑定(注册命令无对应 defun 实现)
#   3. defvar/defun 声明但全文零引用的疑似死代码
#   4. 命名不一致:literal/xxx vs literal-xxx 混用;defvar/defun 同名注入点
#   5. tangle 目标非 main.el 的 src 块
#
# 注意:输出含误报;需人工逐条对照源码判定真问题 / 误报。

set -uo pipefail
# 注:不开 -e。审计脚本里很多 grep 在「无匹配」时返回 1,属正常;开 -e 会误中断。

# 脚本位于 literal-config/docs/domain/,项目根 = 上溯两级
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT_DIR"

ORG_FILE="emacs.org"
LISP_DIR="lisp"

# ── 预处理:从 emacs.org 抽出所有 emacs-lisp src 块拼接成临时文件 ──
# 只提取 #+begin_src emacs-lisp ... #+end_src 之间的内容(不含块标记行)
TMP_ORG_CODE="$(mktemp)"
trap 'rm -f "$TMP_ORG_CODE"' EXIT

awk '
  /^#\+begin_src emacs-lisp/ { in_block=1; next }
  /^#\+begin_src/            { in_block=0; next }   # 非 emacs-lisp 块跳过标记
  /^#\+end_src/              { in_block=0; next }
  in_block                   { print }
' "$ORG_FILE" >"$TMP_ORG_CODE"

# 全部待审计源码:org 抽出代码 + lisp/*.el。src_label() 给出行号溯源标签。
src_label() {
	if [[ "$1" == "$TMP_ORG_CODE" ]]; then
		echo "emacs.org(src)"
	else
		echo "$1"
	fi
}

emit() { printf '%s\n' "$*"; }
separator() {
	emit
	emit "────────────────────────────────────────────────────────────────"
}

# ═══════════════════════════════════════════════════════════════════════
# 检查项 1:同名 defun/defvar/defcustom 重复定义
# ═══════════════════════════════════════════════════════════════════════
check_duplicate_defs() {
	emit "## [1] 同名 defun/defvar/defcustom 重复定义(同名出现 ≥ 2)"
	emit
	local tmp sym_defs
	tmp="$(mktemp)"
	sym_defs="$(mktemp)"
	# 汇总 (defun|defvar|defcustom NAME,带来源:行号
	for f in "$TMP_ORG_CODE" "$LISP_DIR"/*.el; do
		local label
		label="$(src_label "$f")"
		grep -noE '^\s*\(\s*(defun|defvar|defcustom)\s+[[:alnum:]:/<>_-]+' "$f" |
			sed -E "s|^\([0-9]+\):||; s|^\s*\(\s*(defun\|defvar\|defcustom)\s+||" \
				>/dev/null 2>&1 || true
		# 上行 sed 仅作格式规整;用 awk 同时取行号 + 符号
		awk -v label="$label" '
      /^[[:space:]]*\([[:space:]]*(defun|defvar|defcustom)[[:space:]]+/ {
        rest=$0
        sub(/^[[:space:]]*\([[:space:]]*(defun|defvar|defcustom)[[:space:]]+/, "", rest)
        sym=rest; sub(/[[:space:]\(\)].*$/, "", sym)
        if (sym != "") printf "%s\t%s\t%s\n", sym, label, FNR
      }
    ' "$f"
	done | sort >"$sym_defs"

	local dupes
	dupes="$(cut -f1 "$sym_defs" | sort | uniq -d)"
	if [[ -z "$dupes" ]]; then
		emit "  (未发现同名重复定义)"
	else
		while IFS= read -r sym; do
			emit "  [$sym]"
			grep -F "$(printf '%s\t' "$sym")" "$sym_defs" | while IFS=$'\t' read -r _ src line; do
				emit "      $src:$line"
			done
		done <<<"$dupes"
	fi
	rm -f "$tmp" "$sym_defs"
}

# ═══════════════════════════════════════════════════════════════════════
# 检查项 2:literal/set-key 悬空绑定
# ═══════════════════════════════════════════════════════════════════════
check_dangling_bindings() {
	emit "## [2] literal/set-key 悬空绑定(注册命令无对应 defun 实现)"
	emit
	emit "  literal/set-key 调用列表(人工核对每个命令符号是否在 defun 全集中):"
	local count=0
	for f in "$TMP_ORG_CODE" "$LISP_DIR"/*.el; do
		local label
		label="$(src_label "$f")"
		# 打印含 literal/set-key 的行,带行号
		local hits
		hits="$(grep -nF 'literal/set-key' "$f" || true)"
		if [[ -n "$hits" ]]; then
			printf '  %s:%s\n' "$label" "$hits"
		fi
		count=$((count + $(printf '%s\n' "$hits" | grep -c .)))
	done
	emit
	emit "  literal/set-key 调用总数: $count"
	emit
	emit "  全部 defun 符号(对照用):"
	for f in "$TMP_ORG_CODE" "$LISP_DIR"/*.el; do
		grep -oE '\(\s*defun[[:space:]]+[[:alnum:]:/<>_-]+' "$f" |
			sed -E 's|\(\s*defun\s+||'
	done | sort -u | sed 's/^/    /'
}

# ═══════════════════════════════════════════════════════════════════════
# 检查项 3:疑似死代码(声明但全文零引用)
# ═══════════════════════════════════════════════════════════════════════
check_dead_code() {
	emit "## [3] 疑似死代码(defun/defvar 声明但全文零引用)"
	emit
	emit "  注:零引用 ≠ 死代码。注入点 defvar 后续 setq、命令被绑定到键、"
	emit "      被 use-package :commands 引用等都算「引用」。逐条人工判定。"
	emit
	local syms
	syms="$(mktemp)"
	for f in "$TMP_ORG_CODE" "$LISP_DIR"/*.el; do
		local label
		label="$(src_label "$f")"
		awk -v label="$label" '
      /^[[:space:]]*\([[:space:]]*defun[[:space:]]+/ {
        rest=$0; sub(/.*defun[[:space:]]+/, "", rest); sub(/[[:space:]\(\)].*$/, "", rest)
        if (rest != "") printf "%s\t%s\t%s\tdefun\n", rest, label, FNR
      }
      /^[[:space:]]*\([[:space:]]*defvar[[:space:]]+/ {
        rest=$0; sub(/.*defvar[[:space:]]+/, "", rest); sub(/[[:space:]\(\)].*$/, "", rest)
        if (rest != "") printf "%s\t%s\t%s\tdefvar\n", rest, label, FNR
      }
    ' "$f"
	done | sort -u >"$syms"

	while IFS=$'\t' read -r sym src line kind; do
		# 引用计数:全文出现该符号的行数;声明行数 = 1(defvar/defun 出现 1 次)
		local refs decls real
		refs="$(grep -hE "(^|[^[:alnum:]:/<>_-])${sym}([^[:alnum:]:/<>_-]|$)" "$TMP_ORG_CODE" "$LISP_DIR"/*.el 2>/dev/null | wc -l)"
		decls="$(grep -hE "\(\s*def(un|var)\s+${sym}([^[:alnum:]:/<>_-]|$)" "$TMP_ORG_CODE" "$LISP_DIR"/*.el 2>/dev/null | wc -l)"
		real=$((refs - decls))
		if [[ "$real" -le 0 ]]; then
			emit "  [$kind] $sym  ($src:$line)  — 引用 $refs,声明 $decls(净 $real)"
		fi
	done <"$syms"
	rm -f "$syms"
}

# ═══════════════════════════════════════════════════════════════════════
# 检查项 4:命名不一致
# ═══════════════════════════════════════════════════════════════════════
check_naming_consistency() {
	emit "## [4] 命名不一致检查"
	emit
	emit "### 4a. defvar/defun 同名注入点(Lisp-2 共存) — 应已在 CONTEXT.md/ADR 0001 标注"
	emit
	local fns vars both
	fns="$(for f in "$TMP_ORG_CODE" "$LISP_DIR"/*.el; do
		grep -oE '\(\s*defun[[:space:]]+[[:alnum:]:/<>_-]+' "$f" | awk '{print $NF}'
	done | sort -u)"
	vars="$(for f in "$TMP_ORG_CODE" "$LISP_DIR"/*.el; do
		grep -oE '\(\s*defvar[[:space:]]+[[:alnum:]:/<>_-]+' "$f" | awk '{print $NF}'
	done | sort -u)"
	both="$(comm -12 <(printf '%s\n' "$fns") <(printf '%s\n' "$vars"))"
	if [[ -z "$both" ]]; then
		emit "  (未发现同名 defun+defvar 共存)"
	else
		while IFS= read -r sym; do
			[[ -z "$sym" ]] && continue
			emit "  $sym  (defun + defvar 同名 = 注入点,确认文档已标注)"
		done <<<"$both"
	fi
	emit
	emit "### 4b. literal/xxx (slash 命名空间,helper/命令) 与 literal-xxx (dash,模块名/require) 混用对照"
	emit
	local slash_syms dash_syms
	slash_syms="$(grep -hEo 'literal/[[:alnum:]:/<>_-]+' "$TMP_ORG_CODE" "$LISP_DIR"/*.el | sort -u)"
	dash_syms="$(grep -hEo 'literal-[[:alnum:]]+' "$TMP_ORG_CODE" "$LISP_DIR"/*.el | sort -u)"
	emit "  literal/ 符号数: $(printf '%s\n' "$slash_syms" | grep -c .)"
	emit "  literal- 符号数: $(printf '%s\n' "$dash_syms" | grep -c .)"
}

# ═══════════════════════════════════════════════════════════════════════
# 检查项 5:tangle 目标一致性
# ═══════════════════════════════════════════════════════════════════════
check_tangle_targets() {
	emit "## [5] tangle 目标一致性(预期统一 main.el)"
	emit
	emit "### 5a. 顶层 #+PROPERTY 默认 tangle:"
	grep -nE '^#\+PROPERTY.*header-args.*:tangle' "$ORG_FILE" | sed 's/^/  /' || emit "  (无顶层默认)"
	emit
	emit "### 5b. 块级 :tangle 覆写(非默认 main.el 的需核对):"
	local found=0
	while IFS=: read -r ln _; do
		local content
		content="$(sed -n "${ln}p" "$ORG_FILE")"
		# 只报告显式覆写为 no 或其他 .el 的块
		if printf '%s' "$content" | grep -qE ':tangle[[:space:]]+(no|[a-z._/-]+\.el)'; then
			emit "  $ORG_FILE:$ln  $content"
			found=1
		fi
	done < <(grep -nE '^#\+begin_src' "$ORG_FILE")
	if [[ "$found" -eq 0 ]]; then
		emit "  (所有 src 块沿用默认 :tangle main.el,无分叉)"
	fi
	emit
	emit "### 5c. src 块配对统计:"
	local begins ends
	begins="$(grep -cE '^#\+begin_src' "$ORG_FILE")"
	ends="$(grep -cE '^#\+end_src' "$ORG_FILE")"
	emit "  begin_src = $begins, end_src = $ends (应相等)"
}

# ═══════════════════════════════════════════════════════════════════════
# 主流程
# ═══════════════════════════════════════════════════════════════════════
emit "literal-config 静态审计报告"
emit "生成时间: $(date '+%Y-%m-%d %H:%M:%S')"
emit "扫描对象: emacs.org(src 块) + lisp/*.el ($(ls "$LISP_DIR"/*.el | wc -l) 个文件)"
emit

separator
check_duplicate_defs
separator
check_dangling_bindings
separator
check_dead_code
separator
check_naming_consistency
separator
check_tangle_targets
separator
emit "审计结束 — 以上条目含误报,逐条人工判定真问题 / 误报。"
