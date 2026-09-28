#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT
#
# hermes-lib.sh — hermes 入口 wrapper（bin/hermes，含 update/desktop 子命令
# 分发）与 libexec/hermes-{update,desktop} 两个子命令实体的共享库。
#
# 单一真理源，覆盖三类共享逻辑：
#   1. 布局常量：HERMES_HOME 解析 + hermes-agent checkout / venv / CLI /
#      desktop release / manifest 的路径约定（desktop 壳 main.cjs 硬编码的
#      布局，详见 hermes-update 头注释）
#   2. XDG data home / hicolor 图标路径解析 + 1024px 图标安装
#   3. FHS 容器边界配置：宿主 GUI 环境解析（GTK 主题/输入法/Ozone）、
#      --preserve 正则、--share/--expose 旗标构建
#
# 关于第 3 类：语义对齐 appimage-run_lib/gui-env.scm + container.scm（bash
# 手译副本），但**独立维护、不跨包引用**——部署域不同（appimage-run 服务任意
# AppImage，hermes 只服务自身 Electron 壳），各自演进漂移是刻意的。
#
# 约定：本库只做赋值与函数定义，不设 shell 选项（跟随调用方的
#       set -euo pipefail）；全部副作用幂等。

# ── 1. 布局常量 ──────────────────────────────────────────────────────────────
# 直接读系统设置的 HERMES_HOME；读不到才 fallback 到 XDG data 下的默认位置。
# 统一 export：desktop 的 PRESERVE 正则要把 HERMES_HOME 透传进容器（desktop 壳
# main.cjs 靠它推导 ACTIVE_HERMES_ROOT，抓不到会 fallback 到默认 ~/.hermes 而
# 找不到安装）；对 git/uv 等子进程无副作用。
: "${HERMES_HOME:=${XDG_DATA_HOME:-$HOME/.local/share}/hermes}"
export HERMES_HOME

HERMES_RUNTIME="${HERMES_HOME}/hermes-agent"
HERMES_CHECKOUT="${HERMES_RUNTIME}"      # desktop 壳要求的源码根（isHermesSourceRoot）
HERMES_VENV="${HERMES_RUNTIME}/venv"
HERMES_CLI_BIN="${HERMES_VENV}/bin/hermes"
HERMES_DESKTOP_RELEASE_DIR="${HERMES_CHECKOUT}/apps/desktop/release/linux-unpacked"
HERMES_DESKTOP_BIN="${HERMES_DESKTOP_RELEASE_DIR}/Hermes"
HERMES_MANIFEST="${HERMES_HOME}/manifest.scm"

# ── 2. XDG data home / hicolor 图标路径 ─────────────────────────────────────
# 带默认、只读解析（不回写 XDG_DATA_HOME 全局）——调用方在 set -u 下也安全。
HERMES_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
HERMES_HICOLOR_ROOT="${HERMES_DATA_HOME}/icons/hicolor"

# 安装 1024px 原图到 hicolor（hermes desktop 启动用；覆盖写天然幂等）。
# 目标目录按尺寸分层、未必存在，先 mkdir -p。
hermes_install_icon_1024() {
  local _src="${1:?hermes_install_icon_1024: 缺少图标源路径参数}"
  local _dst_dir="${HERMES_HICOLOR_ROOT}/1024x1024/apps"
  mkdir -p "${_dst_dir}"
  cp "${_src}" "${_dst_dir}/hermes.png"
}

# ── 3. 宿主 GUI 环境解析 + FHS 容器边界（preserve/share/exec 语义对齐
#       appimage-run container.scm；原为 hermes desktop 实体的内联段） ─────────────

# 会话基础变量：RT_DIR（wayland/dbus socket 所在）+ 真实 WAYLAND_DISPLAY。
# 不硬编码 wayland-0（否则 expose 不存在的 socket，Electron 连不上 compositor
# 导致窗口起不来）。须在 hermes_gui_env_resolve 之前调用（Ozone 探测依赖它）。
hermes_session_env_init() {
  RT_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
  WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
}

# 从宿主动态解析 GUI 环境（不硬编码主题/输入法/路径），结果全部 export，
# 经 hermes_build_share_flags 的 PRESERVE 正则透传进容器。
hermes_gui_env_resolve() {
  # settings.ini 是 GTK3 用户配置源；解析后 export，由 PRESERVE 透传进容器。
  local _gtk_settings="${XDG_CONFIG_HOME:-$HOME/.config}/gtk-3.0/settings.ini"
  local _resolved_theme _resolved_im _p _d _extra_data="" _ozone

  # GTK 主题：GTK_THEME 环境变量 > settings.ini gtk-theme-name
  _resolved_theme="${GTK_THEME:-$(sed -n 's/^gtk-theme-name=//p' "$_gtk_settings" 2>/dev/null)}"
  [[ -n "$_resolved_theme" ]] && export GTK_THEME="$_resolved_theme"

  # 输入法模块：GTK_IM_MODULE 环境变量 > settings.ini gtk-im-module
  _resolved_im="${GTK_IM_MODULE:-$(sed -n 's/^gtk-im-module=//p' "$_gtk_settings" 2>/dev/null)}"
  if [[ -n "$_resolved_im" ]]; then
    export GTK_IM_MODULE="$_resolved_im"
    export QT_IM_MODULE="${QT_IM_MODULE:-$_resolved_im}"
    export XMODIFIERS="@im=${_resolved_im}"
  fi

  # GTK3 immodules 目录（含 im-*.so）：遍历宿主 profile 找第一个存在的
  if [[ -z "${GTK_IM_MODULE_DIR:-}" ]]; then
    for _p in "${HOME}/.guix-home/profile" "/run/current-system/profile"; do
      _d="${_p}/lib/gtk-3.0/3.0.0/immodules"
      [[ -d "$_d" ]] && export GTK_IM_MODULE_DIR="$_d" && break
    done
  fi

  # XDG_DATA_DIRS：前置宿主 profile 的 share（主题/图标/光标搜索路径）
  for _p in "${HOME}/.guix-home/profile" "/run/current-system/profile"; do
    [[ -d "${_p}/share" ]] && _extra_data="${_extra_data:+${_extra_data}:}${_p}/share"
  done
  export XDG_DATA_DIRS="${_extra_data:+${_extra_data}:}${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"

  # Ozone / QPA 平台：有 WAYLAND_DISPLAY → wayland，否则 x11
  _ozone="x11"
  [[ -n "${WAYLAND_DISPLAY:-}" ]] && _ozone="wayland"
  export ELECTRON_OZONE_PLATFORM_HINT="${ELECTRON_OZONE_PLATFORM_HINT:-$_ozone}"
  export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-$_ozone}"
  export GDK_BACKEND="${GDK_BACKEND:-$_ozone}"
}

# --preserve 透传白名单，按语义分组（每行注释即该组透传理由）。
# 拼接顺序即正则 alternation 顺序，新增变量加在对应组末尾即可。
_HERMES_PRESERVE_VARS=(
	# 会话/显示基础：X11 与 Wayland socket、会话类型、X 认证、dbus 地址
	# （与 appimage-run 一致的 GUI/Wayland/音频/dbus 透传集）
	DISPLAY WAYLAND_DISPLAY XDG_RUNTIME_DIR XDG_SESSION_TYPE XAUTHORITY DBUS_SESSION_BUS_ADDRESS
	# Qt / Electron 平台后端选择（Ozone hint）
	QT_QPA_PLATFORM ELECTRON_OZONE_PLATFORM_HINT
	# PulseAudio
	PULSE_SERVER PULSE_COOKIE
	# 语言环境（LC_* 是正则前缀模式）
	LANG 'LC_[A-Z]+'
	# 动态库 / Node 运行时调整
	LD_LIBRARY_PATH NODE_OPTIONS LIBGL_ALWAYS_SOFTWARE
	# desktop 壳 main.cjs 靠它推导 ACTIVE_HERMES_ROOT=HERMES_HOME/hermes-agent；
	# 不 preserve 会 fallback 到默认 ~/.hermes 而找不到安装
	HERMES_HOME
	# Remote gateway 模式（连宿主 hermes-backend 9119）透传给 desktop 壳，
	# 避免它在容器内 spawn 残缺 serve
	HERMES_DESKTOP_REMOTE_URL HERMES_DESKTOP_REMOTE_TOKEN
	# cua-driver 原生 Wayland 抓屏开关：无它容器内 serve 的 computer-use 子进程
	# 走 X11，Wayland 会话上抓屏必炸。宿主侧 spawn 靠 config.org 的
	# extend-environment-variables 声明；此处保证回退容器内 serve 仍继承到
	CUA_DRIVER_RS_ENABLE_WAYLAND
	# 让容器复用宿主 fontconfig 配置，否则回退难看字体
	FONTCONFIG_FILE FONTCONFIG_PATH FONTCONFIG_CACHE_DIR
	# 让容器内 GTK 复用宿主主题/图标/光标搜索路径
	XDG_DATA_DIRS XDG_CONFIG_HOME
	# fcitx5 输入法透传
	GTK_IM_MODULE QT_IM_MODULE XMODIFIERS
	# 光标主题搜索路径
	XCURSOR_PATH XCURSOR_THEME
	# GTK 主题、immodules 目录、GDK 后端
	GTK_THEME GTK_IM_MODULE_DIR GDK_BACKEND
)
HERMES_PRESERVE_RE="^($(IFS='|'; printf '%s' "${_HERMES_PRESERVE_VARS[*]}"))$"

# 构建 FHS 容器的 --share/--expose 旗标 → 全局数组 HERMES_SHARE_FLAGS。
# 前置：须先调 hermes_session_env_init（依赖 RT_DIR / WAYLAND_DISPLAY）。
hermes_build_share_flags() {
  HERMES_SHARE_FLAGS=(
    "--share=/tmp"
    "--share=${HOME}"
    "--expose=${RT_DIR}"                                    # 含 wayland + dbus socket
    "--expose=${RT_DIR}/${WAYLAND_DISPLAY}"                 # 真实 compositor socket
  )
  local _pulse_dir="${RT_DIR}/pulse/native"
  [[ -S "${_pulse_dir}" ]] && HERMES_SHARE_FLAGS+=("--expose=${_pulse_dir}")
  # 系统字体目录挂进容器：宿主 609 字体里有更纱黑体(Sarasa)等，不挂则容器内
  # 只剩 ~ 下 132 个，Electron 回退文泉驿/DejaVu → 字体怪。guix 的 fontconfig
  # 默认扫描此路径，expose 后直接可见。
  [[ -d /run/current-system/profile/share/fonts ]] && HERMES_SHARE_FLAGS+=("--expose=/run/current-system/profile/share/fonts")
  # /dev/dri 用 --share（读写 bind）挂进容器：GPU 进程要对 renderD128 发 ioctl，
  # 必须可写。此前的 SIGILL(exitCode 4) 是 --expose（只读 bind）造成的——只读
  # 设备节点上 ioctl 失败，Chromium GPU 进程直接崩。本机 renderD128 是
  # crw-rw-rw-、用户在 video 组，读写挂入后走硬件渲染（动画/合成层恢复正常）。
  [[ -d /dev/dri ]] && HERMES_SHARE_FLAGS+=("--share=/dev/dri")
  # /sys 只读挂入：mesa 的 drmGetDevice() 要读 /sys/dev/char/<maj>:<min> 解析
  # DRM 设备的 PCI 信息，容器默认无 sysfs → "MESA-LOADER: failed to retrieve
  # device information" → 回退 llvmpipe 软件渲染。挂入后 glxinfo 实测为
  # Mesa Intel Arc (MTL) 硬件渲染器（OpenGL 4.6）。
  [[ -d /sys ]] && HERMES_SHARE_FLAGS+=("--expose=/sys")
  # expose /gnu/store：venv 的 python 软链到 /gnu/store/<hash>/python3.11，
  # 不挂进容器则 venv python 解析不到 → isActiveRuntimeUsable() 失败 →
  # desktop 误判未完成、回退跑 install.sh（exit 127, "prerequisites"）。只读挂。
  [[ -d /gnu/store ]] && HERMES_SHARE_FLAGS+=("--expose=/gnu/store")
  # 宿主 machine-id 挂进容器：FHS 容器内 /var /etc 只读，dbus-uuidgen 写不进；
  # 直接 expose 宿主 /etc/machine-id 让 dbus 初始化（否则报 machine-id 缺失）
  [[ -e /etc/machine-id ]] && HERMES_SHARE_FLAGS+=("--expose=/etc/machine-id")
  # xwayland socket（DISPLAY=:0 时）透进容器，走 X11 backend
  [[ -n "${DISPLAY:-}" ]] && HERMES_SHARE_FLAGS+=("--share=/tmp/.X11-unix")
  # 宿主系统 profile 的 share 目录（hicolor 图标主题等 fallback 资源）
  [[ -d /run/current-system/profile/share ]] && HERMES_SHARE_FLAGS+=("--expose=/run/current-system/profile/share")
  # 末条 [[ -d ]] 为假时函数会带 1 返回 → set -e 下调用方误退，显式归零
  return 0
}
