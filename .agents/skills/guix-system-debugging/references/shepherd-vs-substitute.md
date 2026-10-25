# shepherd 死锁 vs substitute 假象 — 2026-08-30 四次卡死复盘

**来源**：`~/Projects/Config/Guix-configs` `blue rebuild` 频道 bump 后连续 4 次卡死实战；zcode memory `reconfigure-hang-substitute-shepherd`；KB 卡 `20260830-163945`

## 时序

- 15:19 `blue update` 更新 `guix` 包
- 18:48 第 3 次 rebuild（boot 后首轮新 daemon 已安装但未重启）
- 18:50:35 syslog 铁证：
  ```
  Spawning systemd-style service /gnu/store/...-guix-daemon-.../bin/guix-daemon
  Running value of service guix-daemon changed
  ```
- 此后 `herd status root` 卡死，所有 `herd` 命令挂起

## 根因链

1. **重启 `guix-daemon` 时 shepherd 1.0.9 控制 fiber 死锁**（家族 #65178/#67538，#72354 症状逐字一致但被 notabug 关闭）
2. **双重后果**：
   - 客户端 store RPC 永等（`guix system reconfigure` 侧）
   - shepherd 控制 fiber 死锁（`herd` 侧，socket 残留僵尸连接但 syslog 转发 fiber 仍活）
3. 后续 rebuild 在 `current-services` 查询阶段即卡，与 substitute 无关

## 触发条件

- `blue update` 后 `guix` 包版本变化的**首次** rebuild 必触发
- 若 bump 只动普通包不碰 `guix` 则不触发
- `blue home` 永远不触发（不动系统 shepherd）

## 假象与排除

- **表象**：`guix substitute --query` 经 `http-proxy 127.0.0.1:7890` 走 mihomo 黑洞，`ss -tnp` 见大量 CLOSE-WAIT 4 分钟+
- **排除**：`--no-substitutes` 仍卡 + 无新 daemon 重启日志 → substitute 排除
- **陷阱**：shell `curl -I https://substitute.example` 秒回不能证伪（shell 无代理，daemon 有）；必须查 `cat /proc/<daemon-pid>/environ | tr '\0' '\n' | grep -i proxy`

## 恢复

```bash
# 1. 中断
Ctrl+C
# 2. 重置 shepherd（系统已 activate 到目标代，无需回滚）
reboot
# 3. 再 rebuild（此时 daemon 已新版，服务图一致，不再重启）
blue rebuild
```

## 次要坑

- mihomo 对 7 个 `substitute-urls` 黑洞且 guile `read` 无超时（`%fetch-timeout=5` 仅管连接建立），建议 mihomo 规则放行：
  `ci.guix.gnu.org / bordeaux.guix.gnu.org / substitutes.nonguix.org` 等 7 域
- `config.scm` fstrim 定时器（周日 19:00）`command` gexp 报 `list-of-strings?` 类型错
- `guix home` 不受影响（用户缓存全命中），`blue rebuild` 走 root inferior 每次 bump 全新

## 上游

- 已知 #65178 / #67538 家族；本例与 #72354 症状一致，待报上游
