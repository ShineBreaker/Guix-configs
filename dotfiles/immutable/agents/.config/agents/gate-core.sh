#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

# gate-core.sh — zcode / crush / pi / hermes 四方 gate 共享的决策核（单一真相源）
#
# 规则源：anchors.json 两级 ratchet 合并（本目录 anchors-lib.sh 的
# load_merged_anchors；全局 ~/.config/agents/anchors.json + 项目 .agents/anchors.json）。
# 全部判定语义集中于此；四方适配器只做协议转换：
#   - zcode   dotfiles/mutable/agents/zcode/.zcode/hooks/{bash,edit}-gate.sh
#   - crush   dotfiles/immutable/agents/.config/crush/hooks/{bash,edit}-gate.sh
#   - pi      dotfiles/mutable/agents/omp/.config/omp/extensions/pi-gate/index.ts
#   - hermes  dotfiles/mutable/agents/hermes/.local/share/hermes/plugins/gate/__init__.py
#
# CLI（stdout 行协议，每行 `TYPE<TAB>payload`；退出码恒 0，进程级失败=异常）：
#   gate-core.sh bash <cmd>    # Bash 工具命令判定
#   gate-core.sh edit <file>   # 写入判定；待检内容从 stdin 读（可为空）
# 环境变量 GATE_CWD：anchors 层级定位起点（默认 $PWD）。
#
# 行类型：
#   BLOCK      硬拦截（payload 为理由）
#   SENSITIVE  敏感信息命中（crush 协议映射 exit 49）
#   AUTO_ALLOW 只读白名单命中（适配器可输出 auto-approve；pi 忽略）
#   REWRITTEN  改写后的命令（zcode 不支持改写，转提示）
#   NOTES / RM_HINT / REDIRECT / HINT   非阻塞提示
#
# 安全不变量（历史绕过教训，改动前先读）：
#   * 冻结命令按「命令位置词序列」匹配：第一个词，或 ; & | ( ) ` 、
#     ` -- ` 、换行之后的词。参数/字符串/heredoc 正文里的冻结词不再命中
#     （误报主源：commit message、文档字符串）。词序列匹配前剥引号，
#     堵 `reb''uild` 类拆分；片段首词 basename 归一化，堵
#     `/run/.../bin/sudo` 类完整路径绕过；再执行通道（sh -c / xargs /
#     find -exec …）的段内子串兜底堵引号包裹的间接执行；`$(` `)` 视为
#     命令边界，命令替换体内的冻结词照常命中。解释器 heredoc
#     （bash <<EOF 等）的正文会被执行，保留进片段流参与匹配。
#   * 明确放弃的极端 case：`$(printf %s su)do` 这类命令替换输出拼接
#     成冻结词的形态（运行时才存在，静态可见即回全文子串=误报之源；
#     系对抗性构造，非 agent 自然行为）；解释器语言代码内部动态拼接
#     冻结词（os.system("sudo …") 类）同理不追。
#   * --dry-run 豁免是片段级的：仅剔除「blue 前缀且带 --dry-run」的
#     片段，其余片段照常检查；`sudo ... --dry-run` 这类把 --dry-run
#     当免死金牌的不豁免。
#   * edit 走双路径：逻辑路径（不解析 symlink）做 meta-frozen / 部署位置
#     检查——~/.config 下大量路径是 store 软链，物理解析会让这两类保护
#     落空；物理路径（解析 symlink）做 frozen_paths / frozen_globs——防
#     经 /tmp 等中转软链写入冻结目标。任一路径命中即拦。
#   * 词法类检查（交互式 / git / rm / 白名单）只对原始命令做精确匹配，
#     不做归一化——避免 `echo "vim tips"` 这类字符串内容被误拦（rm 的
#     路径形态检测除外，已排除引号内形态）。

set -uo pipefail
# 不用 -e：单个检查工具异常（如 jq 输出非预期）不应中断后续检查

SELF="$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")"
LIB_DIR="$(dirname "$SELF")"
DEFAULT_MERGED='{"frozen_commands":["sudo"],"frozen_paths":[],"frozen_globs":[],"interactive_commands":[],"bare_repl_commands":[],"sensitive_patterns":[],"redirect_conventions":{},"rewrite":{},"path_hints":{},"builtin_rewrite":true,"human_only_actions":[],"anchor_measurements":[]}'

# lib 定位：部署位置优先——home-dotfiles 把每个文件复制成【独立】store 项，
# gate-core.sh 与 anchors-lib.sh 不在同一 store 目录，`dirname $0` 同目录查找
# 在部署形态下必然落空；源码树/直链场景才用同目录。
ANCHORS_LIB=""
for candidate in "$HOME/.config/agents/anchors-lib.sh" "$LIB_DIR/anchors-lib.sh"; do
	if [[ -f "$candidate" ]]; then
		ANCHORS_LIB="$candidate"
		break
	fi
done
if [[ -z "$ANCHORS_LIB" ]] || ! source "$ANCHORS_LIB" 2>/dev/null; then
	MERGED="$DEFAULT_MERGED"
else
	MERGED="$(load_merged_anchors "${GATE_CWD:-$PWD}" 2>/dev/null || printf '%s' "$DEFAULT_MERGED")"
fi

emit() {
	local payload="${2//$'\n'/ }"
	printf '%s\t%s\n' "$1" "$payload"
}

# ─── 词法工具 ────────────────────────────────────────────────────────────────

sed_escape_re() { printf '%s' "$1" | sed 's/[.[\*^$()+?{|\\]/\\&/g'; }
sed_escape_repl() { printf '%s' "$1" | sed 's/[&\\]/\\&/g'; }

trim() {
	local s="$1"
	s="${s#"${s%%[![:space:]]*}"}"
	s="${s%"${s##*[![:space:]]}"}"
	printf '%s' "$s"
}

# 冻结命令匹配预处理：按命令边界（; & | ( ) ` 、` -- ` 参数终结符及
# 换行）切分为每行一个命令片段，片段内剥引号/反斜杠并压缩空白（堵
# reb''uild 类拆分）。heredoc 正文：消费者是解释器（bash <<EOF、
# sh -s <<X 等，取 `<<` 前最后一个词判定）时正文会被执行，保留进
# 片段流参与冻结匹配；数据型消费者（cat/tee 等）的正文仍是纯数据，
# 剔除。
_cmd_segments() {
	awk '
    indelim != "" {
      if ($0 ~ "^[[:space:]]*" indelim "[[:space:]]*$") { indelim = ""; hdrcmd = ""; next }
      if (hdrcmd ~ /^(sh|bash|zsh|dash|ash|fish|python[0-9.]*|node[0-9.]*|deno|guile[0-9.]*|perl|ruby|tclsh)$/) print
      next
    }
    {
      if (match($0, /<<-?[[:space:]]*("[^"]+"|\x27[^\x27]+\x27|[A-Za-z_][A-Za-z0-9_]*)/)) {
        d = substr($0, RSTART, RLENGTH)
        sub(/^<<-?[[:space:]]*/, "", d)
        gsub(/^["\x27]|["\x27]$/, "", d)
        indelim = d
        # 消费者 = `<<` 前的最后一个非标志词（`bash <<E`、`cmd | sh <<E`、
        # `sh -s <<X`、`python3 - <<PY` 都取到解释器名）
        hdrcmd = substr($0, 1, RSTART - 1)
        sub(/[[:space:]]+$/, "", hdrcmd)
        ntok = split(hdrcmd, toks, /[[:space:]]+/)
        hdrcmd = ""
        for (k = ntok; k >= 1; k--) {
          if (toks[k] !~ /^-/) { hdrcmd = toks[k]; break }
        }
        sub(/.*\//, "", hdrcmd)
        # `cat <<X | bash`：heredoc 输出经管道交解释器执行，正文同样保留
        htail = substr($0, RSTART + RLENGTH)
        if (htail ~ /^[[:space:]]*[|;&][[:space:]]*(sh|bash|zsh|dash|ash|fish|python[0-9.]*|node[0-9.]*|deno|guile[0-9.]*|perl|ruby|tclsh)([[:space:]]|$)/)
          hdrcmd = "bash"
      }
      print
    }
  ' | sed -e "s/'//g" -e 's/"//g' -e 's/\\//g' \
		-e 's/[[:space:]][[:space:]]*/ /g' -e 's/^[[:space:]]*//' \
		-e 's/&&/\n/g' -e 's/||/\n/g' -e 's/ -- /\n/g' -e 's/[;&|()`]/\n/g' \
		-e 's/\n[[:space:]]*/\n/g' -e '/^[[:space:]]*$/d'
}

# 在片段流中找冻结命令。主规则：片段行首词序列命中（冻结词必须出现在
# 命令位置——第一个词，或 ; & | ( ) ` / -- / 换行之后的词）；片段首词
# 先做 basename 归一化（`/run/.../bin/sudo x`、`~/.../guix install` 与
# 裸命令同判，堵完整路径绕过锚定）；兜底规则：片段首词是再执行通道
# （sh -c / xargs / find -exec 等，参数会被当作命令执行）时退回段内
# 子串匹配，堵引号包裹的间接执行。
# 输出命中的 frozen 项，无命中输出空。
_match_frozen_in_segments() { # $1=片段流 $2=frozen 列表(换行分隔)
	printf '%s\n' "$1" | awk -v frozen="$2" '
    BEGIN {
      n = split(frozen, arr, "\n")
      for (i = 1; i <= n; i++) {
        f = arr[i]
        if (f == "") continue
        orig[++m] = f
        # 主模式：冻结词序列，词间允许插入任意完整词——`git push origin
        # --force`、`git -C <path> push --force` 与 `git push --force` 同拦；
        # 兜底模式：词边界子串（`sh -c reformat` 的 rm 不再误命中）
        nw = split(f, fw, " ")
        for (w = 1; w <= nw; w++) gsub(/[\\^$.|+()\[\]{}*?]/, "\\\\&", fw[w])
        pats[m] = "^" fw[1]
        subpat[m] = "(^|[^A-Za-z0-9_-])" fw[1]
        for (w = 2; w <= nw; w++) {
          gap = "([[:space:]]+[^[:space:]]+)*[[:space:]]+"
          pats[m] = pats[m] gap fw[w]
          subpat[m] = subpat[m] gap fw[w]
        }
        pats[m] = pats[m] "([[:space:]]|$)"
        subpat[m] = subpat[m] "([^A-Za-z0-9_-]|$)"
      }
    }
    {
      norm = $0
      # 剥 env 赋值前缀（FOO=/x sudo … → sudo …），循环剥多个赋值
      while (match(norm, /^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+/))
        sub(/^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+/, "", norm)
      w = norm; sub(/[[:space:]].*/, "", w)
      if (index(w, "/") > 0) {
        sub(/.*\//, "", w)
        rest = norm; sub(/^[^[:space:]]*/, "", rest)
        norm = w rest
      }
      channel = (norm ~ /^(sh|bash|dash|ash|env|nohup|xargs|ssh|parallel|find|exec)([[:space:]]|$)/) ? 1 : 0
      for (j = 1; j <= m; j++) {
        if (norm ~ pats[j]) { print orig[j]; exit }
        if (channel && norm ~ subpat[j]) { print orig[j]; exit }
      }
    }
  '
}

# resolve_path <path> <logical|physical>
#   logical  = realpath -ms（不解析已存在的 symlink）
#   physical = realpath -mP（解析 symlink；不要求末端存在）
resolve_path() {
	local p="$1" mode="$2"
	case "$p" in
	"~") p="$HOME" ;;
	"~/"*) p="${HOME}${p:1}" ;;
	esac
	if command -v realpath >/dev/null 2>&1; then
		if [[ "$mode" == "physical" ]]; then
			realpath -mP "$p" 2>/dev/null || realpath -ms "$p" 2>/dev/null || printf '%s' "$p"
		else
			realpath -ms "$p" 2>/dev/null || printf '%s' "$p"
		fi
	else
		readlink -f "$p" 2>/dev/null || printf '%s' "$p"
	fi
}

PREFIX='(^|[;&|()$]|&&|\|\|)[[:space:]]*'

# ─── bash 命令判定 ───────────────────────────────────────────────────────────

gate_bash() {
	local CMD="$1"
	local FIRST BASE
	FIRST="$(trim "$CMD")"
	FIRST="${FIRST%%[[:space:]]*}"
	BASE="$(basename "${FIRST:-cmd}" 2>/dev/null || printf '%s' "${FIRST:-cmd}")"

	# 1a 冻结命令（命令位置词序列匹配）+ guix system 宽匹配。
	# --dry-run 豁免是片段级的：只剔除「blue 前缀且带 --dry-run」的片段，
	# 其余片段照常检查——`blue --dry-run rebuild; sudo ...` 的 sudo 片段
	# 不被连带豁免。
	local frozen_list segments hit check_cmd
	frozen_list="$(jq -r '.frozen_commands[]?' <<<"$MERGED" 2>/dev/null)"
	segments="$(printf '%s\n' "$CMD" | _cmd_segments |
		awk '{ split($0, w, " "); c = w[1]; sub(/.*\//, "", c)
		       if (c == "blue" && $0 ~ /--dry-run/) next; print }')"
	check_cmd="$(printf '%s\n' "$segments" | tr '\n' ' ')"
	if [[ -n "${frozen_list//$'\n']/}" && -n "$segments" ]]; then
		hit="$(_match_frozen_in_segments "$segments" "$frozen_list")"
		if [[ -n "$hit" ]]; then
			if [[ "$hit" == "rm" ]]; then
				emit BLOCK "🚫 rm 已冻结：agent 一律不直接删除文件。请改用 trash-put <path> / gio trash <path>，或 mv <path> /tmp/ 保留可恢复副本；确需永久删除请提醒用户手动执行。"
			else
				emit BLOCK "🚫 冻结命令「${hit}」禁止由 agent 执行。如确需执行请提醒用户手动运行。"
			fi
			return 0
		fi
	fi
	if [[ "$check_cmd" == *guix* ]] && printf '%s' "$check_cmd" | grep -qE '\bsystem[[:space:]]+(reconfigure|init)\b'; then
		emit BLOCK "🚫 禁止 guix system reconfigure/init（含 time-machine 包装，需 sudo）。验证请用 \`blue --dry-run rebuild\`；固化请提醒用户手动运行。"
		return 0
	fi

	# 1b 交互式命令（无 TTY 会挂起）——词法匹配原始命令，名单来自 anchors.json
	local name esc
	while IFS= read -r name; do
		[[ -z "$name" ]] && continue
		esc="$(sed_escape_re "$name")"
		if printf '%s' "$CMD" | grep -qE "${PREFIX}${esc}\b"; then
			emit BLOCK "🚫 禁止交互式命令 ${name}（无 TTY 会挂起），请使用对应工具"
			return 0
		fi
	done < <(jq -r '.interactive_commands[]?' <<<"$MERGED" 2>/dev/null)
	# 裸 REPL 仅无参数调用时禁（行尾）
	while IFS= read -r name; do
		[[ -z "$name" ]] && continue
		esc="$(sed_escape_re "$name")"
		if printf '%s' "$CMD" | grep -qE "${PREFIX}${esc}[[:space:]]*$"; then
			emit BLOCK "🚫 禁止裸 REPL ${name}，请使用 ${name} -c '...' 或脚本"
			return 0
		fi
	done < <(jq -r '.bare_repl_commands[]?' <<<"$MERGED" 2>/dev/null)

	# 1c Git 限制
	if printf '%s' "$CMD" | grep -qE "${PREFIX}git[[:space:]]+commit\b"; then
		if ! printf '%s' "$CMD" | grep -qE '([[:space:]]-m[[:space:]]|[[:space:]]--message[[:space:]])'; then
			emit BLOCK "🚫 git commit 必须使用 -m 指定提交信息"
			return 0
		fi
	fi
	if printf '%s' "$CMD" | grep -qE "${PREFIX}git[[:space:]]+add[[:space:]].*-p\b"; then
		emit BLOCK "🚫 禁止 git add -p（交互式）"
		return 0
	fi
	if printf '%s' "$CMD" | grep -qE "${PREFIX}git[[:space:]]+rebase[[:space:]].*-i\b"; then
		emit BLOCK "🚫 禁止 git rebase -i（交互式）"
		return 0
	fi

	# 2 只读命令白名单（位于全部硬拦截之后，不构成绕过）。
	# 仅对无连接符（; & | ` $( ）的单条命令发 AUTO_ALLOW——`ls && curl … |
	# sh` 这类搭车形态回落到默认确认流
	if printf '%s' "$CMD" | grep -qE '[;&|`]|\$\('; then :; else
	case "$BASE" in
	cat | head | tail | bat | echo | printf | seq | date | uptime)
		emit AUTO_ALLOW ""
		return 0
		;;
	wc | sort | uniq | tr | cut | column | rev | tac | paste | comm | diff | patch)
		emit AUTO_ALLOW ""
		return 0
		;;
	whoami | id | hostname | uname | pwd | env | printenv | which | whereis | command | type)
		emit AUTO_ALLOW ""
		return 0
		;;
	file | stat | realpath | readlink | basename | dirname | test | true | false)
		emit AUTO_ALLOW ""
		return 0
		;;
	ls | tree | dust | df | free)
		emit AUTO_ALLOW ""
		return 0
		;;
	rg | ag | ack | fd)
		emit AUTO_ALLOW ""
		return 0
		;;
	jq | yq | mlr)
		emit AUTO_ALLOW ""
		return 0
		;;
	dig | nslookup | host | ping | traceroute)
		emit AUTO_ALLOW ""
		return 0
		;;
	guix)
		local word
		for word in $CMD; do
			case "$word" in
			describe | show | search | hash | lint | size | graph | weather)
				emit AUTO_ALLOW ""
				return 0
				;;
			esac
		done
		;;
	git)
		local git_only_read=1 word
		for word in $CMD; do
			case "$word" in
			commit | push | merge | rebase | reset | checkout | switch | cherry-pick | bisect | am | clean | format-patch)
				git_only_read=0
				break
				;;
			esac
		done
		[[ "$git_only_read" -eq 1 ]] && {
			emit AUTO_ALLOW ""
			return 0
		}
		;;
	esac
	fi

	# 3 命令改写（builtin npm→pnpm / pip→uv pip + 项目层 rewrite map）
	local REWRITTEN="$CMD" NOTES=""
	local builtin_rw has_npm has_pip
	builtin_rw="$(jq -r '.builtin_rewrite' <<<"$MERGED" 2>/dev/null || printf 'true')"
	if [[ "$builtin_rw" == "true" ]]; then
		has_npm="$(jq -r '.rewrite | has("npm")' <<<"$MERGED" 2>/dev/null || printf 'false')"
		has_pip="$(jq -r '.rewrite | has("pip") or has("pip3")' <<<"$MERGED" 2>/dev/null || printf 'false')"
		if [[ "$has_npm" != "true" ]] && printf '%s' "$CMD" | grep -qE '(^|[|&;])[[:space:]]*npm\b'; then
			REWRITTEN="$(printf '%s' "$REWRITTEN" | sed -E 's/(^|[|&;])[[:space:]]*npm\b/\1pnpm/g')"
			NOTES="${NOTES:+$NOTES; }npm → pnpm"
		fi
		if [[ "$has_pip" != "true" ]] && printf '%s' "$CMD" | grep -qE '(^|[|&;])[[:space:]]*pip3?\b'; then
			REWRITTEN="$(printf '%s' "$REWRITTEN" | sed -E 's/(^|[|&;])[[:space:]]*pip3?\b/\1uv pip/g')"
			NOTES="${NOTES:+$NOTES; }pip → uv pip"
		fi
	fi
	local from to new
	while IFS=$'\t' read -r from to; do
		[[ -z "$from" ]] && continue
		esc_from="$(sed_escape_re "$from")"
		esc_to="$(sed_escape_repl "$to")"
		new="$(printf '%s' "$REWRITTEN" | sed -E "s#(^|[|&;])[[:space:]]*${esc_from}\\b#\\1${esc_to}#g")"
		if [[ "$new" != "$REWRITTEN" ]]; then
			REWRITTEN="$new"
			NOTES="${NOTES:+$NOTES; }${from} → ${to}"
		fi
	done < <(jq -r '.rewrite | to_entries[] | "\(.key)\t\(.value)"' <<<"$MERGED" 2>/dev/null)
	[[ "$REWRITTEN" != "$CMD" ]] && emit REWRITTEN "$REWRITTEN"

	# 4 非阻塞提示
	[[ -n "$NOTES" ]] && emit NOTES "本机偏好命令替代：${NOTES}；如适用请改用后重新执行"
	local pat msg REDIRECT_PAT="" REDIRECT_MSG=""
	while IFS=$'\t' read -r pat msg; do
		[[ -z "$pat" ]] && continue
		if [[ "$CMD" == *"$pat"* ]] && [[ ${#pat} -gt ${#REDIRECT_PAT} ]]; then
			REDIRECT_PAT="$pat"
			REDIRECT_MSG="💡 ${msg}"
		fi
	done < <(jq -r '.redirect_conventions | to_entries[] | "\(.key)\t\(.value)"' <<<"$MERGED" 2>/dev/null)
	[[ -n "$REDIRECT_MSG" ]] && emit REDIRECT "$REDIRECT_MSG"
	return 0
}

# ─── 文件写入判定 ─────────────────────────────────────────────────────────────

gate_edit() {
	local FILE="$1"
	local LOGICAL PHYSICAL BASENAME PROJ REL RELP INSIDE=0 INSP=0
	LOGICAL="$(resolve_path "$FILE" logical)"
	PHYSICAL="$(resolve_path "$FILE" physical)"
	BASENAME="${LOGICAL##*/}"
	PROJ="$(find_git_root "${GATE_CWD:-$PWD}")"
	REL="${LOGICAL#"$PROJ"/}"
	RELP="${PHYSICAL#"$PROJ"/}"
	{ [[ "$LOGICAL" == "$PROJ" || "$LOGICAL" == "$PROJ/"* ]] && INSIDE=1; } || true
	{ [[ "$PHYSICAL" == "$PROJ" || "$PHYSICAL" == "$PROJ/"* ]] && INSP=1; } || true

	# 1a meta-frozen：全局 anchors.json 或显式 _meta_frozen 的 anchors.json 禁改。
	# 用逻辑路径比对——物理路径会解析到 /gnu/store，basename 与等值判断双双失效。
	if [[ "$BASENAME" == "anchors.json" ]]; then
		local GA_RESOLVED
		GA_RESOLVED="$(resolve_path "$HOME/.config/agents/anchors.json" logical)"
		if [[ "$LOGICAL" == "$GA_RESOLVED" ]]; then
			emit BLOCK "🚫 全局 anchors.json 是冻结规则源（meta-frozen），禁止 agent 修改。如需调整全局冻结规则请人工编辑。"
			return 0
		fi
		if [[ -f "$LOGICAL" ]] && jq -e '._meta_frozen == true' "$LOGICAL" >/dev/null 2>&1; then
			emit BLOCK "🚫 该 anchors.json 声明了 _meta_frozen，禁止 agent 修改（人工锁定的项目 gate）。如需调整请人工编辑。"
			return 0
		fi
	fi

	# 1b frozen_paths：~/ 前缀按家目录展开；相对路径按 git root 前缀 + 任意
	# 路径后缀（basename 等值，如 channel.lock）。逻辑/物理双查——物理路径
	# 防「/tmp/软链 → 仓库冻结目录」中转写入。
	local frozen exp
	while IFS= read -r frozen; do
		[[ -z "$frozen" ]] && continue
		case "$frozen" in
		"~/"*)
			exp="${HOME}${frozen:1}"
			if [[ "$LOGICAL" == "$exp" || "$LOGICAL" == "$exp/"* ]] || [[ "$PHYSICAL" == "$exp" || "$PHYSICAL" == "$exp/"* ]]; then
				emit BLOCK "🚫 冻结路径「${frozen}」禁止 agent 写入（gate/安全规则源）。确需修改请人工编辑源文件后 blue home 生效。"
				return 0
			fi
			;;
		*)
			if [[ $INSIDE -eq 1 && "$REL" == "$frozen"* ]] || [[ $INSP -eq 1 && "$RELP" == "$frozen"* ]] ||
				[[ "$LOGICAL" == *"$frozen" ]] || [[ "$PHYSICAL" == *"$frozen" ]]; then
				emit BLOCK "🚫 冻结路径「${frozen}」禁止 agent 写入（构建产物/锁文件/gate 规则源）。确需修改请人工编辑源文件。"
				return 0
			fi
			;;
		esac
	done < <(jq -r '.frozen_paths[]?' <<<"$MERGED" 2>/dev/null)

	# 1c frozen_globs：含 / 的对相对路径匹配，不含 / 的对 basename 匹配
	if [[ $INSP -eq 1 ]]; then
		local glob ere
		while IFS= read -r glob; do
			[[ -z "$glob" ]] && continue
			ere="$(glob_to_ere "$glob")"
			if [[ "$glob" == */* ]]; then
				if printf '%s\n' "$RELP" | grep -qE "$ere"; then
					emit BLOCK "🚫 冻结 glob「${glob}」禁止写入（项目级 gate）。"
					return 0
				fi
			elif printf '%s' "$BASENAME" | grep -qE "$ere"; then
				emit BLOCK "🚫 冻结 glob「${glob}」禁止写入（项目级 gate）。"
				return 0
			fi
		done < <(jq -r '.frozen_globs[]?' <<<"$MERGED" 2>/dev/null)
	fi

	# 1d 部署位置保护（机器级）：~/.config/、~/.local/ 直改禁止，项目内豁免。
	# 用逻辑路径——这些位置的 symlink 指向 store 是部署设计，不是攻击面。
	if [[ "$LOGICAL" == "$HOME/.config/"* || "$LOGICAL" == "$HOME/.local/"* ]] && [[ $INSIDE -eq 0 ]]; then
		emit BLOCK "🚫 禁止直接修改已部署位置（~/.config/ 或 ~/.local/）。请修改 dotfiles/ 源文件后运行 blue home。"
		return 0
	fi

	# 2 敏感信息检测（stdin 为待检内容，可为空）
	local INPUT CONTENT
	INPUT="$(cat 2>/dev/null || true)"
	if [[ -n "$INPUT" ]]; then
		local TMPFILE FOUND="" pattern label flags gflag
		TMPFILE="$(mktemp 2>/dev/null || printf '%s/gate-core.%s' "${TMPDIR:-/tmp}" "$$")"
		printf '%s' "$INPUT" >"$TMPFILE"
		while IFS=$'\t' read -r pattern label flags; do
			[[ -z "$pattern" ]] && continue
			gflag="-qE"
			[[ "$flags" == *"i"* ]] && gflag="-qiE"
			if grep $gflag -e "$pattern" "$TMPFILE" 2>/dev/null; then
				FOUND="${FOUND:+$FOUND; }$label"
			fi
		done < <(jq -r '.sensitive_patterns[]? | [.pattern, .label, (.flags // "")] | @tsv' <<<"$MERGED" 2>/dev/null)
		rm -f "$TMPFILE"
		if [[ -n "$FOUND" ]]; then
			emit SENSITIVE "检测到敏感信息: $FOUND。如确认无风险请手动操作。"
			return 0
		fi
	fi

	# 3 path_hints（软提示）
	if [[ $INSIDE -eq 1 ]]; then
		local prefix msg p
		while IFS=$'\t' read -r prefix msg; do
			[[ -z "$prefix" ]] && continue
			p="${prefix%/}/"
			if [[ "$REL" == "$prefix" || "$REL" == "$p"* || "$REL" == "$prefix"* ]]; then
				emit HINT "$msg"
			fi
		done < <(jq -r '.path_hints | to_entries[] | "\(.key)\t\(.value)"' <<<"$MERGED" 2>/dev/null)
	fi
	return 0
}

# ─── 入口 ─────────────────────────────────────────────────────────────────────

case "${1:-}" in
bash)
	shift
	gate_bash "$*"
	;;
edit)
	shift
	gate_edit "${1:-}"
	;;
*)
	printf 'usage: gate-core.sh bash <cmd> | edit <file>\n' >&2
	exit 64
	;;
esac
