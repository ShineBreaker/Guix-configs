#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
# SPDX-License-Identifier: MIT

# emergency-blue.sh — blue 不可用时的应急替代（tangle / home / rebuild / init / check）
# 零依赖 blue 与 blueprint.scm：bash + guix 即可跑，guix 调用与蓝图逐字一致
# 文档：docs/emergency-blue.md

set -euo pipefail

CONFIG_ORG="source/config.org"
CONFIG_SCM="tmp/config.scm"
CHANNEL_LOCK="source/channel.lock"
INFO_SCM="source/information.scm"

DRY_RUN=0
ASSUME_YES=0

die() {
  echo "emergency-blue: 错误: $*" >&2
  exit 1
}

warn() {
  echo "emergency-blue: 警告: $*" >&2
}

# %q 转义使输出可直接复制到 shell 重放
echo_cmd() {
  printf '>> 将执行:'
  printf ' %q' "$@"
  printf '\n'
}

# 所有 guix 调用都经此处：应急时用户必须看清在跑什么
run_cmd() {
  echo_cmd "$@"
  "$@"
}

# sudo 命令先确认；-y 跳过。stdin 不可读一律视为取消，绝不默认放行。
confirm_or_die() {
  local reply
  ((ASSUME_YES)) && return 0
  read -r -p "确认执行以上命令？[y/N] " reply || die "无法读取确认输入（stdin 已关闭），已取消"
  [[ "$reply" == "y" || "$reply" == "Y" ]] || die "已取消"
}

self_check() {
  [[ -f "$CONFIG_ORG" ]] || die "当前目录不是仓库根（找不到 $CONFIG_ORG）。请 cd 到 Guix-configs 仓库根后重试。"
  [[ -f "$CHANNEL_LOCK" ]] || die "当前目录不是仓库根（找不到 $CHANNEL_LOCK）。请 cd 到 Guix-configs 仓库根后重试。"
  command -v guix >/dev/null 2>&1 || die "找不到 guix 命令。应急环境至少需要已安装 Guix。"
}

# --- tangle ---------------------------------------------------------------

# information.scm 经 noweb <<ref>> 进入 tangle 产物，mtime 必须一并比较
config_is_fresh() {
  [[ -f "$CONFIG_SCM" ]] || return 1
  local src
  for src in "$CONFIG_ORG" "$INFO_SCM"; do
    [[ -f "$src" ]] || continue
    [[ "$CONFIG_SCM" -ot "$src" ]] && return 1
  done
  return 0
}

# 与 blue 同款 tangle 命令。env -u 清掉五个 EMACS* 变量，防止用户 emacs
# 的环境干扰新进程（同 blueprint.scm）。
do_tangle() {
  mkdir -p tmp
  run_cmd env \
    -u EMACSLOADPATH -u EMACSDATA -u EMACSDOC -u EMACSPATH -u INSIDE_EMACS \
    guix time-machine "--channels=$CHANNEL_LOCK" -- \
    shell emacs-minimal -- \
    emacs --quick --batch -l org \
    --eval "(require 'ob-tangle)" \
    --eval "(org-babel-tangle-file \"$CONFIG_ORG\")"
  [[ -f "$CONFIG_SCM" ]] || die "tangle 未产出 $CONFIG_SCM，请检查 $CONFIG_ORG 的 :tangle 头。"
}

ensure_config() {
  if config_is_fresh; then
    echo ">> 复用现有 $CONFIG_SCM（新于源文件，跳过 tangle）"
  else
    echo ">> $CONFIG_SCM 缺失或已过期，开始 tangle（首次会经 guix 下载 emacs-minimal）..."
    do_tangle
  fi
}

# --- 括号平衡检查 -----------------------------------------------------------

# blueprint.scm §3 词法扫描的 awk 移植（整文件兜底版）。与 blue 的边界差异
# 见 docs/emergency-blue.md §7。
paren_check() {
  local file="$1"
  [[ -f "$file" ]] || die "括号检查目标不存在: $file"
  awk -v f="$file" '
		{
			n = length($0)
			for (i = 1; i <= n; i++) {
				c = substr($0, i, 1)
				if (instr) {
					if (esc) { esc = 0 }
					else if (c == "\\") { esc = 1 }
					else if (c == "\"") { instr = 0 }
					continue
				}
				if (incom) continue
				if (c == "\"") { instr = 1; esc = 0 }
				else if (c == ";") { incom = 1 }
				else if (c == "(" || c == "[") { stack = stack c }
				else if (c == ")") {
					if (stack == "" || substr(stack, length(stack), 1) != "(") { bad = 1; exit }
					stack = substr(stack, 1, length(stack) - 1)
				}
				else if (c == "]") {
					if (stack == "" || substr(stack, length(stack), 1) != "[") { bad = 1; exit }
					stack = substr(stack, 1, length(stack) - 1)
				}
			}
			incom = 0
		}
		END {
			if (bad) { printf "[ERROR] %s: 括号类型错配 ([ 配 ) 或 ( 配 ])\n", f; exit 1 }
			if (instr) { printf "[ERROR] %s: 字符串未闭合\n", f; exit 1 }
			if (stack != "") { printf "[ERROR] %s: 不平衡（%d 个括号未闭合）\n", f, length(stack); exit 1 }
			printf "[OK] %s: 括号平衡\n", f
			exit 0
		}
	' "$file"
}

# 剥掉上次追加的 %system/%home 尾表达式，避免换目标（home ↔ system）时累积
strip_trailing_tail() {
  local last
  while :; do
    last="$(awk 'NF { l = $0 } END { if (l != "") print l }' "$CONFIG_SCM")"
    if [[ "$last" == "%system" || "$last" == "%home" ]]; then
      sed -i '$d' "$CONFIG_SCM"
    else
      break
    fi
  done
}

# guix 以文件最后一个表达式的值为配置对象，故 prepare 时追加 %system/%home
prepare_config() {
  local tail_expr="$1"
  ensure_config
  strip_trailing_tail
  printf '\n%s\n' "$tail_expr" >>"$CONFIG_SCM"
  paren_check "$CONFIG_SCM"
}

# --- 部署子命令 -------------------------------------------------------------

cmd_home() {
  prepare_config "%home"
  if ((DRY_RUN)); then
    echo "[预演] 验证 home 配置（不写入系统）"
    run_cmd guix time-machine "--channels=$CHANNEL_LOCK" -- \
      home build "$CONFIG_SCM" --dry-run
  else
    run_cmd guix time-machine "--channels=$CHANNEL_LOCK" -- \
      home reconfigure "$CONFIG_SCM" --allow-downgrades --fallback
  fi
}

cmd_rebuild() {
  prepare_config "%system"
  if ((DRY_RUN)); then
    echo "[预演] 验证 system 配置（不写入系统）"
    run_cmd guix time-machine "--channels=$CHANNEL_LOCK" -- \
      system build "$CONFIG_SCM" --dry-run
  else
    # --no-kexec 仅 system 有（防 kexec 挂死电源操作，home 不认此选项）
    run_cmd sudo guix time-machine "--channels=$CHANNEL_LOCK" -- \
      system reconfigure "$CONFIG_SCM" --allow-downgrades --fallback --no-kexec
  fi
}

# init 假设分区/加密/挂载已完成（前置见 README.org 装机节）；挂载点为显式
# 参数（blue 硬编码 /mnt）。init 没有 dry-run 开关，故预演降级为 system build。
cmd_init() {
  local mountpoint="${1:-}"
  [[ -n "$mountpoint" ]] || die "用法: $0 init <挂载点>（目标盘根分区挂载点，如 /mnt）"
  if [[ -d "$mountpoint" ]] && command -v mountpoint >/dev/null 2>&1; then
    mountpoint -q "$mountpoint" || warn "$mountpoint 不是挂载点——请确认已按 README.org 完成分区/加密/挂载，否则会装错地方。"
  else
    warn "无法验证 $mountpoint 是否为挂载点，请自行确认分区/加密/挂载已完成。"
  fi
  prepare_config "%system"
  if ((DRY_RUN)); then
    echo "[预演] 验证 system 配置（不执行 init）"
    run_cmd guix time-machine "--channels=$CHANNEL_LOCK" -- \
      system build "$CONFIG_SCM" --dry-run
  else
    run_cmd sudo guix time-machine "--channels=$CHANNEL_LOCK" -- \
      system init "$CONFIG_SCM" "$mountpoint"
  fi
}

# --- 使用帮助 ---------------------------------------------------------------

usage() {
  cat <<'EOF'
emergency-blue.sh —— blue 不可用时的应急替代

用法: ./tools/emergency-blue.sh [--dry-run] [-y] <子命令> [参数]

子命令:
  tangle            生成/复用 tmp/config.scm（新于源文件则复用，强制重编删掉 tmp/ 即可）
  home              应用 Guix Home 配置（无需 sudo）
  rebuild           应用 Guix System 配置（需要 sudo，执行前确认；-y 跳过确认）
  init <挂载点>     将系统安装到已挂载的目标盘（如 /mnt；需要 sudo）
  check [FILE...]   括号平衡检查（默认 tmp/config.scm）
  help              打印本帮助

全局选项:
  --dry-run         reconfigure/init 降级为 build --dry-run（只验证不写入）
  -y, --yes         跳过 sudo 命令的执行确认

所有 guix 调用均锁定 source/channel.lock 频道。详细文档:
docs/emergency-blue.md（含 blue 彻底不可用时的纯手动命令序列）
EOF
}

# --- 参数解析与入口 -----------------------------------------------------------

main() {
  local subcommand="" sub_args=() arg
  while (($# > 0)); do
    arg="$1"
    shift
    case "$arg" in
      --dry-run) DRY_RUN=1 ;;
      -y | --yes) ASSUME_YES=1 ;;
      -h | --help)
        usage
        exit 0
        ;;
      -*) die "未知选项: $arg（见 --help）" ;;
      *)
        if [[ -z "$subcommand" ]]; then
          subcommand="$arg"
        else
          sub_args+=("$arg")
        fi
        ;;
    esac
  done

  [[ -n "$subcommand" ]] || {
    usage
    exit 1
  }

  self_check

  case "$subcommand" in
    tangle)
      ensure_config
      paren_check "$CONFIG_SCM"
      ;;
    home) cmd_home ;;
    rebuild) cmd_rebuild ;;
    init) cmd_init "${sub_args[@]:-}" ;;
    check)
      if ((${#sub_args[@]})); then
        local f
        for f in "${sub_args[@]}"; do
          paren_check "$f"
        done
      else
        paren_check "$CONFIG_SCM"
      fi
      ;;
    help) usage ;;
    *) die "未知子命令: $subcommand（见 --help）" ;;
  esac
}

main "$@"
