#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT
#
# hermes-lib.sh — bin/hermes 与 libexec/hermes-{update,desktop} 的共享库：
# 布局常量（HERMES_HOME/checkout/venv/desktop release）、图标安装、FHS 容器
# 边界（宿主 GUI 环境解析 + --preserve/--share 旗标）。容器边界语义对齐
# appimage-run_lib/{gui-env,container}.scm 但刻意独立维护（部署域不同）。
# 约定：只做赋值与函数定义——不设 shell 选项、不 exit、副作用幂等。
# 文档：docs/scripts/hermes.md
# shellcheck disable=SC2034  # 常量由 source 本库的 bin/hermes 与 libexec 消费

# --- 布局常量 ---
# export 是契约：desktop 的 PRESERVE 正则要把 HERMES_HOME 透传进容器——壳
# main.cjs 靠它推导 ACTIVE_HERMES_ROOT，抓不到会 fallback 到 ~/.hermes。
: "${HERMES_HOME:=${XDG_DATA_HOME:-$HOME/.local/share}/hermes}"
export HERMES_HOME

HERMES_RUNTIME="${HERMES_HOME}/hermes-agent"
HERMES_CHECKOUT="${HERMES_RUNTIME}" # desktop 壳 isHermesSourceRoot 要求的源码根
HERMES_VENV="${HERMES_RUNTIME}/venv"
HERMES_CLI_BIN="${HERMES_VENV}/bin/hermes"
HERMES_DESKTOP_RELEASE_DIR="${HERMES_CHECKOUT}/apps/desktop/release/linux-unpacked"
HERMES_DESKTOP_BIN="${HERMES_DESKTOP_RELEASE_DIR}/Hermes"
HERMES_MANIFEST="${HERMES_HOME}/manifest.scm"

# --- XDG data home / hicolor 图标路径（只读解析，不回写全局） ---
HERMES_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
HERMES_HICOLOR_ROOT="${HERMES_DATA_HOME}/icons/hicolor"

hermes_install_icon_1024() {
  local _src="${1:?hermes_install_icon_1024: 缺少图标源路径参数}"
  local _dst_dir="${HERMES_HICOLOR_ROOT}/1024x1024/apps"
  mkdir -p "${_dst_dir}"
  cp "${_src}" "${_dst_dir}/hermes.png"
}

# --- 宿主 GUI 环境解析 + FHS 容器边界 ---

# 顺序依赖：须在 hermes_gui_env_resolve 之前调用（Ozone 探测依赖
# WAYLAND_DISPLAY）；不硬编码 wayland-0，否则 expose 不存在的 socket。
hermes_session_env_init() {
  RT_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
  WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
}

# 从宿主动态解析 GUI 环境（不硬编码主题/输入法/路径），结果全部 export，
# 经 hermes_build_share_flags 的 PRESERVE 正则透传进容器。
hermes_gui_env_resolve() {
  local _gtk_settings="${XDG_CONFIG_HOME:-$HOME/.config}/gtk-3.0/settings.ini"
  local _resolved_theme _resolved_im _p _d _extra_data="" _ozone

  # settings.ini 可能不存在（无 gtk-3 配置）——必须吞掉 sed 的非零码，
  # 否则命令替换赋值触发 set -e，desktop 启动在无任何输出的情况下退出
  _resolved_theme="${GTK_THEME:-$(sed -n 's/^gtk-theme-name=//p' "$_gtk_settings" 2>/dev/null || true)}"
  [[ -n "$_resolved_theme" ]] && export GTK_THEME="$_resolved_theme"

  _resolved_im="${GTK_IM_MODULE:-$(sed -n 's/^gtk-im-module=//p' "$_gtk_settings" 2>/dev/null || true)}"
  if [[ -n "$_resolved_im" ]]; then
    export GTK_IM_MODULE="$_resolved_im"
    export QT_IM_MODULE="${QT_IM_MODULE:-$_resolved_im}"
    export XMODIFIERS="@im=${_resolved_im}"
  fi

  if [[ -z "${GTK_IM_MODULE_DIR:-}" ]]; then
    for _p in "${HOME}/.guix-home/profile" "/run/current-system/profile"; do
      _d="${_p}/lib/gtk-3.0/3.0.0/immodules"
      [[ -d "$_d" ]] && export GTK_IM_MODULE_DIR="$_d" && break
    done
  fi

  for _p in "${HOME}/.guix-home/profile" "/run/current-system/profile"; do
    [[ -d "${_p}/share" ]] && _extra_data="${_extra_data:+${_extra_data}:}${_p}/share"
  done
  export XDG_DATA_DIRS="${_extra_data:+${_extra_data}:}${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"

  _ozone="x11"
  [[ -n "${WAYLAND_DISPLAY:-}" ]] && _ozone="wayland"
  export ELECTRON_OZONE_PLATFORM_HINT="${ELECTRON_OZONE_PLATFORM_HINT:-$_ozone}"
  export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-$_ozone}"
  export GDK_BACKEND="${GDK_BACKEND:-$_ozone}"
}

# --preserve 透传白名单，按语义分组；各组透传理由见 docs/scripts/hermes.md。
# 拼接顺序即正则 alternation 顺序，新增变量加在对应组末尾即可。
_HERMES_PRESERVE_VARS=(
  # 会话/显示基础
  DISPLAY WAYLAND_DISPLAY XDG_RUNTIME_DIR XDG_SESSION_TYPE XAUTHORITY DBUS_SESSION_BUS_ADDRESS
  # Qt / Electron 平台后端选择（Ozone hint）
  QT_QPA_PLATFORM ELECTRON_OZONE_PLATFORM_HINT
  # PulseAudio
  PULSE_SERVER PULSE_COOKIE
  # 语言环境（LC_* 是正则前缀模式）
  LANG 'LC_[A-Z]+'
  # 动态库 / Node 运行时调整
  LD_LIBRARY_PATH NODE_OPTIONS LIBGL_ALWAYS_SOFTWARE
  # desktop 壳靠它推导 ACTIVE_HERMES_ROOT；不 preserve 会 fallback 到 ~/.hermes
  HERMES_HOME
  # Remote gateway 模式（连宿主 hermes-backend 9119）
  HERMES_DESKTOP_REMOTE_URL HERMES_DESKTOP_REMOTE_TOKEN
  # cua-driver 原生 Wayland 抓屏开关：无它 Wayland 会话抓屏必炸
  CUA_DRIVER_RS_ENABLE_WAYLAND
  # 容器复用宿主 fontconfig 配置
  FONTCONFIG_FILE FONTCONFIG_PATH FONTCONFIG_CACHE_DIR
  # 容器内 GTK 复用宿主主题/图标/光标搜索路径
  XDG_DATA_DIRS XDG_CONFIG_HOME
  # fcitx5 输入法透传
  GTK_IM_MODULE QT_IM_MODULE XMODIFIERS
  # 光标主题搜索路径
  XCURSOR_PATH XCURSOR_THEME
  # GTK 主题、immodules 目录、GDK 后端
  GTK_THEME GTK_IM_MODULE_DIR GDK_BACKEND
)
HERMES_PRESERVE_RE="^($(
  IFS='|'
  printf '%s' "${_HERMES_PRESERVE_VARS[*]}"
))$"

# 构建 FHS 容器的 --share/--expose 旗标 → 全局数组 HERMES_SHARE_FLAGS。
# 前置：须先调 hermes_session_env_init（依赖 RT_DIR / WAYLAND_DISPLAY）。
# 每条挂载的理由（字体/GPU ioctl/sysfs/gnu-store/machine-id）见
# docs/scripts/hermes.md §容器边界——错了都是「窗口起不来/字体怪/软渲染」级别的坑。
hermes_build_share_flags() {
  HERMES_SHARE_FLAGS=(
    "--share=/tmp"
    "--share=${HOME}"
    "--expose=${RT_DIR}"                    # wayland + dbus socket 目录
    "--expose=${RT_DIR}/${WAYLAND_DISPLAY}" # 真实 compositor socket
  )
  local _pulse_dir="${RT_DIR}/pulse/native"
  [[ -S "${_pulse_dir}" ]] && HERMES_SHARE_FLAGS+=("--expose=${_pulse_dir}")
  [[ -d /run/current-system/profile/share/fonts ]] && HERMES_SHARE_FLAGS+=("--expose=/run/current-system/profile/share/fonts")
  # /dev/dri 必须 --share（读写）：GPU 进程要对 renderD128 发 ioctl，只读 bind 会 SIGILL
  [[ -d /dev/dri ]] && HERMES_SHARE_FLAGS+=("--share=/dev/dri")
  # /sys 只读：mesa drmGetDevice 要读 PCI 信息，缺了回退 llvmpipe 软渲染
  [[ -d /sys ]] && HERMES_SHARE_FLAGS+=("--expose=/sys")
  # /gnu/store 只读：venv python 软链指向 store，不挂则运行时解析失败
  [[ -d /gnu/store ]] && HERMES_SHARE_FLAGS+=("--expose=/gnu/store")
  # FHS 容器内 /etc 只读，dbus-uuidgen 写不进；直接 expose 宿主 machine-id
  [[ -e /etc/machine-id ]] && HERMES_SHARE_FLAGS+=("--expose=/etc/machine-id")
  [[ -n "${DISPLAY:-}" ]] && HERMES_SHARE_FLAGS+=("--share=/tmp/.X11-unix")
  [[ -d /run/current-system/profile/share ]] && HERMES_SHARE_FLAGS+=("--expose=/run/current-system/profile/share")
  # 末条 [[ -d ]] 为假时函数会带 1 返回 → set -e 下调用方误退，显式归零
  return 0
}
