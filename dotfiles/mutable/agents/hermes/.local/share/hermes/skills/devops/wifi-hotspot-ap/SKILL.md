---
name: wifi-hotspot-ap
version: 1.0.0
author: Hermes Agent
license: MIT
description: 开 WiFi 热点让客户端流量过 mihomo 代理。触发：开热点 / 手机连电脑 / hotspot。
metadata:
  hermes:
    tags: [wifi, hotspot, ap, networkmanager, hostapd, mihomo]
    related_skills: [guix-configs-workflow, multi-hop-tcp-debugging]
---

# WiFi 热点（AP+STA 并发 + 流量自动过代理）

给手机等设备一次性开热点。本机栈：Guix + NetworkManager + mihomo(TUN) + nftables 信任模型。
现成脚本：`templates/hotspot-2g4.sh`（已验证可用，start/stop 两子命令）。

## When to Use

- 用户要开热点给手机/其它设备（触发词：开热点、手机连电脑、hotspot）。
- 热点客户端要过代理、或要与本机服务互通（syncthing、KDE Connect 等）。
- 排障：热点起不来（no IR / NM 抢接口）、客户端上不了网、访问不到本机服务。

## 先决侦察（决定路径，先做再动手）

1. **并发能力**：`iw list | sed -n '/valid interface combinations/,/^$/p'`。
   出现 `#{ managed } <= 1, #{ AP, ... } <= 1` + `#channels <= 1` = 可 STA+AP 并发，但**必须同信道**（AP 信道跟随 STA）。
2. **频段选择**：`iw dev <wifi-if> info`（channel/freq）+ `iw phy` 的频段 flags。
   country 00 下 5G 全段 `no IR` → AP 起不来（除非用打了 GO_CONCURRENT 补丁的 hostapd）；
   **把 STA 切到 2.4G，AP 同信道起** —— 这是最省事路径（2.4G 有 IR）。用户连 2.4G 要密码，让其手动 `nmcli device wifi connect <ssid-2.4G>`。
3. **代理接管不用配置**：mihomo auto-route 已加 `ip rule 9002: not from all iif lo lookup 2022` → 任何非 lo 入接口的转发流量自动进 Meta TUN，热点客户端天然过代理（`ip rule` 可确认）。
4. **防火墙**：规则集 input/forward 默认 drop，放行靠 `trusted_ifaces` 集合（真相源：Guix-configs `source/config.org` 的 `nftables-conf` 块）。把热点接口加进该集合 = 全端口放行，**不需要逐端口开**。

## 执行

本机已入仓正式实现：**`hotspot on|off|status`**（`~/.local/bin/hotspot`，源码在 Guix-configs `dotfiles/mutable/tools/hotspot/`，非 root 自动 sudo 重入）。先直接用它；仓库不可用或换机器时才走下面的模板路径。

本 harness 冻结 sudo：root 操作一律做成脚本交给用户执行，脚本分步打印，失败时用户贴回输出即可定位。

1. `hotspot status` 看现状（接口 / 进程 / nft 集合 / 客户端租约）→ `hotspot on` 启动；`on` 内部先自清理，能接管旧脚本起的热点。
2. 无仓库时：复制 `templates/hotspot-2g4.sh` 到 /tmp，改 `WIFI`/`APIF`/`SSID`/`PSK` 后 `sudo bash ... start`（`stop` 关闭并回滚：杀进程、撤 nft 元素、删接口、删 udev 规则）。
3. 脚本顺序：udev 隔离 → 建 uap0 → 配地址 → hostapd → dnsmasq → nft 放行

## 坑（按步骤）

- **NM 抢新接口**（最贵的一个）：uap0 一出现，NM/wpa_supplicant 立刻抓去当 station，把 type 从 AP 强转 managed 并独占打开，之后 `ip link set up` 报 `RTNETLINK answers: Device or resource busy`。修法：**创建接口前**写好 udev 规则 `/run/udev/rules.d/*.rules`（`SUBSYSTEM=="net", ACTION=="add", ATTR{address}=="<uap0 MAC>", ENV{NM_UNMANAGED}="1"`）+ `udevadm control --reload`。规则放 /run（重启即消失），别落 /etc —— /etc 是持久子卷，坏配置跨重启存活（历史断网事故的根因）。运行时兜底可加 `nmcli device set <apif> managed no`，但它有 race，不能替代 udev。
- **type 判定**：`iw dev <apif> info` 打印 `type AP`；`__ap` 只是 `interface add` 的语法。校验按 `AP` 判，等 `__ap` 会误报失败。
- **dnsmasq 撞 mihomo DNS**：不加限制时 dnsmasq 还要绑 `127.0.0.1:53`（被 mihomo 占），报 `failed to create listening socket for 127.0.0.1: Address already in use`。配 `listen-address=<gw>` + `except-interface=lo` + `user=root`，只绑热点网关；上游用 `server=127.0.0.1#53` 交给 mihomo（fake-ip）。
- **hostapd/dnsmasq 不在系统 profile**：`guix build hostapd dnsmasq` 取 store 路径直接调用（禁持久安装）。store 路径会随世代/GC 变化，脚本用具名环境变量（`HOSTAPD=`/`DNSMASQ=`）覆盖并在失效时报错提示重取。
- **hostapd 必须显式 `hw_mode`**：缺省只覆盖 2.4G 信道 1-14，5G 信道报 `Could not determine operating frequency`。
- 重跑 start 前要先清场：旧 hostapd 运行中时 `iw dev del` 删不掉接口。脚本 start 首步自带 stop 清理。
- **udev 规则匹配接口名即可**：`SUBSYSTEM=="net", KERNEL=="uap0", ACTION=="add", ENV{NM_UNMANAGED}="1"` 实测生效，不必先建一次接口去读 MAC（用 `ATTR{address}` 匹配也行，但多一步）。
- **Guix 下脚本内 PATH 只能追加**：写成 `PATH=/run/current-system/profile/bin:$PATH` 会遮蔽 `/run/privileged/bin` 的 setuid sudo，提权时报 `sudo: ... 必须属于用户 ID 0（的用户）并且设置 setuid 位`。用追加形式。
- **依赖路径动态解析，别硬编码**：store 路径随世代/GC 失效；脚本按 `command -v <bin>` → `guix build <pkg>` 两级取，环境变量只作兜底。
- **参数校验放提权前**：`--help` / 非法子命令在 `exec sudo` 之前判定，否则非交互场景直接卡在密码提示。

## 客户端 ↔ 本机互通（结论：无需额外开端口）

- 客户端访问本机服务：dst=网关地址命中 `ip rule 0 lookup local` → 直投本机，**不经 TUN**；nft 已由 trusted_ifaces 全放行。真正的瓶颈是服务只绑 `127.0.0.1`（如 syncthing GUI 8384），需要就改绑定或 socat 转发到网关地址。
- 本机访问客户端：源是网关地址，不走 rule 9002 的 lo 分支 → main 表直连，不经 TUN。
- 验证手法（不用 root）：
  - `ip route get <gw> from <client> iif <apif>` → 应 `local`（客户端可达本机）
  - `ip route get 255.255.255.255 from <client> iif <apif>` → 应 `broadcast dev lo`（广播走 local 表，不被 TUN 吞，局域网发现可用）
  - 客户端清单：`ip neigh show dev <apif>`、dnsmasq 租约文件（含主机名）、`ping -c2 <client>`
- Syncthing 实测：本机侧 `*:22000`（TCP+UDP，监听所有地址）客户端可直连；手机端把电脑设备地址填 `tcp://<gw>:22000`（等 UDP 21027 广播发现也行，手填最稳）。**手机端 22000 由 App 运行时才监听**——App 未启动时电脑侧探测得到"连接被拒绝"属正常，不必当网络问题排查。本机 GUI `8384` 只绑 127.0.0.1，手机浏览器打不开，需要时 socat 转发到网关地址。
- 客户端租约与主机名：`hotspot status` 读 `/var/lib/misc/dnsmasq.leases`；快速对账用 `ip neigh show dev <apif>` + `ping <client>`。

## 收尾

- 用完即 `sudo bash /tmp/hotspot-2g4.sh stop`。
- 常驻/自动化（可信 WiFi 触发自动热点）是另一个量级的工程，历史做过全套又被删（复杂度失控）；默认只做一次性脚本，用户明确要再做。
