#!/usr/bin/env bash
# 2.4G 热点：udev 隔离 uap0 -> hostapd + dnsmasq + nft 放行；客户端流量由 mihomo TUN 接管
# 用法: sudo bash hotspot-2g4.sh [start|stop]
#
# 关键：新接口一出现 NM/wpa_supplicant 就会抢去当 station（强转 type、独占接口，
# 表现为 "RTNETLINK answers: Device or resource busy"）。所以先放 udev NM_UNMANAGED
# 规则（/run 下，重启即消失），再创建 uap0。
set -euo pipefail

# --- 按本机调整 ---------------------------------------------------------------
WIFI=wlp0s20f3          # STA 接口（须已连 2.4G，AP 同信道）
APIF=uap0               # AP 虚拟接口名
APMAC=dc:45:46:c0:78:3b # uap0 的 MAC（通常 = STA MAC 末位 +1；可先建一次接口用 iw dev 读实际值）
SSID=Hermes-AP
PSK=${PSK:-hermes2026}
GW=10.42.0.1
# guix build hostapd dnsmasq 取 store 路径；路径失效时用环境变量覆盖
HOSTAPD=${HOSTAPD:-/gnu/store/96h9p7kd5dg201jl1jfhnhcvp18k0n4k-hostapd-2.10}
DNSMASQ=${DNSMASQ:-/gnu/store/vgxdm9mgg1hnwj4wmcd9icy7ba2diwqj-dnsmasq-2.92}
# -----------------------------------------------------------------------------

CONF=/tmp/hotspot-hostapd.conf
DNS_CONF=/tmp/hotspot-dnsmasq.conf
RULE=/run/udev/rules.d/75-hotspot-uap0.rules
UDEVADM=$(command -v udevadm || echo /run/current-system/profile/bin/udevadm)
NFT=$(command -v nft || echo /run/current-system/profile/sbin/nft)

step() { echo "==> $*"; }
die() { echo "错误: $*" >&2; exit 1; }

stop() {
  [ -f /tmp/hotspot-hostapd.pid ] && kill "$(cat /tmp/hotspot-hostapd.pid)" 2>/dev/null || true
  [ -f /tmp/hotspot-dnsmasq.pid ] && kill "$(cat /tmp/hotspot-dnsmasq.pid)" 2>/dev/null || true
  pkill -f "hostapd.*hotspot-hostapd.conf" 2>/dev/null || true
  pkill -f "dnsmasq.*hotspot-dnsmasq.conf" 2>/dev/null || true
  "$NFT" delete element inet filter trusted_ifaces { "$APIF" } 2>/dev/null || true
  iw dev "$APIF" del 2>/dev/null || true
  rm -f "$RULE"
  [ -x "$UDEVADM" ] && "$UDEVADM" control --reload 2>/dev/null || true
  echo "热点已关闭"
}

start() {
  [ "$(id -u)" = 0 ] || die "需要 root: sudo bash $0 start"

  local freq ch
  freq=$(iw dev "$WIFI" info | sed -n 's/.*(\([0-9]*\) MHz).*/\1/p')
  ch=$(iw dev "$WIFI" info | sed -n 's/.*channel \([0-9]*\).*/\1/p')
  [ -n "$freq" ] && [ "$freq" -lt 3000 ] || die "STA 不在 2.4G（freq=${freq:-无}）。先执行: nmcli device wifi connect <ssid-2.4G>"
  [ -x "$HOSTAPD/sbin/hostapd" ] || die "hostapd 路径不存在，改跑: guix build hostapd"
  [ -x "$DNSMASQ/sbin/dnsmasq" ] || die "dnsmasq 路径不存在，改跑: guix build dnsmasq"

  step "1/6 写 udev 隔离规则 -> $RULE"
  stop >/dev/null 2>&1 || true
  mkdir -p /run/udev/rules.d
  printf 'SUBSYSTEM=="net", ACTION=="add", ATTR{address}=="%s", ENV{NM_UNMANAGED}="1"\n' "$APMAC" > "$RULE"
  "$UDEVADM" control --reload

  step "2/6 清理旧接口并创建 $APIF (__ap)"
  iw dev "$APIF" del 2>/dev/null || true
  sleep 1
  iw dev "$WIFI" interface add "$APIF" type __ap
  sleep 2
  nmcli device set "$APIF" managed no 2>/dev/null || true
  local typ
  typ=$(iw dev "$APIF" info | sed -n 's/.*type \([A-Za-z_]*\).*/\1/p')
  echo "    $APIF type=$typ, NM: $(nmcli -t -f DEVICE,STATE device status | grep -m1 "^$APIF:" || echo '未列出')"
  case "$typ" in AP|__ap) ;; *) die "$APIF 被 NM 抢走并强转成 $typ — udev 隔离未生效" ;; esac

  step "3/6 配地址并拉起接口"
  ip addr replace "$GW/24" dev "$APIF"
  ip link set "$APIF" up

  step "4/6 启动 hostapd (ch$ch)"
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
  sleep 1
  pgrep -F /tmp/hotspot-hostapd.pid >/dev/null || die "hostapd 未存活，看控制台输出"

  step "5/6 启动 dnsmasq (DHCP+DNS, 网关 $GW)"
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

  step "6/6 nft 放行 $APIF"
  "$NFT" add element inet filter trusted_ifaces { "$APIF" }

  echo
  echo "热点 $SSID 已启动: ch$ch / WPA2 / 密码 $PSK / 网关 $GW"
  echo "手机连上后流量 -> mihomo TUN -> 代理。关闭: sudo bash $0 stop"
}

case "${1:-start}" in
  start) start ;;
  stop) stop ;;
  *) echo "用法: sudo bash $0 [start|stop]" >&2; exit 2 ;;
esac
