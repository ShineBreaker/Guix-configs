#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

# gate-core.sh — zcode / crush / pi / hermes / DSH 五端共享的 gate 决策核
# （单一真相源，适配器只做协议转换）。CLI、行协议、环境变量与安全不变量
# 全部定义于 docs/scripts/gate-core.md；修改匹配逻辑前必读其
# §设计决策与不变量——头部逐条不变量对应实现处均有一行指引注释。
#
# 速览（细节见文档）：
#   gate-core.sh bash <cmd>    Bash 命令判定
#   gate-core.sh edit <file>   写入判定（待检内容读 stdin）
#   stdout: TYPE<TAB>payload（BLOCK/SENSITIVE/AUTO_ALLOW/REWRITTEN/NOTES/RM_HINT/REDIRECT/HINT）
#   决策退出码恒 0；GATE_CWD 定位 anchors 层级（默认 $PWD）；
#   GATE_NO_WRITE_TOOLS=1 无写工具会话输出降级；人工总开关
#   /run/agent-gate.off 存在即静默放行（固定路径，不认改道）。
set -uo pipefail
# 不用 -e：单个检查工具异常（如 jq 输出非预期）不应中断后续检查

SELF="$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")"
LIB_DIR="$(dirname "$SELF")"
# shellcheck disable=SC2016 # JSON 字面量
DEFAULT_MERGED='{"frozen_commands":["sudo"],"frozen_paths":[],"frozen_globs":[],"interactive_commands":[],"bare_repl_commands":[],"sensitive_patterns":[],"redirect_conventions":{},"rewrite":{},"path_hints":{},"builtin_rewrite":true,"human_only_actions":[],"anchor_measurements":[]}'

# lib 定位：部署位置优先——home-dotfiles 把各文件复制成独立 store 项，
# 同目录查找在部署形态必然落空（不变量见 gate-core.md §部署形态约束）。
ANCHORS_LIB=""
for candidate in "$HOME/.config/agents/anchors-lib.sh" "$LIB_DIR/anchors-lib.sh"; do
  if [[ -f "$candidate" ]]; then
    ANCHORS_LIB="$candidate"
    break
  fi
done
# shellcheck disable=SC1090 # lib 路径运行时定位（部署位置优先、同目录兜底）
if [[ -z "$ANCHORS_LIB" ]] || ! source "$ANCHORS_LIB" 2>/dev/null; then
  MERGED="$DEFAULT_MERGED"
else
  MERGED="$(load_merged_anchors "${GATE_CWD:-$PWD}" 2>/dev/null || printf '%s' "$DEFAULT_MERGED")"
fi

# 人工总开关：固定路径，不接受环境变量改道（gate-core.md §设计决策与不变量）
GATE_PAUSE_FILE="/run/agent-gate.off"

# 无写工具会话标记（DSH gate.js 置位）：只做输出降级，不制造放行
# （BLOCK 不附 ALT、interactive 去工具引导、软提示抑制——gate-core.md）。
NO_WRITE_TOOLS="${GATE_NO_WRITE_TOOLS:-0}"

emit() {
  local payload="${2//$'\n'/ }"
  printf '%s\t%s\n' "$1" "$payload"
}

# ─── 词法工具 ────────────────────────────────────────────────────────────────

# shellcheck disable=SC2016 # sed 程序文本含 $，须单引号防展开
sed_escape_re() { printf '%s' "$1" | sed 's/[.[\*^$()+?{|\\]/\\&/g'; }
sed_escape_repl() { printf '%s' "$1" | sed 's/[&\\]/\\&/g'; }

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# 片段流切分：按命令边界（; & | ( ) `、` -- `、换行）切片，剥引号/反斜杠
# 并压缩空白；解释器 heredoc（bash <<EOF、`cmd | sh <<E` 等）正文视为
# 可执行内容保留，数据消费者（cat 等）正文剔除（gate-core.md）。
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
        # 消费者取 `<<` 前最后一个非标志词
        hdrcmd = substr($0, 1, RSTART - 1)
        sub(/[[:space:]]+$/, "", hdrcmd)
        ntok = split(hdrcmd, toks, /[[:space:]]+/)
        hdrcmd = ""
        for (k = ntok; k >= 1; k--) {
          if (toks[k] !~ /^-/) { hdrcmd = toks[k]; break }
        }
        sub(/.*\//, "", hdrcmd)
        # `cat <<X | bash`：正文经管道交解释器执行，同样保留
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

# 冻结匹配：主规则=片段行首词序列命中（命令位置限定）；首词 basename
# 归一化堵完整路径绕过；再执行通道首词退回段内子串匹配堵引号包裹的
# 间接执行（逐项不变量见 gate-core.md）。输出命中的 frozen 项，无命中输出空。
_match_frozen_in_segments() { # $1=片段流 $2=frozen 列表(换行分隔)
  printf '%s\n' "$1" | awk -v frozen="$2" '
    BEGIN {
      n = split(frozen, arr, "\n")
      for (i = 1; i <= n; i++) {
        f = arr[i]
        if (f == "") continue
        orig[++m] = f
        # 主模式：词序列、词间允许插入完整词；兜底模式：词边界子串
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
      # 循环剥 env 赋值前缀（FOO=/x sudo … → sudo …）
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

# resolve_path <path> <logical|physical>：logical 不解析 symlink，
# physical 解析——双路径分工见 gate-core.md（edit 检查依赖两者）。
resolve_path() {
  local p="$1" mode="$2"
  # shellcheck disable=SC2088 # 匹配字面 ~/ 前缀
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

# cwd_under <dir>：GATE_CWD 是否位于 dir 子树内；物理解析防软链误判。
cwd_under() {
  local base cwd
  # shellcheck disable=SC2088 # 匹配字面 ~/ 前缀
  case "$1" in
    "~") base="$HOME" ;;
    "~/"*) base="${HOME}${1:1}" ;;
    *) base="$1" ;;
  esac
  base="$(resolve_path "$base" physical)"
  cwd="$(resolve_path "${GATE_CWD:-$PWD}" physical)"
  [[ -n "$base" && ("$cwd" == "$base" || "$cwd" == "$base/"*) ]]
}

PREFIX='(^|[;&|()$]|&&|\|\|)[[:space:]]*'

# ─── bash 命令判定 ───────────────────────────────────────────────────────────
#
# 阶段约定：命中并 emit → return 0（主流程终止）；未命中 → return 1。
# 顺序与早退语义不可变（gate-core.md §判定流水线）。

# 1a 冻结命令 + guix system 宽匹配。预演豁免是片段级的：仅剔除
# 「blue + --dry-run」「just + 非空 dry=」片段（gate-core.md）。
check_frozen_commands() {
  local frozen_list segments hit check_cmd
  frozen_list="$(jq -r '.frozen_commands[]?' <<<"$MERGED" 2>/dev/null)"
  segments="$(printf '%s\n' "$CMD" | _cmd_segments \
    | awk '{ split($0, w, " "); c = w[1]; sub(/.*\//, "", c)
		       if ((c == "blue" && $0 ~ /--dry-run/) ||
		           (c == "just" && $0 ~ /(^|[[:space:]])dry=[^[:space:]]/)) next; print }')"
  check_cmd="$(printf '%s\n' "$segments" | tr '\n' ' ')"
  if [[ -n "${frozen_list//$'\n']/}" && -n "$segments" ]]; then
    hit="$(_match_frozen_in_segments "$segments" "$frozen_list")"
    if [[ -n "$hit" ]]; then
      if [[ "$hit" == "rm" ]]; then
        emit BLOCK "rm 已冻结：agent 一律不直接删除文件。请改用 trash-put <path> / gio trash <path>，或 mv <path> /tmp/ 保留可恢复副本；确需永久删除请提醒用户手动执行。"
      else
        # redirect_conventions 命中的冻结词附替代方案；无写工具会话回落通用理由
        local ALT
        ALT="$(jq -r --arg k "$hit" '.redirect_conventions[$k] // empty' <<<"$MERGED" 2>/dev/null)"
        if [[ -n "$ALT" && "$NO_WRITE_TOOLS" != "1" ]]; then
          emit BLOCK "${ALT}"
        else
          emit BLOCK "冻结命令「${hit}」禁止由 agent 执行。如确需执行请提醒用户手动运行。"
        fi
      fi
      return 0
    fi
  fi
  if [[ "$check_cmd" == *guix* ]] && printf '%s' "$check_cmd" | grep -qE '\bsystem[[:space:]]+(reconfigure|init)\b'; then
    emit BLOCK "禁止 guix system reconfigure/init（含 time-machine 包装，需 sudo）。验证请用 \`just dry=1 rebuild\`；固化请提醒用户手动运行。"
    return 0
  fi
  return 1
}

# 1b 交互式命令——词法匹配原始命令（不做归一化，防字符串内容误拦）。
check_interactive_commands() {
  local name esc
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    esc="$(sed_escape_re "$name")"
    if printf '%s' "$CMD" | grep -qE "${PREFIX}${esc}\b"; then
      # 无写工具会话不引导「请使用对应工具」——该模式通常没有对应工具可调
      if [[ "$NO_WRITE_TOOLS" == "1" ]]; then
        emit BLOCK "禁止交互式命令 ${name}（无 TTY 会挂起）"
      else
        emit BLOCK "禁止交互式命令 ${name}（无 TTY 会挂起），请使用对应工具"
      fi
      return 0
    fi
  done < <(jq -r '.interactive_commands[]?' <<<"$MERGED" 2>/dev/null)
  # 裸 REPL 仅无参数调用时禁
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    esc="$(sed_escape_re "$name")"
    if printf '%s' "$CMD" | grep -qE "${PREFIX}${esc}[[:space:]]*$"; then
      emit BLOCK "禁止裸 REPL ${name}，请使用 ${name} -c '...' 或脚本"
      return 0
    fi
  done < <(jq -r '.bare_repl_commands[]?' <<<"$MERGED" 2>/dev/null)
  return 1
}

# 1c Git 限制
check_git_rules() {
  if printf '%s' "$CMD" | grep -qE "${PREFIX}git[[:space:]]+commit\b"; then
    if ! printf '%s' "$CMD" | grep -qE '([[:space:]]-m[[:space:]]|[[:space:]]--message[[:space:]])'; then
      emit BLOCK "git commit 必须使用 -m 指定提交信息"
      return 0
    fi
  fi
  if printf '%s' "$CMD" | grep -qE "${PREFIX}git[[:space:]]+add[[:space:]].*-p\b"; then
    emit BLOCK "禁止 git add -p（交互式）"
    return 0
  fi
  if printf '%s' "$CMD" | grep -qE "${PREFIX}git[[:space:]]+rebase[[:space:]].*-i\b"; then
    emit BLOCK "禁止 git rebase -i（交互式）"
    return 0
  fi
  return 1
}

# 2 只读白名单——必须位于全部硬拦截之后（不构成绕过）；仅对无连接符的
# 单条命令发 AUTO_ALLOW，搭车形态回落默认确认流。
check_readonly_whitelist() {
  if printf '%s' "$CMD" | grep -qE '[;&|`]|\$\('; then :; else
    case "$BASE" in
      cat | head | tail | bat | echo | printf | seq | date | uptime)
        emit AUTO_ALLOW ""
        return 0
        ;;
      wc | sort | uniq | tr | cut | column | rev | tac | paste | comm | diff)
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
            commit | push | merge | rebase | reset | checkout | switch | cherry-pick | bisect | am | apply | clean | format-patch)
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
  return 1
}

# 3 命令改写 + 4 非阻塞提示（无拦截语义，恒 return 0）
apply_rewrites_and_hints() {
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

  # 无写工具会话整条抑制（gate-core.md）
  [[ -n "$NOTES" && "$NO_WRITE_TOOLS" != "1" ]] && emit NOTES "本机偏好命令替代：${NOTES}；如适用请改用后重新执行"
  local pat msg REDIRECT_PAT="" REDIRECT_MSG=""
  while IFS=$'\t' read -r pat msg; do
    [[ -z "$pat" ]] && continue
    if [[ "$CMD" == *"$pat"* ]] && [[ ${#pat} -gt ${#REDIRECT_PAT} ]]; then
      REDIRECT_PAT="$pat"
      REDIRECT_MSG="${msg}"
    fi
  done < <(jq -r '.redirect_conventions | to_entries[] | "\(.key)\t\(.value)"' <<<"$MERGED" 2>/dev/null)
  [[ -n "$REDIRECT_MSG" && "$NO_WRITE_TOOLS" != "1" ]] && emit REDIRECT "$REDIRECT_MSG"
  return 0
}

gate_bash() {
  local CMD="$1"
  # 0 人工总开关（最优先）：存在即静默放行，不输出任何内容
  # （暂停态对 agent 不可见，与护栏不存在时表现一致）
  if [[ -f "$GATE_PAUSE_FILE" ]]; then
    return 0
  fi
  local FIRST BASE
  FIRST="$(trim "$CMD")"
  FIRST="${FIRST%%[[:space:]]*}"
  BASE="$(basename "${FIRST:-cmd}" 2>/dev/null || printf '%s' "${FIRST:-cmd}")"

  if check_frozen_commands; then return 0; fi
  if check_interactive_commands; then return 0; fi
  if check_git_rules; then return 0; fi
  if check_readonly_whitelist; then return 0; fi
  apply_rewrites_and_hints
  return 0
}

# ─── 文件写入判定 ─────────────────────────────────────────────────────────────

# 与 gate_bash 同一阶段约定。

# 1a meta-frozen——逻辑路径比对（物理解析到 /gnu/store 会让等值判断失效）。
# _meta_frozen 支持 {"unless_inside": "<dir>"} 条件豁免（gate-core.md）。
check_meta_frozen() {
  if [[ "$BASENAME" == "anchors.json" ]]; then
    local GA_RESOLVED
    GA_RESOLVED="$(resolve_path "$HOME/.config/agents/anchors.json" logical)"
    if [[ "$LOGICAL" == "$GA_RESOLVED" ]]; then
      emit BLOCK "全局 anchors.json 是冻结规则源（meta-frozen），禁止 agent 修改。如需调整全局冻结规则请人工编辑。"
      return 0
    fi
    if [[ -f "$LOGICAL" ]]; then
      local MF_KIND MF_SCOPE
      MF_KIND="$(jq -r '._meta_frozen | type' "$LOGICAL" 2>/dev/null || printf 'null')"
      if [[ "$MF_KIND" == "boolean" ]] && jq -e '._meta_frozen == true' "$LOGICAL" >/dev/null 2>&1; then
        emit BLOCK "该 anchors.json 声明了 _meta_frozen，禁止 agent 修改（人工锁定的项目 gate）。如需调整请人工编辑。"
        return 0
      fi
      if [[ "$MF_KIND" == "object" ]]; then
        MF_SCOPE="$(jq -r '._meta_frozen.unless_inside // empty' "$LOGICAL" 2>/dev/null)"
        if [[ -n "$MF_SCOPE" ]] && ! cwd_under "$MF_SCOPE"; then
          emit BLOCK "该 anchors.json 声明了 _meta_frozen（cwd 不在 ${MF_SCOPE} 内），禁止 agent 修改。如需调整请人工编辑。"
          return 0
        fi
      fi
    fi
  fi
  return 1
}

# 1b frozen_paths：逻辑/物理双查——物理路径防「软链中转写入」；
# 对象形式 {"path","unless_inside"} 逐条目条件豁免（gate-core.md）。
check_frozen_paths() {
  local frozen unless exp entry
  while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue
    frozen="$(jq -r 'if type == "string" then . else (.path // empty) end' <<<"$entry" 2>/dev/null)"
    [[ -z "$frozen" ]] && continue
    unless="$(jq -r 'if type == "object" then (.unless_inside // empty) else empty end' <<<"$entry" 2>/dev/null)"
    if [[ -n "$unless" ]] && cwd_under "$unless"; then
      continue
    fi
    # shellcheck disable=SC2088 # 匹配字面 ~/ 前缀条目
    case "$frozen" in
      "~/"*)
        exp="${HOME}${frozen:1}"
        # 尾斜杠必须剥掉，否则 "$exp/"* 双斜杠模式永不匹配
        exp="${exp%/}"
        if [[ "$LOGICAL" == "$exp" || "$LOGICAL" == "$exp/"* ]] || [[ "$PHYSICAL" == "$exp" || "$PHYSICAL" == "$exp/"* ]]; then
          emit BLOCK "冻结路径「${frozen}」禁止 agent 写入（gate/安全规则源）。确需修改请人工编辑源文件后 just home 生效。"
          return 0
        fi
        ;;
      *)
        if [[ $INSIDE -eq 1 && "$REL" == "$frozen"* ]] || [[ $INSP -eq 1 && "$RELP" == "$frozen"* ]] \
          || [[ "$LOGICAL" == *"$frozen" ]] || [[ "$PHYSICAL" == *"$frozen" ]]; then
          emit BLOCK "冻结路径「${frozen}」禁止 agent 写入（构建产物/锁文件/gate 规则源）。确需修改请人工编辑源文件。"
          return 0
        fi
        ;;
    esac
  done < <(jq -c '.frozen_paths[]?' <<<"$MERGED" 2>/dev/null)
  return 1
}

# 1c frozen_globs：含 / 的对 RELP 匹配，不含 / 的对 basename 匹配
check_frozen_globs() {
  if [[ $INSP -eq 1 ]]; then
    local glob ere
    while IFS= read -r glob; do
      [[ -z "$glob" ]] && continue
      ere="$(glob_to_ere "$glob")"
      if [[ "$glob" == */* ]]; then
        if printf '%s\n' "$RELP" | grep -qE "$ere"; then
          emit BLOCK "冻结 glob「${glob}」禁止写入（项目级 gate）。"
          return 0
        fi
      elif printf '%s' "$BASENAME" | grep -qE "$ere"; then
        emit BLOCK "冻结 glob「${glob}」禁止写入（项目级 gate）。"
        return 0
      fi
    done < <(jq -r '.frozen_globs[]?' <<<"$MERGED" 2>/dev/null)
  fi
  return 1
}

# 1d 部署位置保护——逻辑路径检查：store 软链是部署设计，不是攻击面；
# 项目内（INSIDE=1）豁免。
check_deployed_locations() {
  if [[ "$LOGICAL" == "$HOME/.config/"* || "$LOGICAL" == "$HOME/.local/"* ]] && [[ $INSIDE -eq 0 ]]; then
    emit BLOCK "禁止直接修改已部署位置（~/.config/ 或 ~/.local/）。请修改 dotfiles/ 源文件后运行 just home。"
    return 0
  fi
  return 1
}

# 2 敏感信息检测（stdin 待检内容）+ 3 path_hints；本阶段恒 return 0。
check_sensitive_and_hints() {
  local INPUT
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

gate_edit() {
  local FILE="$1"
  # 0 人工总开关：存在即静默放行（同 gate_bash）
  if [[ -f "$GATE_PAUSE_FILE" ]]; then
    return 0
  fi
  local LOGICAL PHYSICAL BASENAME PROJ REL RELP INSIDE=0 INSP=0
  LOGICAL="$(resolve_path "$FILE" logical)"
  PHYSICAL="$(resolve_path "$FILE" physical)"
  BASENAME="${LOGICAL##*/}"
  PROJ="$(find_git_root "${GATE_CWD:-$PWD}")"
  REL="${LOGICAL#"$PROJ"/}"
  RELP="${PHYSICAL#"$PROJ"/}"
  { [[ "$LOGICAL" == "$PROJ" || "$LOGICAL" == "$PROJ/"* ]] && INSIDE=1; } || true
  { [[ "$PHYSICAL" == "$PROJ" || "$PHYSICAL" == "$PROJ/"* ]] && INSP=1; } || true

  if check_meta_frozen; then return 0; fi
  if check_frozen_paths; then return 0; fi
  if check_frozen_globs; then return 0; fi
  if check_deployed_locations; then return 0; fi
  check_sensitive_and_hints
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
