#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT
#
# rescue-chroot.sh — 本机（tmpfs 根 + LUKS + Btrfs 子卷 + Limine）的 chroot 救援入口。
#
# 设计运行环境：live 环境（Guix ISO / Arch / Ubuntu 等）以 root 运行。
# 安全默认：不带 --go 时一律 dry-run，只逐条回显将执行的命令；
#           交互输入 yes 或追加 --go 才真正执行；检测到「当前就是运行中的
#           Guix 主机」时拒绝 mount/chroot（--force 可越过，危险）。
#
# 用法:
#   rescue-chroot.sh status              只读查看解锁/挂载状态（任何时候安全）
#   rescue-chroot.sh mount <MNT>         解密 + 挂全子卷 + rbind + 方案一重建 /etc 一条龙
#   rescue-chroot.sh chroot <MNT>        进入 chroot（store 内 bash，自动 source profile）
#   rescue-chroot.sh umount <MNT>        逆序卸载 + 关闭 LUKS
#   rescue-chroot.sh help                帮助
# 全局选项: --go 直接执行（跳过交互确认）；--force 允许在运行中的 Guix 主机上运行。
#
# 详细手册: docs/rescue-chroot.md
#
# ---------------------------------------------------------------------------
# 拓扑 —— 运行时解析自 source/information.scm（单一真源，换机只改那个
# 文件；config.org 的 file-systems 也引用同一段）。定位顺序：
#   1. 环境变量 INFO_SCM 显式指定
#   2. 脚本同目录下的 information.scm（U 盘救援：两个文件拷在一起即可）
#   3. 脚本所在 tools/ 的 ../source/information.scm（仓库内运行）
# live 环境没有 guile，故用 sed/grep 做受限文本解析（见 load_topology）。
# ---------------------------------------------------------------------------
INFO_SCM="${INFO_SCM:-}"
LUKS_UUID="" LUKS_MAPPER="" BTRFS_DEV="" ESP_UUID="" SWAP_UUID=""
MACHINE_ID="" REPO_IN_DATA="" BTRFS_OPTS=""
SUBVOL_MOUNTS=() DATA_SUBVOL=""
# 子卷挂载表: "子卷|挂载点"（解析自 %btrfs-subvolumes，排除 /home——家目录
# 持久化靠运行时 bind-mount，救援 chroot 用不到）。/data 单列一条：配置
# 仓库所在，最关键。

# ---------------------------------------------------------------------------
set -euo pipefail

EXECUTE=0 # run() 据此决定回显还是执行
GO=0      # --go：跳过交互确认
FORCE=0   # --force：允许在运行中的 Guix 主机上运行

log() { printf '[rescue] %s\n' "$*"; }
warn() { printf '[rescue][!] %s\n' "$*" >&2; }
die() {
	warn "$*"
	exit 1
}

# 回显一条命令；EXECUTE=1 时执行并把退出码透传给调用方：
# 普通调用处失败由 set -e 中止（mount 计划）；`run ... || warn` 处由调用方
# 容错（umount 单条失败仅告警）。dry-run 下不执行、返回 0。
run() {
	printf '  '
	printf '%q ' "$@"
	printf '\n'
	if [ "$EXECUTE" -eq 1 ]; then
		"$@"
	fi
}

# 交互确认：输入 yes 返回 0，其余返回 1
confirm() {
	local reply=""
	printf '[rescue] %s输入 yes 继续（其余取消）: ' "$1"
	read -r reply || reply=""
	[ "$reply" = "yes" ]
}

# 「先 dry-run 回显计划 → 确认 → 再真实执行」的统一骨架：
# 计划函数只经 run() 产生副作用，因此 dry/执行两遍复用同一份代码。
plan_then_execute() { # $1=计划标题；$2..=计划函数及其参数
	local title=$1
	shift
	EXECUTE=0
	log "== $title（dry-run 回显）=="
	"$@"
	if [ "$GO" -eq 1 ] || confirm "真实执行上述计划？"; then
		EXECUTE=1
		log "== 执行 =="
		"$@"
	else
		log "已取消（未做任何改动）。"
	fi
}

# 目标根必须是存在的绝对路径且不是 /
require_target_root() { # $1=mnt $2=缺参时的用法提示
	[ -n "$1" ] || die "$2"
	case "$1" in
	/*) [ "$1" != "/" ] || die "拒绝把 / 作为目标根。" ;;
	*) die "目标根必须是绝对路径。" ;;
	esac
}

path_mounted() { findmnt -rn -M "$1" >/dev/null 2>&1; }

# --- information.scm 解析（受限文本解析，不求值 Scheme）-----------------------

# 定位 information.scm（顺序见文件头注释）
locate_info_scm() {
	local script_dir
	script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
	if [ -z "$INFO_SCM" ]; then
		if [ -f "$script_dir/information.scm" ]; then
			INFO_SCM="$script_dir/information.scm"
		elif [ -f "$script_dir/../source/information.scm" ]; then
			INFO_SCM="$script_dir/../source/information.scm"
		else
			die "未找到 information.scm（拓扑单一真源）。把它放到本脚本同目录，或设 INFO_SCM=<路径>。"
		fi
	fi
	[ -f "$INFO_SCM" ] || die "INFO_SCM 指向的不是文件: $INFO_SCM"
}

# 提取 (define <name> "...") 的字符串值；只认顶格一行式 define
scm_define_str() { # $1=变量名（可带可不带 % 前缀，username 就不带）
	local val
	val=$(sed -nE "s/^[[:space:]]*\(define[[:space:]]+[%]?$1[[:space:]]+\"([^\"]*)\"\).*/\1/p" "$INFO_SCM")
	[ -n "$val" ] || die "未能从 $INFO_SCM 解析出 (define %$1 \"...\")"
	printf '%s\n' "$val"
}

# 提取 %btrfs-subvolumes 的 ("子卷" "挂载点") 二元组 → 每行 "子卷|挂载点"。
# define 行起至文件末尾范围内，只有数据行匹配行首 ("..." "...") 模式；
# 首条目与 '( 同行（quote + 列表括号 + pair 括号），故放行前导 ' 与 (。
scm_subvol_table() {
	sed -n '/^[[:space:]]*(define[[:space:]]\+[%]btrfs-subvolumes/,$p' "$INFO_SCM" |
		sed -nE "s/^[[:space:]]*'?\(*\\(\"([^\"]*)\"[[:space:]]+\"([^\"]*)\"\\).*/\\1|\\2/p"
}

# 解析全部拓扑常量；失败即中止（宁可拒绝运行也不用陈旧拓扑动磁盘）
load_topology() {
	locate_info_scm
	LUKS_UUID=$(scm_define_str luks-uuid)
	LUKS_MAPPER=$(scm_define_str luks-mapper)
	BTRFS_DEV="/dev/mapper/$LUKS_MAPPER"
	ESP_UUID=$(scm_define_str esp-uuid)
	SWAP_UUID=$(scm_define_str swap-uuid)
	BTRFS_OPTS=$(scm_define_str btrfs-mount-opts)
	REPO_IN_DATA=$(scm_define_str repo-in-data)
	# machine-id = md5(username)，与 information.scm 的 generate-machine-id 同式
	local user
	user=$(scm_define_str username)
	MACHINE_ID=$(printf '%s' "$user" | md5sum | cut -d' ' -f1)
	mapfile -t SUBVOL_MOUNTS < <(scm_subvol_table | grep -v '|/home$')
	[ "${#SUBVOL_MOUNTS[@]}" -gt 0 ] || die "未能从 $INFO_SCM 解析出 %btrfs-subvolumes 子卷表"
	DATA_SUBVOL="$(scm_define_str btrfs-subvol-data)|/data"
	log "拓扑解析自: $INFO_SCM"
}

check_deps() {
	local missing=() tool
	for tool in cryptsetup mount umount findmnt chroot md5sum; do
		command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
	done
	if [ "${#missing[@]}" -gt 0 ]; then
		warn "缺少依赖: ${missing[*]}"
		warn "  Arch:          pacman -S cryptsetup btrfs-progs util-linux"
		warn "  Debian/Ubuntu: apt install cryptsetup btrfs-progs util-linux"
		exit 1
	fi
	if ! command -v mount.btrfs >/dev/null 2>&1; then
		warn "缺 mount.btrfs（btrfs-progs 包），挂载 Btrfs 子卷会失败。"
	fi
}

guard_live_host() {
	if [ -d /run/current-system ] || grep -qs 'subvol=/SYSTEM/Guix/@gnu' /proc/self/mounts; then
		if [ "$FORCE" -eq 0 ]; then
			die "当前主机看起来就是运行中的 Guix 系统（/run/current-system 或 @gnu 已挂载）。救援脚本不应在此运行；确要继续（危险）追加 --force。"
		fi
		warn "--force 已指定：继续，后果自负。"
	fi
}

# 挂一条 "子卷|挂载点" 条目（已挂载则跳过）
mount_subvol() { # $1=目标根 $2=条目
	local mnt=$1 sub mp
	sub=${2%%|*}
	mp=${2#*|}
	if path_mounted "$mnt$mp"; then
		log "  已挂载，跳过: $mnt$mp"
	else
		run mkdir -p "$mnt$mp"
		run mount -t btrfs -o "subvol=$sub,$BTRFS_OPTS" "$BTRFS_DEV" "$mnt$mp"
	fi
}

# /etc 重建方式（docs/rescue-chroot.md §3.4）
choose_etc_mode() {
	local reply=""
	printf '\n/etc 重建方式（详见 docs/rescue-chroot.md §3.4）:\n'
	printf '  [1] 方案一: cp -a 拷贝当前代 etc 模板（推荐；缺 passwd/shadow，账户由后续 activation 补回）\n'
	printf '  [2] 方案二: 仅提示命令，进 chroot 后手动跑 /var/guix/profiles/system/activate（完整但副作用多）\n'
	printf '  [s] 跳过\n'
	printf '选择 [1/2/s，回车=1]: '
	read -r reply || reply=""
	case "$reply" in
	2) printf '2' ;;
	s | S) printf 's' ;;
	*) printf '1' ;;
	esac
}

mount_plan() { # $1=目标根 $2=etc 模式(1/2/s) —— 只经 run() 产生副作用
	local mnt=$1 etc_mode=$2 entry
	if [ -e "$BTRFS_DEV" ]; then
		log "1/6 LUKS 已解锁（$BTRFS_DEV 已存在），跳过 cryptsetup open。"
	else
		log "1/6 解密 LUKS（UUID=$LUKS_UUID）:"
		run cryptsetup open "UUID=$LUKS_UUID" "$LUKS_MAPPER"
	fi

	log "2/6 挂载 Btrfs 子卷（label Linux → $BTRFS_DEV）:"
	for entry in "${SUBVOL_MOUNTS[@]}" "$DATA_SUBVOL"; do
		mount_subvol "$mnt" "$entry"
	done

	log "3/6 挂载 ESP（UUID=$ESP_UUID → $mnt/efi）:"
	if path_mounted "$mnt/efi"; then
		log "  已挂载，跳过。"
	else
		run mkdir -p "$mnt/efi"
		run mount "UUID=$ESP_UUID" "$mnt/efi"
	fi

	log "4/6 rbind /dev /proc /sys:"
	run mkdir -p "$mnt/dev" "$mnt/proc" "$mnt/sys"
	run mount --rbind /dev "$mnt/dev"
	run mount --make-rslave "$mnt/dev"
	run mount --rbind /proc "$mnt/proc"
	run mount --make-rslave "$mnt/proc"
	run mount --rbind /sys "$mnt/sys"
	run mount --make-rslave "$mnt/sys"

	log "5/6 重建 /etc:"
	case "$etc_mode" in
	1)
		# etc 模板 = /var/guix/profiles/system/etc（符号链 → store 的 -etc 条目）。
		# cp -a 保留指向 store 的符号链；不含 passwd/shadow/group（activation 运行时生成）。
		run mkdir -p "$mnt/etc"
		run cp -a "$mnt/var/guix/profiles/system/etc/." "$mnt/etc/"
		;;
	2)
		log "  方案二：进入 chroot 后手动执行:"
		log "    /var/guix/profiles/system/activate"
		log "  （禁止在 chroot 之外运行——绝对路径会写坏 live 环境自身的目录）"
		;;
	*)
		log "  跳过。chroot 时将没有 /etc/profile，需手动 source（chroot 子命令已处理）。"
		;;
	esac

	log "6/6 网络:"
	run cp -L /etc/resolv.conf "$mnt/etc/resolv.conf"

	log "完成。下一步: rescue-chroot.sh chroot $mnt（或 --go 直接进）"
}

umount_plan() { # 逆序: rbind → ESP → 子卷（挂载点深者在先）→ 关 LUKS。单条失败仅告警继续。
	local mnt=$1 mp
	log "1/4 撤 rbind:"
	run umount "$mnt/dev" || warn "占用: $mnt/dev（有 shell 还在 chroot 里？）"
	run umount "$mnt/proc" || warn "占用: $mnt/proc"
	run umount "$mnt/sys" || warn "占用: $mnt/sys"
	log "2/4 卸载 ESP:"
	run umount "$mnt/efi" || warn "占用: $mnt/efi"
	log "3/4 卸载子卷（按挂载点深度降序，嵌套的先卸）:"
	# 按挂载点内 '/' 数降序卸载，天然先卸 /var/lib/flatpak 这类嵌套挂载点，
	# 不依赖 %btrfs-subvolumes 的书写顺序；-s 稳定排序让同层的 /data 保持
	# 输入序（表尾）最后卸
	printf '%s\n' "${SUBVOL_MOUNTS[@]}" "$DATA_SUBVOL" | sed 's/.*|//' |
		awk -F/ '{print NF, $0}' | sort -rns | cut -d' ' -f2- |
		while IFS= read -r mp; do
			run umount "$mnt$mp" || warn "占用: $mnt$mp"
		done
	log "4/4 关闭 LUKS:"
	if [ -e "$BTRFS_DEV" ]; then
		run cryptsetup close "$LUKS_MAPPER" || warn "关闭失败: $BTRFS_DEV 可能仍被占用。"
	else
		log "  $BTRFS_DEV 不存在，跳过。"
	fi
	log "完成。"
}

do_mount() {
	local mnt=${1:-}
	require_target_root "$mnt" "用法: rescue-chroot.sh mount <目标根挂载点,如 /mnt>"
	check_deps
	guard_live_host
	local etc_mode
	etc_mode=$(choose_etc_mode)
	plan_then_execute "mount 计划 → $mnt" mount_plan "$mnt" "$etc_mode"
}

resolve_shell() { # 输出 chroot 内可用的 bash 绝对路径（mnt 内路径）
	local mnt=$1 cand
	if [ -x "$mnt/var/guix/profiles/system/profile/bin/bash" ]; then
		printf '%s' "/var/guix/profiles/system/profile/bin/bash"
		return 0
	fi
	# 兜底: 直接在 store 里找 bash（tmpfs 根下 /bin 不存在，chroot 必须用 store 路径）
	for cand in "$mnt"/gnu/store/*-bash-*/bin/bash; do
		if [ -x "$cand" ]; then
			printf '%s' "${cand#"$mnt"}"
			return 0
		fi
	done
	return 1
}

build_chroot_inner() { # 组装传给 chroot bash -c 的内层脚本（$PATH 等必须在 chroot 内展开）
	local shell_path=$1
	printf 'export PS1="[RESCUE] \\w \\$ "; '
	# shellcheck disable=SC2016  # 刻意保留字面 $PATH，进入 chroot 后才展开
	printf 'export PATH="/var/guix/profiles/per-user/root/current-guix/bin:%s"; ' '$PATH'
	printf '[ -d "%s" ] && cd "%s"; ' "$REPO_IN_DATA" "$REPO_IN_DATA"
	printf 'exec "%s" --login -i' "$shell_path"
}

do_chroot() {
	local mnt=${1:-}
	[ -n "$mnt" ] || die "用法: rescue-chroot.sh chroot <目标根挂载点>"
	check_deps
	guard_live_host
	[ -d "$mnt/gnu/store" ] || die "$mnt/gnu/store 不存在——先运行: rescue-chroot.sh mount $mnt"

	local shell_path inner p
	shell_path=$(resolve_shell "$mnt") || die "在 $mnt 中找不到可用的 bash（profile 与 store 都没有）。先完成 mount。"
	inner=$(build_chroot_inner "$shell_path")

	# chroot 前确保 rbind 就位（mount 子命令做过则跳过）
	for p in dev proc sys; do
		if ! path_mounted "$mnt/$p"; then
			warn "$mnt/$p 未 rbind——建议先跑 mount 子命令；仍要继续，chroot 内网络/设备可能异常。"
		fi
	done

	if [ "$GO" -eq 1 ] || {
		log "(dry-run) 将执行:"
		printf '  chroot %q %q -c %q\n' "$mnt" "$shell_path" "$inner"
		log "内层动作: 设 RESCUE 提示符 → PATH 加 root 的 current-guix → 尽力 cd $REPO_IN_DATA → login shell（自动读 /etc/profile）"
		confirm "真实进入 chroot？"
	}; then
		EXECUTE=1
		log "进入 chroot（shell: $shell_path）。exit 退出返回 live 环境。"
		exec chroot "$mnt" "$shell_path" -c "$inner"
	fi
	log "已取消。"
}

do_umount() {
	local mnt=${1:-}
	require_target_root "$mnt" "用法: rescue-chroot.sh umount <目标根挂载点>"
	check_deps
	plan_then_execute "umount 计划 ← $mnt（逆序）" umount_plan "$mnt"
}

do_status() { # 纯只读：/proc、findmnt、readlink，无任何写操作
	log "== status（只读）=="
	local src esp
	if [ -e "$BTRFS_DEV" ]; then
		log "LUKS: 已解锁 → $BTRFS_DEV"
	else
		log "LUKS: 未解锁（无 $BTRFS_DEV）"
	fi
	src=$(readlink -f "/dev/disk/by-uuid/$LUKS_UUID" 2>/dev/null || true)
	if [ -n "$src" ]; then
		log "LUKS 分区（$LUKS_UUID）: $src"
	else
		log "LUKS 分区（$LUKS_UUID）: 未找到（live 环境缺 udev 数据属正常）"
	fi
	src=$(readlink -f "/dev/disk/by-uuid/$SWAP_UUID" 2>/dev/null || true)
	if [ -n "$src" ]; then
		log "swap 分区（$SWAP_UUID，休眠用，勿格式化）: $src"
	fi
	log "machine-id（固定值）: $MACHINE_ID"

	if grep -qs 'subvol=/SYSTEM/Guix/@gnu' /proc/self/mounts; then
		warn "检测到 @gnu 已挂载——当前主机是运行中的 Guix 系统。mount/chroot 需要 --force 才会放行。"
	fi
	grep -o 'subvol=[^[:space:],]*' /proc/self/mounts | sort -u | sed 's/^/  本机已挂子卷: /' || true

	esp=$(findmnt -rno TARGET -S "UUID=$ESP_UUID" 2>/dev/null || true)
	if [ -n "$esp" ]; then
		log "ESP（$ESP_UUID）已挂载于: $esp"
	else
		log "ESP（$ESP_UUID）: 未挂载"
	fi

	local g
	for g in /var/guix /mnt/var/guix; do
		if [ -e "$g/profiles/system" ]; then
			log "system 代链 $g/profiles/system -> $(readlink "$g/profiles/system")"
		fi
	done
	if [ -d /mnt/gnu/store ]; then
		log "/mnt 已含 /gnu/store——目标根可用，可执行 chroot 子命令。"
	fi
}

usage() {
	cat <<'EOF'
用法: rescue-chroot.sh [--go] [--force] <子命令> [参数]

子命令:
  status            只读查看当前解锁/挂载状态（任何时候安全）
  mount <MNT>       解密 LUKS + 挂全部 Btrfs 子卷 + rbind /dev,/proc,/sys
                    + 挂 ESP + 重建 /etc（方案一拷模板）+ resolv.conf
  chroot <MNT>      进入 chroot（store 内 bash，自动 source profile、PATH 加 guix）
  umount <MNT>      逆序卸载全部挂载并关闭 LUKS
  help              本帮助

选项:
  --go              真实执行（默认 dry-run 只回显计划；不带 --go 时也可交互输入 yes）
  --force           允许在检测到「运行中的 Guix 主机」时继续（危险）

示例（live USB 上，root）:
  rescue-chroot.sh status
  rescue-chroot.sh mount /mnt          # 先看计划
  rescue-chroot.sh mount /mnt --go     # 执行
  rescue-chroot.sh chroot /mnt --go
  rescue-chroot.sh umount /mnt --go

拓扑运行时解析自 source/information.scm（单一真源；可用 INFO_SCM 覆盖路径）；
手册: docs/rescue-chroot.md
EOF
}

main() {
	local cmd="" args=()
	while [ $# -gt 0 ]; do
		case "$1" in
		--go) GO=1 ;;
		--force) FORCE=1 ;;
		-h | --help | help)
			usage
			exit 0
			;;
		-*) die "未知选项: $1（见 help）" ;;
		*)
			if [ -z "$cmd" ]; then
				cmd=$1
			else
				args+=("$1")
			fi
			;;
		esac
		shift
	done
	case "$cmd" in
	status)
		load_topology
		do_status
		;;
	mount)
		load_topology
		do_mount "${args[0]:-}"
		;;
	chroot)
		load_topology
		do_chroot "${args[0]:-}"
		;;
	umount)
		load_topology
		do_umount "${args[0]:-}"
		;;
	"")
		usage
		exit 1
		;;
	*) die "未知子命令: $cmd（见 help）" ;;
	esac
}

main "$@"
