#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT
#
# hermes-lib.sh — hermes 入口 wrapper（bin/hermes，含 update/desktop 子命令
# 分发）与 libexec/hermes-{update,desktop} 两个子命令实体的共享库。
#
# 收敛历史上三份拷贝、且已互相漂移的逻辑（单一真理源）：
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
# 统一 export（漂移裁决：取 hermes wrapper 的导出版）。desktop 的 PRESERVE
# 正则要把 HERMES_HOME 透传进容器（desktop 壳 main.cjs 靠它推导
# ACTIVE_HERMES_ROOT，抓不到会 fallback 到默认 ~/.hermes 而找不到安装）；
# desktop/update 此前不导出属漂移遗漏而非设计，导出对 git/uv 等子进程无副作用。
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
# 两个 bin 曾各自解析 XDG_DATA_HOME 且已漂移（desktop 版无默认值 → set -u 下
# 未导出直接崩）。统一为：带默认、只读解析（不回写 XDG_DATA_HOME 全局）。
HERMES_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
HERMES_HICOLOR_ROOT="${HERMES_DATA_HOME}/icons/hicolor"

# 安装 1024px 原图到 hicolor（hermes desktop 启动用；覆盖写天然幂等）。
# 目标目录缺失时先 mkdir -p（此前直接 cp，hicolor/1024x1024/apps 不存在即崩）。
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

# --preserve 正则（与 appimage-run 一致：GUI/Wayland/音频/dbus 变量透传）
# 额外含 HERMES_HOME：desktop 壳(main.cjs) 靠它推导 ACTIVE_HERMES_ROOT=
# HERMES_HOME/hermes-agent，不 preserve 会 fallback 到默认 ~/.hermes 而找不到安装
# 额外含 FONTCONFIG_FILE/PATH：让容器复用宿主 fontconfig 配置，否则回退难看字体
# 额外含 XDG_DATA_DIRS/XDG_CONFIG_HOME：让容器内 GTK 复用宿主主题/图标/光标搜索路径
# 额外含 IME 变量（GTK_IM_MODULE/QT_IM_MODULE/XMODIFIERS）：fcitx5 输入法透传
# 额外含 XCURSOR_PATH/XCURSOR_THEME：光标主题搜索路径
# 额外含 HERMES_DESKTOP_REMOTE_URL/TOKEN：Remote gateway 模式（连宿主
# hermes-backend 9119）时透传给 desktop 壳，避免它在容器内 spawn 残缺 serve
# 额外含 CUA_DRIVER_RS_ENABLE_WAYLAND：cua-driver 原生 Wayland 抓屏开关
# （无它则 spawn 出的 cua-driver 走 X11，Wayland 会话上抓屏必炸）。宿主侧
# spawn 靠声明式环境变量（config.org extend-environment-variables）；
# 此处保证回退容器内 serve 时 computer-use 的子进程仍能继承到
HERMES_PRESERVE_RE='^(DISPLAY|WAYLAND_DISPLAY|XDG_RUNTIME_DIR|XDG_SESSION_TYPE|XAUTHORITY|DBUS_SESSION_BUS_ADDRESS|QT_QPA_PLATFORM|ELECTRON_OZONE_PLATFORM_HINT|PULSE_SERVER|PULSE_COOKIE|LANG|LC_[A-Z]+|LD_LIBRARY_PATH|NODE_OPTIONS|LIBGL_ALWAYS_SOFTWARE|HERMES_HOME|HERMES_DESKTOP_REMOTE_URL|HERMES_DESKTOP_REMOTE_TOKEN|CUA_DRIVER_RS_ENABLE_WAYLAND|FONTCONFIG_FILE|FONTCONFIG_PATH|FONTCONFIG_CACHE_DIR|XDG_DATA_DIRS|XDG_CONFIG_HOME|GTK_IM_MODULE|QT_IM_MODULE|XMODIFIERS|XCURSOR_PATH|XCURSOR_THEME|GTK_THEME|GTK_IM_MODULE_DIR|GDK_BACKEND)$'

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
