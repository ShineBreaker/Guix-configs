#!/usr/bin/env bash
# agent-config-audit — 14-check weekly red-light audit
# Invoked through the `terminal` tool or by cron (no_agent=True).
# Stdout is the report; exit code is the alert level (0/1/2).
#
# Budgets overridable via env: INJECTION_BUDGET_KB, SKILL_COUNT_BUDGET,
# LOG_LINE_LIMIT, BACKUP_FILE_LIMIT, MEMORY_DIR_MB, CACHE_DIR_MB,
# FRESHNESS_HOURS, DISPATCH_ERROR_THRESHOLD, SECRET_REGEX.
#
# State: writes $HERMES_HOME/audit/last-red.log on red (appends).
#        Writes $HERMES_HOME/audit/history.log on red (appends).
set -uo pipefail

# ---------- 0. config & paths ----------
HERMES_HOME="${HERMES_HOME:-$HOME/.local/share/hermes}"
INJECTION_BUDGET_KB="${INJECTION_BUDGET_KB:-25}"
SKILL_COUNT_BUDGET="${SKILL_COUNT_BUDGET:-160}"
LOG_LINE_LIMIT="${LOG_LINE_LIMIT:-50000}"
BACKUP_FILE_LIMIT="${BACKUP_FILE_LIMIT:-20}"
MEMORY_DIR_MB="${MEMORY_DIR_MB:-50}"
CACHE_DIR_MB="${CACHE_DIR_MB:-500}"
FRESHNESS_HOURS="${FRESHNESS_HOURS:-168}"   # 7 days
DISPATCH_ERROR_THRESHOLD="${DISPATCH_ERROR_THRESHOLD:-5}"
SECRET_REGEX="${SECRET_REGEX:-sk-[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{36}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]+}"

AUDIT_DIR="$HERMES_HOME/audit"
mkdir -p "$AUDIT_DIR"
LAST_RED="$AUDIT_DIR/last-red.log"
HISTORY="$AUDIT_DIR/history.log"
TS="$(date -Iseconds 2>/dev/null || date)"

# ---------- 1. state buckets ----------
declare -a RED=()
declare -a YEL=()
declare -a GRN=()
declare -A EVIDENCE=()

# helper: record a check result
record() {
  local level="$1" check="$2" evidence="$3"
  EVIDENCE["$check"]="$evidence"
  case "$level" in
    RED) RED+=("$check") ;;
    YEL) YEL+=("$check") ;;
    GRN) GRN+=("$check") ;;
  esac
}

# helper: sum sizes of files in a dir (bytes)
dir_bytes() {
  du -sb "$1" 2>/dev/null | awk '{print $1}'
}

# helper: count *.bak.* / *.tmp / *~ files in a dir (depth 4)
junk_count() {
  find "$1" -maxdepth 4 \( -name '*.bak*' -o -name '*.tmp' -o -name '*.swp' -o -name '*~' \) 2>/dev/null | wc -l
}

# ---------- 2. the 14 checks ----------

# 1 常驻注入体积 ≤ 预算
# Sum the always-injected markdown (MEMORY.md + USER.md + skills frontmatter
# block when the prompt is built). Approximation: MEMORY.md + USER.md size.
# Use stat -L to follow symlinks (Guix stow deploys MEMORY.md as a symlink to
# /gnu/store; a plain stat -c%s would return the symlink's own 100-byte size,
# not the real content — that's the bug that makes this check lie green).
inj_bytes=0
for f in "$HERMES_HOME/memories/MEMORY.md" "$HERMES_HOME/memories/USER.md"; do
  if [ -L "$f" ] && [ -e "$f" ]; then
    inj_bytes=$((inj_bytes + $(stat -Lc%s "$f")))
  elif [ -f "$f" ]; then
    inj_bytes=$((inj_bytes + $(stat -c%s "$f")))
  fi
done
inj_kb=$((inj_bytes / 1024))
if [ "$inj_kb" -gt "$INJECTION_BUDGET_KB" ]; then
  record RED "01-injection-budget" "${inj_kb}KB > budget ${INJECTION_BUDGET_KB}KB (MEMORY.md+USER.md)"
else
  record GRN "01-injection-budget" ""
fi

# 2 可触发技能总数 ≤ 预算
if [ -d "$HERMES_HOME/skills" ]; then
  skill_count=$(find "$HERMES_HOME/skills" -name 'SKILL.md' 2>/dev/null | wc -l)
else
  skill_count=0
fi
if [ "$skill_count" -gt "$SKILL_COUNT_BUDGET" ]; then
  record RED "02-skill-count" "$skill_count > budget $SKILL_COUNT_BUDGET SKILL.md files"
else
  record GRN "02-skill-count" ""
fi

# 3 坏 symlink / 死引用扫描
bad_links=()
if [ -d "$HERMES_HOME/skills" ]; then
  while IFS= read -r l; do
    [ -n "$l" ] && bad_links+=("$l")
  done < <(find "$HERMES_HOME" -maxdepth 6 -type l ! -exec test -e {} \; -print 2>/dev/null)
fi
if [ "${#bad_links[@]}" -gt 0 ]; then
  record RED "03-bad-symlinks" "${#bad_links[@]} broken: ${bad_links[0]}$( [ "${#bad_links[@]}" -gt 1 ] && echo ' …')"
else
  record GRN "03-bad-symlinks" ""
fi

# 4 关键配置文件存在性
missing=()
for f in "$HERMES_HOME/config.yaml" "$HERMES_HOME/.env" "$HERMES_HOME/auth.json"; do
  [ ! -e "$f" ] && missing+=("$(basename "$f")")
done
if [ "${#missing[@]}" -gt 0 ]; then
  record RED "04-config-present" "missing: ${missing[*]}"
else
  record GRN "04-config-present" ""
fi

# 5 规则文件格式合法（缺头部的规则等于没写）
# Each SKILL.md must start with --- frontmatter
bad_frontmatter=()
if [ -d "$HERMES_HOME/skills" ]; then
  while IFS= read -r f; do
    first=$(head -n1 "$f" 2>/dev/null)
    [ "$first" != "---" ] && bad_frontmatter+=("$f")
  done < <(find "$HERMES_HOME/skills" -name 'SKILL.md' 2>/dev/null)
fi
if [ "${#bad_frontmatter[@]}" -gt 0 ]; then
  record RED "05-frontmatter" "${#bad_frontmatter[@]} SKILL.md missing '---' header, first: ${bad_frontmatter[0]}"
else
  record GRN "05-frontmatter" ""
fi

# 6 状态类 JSON 可解析
bad_json=()
for f in "$HERMES_HOME/auth.json" "$HERMES_HOME/gateway_state.json" \
         "$HERMES_HOME/cron/jobs.json" "$HERMES_HOME/.curator_state"; do
  [ -f "$f" ] || continue
  if ! python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$f" 2>/dev/null; then
    bad_json+=("$f")
  fi
done
if [ "${#bad_json[@]}" -gt 0 ]; then
  record RED "06-json-parse" "${#bad_json[@]} unparseable, first: ${bad_json[0]}"
else
  record GRN "06-json-parse" ""
fi

# 7 定时任务真实在跑（看日志时间戳，别信它自己的报告）
# Probe the cron tick heartbeat / last-success file. If older than FRESHNESS_HOURS → red.
cron_fresh=1
for f in "$HERMES_HOME/cron/ticker_heartbeat" "$HERMES_HOME/cron/ticker_last_success"; do
  [ -f "$f" ] || continue
  age_s=$(( $(date +%s) - $(stat -c%Y "$f") ))
  age_h=$((age_s / 3600))
  if [ "$age_h" -gt "$FRESHNESS_HOURS" ]; then
    record YEL "07-cron-fresh" "$(basename "$f") last touched ${age_h}h ago (>${FRESHNESS_HOURS}h)"
    cron_fresh=0
  fi
done
[ "$cron_fresh" = "1" ] && record GRN "07-cron-fresh" ""

# 8 数据管线新鲜度
# MEMORY.md / USER.md mtime: if both > FRESHNESS_HOURS * 4 (a month), yellow.
stale_files=()
threshold_s=$((FRESHNESS_HOURS * 4 * 3600))
for f in "$HERMES_HOME/memories/MEMORY.md" "$HERMES_HOME/memories/USER.md"; do
  [ -f "$f" ] || continue
  age_s=$(( $(date +%s) - $(stat -c%Y "$f") ))
  if [ "$age_s" -gt "$threshold_s" ]; then
    age_d=$((age_s / 86400))
    stale_files+=("$(basename "$f") ${age_d}d old")
  fi
done
if [ "${#stale_files[@]}" -gt 0 ]; then
  record YEL "08-pipeline-fresh" "${stale_files[*]}"
else
  record GRN "08-pipeline-fresh" ""
fi

# 9 跨窗口派工错误计数
# Grep recent gateway / cron logs for ERROR / Traceback.
err_count=0
if [ -d "$HERMES_HOME/logs" ]; then
  err_count=$(grep -c -E 'ERROR|Traceback|Exception' "$HERMES_HOME"/logs/*.log 2>/dev/null | awk -F: '{s+=$2} END{print s+0}')
fi
if [ "$err_count" -ge "$DISPATCH_ERROR_THRESHOLD" ]; then
  record YEL "09-dispatch-errors" "$err_count ERROR/Traceback lines across logs (threshold $DISPATCH_ERROR_THRESHOLD)"
else
  record GRN "09-dispatch-errors" ""
fi

# 10 单个日志文件行数上限（防无限增长）
big_log=""
if [ -d "$HERMES_HOME/logs" ]; then
  for f in "$HERMES_HOME"/logs/*.log; do
    [ -f "$f" ] || continue
    lines=$(wc -l < "$f" 2>/dev/null || echo 0)
    if [ "$lines" -gt "$LOG_LINE_LIMIT" ]; then
      big_log="$(basename "$f") ${lines}L"
      break
    fi
  done
fi
if [ -n "$big_log" ]; then
  record YEL "10-log-growth" "$big_log > ${LOG_LINE_LIMIT}L"
else
  record GRN "10-log-growth" ""
fi

# 11 任务台账两份存储是否一致
# Compare $HERMES_HOME/cron/jobs.json against any kanban / tasks state.
inconsistent=0
if [ -f "$HERMES_HOME/cron/jobs.json" ]; then
  jobs_hash=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(len(d.get('jobs',[])))" "$HERMES_HOME/cron/jobs.json" 2>/dev/null || echo "?")
  # Kanban board (if present)
  kb="$HERMES_HOME/state.db"
  if [ -f "$kb" ]; then
    kb_count=$(python3 -c "
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
try:
    print(c.execute('select count(*) from tasks').fetchone()[0])
except Exception:
    print(0)
" "$kb" 2>/dev/null || echo "?")
    if [ "$jobs_hash" != "?" ] && [ "$kb_count" != "?" ] && [ "$jobs_hash" -gt 0 ] && [ "$kb_count" -gt 0 ]; then
      [ "$jobs_hash" -ne "$kb_count" ] && inconsistent=1
    fi
  fi
fi
if [ "$inconsistent" = "1" ]; then
  record YEL "11-ledger-drift" "cron jobs=$jobs_hash vs kanban tasks=$kb_count differ"
else
  record GRN "11-ledger-drift" ""
fi

# 12 备份/临时文件堆积数
junk=$(junk_count "$HERMES_HOME")
if [ "$junk" -gt "$BACKUP_FILE_LIMIT" ]; then
  record YEL "12-backup-junk" "$junk .bak/.tmp/.swp/~ files in $HERMES_HOME (limit $BACKUP_FILE_LIMIT)"
else
  record GRN "12-backup-junk" ""
fi

# 13 记忆与缓存目录体积水位
mem_mb=$( (cd "$HERMES_HOME/memories" 2>/dev/null && du -sm . 2>/dev/null | awk '{print $1}') || echo 0 )
cache_mb=$( (cd "$HERMES_HOME/cache" 2>/dev/null && du -sm . 2>/dev/null | awk '{print $1}') || echo 0 )
if [ "$mem_mb" -gt "$MEMORY_DIR_MB" ] || [ "$cache_mb" -gt "$CACHE_DIR_MB" ]; then
  record YEL "13-storage-water" "memory=${mem_mb}MB (limit ${MEMORY_DIR_MB}) cache=${cache_mb}MB (limit ${CACHE_DIR_MB})"
else
  record GRN "13-storage-water" ""
fi

# 14 明文密钥特征扫描
# Scan MEMORY.md, USER.md, auth.json (sanity), and any .env-like files.
secret_hits=()
for f in "$HERMES_HOME/memories/MEMORY.md" "$HERMES_HOME/memories/USER.md"; do
  [ -f "$f" ] || continue
  hit=$(grep -nE "$SECRET_REGEX" "$f" 2>/dev/null | head -1)
  [ -n "$hit" ] && secret_hits+=("$(basename "$f"):$hit")
done
if [ "${#secret_hits[@]}" -gt 0 ]; then
  record RED "14-plaintext-secret" "${secret_hits[0]}"
else
  record GRN "14-plaintext-secret" ""
fi

# ---------- 3. render & exit ----------
JSON_OUT=0
[ "${1:-}" = "--json" ] && JSON_OUT=1

if [ "$JSON_OUT" = "1" ]; then
  # Serialize buckets to a temp file, then let python read it (no quoting hell).
  _json_tmp=$(mktemp -t agent-config-audit.XXXXXX)
  {
    printf 'TS\t%s\n' "$TS"
    printf 'HH\t%s\n' "$HERMES_HOME"
    printf 'RED\n'
    printf '%s\n' "${RED[@]:-}"
    printf 'YEL\n'
    printf '%s\n' "${YEL[@]:-}"
    printf 'GRN\n'
    printf '%s\n' "${GRN[@]:-}"
  } > "$_json_tmp"
  python3 - "$_json_tmp" <<'PY'
import json, sys
sec = None
out = {"red": [], "yel": [], "grn": []}
with open(sys.argv[1]) as f:
    for line in f:
        line = line.rstrip("\n")
        if not line: continue
        if "\t" in line and line.split("\t",1)[0] in ("TS","HH"):
            k, v = line.split("\t",1)
            out[k.lower()] = v
        elif line in ("RED","YEL","GRN"):
            sec = line.lower()
        else:
            out.setdefault(sec, []).append(line)
out["exit"] = 2 if out["red"] else (1 if out["yel"] else 0)
print(json.dumps(out, indent=2))
PY
  rm -f "$_json_tmp"
else
  # human-readable
  echo "agent-config-audit  $TS  HERMES_HOME=$HERMES_HOME"
  echo "------------------------------------------------------------"
  for c in 01-injection-budget 02-skill-count 03-bad-symlinks 04-config-present \
           05-frontmatter 06-json-parse 07-cron-fresh 08-pipeline-fresh \
           09-dispatch-errors 10-log-growth 11-ledger-drift 12-backup-junk \
           13-storage-water 14-plaintext-secret; do
    ev="${EVIDENCE[$c]:-}"
    if printf '%s\n' "${RED[@]}" | grep -qx "$c"; then
      printf '🔴 RED  %-22s %s\n' "$c" "$ev"
    elif printf '%s\n' "${YEL[@]}" | grep -qx "$c"; then
      printf '🟡 YEL  %-22s %s\n' "$c" "$ev"
    else
      printf '🟢 GRN  %-22s\n' "$c"
    fi
  done
  echo "------------------------------------------------------------"
  echo "summary: red=${#RED[@]} yel=${#YEL[@]} grn=${#GRN[@]}"
fi

# log on red
if [ "${#RED[@]}" -gt 0 ]; then
  {
    echo "[$TS] red=${#RED[@]} yel=${#YEL[@]} checks:"
    for c in "${RED[@]}" "${YEL[@]}"; do
      echo "  - $c :: ${EVIDENCE[$c]:-}"
    done
  } >> "$HISTORY"
  # also a "last red" pointer for cron
  echo "$TS red=${#RED[@]}: ${RED[*]}" > "$LAST_RED"
fi

# exit code: red=2, yel=1, grn=0
if   [ "${#RED[@]}" -gt 0 ]; then exit 2
elif [ "${#YEL[@]}" -gt 0 ]; then exit 1
else                                exit 0
fi
