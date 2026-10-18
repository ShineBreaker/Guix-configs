---
name: wifi-hotspot-sharing
description: Use when 开 WiFi 热点给其他设备并让流量过本机代理。
---

# WiFi 热点 + 客户端流量过代理

单网卡 Linux 主机开热点：STA 保持联网、AP 供其他设备接入，客户端流量经本机代理（TUN 型）出网。

> 本机已入仓命令 `hotspot on|off|status`；更完整的坑清单与互通验证见 `wifi-hotspot-ap`——两篇重叠，以那篇为准。

## 一、动手前必查的三项判据（顺序读，读完再决定方案）

1. 并发能力：`iw list` 的 `valid interface combinations`
   - 形如 `#{ managed } <= 1, #{ AP, P2P-client, P2P-GO } <= 1, #channels <= 1` → 支持 STA+AP 并发，但**必须同信道**：AP 的信道 = STA 当前信道，不能给 AP 另挑频段/频带。
2. 信道是否允许起 AP：`iw phy` 看目标信道的 IR 标记
   - 带 `no IR` 的信道起不了 AP。根因通常是监管域未设定（`iw reg get` 显示 `country 00`），**不是 hostapd 的 bug** —— 别先去 patch hostapd，先换到有 IR 的频段。
   - 常见形态：country 00 下 5G 全段 no IR、2.4G 有 IR → 热点走 2.4G，同时把 STA 也切到 2.4G（同信道要求）。
   - 检查命令：`iw phy | sed -n '/Band 2:/,/Band 4:/p' | grep -E '5[78][0-9][0-9] MHz'`（5G 段有无 no IR）／看 Band 1 有无 `no IR`。
3. 代理是否自动覆盖转发流量：本机若有 TUN 型代理（mihomo / sing-box），读路由策略：
   - `ip rule` 中若存在「非 lo 入接口 → tun 路由表」的规则（mihomo 为 `9002: not from all iif lo lookup 2022`），且该表含默认路由拆分（`ip route show table 2022` 里 `0.0.0.0/2 … 128.0.0.0/1 via 198.18.0.2 dev Meta`）→ **转发流量会自动进 TUN，不需要再叠 tproxy/redsocks，也不需要 NAT**。
   - 注意 TUN 的排除段（如 `route-exclude-address: 100.64.0.0/10`）内的目标不会过代理。

## 二、落地步骤

1. 切 STA 到有 IR 的频段（如 2.4G），记下信道：`iw dev <sta> info`。
2. 建 AP 接口并防 NetworkManager 抢占（**先隔离、后建接口，顺序反了必挂**）：
   ```
   # 1) 先写 udev 隔离规则（放 /run/udev/rules.d/，重启即失；勿落 /etc）
   printf 'SUBSYSTEM=="net", KERNEL=="<ap>", ACTION=="add", ENV{NM_UNMANAGED}="1"\n' > /run/udev/rules.d/75-hotspot.rules
   udevadm control --reload
   # 2) 再建接口
   iw dev <sta> interface add <ap> type __ap
   ip addr add 10.42.0.1/24 dev <ap>; ip link set <ap> up
   ```
   NM 在接口出现瞬间就把它抓给 wpa_supplicant 强转 station 并独占，之后 `ip link set up` 报 `RTNETLINK answers: Device or resource busy`；事后补 `nmcli device set <ap> managed no` 有 race，不能替代 udev。校验时 `iw dev <ap> info` 打印的是 `type AP`（`__ap` 只是 `interface add` 的语法）。NM 不会凭 profile 自动创建 AP 虚拟接口，这类接口必须自己用 iw 建。
3. hostapd：`hw_mode` 必须与频段匹配（2.4G=`g`、5G=`a`）并**显式写 `channel=`** —— 缺失/不匹配会报 `Could not determine operating frequency`。
4. dnsmasq：`--interface=<ap> --bind-interfaces` **并额外限定 `listen-address=<网关>` + `except-interface=lo`**——否则它还会去绑 `127.0.0.1:53`，与代理内建 DNS 端口冲突（`failed to create listening socket for 127.0.0.1: Address already in use`）；DHCP 的网关（option 3）与 DNS（option 6）都下发网关 IP；上游写 `server=127.0.0.1#53` 指向代理内建 DNS，让客户端拿到 fake-ip。
   - 坑：客户端若直查外部 53，代理的 `ip rule ... dport 53 lookup main suppress_prefixlength 0` 会让查询走直连 —— 绕过 fake-ip、可能被污染。DNS 必须由 DHCP 下发给网关。
5. 防火墙放行：本机 nft 若 input/forward 默认 drop，AP 接口要加入放行集合。
   - 本机（Guix-configs）集合为 `inet filter trusted_ifaces`：`nft add element inet filter trusted_ifaces { "<ap>" }`；收尾时 delete。
   - 该规则集开机一次性加载、运行期只做集合增删，**不要 flush ruleset**。
   - masquerade 通常不必要（流量进 TUN）；仅当客户端流量走直连/NAT 路径时才加。
6. 工具获取：hostapd / dnsmasq 可能不在系统 profile，用 `guix build hostapd dnsmasq` 取 store 路径直接引用 —— **禁止持久安装**，一次性使用。

## 三、交付方式（本机 sudo 被 harness 冻结）

- agent 不能执行 sudo：把整套流程写成幂等脚本（`start|stop`）交用户手动执行；连 WiFi 这类要密码的动作也让用户在自己的终端跑。
- agent 从旁验证：`ip -br addr show <ap>`、hostapd/dnsmasq 进程存活、nft 集合成员、`ss -lunp` 见到 DHCP 监听。
- 端到端过代理的验证只有真实客户端能做：设备连热点后访问回显 IP 的服务，出口应为代理节点而非本地宽带。
- 客户端不通时的排查序：先查 forward 链（接口是否在放行集合）→ 再看 `ip rule`/table 2022 → 最后查 DNS 是否拿到 fake-ip。

## 参考

- 可直接复制改造的启停脚本：`templates/hotspot-2g4.sh`（改顶部 WIFI/APIF/SSID/PSK 与 hostapd/dnsmasq 路径）。
