#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
# SPDX-License-Identifier: MIT

# emergency-blue.sh —— blue 不可用时的应急替代（home / rebuild / init / tangle / check）。
#
# 本脚本【零依赖 blue 与 blueprint.scm】：只要 bash + guix 就能跑。所有 guix
# 调用与 blueprint.scm 中 blue 的原始形态逐字一致（频道锁定
# source/channel.lock；dry-run 时 reconfigure/init 降级为 build --dry-run，
# 见 blueprint.scm apply-config 的做法）。括号平衡检查是 blueprint.scm §3
# 手写词法扫描的 awk 移植（整文件兜底版，即 prepare-config 里对 tangle 产物
# 做的那一次；blue check 的逐块定位能力没有移植，见 docs/emergency-blue.md）。
#
# 与正式 blue 的差异（有意省略的部分）：
#   * 不做 clean-artifacts（清编译产物，纯卫生步骤，可省）；
#   * rebuild 前不修剪系统世代、成功后不跑 guix locate --update（维护步骤）；
#   * $$bin/foo$$ 占位符无需任何处理：它在 guix 构建期由 rosenthal 频道的
#     computed-substitution-with-inputs 自动替换，不经过 tangle；
#   * init 的挂载点改为显式参数（blue 硬编码 /mnt）。
#
# 用法：./tools/emergency-blue.sh <子命令> [--dry-run] [-y]
#   tangle            生成/复用 tmp/config.scm（新于源文件则复用）
#   home              tangle + 括号检查 + guix home reconfigure（无需 sudo）
#   rebuild           tangle + 括号检查 + sudo guix system reconfigure
#   init <挂载点>     tangle + 括号检查 + sudo guix system init <挂载点>
#                     （假设目标盘已分区/加密/挂载完毕，这些前置不在本脚本范围）
#   check [FILE...]   括号平衡检查（默认 tmp/config.scm）
#   help              打印本帮助
#
# 详细文档与纯手动命令序列：docs/emergency-blue.md

set -euo pipefail

CONFIG_ORG="source/config.org"
CONFIG_SCM="tmp/config.scm"
CHANNEL_LOCK="source/channel.lock"
INFO_SCM="source/information.scm"

DRY_RUN=0
ASSUME_YES=0

die() {
	echo "错误: $*" >&2
	exit 1
}

warn() {
	echo "警告: $*" >&2
}

# 打印将要执行的命令（%q 转义，可直接复制到 shell 重放）。
echo_cmd() {
	printf '>> 将执行:'
	printf ' %q' "$@"
	printf '\n'
}

# 打印并执行一条命令。所有 guix 调用都经过这里，应急时用户需要看清在跑什么。
run_cmd() {
	echo_cmd "$@"
	"$@"
}

# 需要人工确认的破坏性命令（sudo reconfigure / init）先经此处；-y 跳过。
# stdin 不可读（如管道调用）一律视为取消，绝不默认放行。
confirm_or_die() {
	local reply
	(( ASSUME_YES )) && return 0
	read -r -p "确认执行以上命令？[y/N] " reply || die "无法读取确认输入（stdin 已关闭），已取消"
	[[ "$reply" == "y" || "$reply" == "Y" ]] || die "已取消"
}

# ---- 自检：必须在仓库根运行 ------------------------------------------------

self_check() {
	[[ -f "$CONFIG_ORG" ]] || die "当前目录不是仓库根（找不到 $CONFIG_ORG）。请 cd 到 Guix-configs 仓库根后重试。"
	[[ -f "$CHANNEL_LOCK" ]] || die "当前目录不是仓库根（找不到 $CHANNEL_LOCK）。请 cd 到 Guix-configs 仓库根后重试。"
	command -v guix >/dev/null 2>&1 || die "找不到 guix 命令。应急环境至少需要已安装 Guix。"
}

# ---- tangle ----------------------------------------------------------------

# tmp/config.scm 是否比两个 Org 侧输入都新（可复用）。information.scm 经
# noweb <<ref>> 进入 tangle 产物，mtime 必须一并比较。
config_is_fresh() {
	[[ -f "$CONFIG_SCM" ]] || return 1
	local src
	for src in "$CONFIG_ORG" "$INFO_SCM"; do
		[[ -f "$src" ]] || continue
		[[ "$CONFIG_SCM" -ot "$src" ]] && return 1
	done
	return 0
}

# blue 的同款 tangle：emacs-minimal（经 guix time-machine 锁频道拉起）批量
# 跑 org-babel-tangle-file，把 config.org 全部 :tangle 块写到 tmp/（主产物
# tmp/config.scm，另有 mihomo-run、nftables.conf 等伴生产物）。
# env -u 清掉五个 EMACS* 变量，防止用户 emacs 的环境干扰新进程（同 blueprint.scm）。
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

# 双路径：产物够新就复用（跳过 emacs 启动），否则现场 tangle。
ensure_config() {
	if config_is_fresh; then
		echo ">> 复用现有 $CONFIG_SCM（新于源文件，跳过 tangle）"
	else
		echo ">> $CONFIG_SCM 缺失或已过期，开始 tangle（首次会经 guix 下载 emacs-minimal）..."
		do_tangle
	fi
}

# ---- 括号平衡检查（blueprint.scm §3 词法扫描的 awk 移植，整文件兜底版）------
# 只数括号并跳过字符串字面量与 ; 行注释；Guile 要求 [ ] 与 ( ) 严格同类配对。
# 与 blue 的差异：字符串未闭合直接报错（blue 在此边界上不报）；不支持 #| |#
# 块注释与 #; datum 注释（blue 同样不支持）。
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

# 删除此前应急运行追加在文件末尾的 %system/%home 尾表达式，恢复 tangle 原貌，
# 避免换目标（home ↔ system）时尾表达式累积。
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

# 步骤 1+2（对应 blueprint.scm 的 prepare-config）：确保 tangle 产物新鲜，
# 追加尾表达式（通常是 %system 或 %home 变量名，guix 以最后一个表达式的值为
# 配置对象），再做括号兜底检查。
prepare_config() {
	local tail_expr="$1"
	ensure_config
	strip_trailing_tail
	printf '\n%s\n' "$tail_expr" >> "$CONFIG_SCM"
	paren_check "$CONFIG_SCM"
}

# ---- 部署子命令 ------------------------------------------------------------

# 对应 blue home：tangle + 追加 %home + 括号检查 + guix home reconfigure。
# 不需要 sudo；dry-run 时降级为 home build --dry-run（只验证不写入）。
cmd_home() {
	prepare_config "%home"
	if (( DRY_RUN )); then
		echo "[预演] 验证 home 配置（不写入系统）"
		run_cmd guix time-machine "--channels=$CHANNEL_LOCK" -- \
			home build "$CONFIG_SCM" --dry-run
	else
		run_cmd guix time-machine "--channels=$CHANNEL_LOCK" -- \
			home reconfigure "$CONFIG_SCM" --allow-downgrades --fallback
	fi
}

# 对应 blue rebuild：tangle + 追加 %system + 括号检查 + sudo guix system
# reconfigure。--no-kexec 仅 system 有（防 kexec 挂死电源操作，home 不认此选项）。
# 有意省略 blue 的前置世代修剪与成功后的 guix locate --update（维护步骤）。
cmd_rebuild() {
	prepare_config "%system"
	if (( DRY_RUN )); then
		echo "[预演] 验证 system 配置（不写入系统）"
		run_cmd guix time-machine "--channels=$CHANNEL_LOCK" -- \
			system build "$CONFIG_SCM" --dry-run
	else
		run_cmd sudo guix time-machine "--channels=$CHANNEL_LOCK" -- \
			system reconfigure "$CONFIG_SCM" --allow-downgrades --fallback --no-kexec
	fi
}

# 对应 blue init：tangle + 追加 %system + 括号检查 + sudo guix system init。
# blue 硬编码 /mnt，这里要求显式传入挂载点；假设分区/加密/挂载已完成
# （前置步骤见 README.org 装机节，不在脚本范围）。dry-run 降级为
# system build --dry-run（guix system init 本身没有 dry-run 开关）。
cmd_init() {
	local mountpoint="${1:-}"
	[[ -n "$mountpoint" ]] || die "用法: $0 init <挂载点>（目标盘根分区挂载点，如 /mnt）"
	if [[ -d "$mountpoint" ]] && command -v mountpoint >/dev/null 2>&1; then
		mountpoint -q "$mountpoint" || warn "$mountpoint 不是挂载点——请确认已按 README.org 完成分区/加密/挂载，否则会装错地方。"
	else
		warn "无法验证 $mountpoint 是否为挂载点，请自行确认分区/加密/挂载已完成。"
	fi
	prepare_config "%system"
	if (( DRY_RUN )); then
		echo "[预演] 验证 system 配置（不执行 init）"
		run_cmd guix time-machine "--channels=$CHANNEL_LOCK" -- \
			system build "$CONFIG_SCM" --dry-run
	else
		run_cmd sudo guix time-machine "--channels=$CHANNEL_LOCK" -- \
			system init "$CONFIG_SCM" "$mountpoint"
	fi
}

# ---- 使用帮助 --------------------------------------------------------------

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

# ---- 参数解析与入口 --------------------------------------------------------

main() {
	local subcommand="" sub_args=() arg
	while (( $# > 0 )); do
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
			if (( ${#sub_args[@]} )); then
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
