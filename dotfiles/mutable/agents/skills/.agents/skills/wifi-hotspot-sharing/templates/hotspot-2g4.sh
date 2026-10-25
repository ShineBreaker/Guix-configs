#!/usr/bin/env bash
# 单网卡热点模板：udev 隔离 uap0 -> hostapd + dnsmasq + nft 放行；客户端流量交本机 TUN 代理接管。
# 用法: sudo bash hotspot-2g4.sh [start|stop]
# 前置：STA 已连到有 IR 的频段（本机为 2.4G），且与 AP 同信道（网卡 #channels <= 1）。
# 本机（Guix-configs）已有入仓实现 hotspot on|off|status，优先用它；本模板供无仓库/换机器时复制改造。
set -euo pipefail

WIFI=wlp0s20f3            # STA 物理接口
APIF=uap0                 # 虚拟 AP 接口
SSID=Hermes-AP
PSK=${PSK:-hermes2026}    # 至少 8 位；收尾提醒用户改
GW=10.42.0.1
CONF=/tmp/hotspot-hostapd.conf
DNS_CONF=/tmp/hotspot-dnsmasq.conf
RULE=/run/udev/rules.d/75-hotspot-uap0.rules
# guix build hostapd dnsmasq 取路径（不持久安装）；路径随世代/GC 失效时用环境变量覆盖
HOSTAPD=${HOSTAPD:-/gnu/store/96h9p7kd5dg201jl1jfhnhcvp18k0n4k-hostapd-2.10}
DNSMASQ=${DNSMASQ:-/gnu/store/vgxdm9mgg1hnwj4wmcd9icy7ba2diwqj-dnsmasq-2.92}
UDEVADM=$(command -v udevadm || echo /run/current-system/profile/bin/udevadm)
NFT=$(command -v nft || echo /run/current-system/profile/sbin/nft)

stop() {
  [ -f /tmp/hotspot-hostapd.pid ] && kill "$(cat /tmp/hotspot-hostapd.pid)" 2>/dev/null || true
  [ -f /tmp/hotspot-dnsmasq.pid ] && kill "$(cat /tmp/hotspot-dnsmasq.pid)" 2>/dev/null || true
  pkill -f 'hotspot-hostapd.conf' 2>/dev/null || true
  pkill -f 'hotspot-dnsmasq.conf' 2>/dev/null || true
  "$NFT" delete element inet filter trusted_ifaces { "$APIF" } 2>/dev/null || true
  iw dev "$APIF" del 2>/dev/null || true
  rm -f "$RULE" /tmp/hotspot-hostapd.pid /tmp/hotspot-dnsmasq.pid
  [ -x "$UDEVADM" ] && "$UDEVADM" control --reload 2>/dev/null || true
  echo "热点已关闭"
}

die() { echo "错误: $*" >&2; exit 1; }

start() {
  [ "$(id -u)" = 0 ] || die "需要 root: sudo bash $0 start"

  # 同信道约束：AP 必须与 STA 同信道；no IR 信道起不了 AP，先确认频段
  local freq ch
  freq=$(iw dev "$WIFI" info | sed -n 's/.*(\([0-9]*\) MHz).*/\1/p')
  ch=$(iw dev "$WIFI" info | sed -n 's/.*channel \([0-9]*\).*/\1/p')
  [ -n "$freq" ] && [ "$freq" -lt 3000 ] || die "STA 不在 2.4G（freq=${freq:-无}）。先执行: nmcli device wifi connect <2.4G-SSID>"

  [ -x "$HOSTAPD/sbin/hostapd" ] || die "hostapd 路径不存在，改跑: guix build hostapd"
  [ -x "$DNSMASQ/sbin/dnsmasq" ] || die "dnsmasq 路径不存在，改跑: guix build dnsmasq"

  step_udev() {
    mkdir -p /run/udev/rules.d
    printf 'SUBSYSTEM=="net", KERNEL=="%s", ACTION=="add", ENV{NM_UNMANAGED}="1"\n' "$APIF" > "$RULE"
    "$UDEVADM" control --reload
  }

  # 关键顺序：先写 udev 隔离规则，再建接口。NM/wpa_supplicant 会抢新接口强转 station 并独占，
  # 事后补 nmcli managed no 有 race；顺序反了 ip link set up 必报 "Device or resource busy"。
  step_udev
  stop >/dev/null 2>&1 || true
  step_udev

  iw dev "$WIFI" interface add "$APIF" type __ap
  sleep 2
  nmcli device set "$APIF" managed no 2>/dev/null || true
  local typ
  typ=$(iw dev "$APIF" info | sed -n 's/.*type \([A-Za-z_]*\).*/\1/p')   # iw 打印 "AP"，不是 "__ap"
  case "$typ" in AP | __ap) ;; *) die "$APIF 被 NM 强转为 $typ（udev 隔离未生效）" ;; esac

  ip addr replace "$GW/24" dev "$APIF"
  ip link set "$APIF" up

  cat > "$CONF" <<EOF
interface=$APIF
driver=nl80211
ssid=$SSID
hw_mode=g
channel=$ch
wpa=2
wpa_passphrase=$PSK
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
EOF
  "$HOSTAPD/sbin/hostapd" -B -P /tmp/hotspot-hostapd.pid "$CONF"

  # DHCP 网关与 DNS 都下发网关；上游指到代理内建 DNS（fake-ip）。
  # listen-address/except-interface 必写：不写 dnsmasq 还会绑 127.0.0.1:53，与代理 DNS 端口冲突。
  cat > "$DNS_CONF" <<EOF
interface=$APIF
listen-address=$GW
except-interface=lo
bind-interfaces
user=root
dhcp-range=10.42.0.50,10.42.0.150,255.255.255.0,12h
dhcp-option=3,$GW
dhcp-option=6,$GW
no-resolv
server=127.0.0.1#53
EOF
  "$DNSMASQ/sbin/dnsmasq" --conf-file="$DNS_CONF" --pid-file=/tmp/hotspot-dnsmasq.pid

  # forward/input 默认 drop 的系统：热点接口必须进放行集合
  # shellcheck disable=SC1083  # { } 是 nft 集合字面量语法
  nft add element inet filter trusted_ifaces { "$APIF" }
  echo "热点 $SSID 已启动: $APIF ch$ch / WPA2 $PSK / DHCP+DNS $GW"
  echo "客户端流量 -> TUN 代理。关闭: sudo bash $0 stop"
}

case "${1:-start}" in
  start) start ;;
  stop) stop ;;
  *) echo "用法: sudo bash $0 [start|stop]" >&2; exit 2 ;;
esac
