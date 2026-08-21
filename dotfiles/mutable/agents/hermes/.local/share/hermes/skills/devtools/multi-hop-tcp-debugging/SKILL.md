---
name: multi-hop-tcp-debugging
description: "Diagnose TCP services that span multiple hops — rootlessport → container → iptables DNAT → QEMU user networking → guest VM, or any chained proxy / NAT / userspace forwarder. Triggers when a 'TCP service not reachable' symptom has multiple plausible layer-3/4/7 explanations, when `nc -zv` says succeeded but the application still errors, when packet counters on iptables / NAT rules stay at 0, or when the user reports an RDP/VNC/SSH/DB connection failing despite some TCP handshake seemingly working. Covers hop-by-hop verification, what `nc -zv succeeded` actually proves, packet-counter-driven root-causing, and how to spot a host-side listener (rootlessport, socat, haproxy) that has nothing behind it."
version: 1.0.0
platforms: [linux]
metadata:
  hermes:
    tags: [tcp, networking, debugging, rdp, qemu, podman, rootlessport, iptables, nat, devtools]
    related_skills: [electron-wayland-ime, hermes-skill-curation]
---

# Multi-hop TCP Debugging

> 当一个 TCP 服务跨越 **多个命名空间 / 端口转发链 / 网桥 / NAT / 协议代理层** 时，诊断它的标准工作流 —— 用逐跳验证替代单点探测。

适用场景的典型形态：

```
client
  └─ host (rootlessport / sshd / haproxy / socat / nginx stream)
       └─ container / VM (iptables NAT / 自有网络栈)
            └─ inner service (qemu user net / xrdp / 内嵌代理 / guest OS)
                 └─ real backend (guest VM 的 3389、容器内 socat 后端等)
```

RDP 经过 dockur/windows 容器是其中一个常见实例；同样形态还有 SSH 经 jump host、Docker publish 到非默认网络、k8s NodePort 经 kube-proxy 转发等。

## 触发条件

出现下列任一情况加载本 skill：

- 用户报告"xfreerdp / ssh / psql / curl 连不上某端点"，但 TCP 看起来"通"
- `nc -zv host port` 返回 succeeded，但应用仍报 `connection reset` / `read timeout` / `BIO_read retries exceeded`
- `iptables -t nat -L` 显示 DNAT 规则正确，但 `pkts/bytes` 计数器停在 0
- 容器 / VM 内 `ss -ltn` 看不到某端口的 listener，但 podman/nerdctl 显示该端口已 publish
- 同一主机跑多个 VM / 容器 + 多套端口转发，无法确定 xfreerdp 该连哪个目标
- 需要先**确认目标存在**才能诊断（不要先入为主假设某 VM 是正确的那个）

## 1. 方法论：逐跳验证框架

任何多跳 TCP 链路，按下面五跳**逐跳**验证，**不跳过任何一跳**，**不被单跳证据误导**。

### 1.1 列出链路上的所有跳

先**显式列出**你猜测的拓扑，并写下来（哪怕只是回复里的一段）。这一段不是为了给用户看 —— 是为了**强迫你检查假设**。

```
[client] ---> host:127.0.0.1:3389
                 |
                 v  (rootlessport / podman publish)
[container WinApps] ---> 10.89.0.2:3389
                 |
                 v  (iptables PREROUTING DNAT)
[vmnet bridge docker] ---> 172.30.0.1
                 |
                 v  (QEMU tap/qemu 用户态网)
[Windows guest] ---> 172.30.0.2:3389
```

每跳都有自己的地址族、自己的 listener、自己的 NAT/forward 规则。**不同跳的"通"等价于不同的事实**。

### 1.2 五跳验证清单

| 跳 | 命令 | 验证的事 | "通"等价于 |
| --- | --- | --- | --- |
| 1. host listener | `ss -ltnp | grep :PORT` | 主机有进程 listen 该端口 | 只证明有进程 accept SYN，**不证明后端存在** |
| 2. host → client | `nc -zv host PORT` (or `nc IP PORT`) | 主机 TCP 入口能 accept | 同上，**只到 rootlessport / publish 入口为止** |
| 3. container entry | `podman exec CNTR sh -c 'ss -ltn | grep :PORT'`<br>`podman exec CNTR nc -vz IP PORT` | 容器内端口有进程 listen 或转发 | **容器侧真有进程在 listen 这一条很关键** |
| 4. NAT/forward rule counters | `iptables -t nat -L PREROUTING -n -v`<br>`socat -d -d ... 2>&1` | NAT/forward 规则**真的有匹配** | pkts=0 ⇒ 包根本没到这一行（要么在更早的链被丢了，要么上游根本没人收 SYN） |
| 5. real backend | `podman exec CNTR nc -vz guest_ip guest_port`<br>或 VNC/noVNC 进 guest 系统内 `netstat -an` | **真实后端服务**在 listen | 确认 RDP/SSH/DB 等协议端口真实暴露 |

**常见反模式**：

- ❌ **只跑一次 `nc -zv host PORT` 就宣布"通了"**。这只到第 2 跳为止。
- ❌ **看到 `Connection refused` 在某跳就直接归因"服务没起"**。先看是哪一跳拒的 —— 可能在容器入口（10.89.0.2:3389 上无 listener），也可能在 guest 内 3389。**跳位置决定根因**。
- ❌ **看到 iptables 规则存在但 pkts=0 就以为"包丢了"**。先想包有没有真的到这一行 —— 如果更早的链已经 RST，pkts 当然不动。
- ❌ **看到应用层报错（`BIO_read retries exceeded` / `connection reset`）就直接归因到当前假设的那一跳**。换一条路再跑一次，看错误形态是否变化。

### 1.3 应用层错误码字典（按错误判定"在第几跳失败"）

| 错误 | 在哪一跳失败 |
| --- | --- |
| `Connection refused` | 跳 N 的入口 IP 上**完全没 listener** —— 内核 RST |
| `Connection timed out` | 包被静默丢弃（防火墙 DROP / 路由黑洞 / 后端无应答且不 RST） |
| `Connection reset by peer` (`ECONNRESET` / errno 104) | 跳 N 接收了 SYN，但**转发到下游时被 RST** —— 下游没 listener 或主动 reset |
| `BIO_read retries exceeded` | 应用层 read 超时，可能代理吞了流量 / 后端没应答字节 |
| `HTTP 502 / 503` | 上游代理/反代报告后端不可达 |
| `TLS handshake failed` | 后端没在预期的端口上应答 TLS（多半 RDP 被劫持成 HTTP 代理） |

> 应用层"读超时"和"RST"经常一起出现 —— 因为客户端先 read 超时，但底层实际在超时前已经被 RST。把错误码组合记下来，比单看一句 `connection failed` 信息量大得多。

## 2. 多套 VM / 容器并存：先确认目标

**在按上面五跳验证之前**，先回答："xfreerdp 该连哪一台？"

```
ps -eo pid,cmd | grep qemu
podman ps -a
```

把每台 VM / 容器的**端口发布情况**列出来：

- QEMU 裸进程：直接看 `-netdev user,hostfwd=...` 里的 hostfwd 列表，或 `qemu-monitor` telnet 进去 `info network`
- podman 容器：`podman port CNTR` 或 `podman inspect CNTR --format '{{json .NetworkSettings.Ports}}'`

不同 VM 可能用相同端口（如都 publish 3389），但只会有**一台**真正生效。

**反模式**：

- ❌ 主机跑着两个 QEMU Windows（一个 podman 容器、一个裸 qemu），xfreerdp 报失败就直接排查其中一台，**不确认用户到底要连哪台**
- ❌ 用户的"本地 windows"语义上指一个，但实际配置里存在多个候选 —— 先**列出来问用户**

## 3. 跨命名空间的工具技巧

跨 rootless 容器、rootlesskit 网络命名空间、容器内 PID 命名空间操作时，**默认你看不到任何东西**。下面的命令是逐跳验证工具箱。

### 3.1 看 host 侧真实监听者

```bash
ss -ltnp | grep :3389         # -p 看到 rootlessport / sshd / haproxy
ps -o pid,ppid,comm -p PID    # 看转发器的父进程链
ls -l /proc/$PID/exe          # 确认是 rootlessport 还是别的转发器
```

`rootlessport` 的存在是 podman rootless 模式的强标志。`rootlesskit` / `slirp4netns` 是另一种 rootless 网络栈。

### 3.2 看容器侧网络

```bash
podman exec CNTR ip -4 addr show        # 多个接口：eth0 (host net) / docker (vm bridge) / lo
podman exec CNTR ss -ltn
podman exec CNTR iptables -t nat -L PREROUTING -n -v
podman exec CNTR iptables -t nat -L POSTROUTING -n -v
podman exec CNTR arp -an                # vm guest 在 bridge 上的 MAC
podman exec CNTR cat /var/lib/misc/dnsmasq.leases  # DHCP lease
```

### 3.3 跨 rootlesskit 网络命名空间（一般进不去）

```bash
nsenter -t $ROOTLESSPORT_PID -n ss -ltn  # 多半会被 nsenter 拒（不允许的操作）
```

如果进不去，**就只通过容器入口 IP (10.89.0.2) 来间接验证** —— 这本身是一条有价值的信息。

### 3.4 看镜像 / 容器内启动脚本的 RDP 配置

```bash
podman inspect CNTR --format '{{.ImageName}} ({{.Id}})'
podman exec CNTR cat /run/entry.sh | head
podman exec CNTR cat /run/network.sh | grep -E 'hostfwd|DNAT|forward|3389'
```

dockur/windows 镜像的网络路径在 `network.sh` 里写死，iptables DNAT 配置也写在那里。**重启时跳过的配置常常藏在启动脚本的条件分支里**。

## 4. 跨层诊断的反模式（本次会话犯过）

按从最易犯到最严重的顺序：

1. ❌ **`nc -zv host PORT` 返回 succeeded 就说"通了"** —— 只证明了第 1、2 跳，没证明后端。

2. ❌ **看到应用层报错直接套上当前最显眼的解释**。比如：
   - `BIO_read retries exceeded` → "代理丢包" → 直接归因到 `http_proxy=7890` → 报告"问题在代理"。
   - 实际上**正确的诊断动作是绕开代理再跑一次**，让错误形态变化（超时 → RST）才能确认代理是叠加因素还是根因。

3. ❌ **同一容器网络栈里 `nc 127.0.0.1:PORT` `Connection refused` 就说"服务没起"**。先看：
   - 127.0.0.1 上是否有监听（`ss -ltn | grep :PORT`）？
   - 容器入口 IP（10.89.0.2:PORT）呢？
   - 容器内 guest IP（172.30.0.x:PORT）呢？
   三个地址，三件事，**别合并**。

4. ❌ **看到 iptables DNAT 规则存在但 pkts=0 就以为"包被静默丢"**。可能性有：
   - 包在更早的链上被 RST（容器入口 IP 上根本无 listener）
   - DNAT 规则的匹配条件与实际流量不匹配（如 multiport 排除集）
   - 表未生效（kernel 模块未加载、容器内 capabilities 被裁剪）
   **先核 PREROUTING 的早期规则和容器入口 IP 的 listener，再回来查 DNAT 计数器**。

5. ❌ **在 Windows guest 内部的某个 UI 截图里看到"启用远程桌面 = 开"，就认为 RDP 服务真的在 listen**。Windows 的开关改的是注册表 / 服务启动类型 / 防火墙规则，**不等于 TermService 已经起来**。直接 nc guest IP:3389 比相信 UI 截图可靠得多。

6. ❌ **不重启、不查看启动日志就把问题归到"VM 反复重启"**。看 iptables 计数器、ss 监听、容器日志三件套，比反复看 QEMU 启动循环日志更有信息量。

7. ❌ **让用户去重启 / 改配置，自己不验证假设**。在提"重启 WinApps 容器"之前，至少**先把链路画出来 + 给出三条互相佐证的证据**，让用户能判断重启是否值得。

## 5. 决策模板

当拿到 "TCP 服务连不上" 的报告，按下面流程产出报告：

### Step 1：拓扑陈述

```text
目标：用户想连 <协议> 到 <端点>
猜测链路：
  client → <跳 1> → <跳 2> → ... → <跳 N> → real backend
```

### Step 2：五跳验证状态表

```text
| 跳 | 命令 | 结果 | "通"等价于 |
|----|------|------|-----------|
| 1  | ss -ltnp |     |           |
| 2  | nc -zv   |     |           |
| 3  | podman exec ... ss |    |    |
| 4  | iptables -t nat -L -v |    |    |
| 5  | nc guest_ip |    |    |
```

### Step 3：失败跳定位

如果某跳失败，先用 **应用层错误码字典**（§1.3）判定失败模式，再去下一跳排查。

### Step 4：根因 + 修复建议

按从最便宜的"重启容器"到最贵的"改镜像"的顺序列出来。每条建议都要带上"验证方法"。

## 6. 配套

- `references/rdp-via-dockur-windows.md` —— 完整 RDP 链路案例（rootlessport + iptables DNAT + QEMU user net + Windows guest），含本次会话踩过的所有坑。
- `scripts/hop-check.sh` —— 五跳验证的脚本化版本，可在类似场景下复用。