# RDP via dockur/windows podman 容器 — 完整案例留痕

> 2026-06-28 一次 xfreerdp 失败的诊断全程。本文件是 `multi-hop-tcp-debugging` SKILL.md 的具体案例，演示方法论在真实场景里怎么落地。

## 环境

- 主机：Guix System（rootless podman）
- 主机期望目标：连本地 `127.0.0.1:3389`
- 真实拓扑：xfreerdp → rootlessport → podman WinApps 容器（10.89.0.2）→ iptables DNAT → docker bridge → QEMU tap → Windows guest 172.30.0.2
- 镜像：`ghcr.io/dockur/windows:latest`
- 同时主机还跑了**另一台**裸 qemu-system-x86_64（pid 750，name=windows），但它只暴露 VNC :0 + monitor 7100，**没碰 3389**

## 错误现象

```text
$ xfreerdp /u:"BrokenShine" /p:"114514" /v:127.0.0.1 /cert:tofu /sec:tls +auth-only
[ERROR] transport_read_layer: BIO_read retries exceeded
[ERROR] freerdp_connect_begin: Authentication only, exit status 0
```

## 第一次错误归因（错的）

看到 `BIO_read retries exceeded`，第一反应是"代理丢包"。理由是环境里有：

```
http_proxy=http://127.0.0.1:7890
https_proxy=http://127.0.0.1:7890
```

xfreerdp 看到 HTTP 代理就走 CONNECT 隧道，CONNECT 200 之后代理对非 HTTP 流量静默丢弃，read 超时报 retries exceeded。

**这个归因只是部分对**：绕开代理后错误形态**变了**：

```
[ERROR] BIO_read returned a system error 104: 连接被对方重置
[ERROR] ERRCONNECT_CONNECT_TRANSPORT_FAILED [0x0002000D]
```

错误从 read timeout 变成 RST，说明**代理是叠加因素，不是根因**。如果一开始就只盯着代理，会得出"绕开代理就好了"的错误结论。

## 五跳验证执行

按 SKILL.md §1.2 跑：

### 跳 1：host listener

```bash
$ ss -ltnp | grep :3389
LISTEN 0 4096 *:3389 *:* users:(("rootlessport",pid=32679,fd=13))
```

rootlessport 在 listen —— 第 1 跳有进程。

### 跳 2：host → client

```bash
$ nc -zv 127.0.0.1 3389
Connection to 127.0.0.1 3389 port [tcp/*] succeeded!
```

第 2 跳 TCP 入口 accept 通过。**但这只证明 rootlessport 在 accept SYN，不证明后端存在。**

### 跳 3：容器入口 listener

```bash
$ podman exec WinApps ss -ltn | grep :3389
(空)
```

**关键证据** —— 容器内 3389 没有任何 listener。容器内 listener 表长这样：

```
0.0.0.0:5700    (QEMU VNC websocket)
0.0.0.0:5900    (QEMU VNC)
*:8006          (noVNC 控制台)
172.30.0.1:445  (samba)
127.0.0.1:8004  (QEMU monitor websocket)
127.0.0.1:53    (dnsmasq)
```

**没有 3389**。

### 跳 4：iptables DNAT 计数器

```bash
$ podman exec WinApps iptables -t nat -L PREROUTING -n -v -x
pkts  bytes target  prot opt in   out source      destination
0     0     DNAT    tcp  --  eth0 *  0.0.0.0/0   10.89.0.2  multiport dports !5700,5900,7100,8006,8004 to:172.30.0.2
0     0     DNAT    udp  --  eth0 *  0.0.0.0/0   10.89.0.2  to:172.30.0.2
```

DNAT 规则写对了，**但 pkts=0** —— 包根本没经过这一行。早期链（INPUT）已经把 SYN RST 了。

### 跳 5：real backend (Windows guest)

```bash
$ podman exec WinApps nc -v -w 3 172.30.0.2 3389
Connection to 172.30.0.2 3389 port [tcp/ms-wbt-server] succeeded!
```

**跳 5 是通的**！`ms-wbt-server` 是 RDP 协议在 `/etc/services` 里的注册名。这说明 Windows guest 内 RDP 服务实际在 listen。

## 链路总结

| 跳 | 状态 | 关键事实 |
|----|------|---------|
| 1. host listener | ✅ | rootlessport 在 listen |
| 2. host 入口 | ✅ | TCP 握手通过 |
| 3. 容器入口 listener | ❌ | **没有任何进程 listen 3389** |
| 4. iptables DNAT | n/a | pkts=0（因跳 3 已 RST） |
| 5. real backend | ✅ | Windows guest RDP 正常 listen |

**失败跳：第 3 跳** —— 容器网络栈的 10.89.0.2:3389 上没有任何 accept。rootlessport 把 SYN 转到容器，容器内核看到 10.89.0.2:3389 上无 listener，RST。

## 二次踩坑：过早归因到 "Windows RDP 没启用"

第一次诊断时，xfreerdp 报 RST，我看到容器内 `nc 127.0.0.1 3389` 是 `Connection refused`，**直接**得出"Windows guest 内 RDP 没启用"。这个结论**错的**。

正确做法是先跳 5 验证：nc guest IP 3389，结果是 `tcp/ms-wbt-server` —— RDP 在 listen。

我跳过了跳 5 的验证，导致错把根因放到 guest 上。

## 三次踩坑：相信 Windows 设置 UI 截图

用户后来打开了 noVNC，在 Windows guest 内部看到 "启用远程桌面 = 开" 的设置截图。我又过早归因："guest RDP 没起来，开关没生效"。

实际上：
- 设置 UI 改了不等于 TermService 实际启动
- 就算服务起了，如果 iptables DNAT / publish / rootlessport 这条链路有别的问题，guest 内部是否 listen 与外层通路无关

正确做法：永远 nc guest IP:3389 看真实 listener 状态。

## 四次踩坑：直接推"重启 WinApps 容器"

在 `iptables -t nat -L PREROUTING -v` 给出 pkts=0 的决定性证据后，我提了"重启 WinApps 容器"作为第一步建议 —— **但我没解释清楚重启预期会改变什么**。

更负责的做法：先看 entry.sh / network.sh 的启动逻辑，找 pkts=0 的根因（容器内 3389 listener 缺失）是不是启动时某分支跳过。重启只是兜底，不解决根因。

## 修复路径（用户决定）

下一步推荐三选一（按风险/收益排）：

1. **重启 WinApps 容器**（最快但丢当前 Windows 状态）：
   ```bash
   podman restart WinApps
   ```
   重启后看 `iptables -t nat -L PREROUTING -v` 计数器有没有动 + 容器内 `ss -ltn | grep 3389` 有没有 listener。

2. **不重启，看 entry.sh 启动日志**：
   ```bash
   podman exec WinApps sh -c 'cat /run/shm/qemu.log | tail -40; echo ===; dmesg 2>/dev/null | tail -20'
   ```
   找 network.sh 配置阶段有没有报错。

3. **改走直连 guest IP**（绕过 rootlessport / 容器网络栈）：
   ```bash
   xfreerdp /v:172.30.0.2:3389 ...   # 但需要从容器网络可达，容器内能跑通
   ```
   这条路不修 rootlessport 的问题，只在用户**只用 RDP 不修链路**时作为短期方案。

## 经验值

- 第一次跑 `nc -zv` 就停手是**最大的反模式**。每多一跳多一次验证的边际成本很小，跳数深带来的诊断精度提升却很大。
- 当错误码形态随绕路（绕代理、改端口、改证书模式）变化时，**说明当前归因只是叠加层**，根因还在更深。
- 不要相信 Windows 设置 UI 的截图。`netstat -an | grep 3389` / `nc guest_ip 3389` 是 RDP 是否真的活着的唯一可靠信号。
- `iptables -t nat -L -v` 的 0/0 计数器经常**先告诉你包没到 DNAT 这一行**，而不是包被 DNAT 后丢了。要顺着上游回去找。