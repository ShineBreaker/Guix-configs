<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# hotspot — 一键启停 WiFi 热点（2.4G，客户端流量走 mihomo TUN 代理）

`dotfiles/mutable/tools/hotspot/.local/bin/hotspot` · mutable（`blue stow tools/hotspot`，改源即生效）· 手动调用，非 root 自动 `sudo` 重入

## 用法

```console
$ hotspot on       # 启动；须先连 2.4G WiFi（AP 与 STA 同信道，见下）
$ hotspot off      # 关闭，清理接口、udev 规则、nft 放行与 pid 文件
$ hotspot status   # 默认动作：接口、进程、防火墙放行、客户端租约
```

SSID 与密码存于 secrets 体系的 `wifi-hotspot.age` 条目（`secrets set wifi-hotspot SSID '热点名'` / `secrets set wifi-hotspot PSK '密码'`；文件缺失时 `on` 会打印这两条命令）；网关固定 `10.42.0.1`，DHCP 池 `10.42.0.50-150`。

## 实现与约束

- **仅 2.4G，与 STA 同信道**：网卡并发组合是 `#{ managed } <= 1, #{ AP, ... } <= 1, #channels <= 1`——AP 必须与 STA 同信道，`on` 直接取 STA 当前信道。5G 不可用：本卡是 LAR（固件自管监管域），用户态 `iw reg set` 对 self-managed phy 无效，5G 信道永远 no IR，起不了 AP（曾评估过内核并发发射豁免路线，上游只为 P2P-GO 设计，打通需改内核源码，成本过高已放弃）；STA 不在 2.4G（2400-2494MHz）时拒绝。
- **udev 隔离新接口**：`uap0` 出现的瞬间 NetworkManager 会把它交给 wpa_supplicant 强转 station 并独占，之后的 `ip link set up` 报 `RTNETLINK answers: Device or resource busy`。脚本先写 `/run/udev/rules.d/75-hotspot-uap0.rules`（`ENV{NM_UNMANAGED}="1"`，内存盘、重启即失），再建接口；`off` 时删除规则。
- **dnsmasq 只绑网关地址**：`127.0.0.1:53` 被 mihomo 的 DNS 占用，dnsmasq 必须用 `listen-address=10.42.0.1` + `except-interface=lo` 限定绑定，否则启动即报端口占用。
- **nft 放行**：接口加入 `inet filter trusted_ifaces` 集合（接口信任模型：input/forward 整接口全端口放行），`off` 时移除。规则集开机一次性加载，运行期只做集合增删。
- **代理接管转发流量**：客户端流量命中 mihomo 的 `ip rule 9002`（非 lo 入接口 → 表 2022 → `Meta` TUN），无需 tproxy 或 NAT；DNS 由 dnsmasq 转发到 `127.0.0.1:53` 拿到 fake-ip。客户端访问本机服务（如 Syncthing `22000`）走 `local` 表直投，不过代理。
- **依赖获取**：hostapd / dnsmasq 不在系统 profile，脚本先查 `PATH`，找不到就用 `guix build` 取 store 路径（一次性使用，不持久安装）。

## 排障

- `uap0` 被强转成 `managed`：udev 规则未生效——确认 `/run/udev/rules.d/75-hotspot-uap0.rules` 内容与 `udevadm control --reload` 执行成功。
- hostapd 报 `Could not determine operating frequency`：`hw_mode` 与 `channel` 的频段不匹配（2.4G 用 `g`、5G 用 `a`）。
- dnsmasq 报 `failed to create listening socket for 127.0.0.1`：缺少 `listen-address` / `except-interface=lo` 限定。
- 客户端连上但不通：依次查 forward 链（接口是否在 `trusted_ifaces`）→ `ip rule` 与 `ip route show table 2022`（是否进 TUN）→ 客户端 DNS 是否指向网关。
