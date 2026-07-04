#!/usr/bin/env bash
# hop-check.sh — 五跳验证工具脚本
#
# 用法:
#   ./hop-check.sh <host_port> [container_name] [guest_ip]
#
# 示例:
#   ./hop-check.sh 3389 WinApps 172.30.0.2
#   ./hop-check.sh 22
#   ./hop-check.sh 5900 myvm
#
# 输出的每一段对应 SKILL.md §1.2 的五跳。
# 每跳单独 fail 不会终止脚本 —— 跑完五跳，让你看到完整链路图。

set -u

HOST_PORT="${1:?用法: $0 <host_port> [container_name] [guest_ip]}"
CNTR="${2:-}"
GUEST_IP="${3:-}"

bold() { printf '\n\033[1m== %s ==\033[0m\n' "$*"; }
ok()   { printf '  ✅ %s\n' "$*"; }
warn() { printf '  ⚠️  %s\n' "$*"; }
bad()  { printf '  ❌ %s\n' "$*"; }

bold "链路概览"
echo "  host_port = $HOST_PORT"
echo "  container = ${CNTR:-(未指定)}"
echo "  guest_ip  = ${GUEST_IP:-(未指定)}"

# ---------- 跳 1: host listener ----------
bold "跳 1 — host listener (ss -ltnp)"
if command -v ss >/dev/null; then
  SS_OUT=$(ss -ltnp 2>/dev/null | grep ":${HOST_PORT}\b" || true)
  if [[ -n "$SS_OUT" ]]; then
    ok "主机有进程在 listen :$HOST_PORT"
    echo "$SS_OUT" | sed 's/^/      /'
  else
    bad "主机没有任何进程 listen :$HOST_PORT"
  fi
else
  warn "ss 命令缺失，跳过"
fi

# ---------- 跳 2: host TCP 入口 ----------
bold "跳 2 — host TCP 入口 (nc -zv)"
if command -v nc >/dev/null; then
  NC_OUT=$(timeout 4 nc -zv 127.0.0.1 "$HOST_PORT" 2>&1 || true)
  echo "$NC_OUT" | sed 's/^/      /'
  if echo "$NC_OUT" | grep -qi 'succeeded\|open'; then
    ok "TCP 入口 accept 通过（只证明 SYN 被收，不证明后端存在）"
  else
    bad "TCP 入口无法连接 —— 检查 rootlessport / 防火墙"
  fi
else
  warn "nc 命令缺失，跳过"
fi

# ---------- 跳 3: 容器入口 listener ----------
if [[ -n "$CNTR" ]] && command -v podman >/dev/null; then
  bold "跳 3 — 容器 ${CNTR} 内 listener (ss -ltn)"
  CNTR_SS=$(podman exec "$CNTR" ss -ltn 2>/dev/null | grep ":${HOST_PORT}\b" || true)
  if [[ -n "$CNTR_SS" ]]; then
    ok "容器内 :$HOST_PORT 有 listener"
    echo "$CNTR_SS" | sed 's/^/      /'
  else
    bad "容器内 :$HOST_PORT 无 listener —— SYN 在容器入口被 RST，root cause 多半在这里"
  fi

  bold "跳 3b — 容器入口 IP 上 nc 自检"
  CNTR_IPS=$(podman inspect "$CNTR" --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{"\n"}}{{end}}' 2>/dev/null | grep -v '^$' || true)
  if [[ -n "$CNTR_IPS" ]]; then
    while IFS= read -r ip; do
      [[ -z "$ip" ]] && continue
      NC_CNTR=$(timeout 3 podman exec "$CNTR" sh -c "printf X | nc -v -w 2 $ip $HOST_PORT" 2>&1 || true)
      if echo "$NC_CNTR" | grep -qi 'succeeded\|open'; then
        ok "容器内 nc $ip:$HOST_PORT succeeded"
      else
        bad "容器内 nc $ip:$HOST_PORT 失败"
        echo "$NC_CNTR" | sed 's/^/      /'
      fi
    done <<< "$CNTR_IPS"
  fi
else
  warn "未指定容器或无 podman，跳过跳 3"
fi

# ---------- 跳 4: NAT/forward 规则计数器 ----------
if [[ -n "$CNTR" ]] && command -v podman >/dev/null; then
  bold "跳 4 — 容器内 iptables NAT 规则计数器"
  if podman exec "$CNTR" sh -c 'command -v iptables >/dev/null' 2>/dev/null; then
    podman exec "$CNTR" iptables -t nat -L PREROUTING -n -v 2>&1 | sed 's/^/      /'
    PREROUTE_PKTS=$(podman exec "$CNTR" iptables -t nat -L PREROUTING -n -v -x 2>/dev/null | awk 'NR>2 && /DNAT/ {sum+=$1} END{print sum+0}')
    if [[ "${PREROUTE_PKTS:-0}" -eq 0 ]]; then
      bad "DNAT 计数器 = 0 —— SYN 在更早的链上已经被 RST/丢了，先回跳 3 查"
    else
      ok "DNAT 计数器 = ${PREROUTE_PKTS} —— 流量确实走过 DNAT"
    fi
  else
    warn "容器内无 iptables，跳过"
  fi
else
  warn "未指定容器，跳过跳 4"
fi

# ---------- 跳 5: real backend ----------
if [[ -n "$CNTR" ]] && [[ -n "$GUEST_IP" ]] && command -v podman >/dev/null; then
  bold "跳 5 — guest real backend (nc $GUEST_IP:$HOST_PORT 容器内)"
  NC_GUEST=$(timeout 4 podman exec "$CNTR" sh -c "printf X | nc -v -w 3 $GUEST_IP $HOST_PORT" 2>&1 || true)
  echo "$NC_GUEST" | sed 's/^/      /'
  if echo "$NC_GUEST" | grep -qi 'succeeded\|open'; then
    # 尝试 /etc/services 名字识别
    PROTO=$(getent services "$HOST_PORT" 2>/dev/null | awk '{print $1}' || echo '')
    if [[ -n "$PROTO" ]]; then
      ok "real backend 通，协议端口名 = $PROTO"
    else
      ok "real backend 通"
    fi
  else
    bad "real backend 不通 —— 检查 guest 内部服务状态（Windows: netstat / Linux: ss -ltn）"
  fi
elif [[ -z "$GUEST_IP" ]]; then
  warn "未指定 guest_ip，跳过跳 5（但这一跳很关键，建议补上）"
else
  warn "未指定容器，跳过跳 5"
fi

bold "完成"
echo "  回到 SKILL.md §1.2 表对照每跳状态。如有跳失败，应用层错误码见 §1.3。"