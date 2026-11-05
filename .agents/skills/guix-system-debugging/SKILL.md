---
name: guix-system-debugging
description: "Guix System 重建卡死排查：区分 shepherd 死锁与 substitute 代理假象，给出取证命令、恢复步骤与 profile PATH 漂移处理。触发：guix system reconfigure 卡住 / herd 命令挂起 / substitute 长时间无响应——任一出现即调用。"
version: 0.2.0
license: MIT
metadata:
  hermes:
    tags: [guix, shepherd, guix-daemon, substitute, debugging]
---

# Guix System 卡死排查

适用于 `guix system reconfigure` 长时间无进展、`herd` 命令挂起、substitute 下载卡住的场景。先分类，再取证，不要在没有证据前回滚配置。

## 先区分两类原因

### shepherd 死锁

特征：

- 重建停在引导加载程序安装之后不再推进。
- 重启 `guix-daemon` 服务后控制 fiber 死锁，之后所有 `herd` 命令挂起，socket 留着僵尸连接。
- 日志里能看到 `Spawning systemd-style service ... guix-daemon` 与 `Running value of service guix-daemon changed` 相邻出现。
- 之后每次重建都在查询当前服务阶段就卡住，与网络无关。

恢复：中断重建，重启系统（重置 shepherd），再跑一次重建。此时 daemon 已是新版，不会再触发同一轮重启。

### substitute 代理假象

特征：

- daemon 配了 `http-proxy`，`guix substitute --query` 连不上，连接停在 CLOSE-WAIT 数分钟。
- shell 里 `curl` 直连镜像正常，看起来网络没问题。这是假象：shell 没有代理变量，daemon 有。
- 判断代理是否参与：看 daemon 进程的环境，不是 shell 的环境。

排除法：加 `--no-substitutes` 仍然卡，且日志里没有新的 daemon 重启记录，说明 substitute 不是原因。

## 取证命令

```bash
pgrep -af guix
ps --ppid "$(pgrep -x shepherd)" -o pid,cmd          # 进程树
ss -tnp | grep <代理端口>                             # 代理连接状态
tr '\0' '\n' < /proc/"$(pgrep -x guix-daemon)"/environ | grep -i proxy
time herd status root                                 # 正常一秒内返回，挂起说明控制 fiber 死了
grep 'shepherd\[1\]' /var/log/messages | tail -20
```

`guix home reconfigure` 不受系统 shepherd 死锁影响，可以拿来做对照：Home 侧能正常重建，系统侧卡住，基本可以确定是系统 shepherd 的问题。

## 恢复顺序

1. 中断当前重建。
2. 系统 shepherd 死锁：重启系统。
3. 代理问题：先在 daemon 配置里绕开代理，或放行 substitute 域名，再重跑。
4. 重跑前确认没有新的死锁迹象，不要连续重试。

## Profile PATH 漂移

`~/.guix-home/profile` 指向 `/gnu/store/*-profile`。重建后 hash 变化，旧 store 可能残留，`$PATH` 里的旧 profile 会让命令报 `command not found`。

```bash
ls /gnu/store/*-profile/bin/git          # 找存活的 profile
export PATH="/gnu/store/<alive>-profile/bin:$PATH"
```

或用绝对路径调用该 profile 里的程序，等下次登录重新生成环境。

## 取证边界

- 日志按 locale 输出，grep 英文关键词可能为空。
- `herd status` 缓存的 PID 不可信，进程是否活着看 `/proc/<pid>`。
- 代理配置在 daemon 侧，排查时读 daemon 的环境，不要读 shell 的。
