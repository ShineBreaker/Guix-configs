# NM 共享热点 dnsmasq 端口冲突 —— 完整诊断与修复

> 症状：手机能连上电脑热点 WiFi 但卡在"获取 IP 地址"，热点接口已分配静态 IP（`10.42.0.1/24`），`ipv4.method=shared`。

## 诊断三步

### 1. 确认 dnsmasq 是否在跑

```bash
pgrep -af dnsmasq
```

空输出 = dnsmasq 没跑。NM 的 `ipv4.method=shared` 应该自动启动 dnsmasq 提供 DHCP + DNS。

### 2. 查看 NM 日志找到失败原因

```bash
sudo grep -E 'dnsmasq|sharing|shared' /var/log/messages | tail -20
```

关键行模式：
```
dnsmasq-manager: starting dnsmasq...
dnsmasq[PID]: failed to create listening socket for 10.42.0.1: Address already in use
dnsmasq-manager: dnsmasq exited with error: Network access problem (address in use, permissions) (2)
```

`Address already in use` 说明 `10.42.0.1:53` 已被占用。

### 3. 找出是谁占用了 53 端口

```bash
sudo ss -tlnp | grep ':53'
sudo ss -ulnp | grep ':53'
```

典型输出：
```
LISTEN  *:53  users:(("mihomo",pid=1282,fd=11))   # ← 占用了 0.0.0.0:53
```

## 常见冲突进程

| 进程 | 典型配置 | 修复方法 |
|------|----------|----------|
| **mihomo** (clash-meta) | `dns.listen: 0.0.0.0:53` | 改为 `listen: 127.0.0.1:53` |
| **dnsmasq** (独立实例) | 系统级 dnsmasq service | 改其 listen-address 或停掉 |
| **systemd-resolved** | stub listener on 127.0.0.53 | Guix 下不常见 |
| **unbound / bind** | 递归 DNS | 检查配置中的 interface 绑定 |

## mihomo 特定情况

### 为什么 mihomo 可以安全改为只监听 127.0.0.1

mihomo 有两层 DNS 机制：

1. **`dns.listen`**：mihomo 自身的 DNS 服务器，对外提供 DNS 查询服务
2. **`dns-hijack` + nftables redirect**：在网络层劫持所有 DNS 流量（`any:53` / `tcp://any:53`），通过 nftables DNAT 到 mihomo 的 Meta 接口（`198.18.0.2:53`），再走 mihomo 的内部 DNS 链路

**两层独立运作**。把 `listen` 从 `0.0.0.0:53` 改为 `127.0.0.1:53` 后：
- 本地进程仍可通过 `127.0.0.1:53` 使用 mihomo DNS
- 网络层 DNS 劫持（nftables redirect）不受影响——它不走 `listen` 端口
- `10.42.0.1:53` 被释放，dnsmasq 可以绑定并提供热点 DNS

### mihomo nftables 对热点的特殊处理

mihomo 的 `tun.route-exclude-address` 配置了 `10.42.0.0/24`，在 nftables prerouting 链中有对应的 `return` 规则：

```
ip daddr { 10.42.0.0/24, 100.64.0.0/10 } return
```

这表示发往 `10.42.0.0/24` 的 DNS 查询不会被 mihomo 劫持。所以热点客户端使用 `10.42.0.1`（dnsmasq）作为 DNS 服务器是必要的——mihomo 主动放过了这些查询。

### 修复操作

```bash
# 1) 改 mihomo 配置（部署位置 AND 骨架源）
# ~/.config/mihomo/config.yaml → listen: 127.0.0.1:53
# source/files/skel/.config/mihomo/config.yaml → 同上

# 2) 重启 mihomo（system shepherd service）
sudo herd restart mihomo-daemon

# 3) 验证 mihomo 不再占用 *:53
sudo ss -tlnp | grep ':53'
# 应显示 127.0.0.1:53 而非 *:53

# 4) 重新激活热点，触发 NM 启动 dnsmasq
sudo nmcli connection down auto-hotspot
sudo nmcli connection up auto-hotspot

# 5) 验证
pgrep -af dnsmasq                          # 应有进程
sudo ss -ulnp | grep ':67'                 # DHCP 端口
sudo ss -tlnp | grep '10.42.0.1:53'        # DNS 端口
```

## 验证成功标志

```
pgrep -af dnsmasq
# → /gnu/store/.../sbin/dnsmasq --conf-file=/dev/null ... --listen-address=10.42.0.1 --dhcp-range=10.42.0.10,10.42.0.254,3600 ...

sudo tail -5 /var/log/messages | grep dnsmasq
# → dnsmasq[PID]: started, version UNKNOWN cachesize 150
# → dnsmasq-dhcp[PID]: DHCP, IP range 10.42.0.10 -- 10.42.0.254, lease time 1h
```

## 为什么不是防火墙问题

如果热点激活成功、nftables `nm-shared-wlp0s20f3` 表存在（含 NAT masquerade 和 forward 规则），且主 `inet filter` 的 input 链有 `iifname "wlp0s20f3" accept`——那么防火墙不是原因。DHCP 请求（UDP 67/68）在 `accept` 范围内。

## 为什么不是 IP forwarding 问题

IP forwarding 只影响数据包转发，不影响 DHCP 服务监听。手机卡在"获取 IP 地址"而不是"已连接但无法上网"说明 DHCP 阶段就失败了。

## 相关日志位置

| 信息 | 位置 |
|------|------|
| NM 启动 dnsmasq 的命令行 | `/var/log/messages` grep `dnsmasq-manager: command line:` |
| dnsmasq 启动失败原因 | `/var/log/messages` grep `dnsmasq.*failed` |
| dnsmasq DHCP 范围 | `/var/log/messages` grep `dnsmasq-dhcp` |
| 当前 DHCP 租约 | `/var/lib/NetworkManager/dnsmasq-wlp0s20f3.leases` |
| mihomo 日志 | `/var/log/mihomo.log` |
| nftables NM 热点表 | `sudo nft list table ip nm-shared-wlp0s20f3` |
