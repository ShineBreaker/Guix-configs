# Hermes Nix 安装布局 — 完整诊断参考

本参考文件给出 hermes 在 Nix 部署下的完整诊断操作清单,适用版本 v0.17.0+。

## §1 hermes-agent-env store path 解析

### 标准探测命令

```bash
# 取最新(按 mtime 倒序)的 hermes-agent-env 路径
HERMES_ENV="$(ls -t /nix/store/*-hermes-agent-env 2>/dev/null | head -1)"
echo "$HERMES_ENV"
# 典型输出:/nix/store/8bgx2c9vim0f0x9mkm8c34m9av5f94rq-hermes-agent-env

# bin 路径
HERMES_BIN="$HERMES_ENV/bin/hermes"
[ -x "$HERMES_BIN" ] && echo "OK: $HERMES_BIN" || echo "MISSING: $HERMES_BIN"
```

### 用 nix-store --query 校验(高级)

```bash
# 解析 hermes 二进制的所有 runtime 依赖
nix-store --query --requisites "$HERMES_BIN" 2>/dev/null | head -20

# 看 hermes 的 closure size(依赖图总大小)
nix-store --query --size "$HERMES_BIN"

# 看 hermes 的 references(直接引用)
nix-store --query --references "$HERMES_BIN"

# 反向:谁在引用 hermes-agent-env(可能有其他组件共享)
nix-store --query --referrers "$HERMES_BIN"
```

**实战坑**:如果 hermes 是通过 `nix profile install` 装的(典型路径 `~/.nix-profile/bin/hermes`),直接执行那个就行(它本身就是 wrapper 指向 store)。但 Guix 用户的 PATH 默认不含 `~/.nix-profile/bin/`,所以手动探测是必要的。

## §2 hermes-agent-env 内部布局

```
/nix/store/<hash>-hermes-agent-env/
├── bin/
│   ├── hermes                      # 主 CLI,Python 启动器
│   ├── python3, python3.12         # 嵌入式 Python
│   └── ...                         # 其他工具入口(acp, dashboard 等)
├── lib/python3.12/site-packages/   # hermes 全部 Python 源码
│   ├── hermes_cli/                 # CLI 子命令
│   ├── cron/                       # cron scheduler, jobs, suggestion_catalog
│   ├── agent/                      # 主 agent loop, prompt_builder
│   ├── tools/                      # 所有 tool 实现
│   ├── gateway/                    # gateway + platforms/
│   ├── plugins/                    # 内置 plugin
│   ├── hermes_state.py             # SQLite session store
│   └── hermes_logging.py           # 日志配置(RotatingFileHandler)
├── share/                          # 文档、license、示例
└── nix-support/                    # nix 包构建辅助
```

### 关键 sub-package 路径

| 功能 | 路径(相对 site-packages) |
|---|---|
| CLI 主入口 | `hermes_cli/main.py`, `hermes_cli/commands.py` |
| Cron 调度 | `cron/scheduler.py`, `cron/jobs.py` |
| Session store | `hermes_state.py` |
| 工具注册 | `tools/registry.py`, `toolsets.py` |
| MCP 客户端 | 内置 |
| 配置默认 | `hermes_cli/config.py` 的 `DEFAULT_CONFIG` |
| Logging 配置 | `hermes_logging.py` |

## §3 版本兼容矩阵(本用户已知)

| Nix 装版本 | site-packages 路径 | cron 模块位置 | 备注 |
|---|---|---|---|
| 0.17.0 | `lib/python3.12/site-packages/` | `share/hermes-agent/plugins/cron/`(plugins 风格,无 `jobs` re-export) | `from cron import jobs` 在 web_server 里会 ImportError,因为 plugins/cron/__init__.py 只暴露 discover 函数 |
| 0.18.0 | `lib/python3.12/site-packages/` | `cron/`(core 风格,`__init__.py` 显式 re-export `from cron.jobs import ...`) | 当前用户装的版本,正常 |

**坑**:如果 dashboard / gateway 进程跑的是 0.17.0 但 cron 模块是 0.18.0(或反之),`from cron import jobs` 在某个版本会失败。原因通常是 `nix-collect-garbage` 删了老版本,但旧 PID 还在用旧 binary 的 fd,启动新进程时才解析新的 `cron` 模块,两个版本的 sys.path 都暴露在 Python 解析路径上。

**修法**:`kill <old_pid>` + 重启 dashboard/gateway。如果 Nix profile 还在 0.17.0,需要先 `nix profile upgrade hermes-agent` 到 0.18.0。

## §4 用户特定路径(本 Guix-configs 部署)

| 路径 | 用途 | 是否 git 跟踪 |
|---|---|---|
| `~/.local/share/hermes/` | HERMES_HOME(hermes 全部运行时状态) | NO(由 hermes 自己管理) |
| `~/.local/share/hermes/skills/` | 本地 skill 库 | YES(softlink → `~/Projects/Config/Guix-configs/dotfiles/mutable/hermes/.local/share/hermes/skills/`) |
| `~/.local/share/hermes/config.yaml` | 主配置 | NO |
| `~/.local/share/hermes/.env` | API keys / secrets | NO(权限 0600) |
| `~/.local/share/hermes/state.db` | SQLite session store | NO |
| `~/.local/share/hermes/memory_store.db` | holographic memory provider | NO |
| `~/.local/share/hermes/auth.json` | OAuth tokens / credential pools | NO(权限 0600) |
| `~/.local/share/hermes/cron/jobs.json` | cron 任务持久化 | NO |
| `~/.local/share/hermes/logs/*.log` | 日志(ConcurrentRotatingFileHandler,默认轮转) | NO |
| `~/.local/share/hermes/scripts/` | cron script 唯一允许的根目录 | NO |
| `~/.local/bin/hermes` | wrapper(本 skill 装的) | NO |
| `~/.config/agents/skills/` | 第二个 skill 源(guix home immutable 软链) | NO(immutable 部署) |

## §5 故障排查流程

按顺序排查,大部分问题在这 5 步内能定位:

1. **`hermes: command not found`**: 跑 `scripts/install-wrapper.sh`,确认 `which hermes` 输出 wrapper 路径
2. **`hermes --version` 报错**: 看 stderr 是否 Python 缺包;跑 `nix-store --query --requisites $(which hermes) | xargs -I {} nix-store --verify-path {}`
3. **`hermes status` 报 "Config version outdated v32 → v33"**: 跑 `hermes config migrate`(会改 config.yaml,先备份)
4. **`hermes cron list` 报 "Script not found"**: 看本 skill SKILL.md §3,确认 jobs.json 的 script 字段是不是裸名,确认 wrapper 已在 `~/.local/share/hermes/scripts/` 下
5. **dashboard / gateway ImportError**: 见 §3 版本兼容矩阵,`pkill -f 'hermes (dashboard|gateway)'` 然后 `systemctl --user restart hermes-gateway`(或对应启动方式)

## §6 Nix profile 升级后的注意事项

`nix profile upgrade hermes-agent` 之后:

1. **新 store 路径生成**,旧路径保留(直到 gc)
2. **当前 PID 还在用旧 binary**(fd 不变),不会立即换
3. **下次启动的进程**会用新 store 路径
4. **`~/.local/bin/hermes` wrapper** 因为是动态探测,自动跟上

所以升级后**最稳的做法**是 `kill <old_pids>; systemctl restart hermes-gateway`,或者直接重启电脑(用户偏好 lazy)。

如果升级后启动失败,先看 `~/.local/share/hermes/logs/agent.log` 最近 50 行(参考本 skill SKILL.md §4 提到的 truncate 方式),查 ImportError 指向的 store 路径是否还有效(`nix-store --verify-path <path>`)。