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
# 拓扑常量 —— 同步自 source/information.scm（2026-09-22 与本机 /proc/mounts
# 逐项核对一致）。应急脚本必须自包含，因此在此硬编码；**改动仓库拓扑时必须
# 两处同步**（information.scm 与本文件），并顺手更新 docs/rescue-chroot.md。
# ---------------------------------------------------------------------------
LUKS_UUID="327f2e02-1e4f-48b2-87f0-797c481850c9"  # LUKS2 分区（本机: /dev/nvme0n1p2）
LUKS_MAPPER="root"                                # 解锁名 → /dev/mapper/root
BTRFS_DEV="/dev/mapper/root"                      # 解锁后的 Btrfs（label: Linux）
ESP_UUID="9699-52A2"                              # ESP vfat（本机: /dev/nvme0n1p1）
SWAP_UUID="169557cc-00a4-448c-9bb6-7bd80fc2b023"  # 明文 swap（休眠镜像住这，禁 mkswap/格式化）
MACHINE_ID="7edb01e408858012cb48ab345b029b63"     # md5("brokenshine")，随 etc 模板部署
REPO_IN_DATA="/data/Projects/Config/Guix-configs" # 配置仓库物理路径（Projects 在 %data-dirs）
BTRFS_OPTS="compress=zstd:3"

# 子卷挂载表: "子卷|挂载点"。父挂载点在前；umount 按逆序执行。
# 最小必挂集: @gnu / @persist/guix / @boot / DATA/Share；其余默认全挂（可注释掉可选行）。
SUBVOL_MOUNTS=(
  "SYSTEM/Guix/@gnu|/gnu"
  "SYSTEM/Guix/@persist/guix|/var/guix"
  "SYSTEM/Guix/@boot|/boot"
  "SYSTEM/Guix/@data|/var/lib"
  "DATA/Flatpak|/var/lib/flatpak"
  "DATA/LibVirt|/var/lib/libvirt"
  "SYSTEM/Guix/@nix|/nix"
  "SYSTEM/Guix/@persist/cache/root|/root/.cache"
  "SYSTEM/Guix/@persist/cache/var|/var/cache"
  "SYSTEM/Guix/@persist/db|/var/db"
  "SYSTEM/Guix/@persist/log|/var/log"
  "SYSTEM/Guix/@persist/tmp|/var/tmp"
  "SYSTEM/Guix/@tmp|/tmp"
  "SYSTEM/Guix/@etc/guix|/etc/guix"
  "SYSTEM/Guix/@etc/libvirt|/etc/libvirt"
  "SYSTEM/Guix/@etc/NetworkManager|/etc/NetworkManager"
  "SYSTEM/Guix/@etc/ssh|/etc/ssh"
)
DATA_SUBVOL="DATA/Share|/data" # /data 单列一条：配置仓库所在，最关键

# ---------------------------------------------------------------------------
set -euo pipefail

EXECUTE=0 # run() 据此决定回显还是执行
GO=0      # --go：跳过交互确认
FORCE=0   # --force：允许在运行中的 Guix 主机上运行

log()  { printf '[rescue] %s\n' "$*"; }
warn() { printf '[rescue][!] %s\n' "$*" >&2; }
die()  { warn "$*"; exit 1; }

# 回显一条命令；EXECUTE=1 时真正执行（失败由 set -e 中止，除非调用方带 || 容错）
run() {
  printf '  '
  printf '%q ' "$@"
  printf '\n'
  if [ "$EXECUTE" -eq 1 ]; then "$@"; fi
  return 0
}

path_mounted() { findmnt -rn -M "$1" >/dev/null 2>&1; }

check_deps() {
  local missing=() tool
  for tool in cryptsetup mount umount findmnt chroot; do
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

mount_plan() { # $1=目标根 $2=etc 模式(1/2/s) —— 只经 run() 产生副作用，供 dry-run/执行两遍复用
  local mnt=$1 etc_mode=$2 entry sub mp
  if [ -e "$BTRFS_DEV" ]; then
    log "1/6 LUKS 已解锁（$BTRFS_DEV 已存在），跳过 cryptsetup open。"
  else
    log "1/6 解密 LUKS（UUID=$LUKS_UUID）:"
    run cryptsetup open "UUID=$LUKS_UUID" "$LUKS_MAPPER"
  fi

  log "2/6 挂载 Btrfs 子卷（label Linux → $BTRFS_DEV）:"
  for entry in "${SUBVOL_MOUNTS[@]}"; do
    sub=${entry%%|*}
    mp=${entry#*|}
    if path_mounted "$mnt$mp"; then
      log "  已挂载，跳过: $mnt$mp"
    else
      run mkdir -p "$mnt$mp"
      run mount -t btrfs -o "subvol=$sub,$BTRFS_OPTS" "$BTRFS_DEV" "$mnt$mp"
    fi
  done
  sub=${DATA_SUBVOL%%|*}
  mp=${DATA_SUBVOL#*|}
  if path_mounted "$mnt$mp"; then
    log "  已挂载，跳过: $mnt$mp"
  else
    run mkdir -p "$mnt$mp"
    run mount -t btrfs -o "subvol=$sub,$BTRFS_OPTS" "$BTRFS_DEV" "$mnt$mp"
  fi

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

do_mount() {
  local mnt=${1:-}
  [ -n "$mnt" ] || die "用法: rescue-chroot.sh mount <目标根挂载点,如 /mnt>"
  case "$mnt" in
    /*) [ "$mnt" != "/" ] || die "拒绝把 / 作为目标根。" ;;
    *) die "目标根必须是绝对路径。" ;;
  esac
  check_deps
  guard_live_host

  local etc_mode reply
  etc_mode=$(choose_etc_mode)
  log "== mount 计划 → $mnt（dry-run 回显）=="
  EXECUTE=0
  mount_plan "$mnt" "$etc_mode"
  if [ "$GO" -eq 1 ]; then
    EXECUTE=1
    log "== 执行 =="
    mount_plan "$mnt" "$etc_mode"
  else
    printf '[rescue] 真实执行上述计划？输入 yes 继续（其余取消）: '
    read -r reply || reply=""
    if [ "$reply" = "yes" ]; then
      EXECUTE=1
      log "== 执行 =="
      mount_plan "$mnt" "$etc_mode"
    else
      log "已取消（未做任何改动）。"
    fi
  fi
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

  local shell_path inner reply p
  shell_path=$(resolve_shell "$mnt") || die "在 $mnt 中找不到可用的 bash（profile 与 store 都没有）。先完成 mount。"
  inner=$(build_chroot_inner "$shell_path")

  # chroot 前确保 rbind 就位（mount 子命令做过则跳过）
  for p in dev proc sys; do
    if ! path_mounted "$mnt/$p"; then
      warn "$mnt/$p 未 rbind——建议先跑 mount 子命令；仍要继续，chroot 内网络/设备可能异常。"
    fi
  done

  if [ "$GO" -eq 1 ]; then
    log "进入 chroot（shell: $shell_path）。exit 退出返回 live 环境。"
    exec chroot "$mnt" "$shell_path" -c "$inner"
  fi
  log "(dry-run) 将执行:"
  printf '  chroot %q %q -c %q\n' "$mnt" "$shell_path" "$inner"
  log "内层动作: 设 RESCUE 提示符 → PATH 加 root 的 current-guix → 尽力 cd $REPO_IN_DATA → login shell（自动读 /etc/profile）"
  printf '[rescue] 真实进入 chroot？输入 yes 继续（其余取消）: '
  read -r reply || reply=""
  if [ "$reply" = "yes" ]; then
    EXECUTE=1
    log "进入 chroot（shell: $shell_path）。exit 退出返回 live 环境。"
    exec chroot "$mnt" "$shell_path" -c "$inner"
  fi
  log "已取消。"
}

do_umount() {
  local mnt=${1:-}
  [ -n "$mnt" ] || die "用法: rescue-chroot.sh umount <目标根挂载点>"
  case "$mnt" in
    /*) [ "$mnt" != "/" ] || die "拒绝把 / 作为目标根。" ;;
    *) die "目标根必须是绝对路径。" ;;
  esac
  check_deps

  local entry mp i reply
  log "== umount 计划 ← $mnt（dry-run 回显，逆序）=="
  EXECUTE=0
  umount_plan "$mnt"
  if [ "$GO" -eq 1 ]; then
    EXECUTE=1
    log "== 执行 =="
    umount_plan "$mnt"
  else
    printf '[rescue] 真实执行上述卸载？输入 yes 继续（其余取消）: '
    read -r reply || reply=""
    if [ "$reply" = "yes" ]; then
      EXECUTE=1
      log "== 执行 =="
      umount_plan "$mnt"
    else
      log "已取消（未做任何改动）。"
    fi
  fi
}

umount_plan() { # 逆序: rbind → ESP → 子卷（叶子在先）→ /data → 关 LUKS。单条失败仅告警继续。
  local mnt=$1 entry mp i
  log "1/4 撤 rbind:"
  run umount "$mnt/dev" || warn "占用: $mnt/dev（有 shell 还在 chroot 里？）"
  run umount "$mnt/proc" || warn "占用: $mnt/proc"
  run umount "$mnt/sys" || warn "占用: $mnt/sys"
  log "2/4 卸载 ESP:"
  run umount "$mnt/efi" || warn "占用: $mnt/efi"
  log "3/4 逆序卸载子卷:"
  for ((i = ${#SUBVOL_MOUNTS[@]} - 1; i >= 0; i--)); do
    entry=${SUBVOL_MOUNTS[i]}
    mp=${entry#*|}
    run umount "$mnt$mp" || warn "占用: $mnt$mp"
  done
  mp=${DATA_SUBVOL#*|}
  run umount "$mnt$mp" || warn "占用: $mnt$mp"
  log "4/4 关闭 LUKS:"
  if [ -e "$BTRFS_DEV" ]; then
    run cryptsetup close "$LUKS_MAPPER" || warn "关闭失败: $BTRFS_DEV 可能仍被占用。"
  else
    log "  $BTRFS_DEV 不存在，跳过。"
  fi
  log "完成。"
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

拓扑常量同步自 source/information.scm；手册: docs/rescue-chroot.md
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
    status) do_status ;;
    mount) do_mount "${args[0]:-}" ;;
    chroot) do_chroot "${args[0]:-}" ;;
    umount) do_umount "${args[0]:-}" ;;
    "")
      usage
      exit 1
      ;;
    *) die "未知子命令: $cmd（见 help）" ;;
  esac
}

main "$@"
