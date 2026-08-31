---
name: guix-system-debugging
description: "当 blue rebuild 或 herd 卡死时排查 shepherd 死锁与 substitute 代理假象。"
version: 0.1.0
license: MIT
metadata:
  hermes:
    tags: [guix, shepherd, guix-daemon, substitute, mihomo, blue, debugging]
    related_skills: [guix-configs-workflow, hermes-install-layout]
---

# Guix System 调试

> 针对 `~/Projects/Config/Guix-configs` 仓库的 `blue rebuild` / `guix system reconfigure` / `herd` 卡死场景。核心是区分 **shepherd 层死锁**与 **substitute/代理层假象**，并提供可复用的取证命令组。

## 何时使用

- `blue rebuild` 卡在 `引导加载程序已成功安装` 之后无进展
- `sudo herd status root` 卡死、任何 `herd` 命令挂起
- `guix substitute --query` 长时间 CLOSE-WAIT，但 `--no-substitutes` 仍卡
- 频道 `blue update` 后首次 rebuild，怀疑 `guix` 包版本变化触发服务重启
- `git` / `guix` 等命令在 Guix Home 容器内 `command not found`

## 核心鉴别：shepherd 死锁 vs substitute 假象

**shepherd 死锁（真凶）特征**（2026-08-30 实测，shepherd 1.0.9）：
- syslog 18:50:35 `Spawning systemd-style service .../guix-daemon` + `Running value of service guix-daemon changed`
- 触发：`upgrade-shepherd-services` 重启 `guix-daemon` 服务 → 控制 fiber 死锁
- 后果双重：客户端 store 连接被抽（RPC 永等）+ shepherd 控制 fiber 死锁（所有 herd 挂，socket 残留僵尸连接但 syslog 转发仍活）
- 后续每次 rebuild 在 `current-services` 查询阶段即卡，与 substitute 无关
- 恢复：`Ctrl+C` → `reboot`（重置 shepherd）→ 再 rebuild 一次（此时 daemon 已新版，不再触发重启）

**substitute 代理假象**（常误导数小时）：
- daemon 配 `http-proxy 127.0.0.1:7890`（`guix-service-type` 字段），`guix substitute --query` 走 mihomo 黑洞 + CLOSE-WAIT 4 分钟+
- **排除法**：`--no-substitutes` 仍卡 + 无新 daemon 重启日志 → substitute 已排除
- **取证陷阱**：shell `curl` 直连镜像秒回不能证伪代理路径（shell 无代理变量，daemon 有）；必须查 ` /proc/<daemon-pid>/environ` 的 proxy env

详见 `references/shepherd-vs-substitute.md`（含完整根因链、时序图、触发条件、mihomo 放行清单）。

## 取证命令组（直接可用）

```bash
pgrep -af guix
ps --ppid $(pgrep -x shepherd) -o pid,cmd  # 进程树
sudo ss -tnp | grep 7890                    # 代理连接状态
sudo cat /proc/$(pgrep -x guix-daemon)/environ | tr '\0' '\n' | grep -i proxy
time sudo herd status root                  # 是否卡死（正常 <1s，死锁 >5s 挂起）
sudo grep "shepherd\[1\]" /var/log/messages | tail -20
```

`blue home` 永远不受影响（不动系统 shepherd），可作为对照。

## Guix Home profile PATH 漂移

`~/.guix-home/profile` 是 `/gnu/store/*-profile` symlink，`guix home` 重建后 hash 变化但旧 store 残留时 `$PATH` 指向旧 profile 导致 `git: command not found`：

```bash
ls /gnu/store/*-profile/bin/git  # 定位存活 profile
export PATH="/gnu/store/<alive>-profile/bin:$PATH"
# 或绝对路径调用：/gnu/store/<alive>-profile/bin/git -C ~/Documents/Org status --short
```

## fstrim 定时器等次要坑

- `config.scm` fstrim 定时器（周日 19:00 ~1201行）`command` gexp 报 `list-of-strings?` 类型错从未跑成，待修
- mihomo 对 7 个 `substitute-urls` 黑洞且 guile `read` 无超时（`%fetch-timeout` 仅管连接），建议规则放行（见 references）

## References

- `references/shepherd-vs-substitute.md` — 完整复盘（2026-08-30 四次卡死实战，含日志片段、恢复步骤、上游 #72354 关联）
- `references/guix-home-profile-path.md` — PATH 漂移取证与多 profile 并存时的 git 定位技巧
