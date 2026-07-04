# hermes-gateway 作为 shepherd service 的诊断协议

> 适用场景:用户用 home-shepherd 服务管理 `hermes-gateway`(典型: `source/config.org` 的 `home-shepherd-services` 块),
> gateway 反复重启 / 聊天平台连不上 / 进程列表里看到多个 `hermes gateway run [--replace]` 同时存在。
> 与 `references/hermes-desktop-diagnostics.md`(诊断 Electron 启动失败)互补——那份处理桌面 GUI 启动,本份处理长驻 messaging gateway。

## 服务定义参考

在 `source/config.org` 的 `home-shepherd-services` 块里,本仓库有两个 hermes 相关 service:

```scheme
(simple-service 'hermes-services home-shepherd-service-type
  (list (shepherd-service (provision '(hermes-backend)) ...)
        (shepherd-service (provision '(hermes-gateway))
                          (requirement '(hermes-backend))
                          (start #~(lambda args
                                    ((make-forkexec-constructor
                                      (list (string-append (getenv "HOME") "/.nix-profile/bin/hermes")
-                                         "gateway" "run" "--replace")  ; ❌ 触发 self-kick
+                                         "gateway" "run")             ; ✅
                                      #:log-file (string-append (getenv "HOME")
                                                                "/.local/state/shepherd/hermes-gateway.log"))
                                     args)))
                          ...)))
```

设计意图是把 dashboard backend 和 messaging gateway 做成常驻 shepherd 守护进程(类比 NixOS `nixosModules.hermes-agent` 的 systemd 单元)。

## 症状速查

| 现象 | 根因 | 跳到 |
|------|------|------|
| gateway PID 每 4 秒换一个,日志交替出现 SIGTERM + connected | `--replace` self-kick loop(§1) | §1 |
| `herd restart hermes-gateway` 后日志报 `Another gateway instance is already running (PID XXXX)`,X 是另一个 daemon 的服务 PID | 多个 home-shepherd 并存(§2) | §2 |
| `herd restart` 后进程列表里仍看到带 `--replace` 的 gateway | 旧 shepherd 的服务没被新 daemon 接管(§2) | §2 |
| QQ Bot 间歇性 `400 Bad Request`(与重启循环叠加出现) | 自踢循环的副作用——冷启动时 token 还没刷就被踢(§3) | §3 |
| 想用 `blue block-replace` 改 config.org 块但报 `Symbol's value as variable is void: replaced` | emacs-minimal 跑工具的脚本 bug(§4) | §4 |

## 1. self-kick loop(`--replace` 触发)

### 触发机制

`hermes gateway run --replace` 的语义是:启动时主动给已存在的 gateway 发 SIGTERM,自己接管。

放在 shepherd service 里就出 bug:

```
旧 gateway(配置带 --replace)
  └─ 启动 → 给"前任"(如果有)发 SIGTERM
  └─ 收到 SIGTERM 或自踢 → 退出码非 0
  └─ shepherd (respawn? #t) 视为失败
  └─ 启动新 gateway(仍带 --replace)
  └─ 给"前任"发 SIGTERM
  └─ ... (无限循环)
```

每轮 ~4 秒,`gateway.log` 显示 `✓ qqbot connected` 与 `Received SIGTERM as a planned --replace takeover` 交替出现。

### 修复(改源)

从 `source/config.org` 的 `home-shepherd-services` 块里删 `"--replace"`:

```diff
- "gateway" "run" "--replace")
+ "gateway" "run")
```

**为什么能删**:shepherd 自己负责"已存在实例怎么办",不需要 gateway CLI 再 `--replace`。NixOS `nixosModules.hermes-agent` 的 systemd 单元也是这么写的(`ExecStart=hermes gateway run`,没有 `--replace`)。

## 2. 多个 home-shepherd 并存

`blue home` 不会终止在跑的 home-shepherd(见 SKILL §1 不变量 #1 的子项)。如果用户做了这些操作,容易产生多个 daemon 实例:

- 跑了多次 `blue home` 期间没有 logout(每个 PAM session 可能启一个 shepherd)
- 手动 `herd` 命令触发 spawn 新 daemon
- 系统升级后 Guix 启了新 shepherd,旧 daemon 还活着

诊断:

```bash
pgrep -af "shepherd-for-home"
# 典型输出:多个 PID,各自带不同 --config <hash>-shepherd.conf
```

清理流程:

```bash
# 1) 找出"想保留的"——通常是最新启动的(etime 最小)、吃了最新 config hash 的
ps -o pid,etime,cmd -p $(pgrep -f "shepherd-for-home")

# 2) kill 其他旧的(SIGTERM,shepherd 会清理其 fork 的服务进程)
kill <old-pid-1> <old-pid-2>

# 3) 验证只剩一个
pgrep -af "shepherd-for-home"

# 4) 此时旧 daemon fork 的孤儿服务进程(典型: gateway 还占着端口)再单独 kill
pgrep -af "hermes gateway run"   # 看哪些是孤儿
kill <orphan-gateway-pid>

# 5) herd restart 让新 daemon 用新配置起服务
herd restart hermes-gateway
```

**验证服务定义已加载**:

```bash
herd status hermes-gateway
# 看 "命令:" 行,确认是新版(去掉 --replace 且日志文件是 hermes-gateway.log)
```

## 3. 自踢循环的副作用(非根因)

`--replace` 触发的循环掩盖了**真实**的 QQ Bot 间歇性 400:

```
gateway.platforms.qqbot.adapter: QQ startup failed:
  Failed to get QQ Bot gateway URL: Client error '400 Bad Request' for url 'https://api.sgroup.qq.com/gateway'
```

这条**本身**不是 hermes bug,可能源于:
- QQ Bot 开放平台 token 缓存问题(hermes 0.17.0 vs 当前 API)
- access token 用了旧的(冷启动时没刷新就发请求)

修完 §1 的 self-kick loop 后,gateway 持续在线,token 缓存正常,400 错误消失。如果还有零星 400,优先排查 token 刷新时序而不是 hermes 本身。

**不要把 400 当成根因去排查**——它是被循环掩盖的噪音。

## 4. `blue block-replace` 工具踩坑

`source/AGENTS.md` 的"块级精准编辑"章节描述了:

```bash
cat new.scm | ORG_BLOCK=<name> blue block-replace
```

实际**两种用法都跑不通**:

1. **`ORG_BLOCK=<name> blue block-replace`**(环境变量)→ `usage: blue block-replace BLOCK BODY-FILE`(被当成位置参数)
2. **`cat new.scm | blue block-replace BLOCK`**(stdin pipe)→ 同上,blue 要的是文件路径不是 stdin

**正确用法**(看 `blueprint.scm:624-625` 确认 `match arguments ((name body-file) ...)`):

```bash
# 1. 提取块到临时文件(位置参数 BLOCK)
blue block-show <name>   # 输出 tmp/block-<name>.scm 路径

# 2. 编辑(tmp/block-<name>.scm 前两行是 "scheme" / "plain" 标记,第 3 行起是 body)

# 3. 替换:位置参数 BLOCK 和 BODY-FILE
blue block-replace <name> /path/to/new-body.scm
```

**而且**实际跑起来还报 `Symbol's value as variable is void: replaced`——blueprint 的 `block-replace.el` 用 lexical binding `let` 绑 `replaced` 变量,但调用的 `guix time-machine` 拉的 `emacs-minimal` 没启用 lexical binding。绕过方法:**直接用 `patch` 工具精确改 `source/config.org`**,或退而用 `python3` + `str.replace` 改临时块文件再写回。

**结论**:`blue block-show` 可以用(只读);`blue block-replace` 在当前 Guix 时间机器 + emacs-minimal 组合下跑不通。改 `config.org` 的少量行优先用 `patch` 工具,大批量改走 `blue tangle` → 直接编辑 `tmp/config.scm` → `blue home`(但 `tmp/` 是 blue 自动生成,会被覆盖,慎用)。

## 5. 关键日志位置

| 用途 | 路径 |
|------|------|
| gateway 服务日志(shepherd 写的) | `~/.local/state/shepherd/hermes-gateway.log` |
| gateway 内部日志(hermes 自己写的,带 INFO/ERROR level) | `~/.local/share/hermes/logs/gateway.log` |
| gateway 异常退出诊断 | `~/.local/share/hermes/logs/gateway-shutdown-diag.log` |
| gateway 重启记录(结构化 JSON) | `~/.local/share/hermes/logs/gateway-exit-diag.log` |
| 当前活跃 gateway 状态 | `~/.local/share/hermes/gateway_state.json` |
| PID 锁 | `~/.local/share/hermes/gateway.pid` / `gateway.lock` |

**优先级**:看 self-kick 状态先看 `gateway.log`(hermes 自己的 INFO 最准);看服务定义是否生效看 `herd status` 的"命令:"字段;看进程级细节看 `/proc/<pid>/cmdline`。
