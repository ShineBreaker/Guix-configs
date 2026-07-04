# hermes-desktop 启动失败诊断协议

> 适用场景：`hermes-desktop` 打不开、闪退、或 Electron 窗口出现后立即消失。
> hermes-desktop 通过 Nix flake (`source/nix/flake.nix`) 的 `hermes-agent` input 安装，
> 包名 `hermes-agent-packages.full.hermesDesktop`。

## 日志优先级（从高到低）

1. **`~/.local/share/hermes/logs/desktop.log`** — Electron 主进程 + 后端 boot 循环，最关键
2. **`~/.local/share/hermes/logs/gui.log`** — Web 后端的 Python logging（带时间戳）
3. **`~/.local/share/hermes/logs/errors.log`** — 所有组件错误汇总
4. **`~/.local/share/hermes/logs/gateway.log`** — gateway 生命周期
5. **`~/.local/share/hermes/logs/gateway-exit-diag.log`** — gateway 异常退出时的诊断 JSON
6. **`~/.local/share/hermes/logs/bootstrap-*.log`** — 自举失败记录

## 诊断流程

### Step 1: 找直接致死原因

在 `desktop.log` 尾部搜索 `Desktop boot failed` 或 `bootstrap`：

```
grep -n 'boot failed\|bootstrap\|Fatal\|Error:' ~/.local/share/hermes/logs/desktop.log | tail -20
```

常见致死模式：
- **`Hermes bootstrap failed: Cannot resolve install.sh`** — Electron 的 CLI 版本探测失败后进入自举路径，但 Nix 包没打包 `install.sh`
- **`--version probe failed`** — Electron 跑 `hermes --version` 超时（5 秒）或返回非零

### Step 2: 追溯版本探测失败原因

如果致命行附近有 `--version probe failed; falling through to bootstrap`：

1. 手动验证 CLI 是否真的坏了：
   ```bash
   /nix/store/<hash>-hermes-agent-0.17.0/bin/hermes --version
   ```
   如果手动跑 OK，说明是瞬态失败（负载、竞态、超时）

2. 检查系统负载：
   ```bash
   cat ~/.local/share/hermes/logs/gateway-shutdown-diag.log | grep loadavg
   ```

3. 检查是否有大量 cron 线程崩溃日志（加重 I/O 负载）：
   ```bash
   grep -c 'Exception in thread desktop-cron-ticker' ~/.local/share/hermes/logs/desktop.log
   grep -c 'Exception in thread cron-scheduler' ~/.local/share/hermes/logs/desktop.log
   ```

### Step 3: 查 cron 模块导入竞态（常见背景噪音）

`desktop.log` 或 `gateway-exit-diag.log` 中反复出现：
```
from cron.scheduler_provider import resolve_cron_scheduler
ModuleNotFoundError: No module named 'cron.scheduler_provider'
```

这是 **hermes-agent 0.17.0 上游 bug**——间歇性导入竞态。验证方法：
```bash
# 直接导入总是成功（证明包完整）
/nix/store/<hash>-hermes-agent-env/bin/python3 -c "from cron.scheduler_provider import resolve_cron_scheduler"
```

如果直接导入成功但日志里有错误，说明是进程内竞态。通常在 gateway/桌面后端重启后会自行恢复。

### Step 4: 追溯 Nix 包版本

```bash
# 查看 flake.lock 中 hermes-agent 的 commit
grep -A6 '"hermes-agent"' ~/Projects/Config/Guix-configs/source/nix/flake.lock | grep rev
```

然后用 commit hash 去 https://github.com/NousResearch/hermes-agent 查看是否有新版本。

### Step 5: 确认 Store 路径未被 GC

```bash
# 从 desktop.log 提取 store 路径
grep -oP '/nix/store/[a-z0-9]+-hermes-agent[^/"]*' ~/.local/share/hermes/logs/desktop.log | sort -u

# 逐一检查是否存在
ls -la <path>
```

### 快速尝试：杀进程重启

```bash
pkill -f hermes-desktop
pkill -f 'hermes dashboard'
sleep 2
# 再双击桌面图标
```

## 关键架构要点

- hermes-desktop 的 Electron 主进程通过 `backend-probes.cjs` 的 `verifyHermesCli()` 探测 hermes CLI——跑 `hermes --version`，5 秒超时
- 探测失败 → 进入 bootstrap → 需要 `install.sh` → Nix 包不提供 → 崩溃
- `hermes dashboard` 后端（由 Electron 启动）与 gateway 是独立进程
- Nix flake 锁定在特定 commit，更新用 `nix flake update hermes-agent`（在 `source/nix/` 目录下）
