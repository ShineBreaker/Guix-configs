---
name: hermes-cron-ops
description: "Create/debug Hermes cron jobs; deliver reports to QQ/WeChat."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [hermes, cron, scheduling, qqbot, delivery, ops]
---

# Hermes Cron Ops

Hermes cron 定时任务的创建、诊断与投递配置。覆盖：把用户给的巡检/报告计划转成 cron job 的完整流程、模型 pin 铁律（#44585 漂移防护）、QQ/微信平台投递的确认方法、报告格式适配。

## When to Use

- 用户说"设置定时任务 / 每周X跑一次 / 依照计划设置 cron / 定时巡检 / 按这个计划定时执行"
- cron job 报了 `last_status: error` 但没有任何可见输出（很可能被漂移防护跳过）
- 用户手动触发 cron 后说"用不了 / 没反应"
- 需要把 cron 报告投递到 QQ（qqbot）、微信（weixin）等消息平台

## 触发信号

- 用户说"设置定时任务 / 每周X跑一次 / 依照计划设置 cron / 定时巡检"
- cron job 报了 `last_status: error` 但没有任何可见输出（很可能被漂移防护跳过）
- 用户手动触发 cron 后说"用不了 / 没反应"
- 需要把 cron 报告投递到 QQ（qqbot）、微信（weixin）等消息平台

## 创建 cron job 的最佳实践

1. **deliver 机制**：cron 的 agent 最终回复会被自动投递到 `deliver` 目标——agent **不需要**调用任何发消息工具，也不要把报告写文件（除非用户明确要双写）。prompt 里写清楚「报告作为最终回复输出即可」。
2. **prompt 必须自包含**：cron 在全新 session 运行，无对话上下文。把用户给的完整计划（环境路径、API、步骤、约束、容错规则）原样打包进 prompt，不要精简到看不懂。
3. **workdir**：设到仓库根（如 `/home/brokenshine/Projects/Config/Guix-configs`），该目录的 AGENTS.md / CLAUDE.md 会自动注入 system prompt，agent 能拿到仓库约定。
4. **enabled_toolsets**：按任务实际需要收窄工具集（如 `["web", "terminal", "file"]`），省 token 开销。**不要**给 cron 加 `messaging`（投递由框架做）、`cronjob`（cron 内禁止递归建 cron）、`clarify`（无人可问）。
5. **3 分钟硬中断限制**：复杂任务（guix refresh、批量 API 抓取）可能跑不完。prompt 里要设计优先级兜底：「时间紧张时优先保证核心步骤（如频道活动+上游版本），changelog 抓多少算多少」。
6. **格式适配**：投递到 IM 平台（QQ/微信）时 **markdown 完全不被渲染**——表格、加粗、代码块全部以纯文本裸露。报告必须先渲染成图片再随回复发出（正文写 `MEDIA:/绝对路径.png`），图内只放消息内容本身，执行说明另发一条文字消息或干脆不发。完整管线见 `references/image-report-rendering.md`。

## 更新巡检类任务：weather 口径与就近回溯

适用：「扫描上游更新 + 编译就绪检查 + 自动更新」类 cron（如 guix-package-update-scanner）。

**weather 检查口径 = 用户的包集合，不是上游更新包全集**。2026-09-05 教训：按上游全部更新包跑 `guix time-machine -- weather`，librewolf/nss-rapid 未就绪 → 判「部分就绪，不更新」；实际这两个包根本不在用户 config.org 里，白白卡住一轮更新。包清单从用户配置源提取（如 config.org 的 `specifications->packages` 字符串 spec），不是从 commit message 收集的更新包列表。

**决策：更新到「全就绪的最新 commit」，不是「有缺就不更新」**（2026-09-06 用户拍板，取代旧的「部分包未编译好 → 整体等待」）：
1. 先对上游 HEAD + 用户包集合跑 weather；全就绪 → 直接更新 lock 到 HEAD
2. 有缺 → 从 HEAD 往回找「用户所需包全部就绪」的最新 commit，把 lock pin 到那里（可二分），简报说明 pin 位置与 HEAD 仍缺的包
3. pin 走正规入口：`blue update --guix -c NAME -C COMMIT`（`-c/--channel` 选频道、`-C/--commit` 指定 commit，其余频道保持 lock 现值；2026-09-06 已落地）。无需再手动改 channel.lock，commit message 由 blue 自动生成为 `build(channel.lock): pin <name> at <短哈希>`

## 抓取型 cron：分批断点 + 报告加工职责分离

适用：每轮要抓 N 个独立单元（账号/仓库/页面）再出报告的 cron。

**抓取必须分批且断点续跑，不要把一轮工作塞进单次 tick。** 单 tick 只有 3 分钟，且上游限流窗口不可预测（实测 X GraphQL 224 账号、`--interval 2` 仍需跨多次 tick）。做法：`progress.json` 记已抓单元，每次 tick 抓一批（`--resume`），全部抓完自动清断点，下一轮从头开始。用户对时效要求低时（「夜间跑、白天发」）这反而比赶时间更稳——限流就睡到 reset 或留给下一批。

**分批写盘必须按 id 合并，不能覆盖。** 每批各自落盘当天文件，后一批若 `write_text` 全量覆盖会把前一批冲掉。合并时同一 id 只保留首次出现那份。

**错误记录即时落盘，不要攒到函数末尾。** 攒在局部 list 里、收尾时一次性写，进程被超时/限流打死就全部丢失——报告会「正常地」缺内容且无迹可查。每次失败当即 append 到 `errors/<date>.log`。

**每一条失败都必须让断点推进。** `except` 里记完错误却忘了把该单元标成已完成，`--resume` 下一轮会死循环在同一个单元上；限流睡到 reset 后重试成功的路径同样要推进断点。成功/失败/跳过三条分支必须汇到同一个出口，写完后用一个已知会失败的单元实测断点是否清空。

**上游返回的空壳响应会 KeyError 崩掉整批。** 接口对不存在的 id 常返回 `{"data": {"user": {}}}` 这类空壳，直接下标取值抛的 KeyError 不被业务异常类接住，一个坏单元带走剩下全部。取值前判空，并把解析收进一个 helper 给所有调用点共用（同一处判空，而不是每处各自 try）。

**prompt 里明确划分「脚本产出」与「agent 加工」的边界**：脚本给原始素材（原文+链接+互动数），agent 负责翻译/摘要/聚类/加导读。想让它加工，prompt 就要把加工规则写全（摘要字数、保留哪些实体原文、分组口径、字数上限、禁止编造）；若 prompt 里留着「不要改写、不要润色」，它会忠实照搬原文。

**prompt 自身必须是它要求的样子的活样板。** 要求 agent 输出禁破折号、禁满屏粗体、sentence case、禁套话结尾，那 prompt 正文里一个破折号、一句客套都不能有——否则它照抄的是你的样子不是你的规则。改完 prompt 后 `grep -c '[—–]'` 自查一遍。

**「第一行就是正文」必须写成铁则。** 只写「不要客套」挡不住它加一句「素材已处理完毕」；直接规定「第一行必须是标题，之前不许有任何文字」，并说明投递机制会把最终回复原样送到用户手机上。交付物是图片时，铁则改成「最终回复就是那一行 `MEDIA:<绝对路径>`」，并给一条兜底：渲染报错就退回 markdown 原文输出，不许交白卷。

**给每个加工产物带参数版本。** 阈值、条数上限、口径这类会变的参数，落盘时写成 `{threshold, tweets}` 而不是裸数组——否则改阈值后跑着旧参数的进程 flush 一次，就把新口径静默覆盖掉。读方同时兼容旧格式。

**条数上限按条数推，字数上限不要拍脑袋，且优先问「要不要上限」。** 要闻 ≤N 条 + 正文 ≤M 条 + 总计 X 字三个数，比单一「控制在 1500 字」可执行；先跑一版量出实际字数再校准。但上限本身是可选项：用户若明确说「没必要有字数限制，消息多就多写，长一点不影响阅读」，就把上限整句删掉、换成「不设字数上限，删条目的唯一标准是没有信息量」，并同步把**导出条数的 `--top`** 一起放开（它同样是隐性上限，只改 prompt 不改脚本等于没改）。

报告格式以用户给的一份样例为唯一权威。 用户贴一份他认可的日报/早报时，逐条对照提取硬规则（要不要互动数、要不要作者前缀、要不要链接、要闻几条、单条多长），写进 prompt 的格式段并附一句「参考下面这个样例」。用户说「不需要 X」时，同步把 X 从**素材生成脚本**里也删掉——只改 prompt 的话脚本还在喂它已经不需要的字段。

**同一事件的不同侧面要合并，不只合并转发。** prompt 只写「转发/跟进合并为一条」时，官宣、官方说明、评测、实测、体验会被拆成 N 条——它们不是转发关系，却说的是同一件事。要单独写一条规则：官宣/说明/评测/实测/体验若是同一事件，合成一条，先写事件本身再补各方新增信息并标注来源，判断标准是「读者是否会觉得在读同一条新闻的重复」。

## IM 投递：markdown 渲染不了，报告必须出图

QQ/微信不渲染 markdown，cron 最终回复若是 markdown，用户看到的是带 `##`、`**`、`|` 的纯文本。凡是投递到 IM 的报告，一律走「HTML → headless chromium 截图 → PNG → `MEDIA:` 发出」。

**图内只放消息内容，执行说明走另一条文字消息。** 抓取多少条、哪一步失败、阈值是多少，属于过程信息，不进图。这是用户的硬偏好，不是可选项。

**解析 cron 输出文件时，正文在 `## Response` 之后、独立 `---` 行之前。** `$HERMES_HOME/cron/output/<job_id>/*.md` 头部是 job prompt 与执行约束，尾部是执行说明。按全文解析会把整份 prompt 指令渲染进图里。先定位 `^## Response$` 截断，再遇到独立 `---` 行停止；`## Response` 与 `# 标题` 之间的过渡句按「无组名条目」过滤。

**模板占位符不得与配色键撞名。** `@KEY@` 模板若把配色 dict 的键（`bg`/`card`/`title`/`body`/`muted`/…）注册成大写放进同一个替换表，`title` 的色值会覆盖页面标题、`body` 的色值会让整块正文消失，而且不报错。结构键用 `@PAGETITLE@`/`@CONTENT@`/`@LEDE@` 这类不会撞的名字；替换完 `grep -o '@[A-Z_]*@' out.html` 必须为空。

**Guix 上 headless chromium 看不到 store 里的字体。** fontconfig 只扫 `/etc/fonts/fonts.conf` 列出的目录，`/gnu/store/*-font-*/share/fonts` 与 `~/.guix-home/profile/share/fonts` 都不在内，衬线静默回退黑体、emoji 变豆腐块。运行时生成一份 fonts.conf 把这两个目录 include 进去，用 `FONTCONFIG_FILE` 传给 chromium 子进程，配方见 `references/image-report-rendering.md`。

**渲染前先确认素材里真有要渲染的字段。** picked/scored JSON 是上游脚本某次运行的产物，字段由当时那版代码写入；上游加了新字段后历史文件里没有，直接渲染得到「无图卡片」，看起来像渲染器坏了。拿一份新抓的数据端到端验证，再回头渲染历史文件。

## 模型 pin 铁律（最重要的坑）

**背景**：`cronjob` 工具的 schema **没有** model/provider 参数——inference pins 是 user-owned，agent 无法自设。未 pin 的任务跟随全局默认模型，并在创建时**快照**当时的全局配置。

**症状**：任务创建后，用户改了全局默认模型（`hermes model` / /model）→ 任务下次运行被 #44585 漂移防护直接跳过执行：`Skipped to prevent unintended spend: global inference config drifted since this job was created ... and this job is unpinned. No inference call was made.` 表现为「手动触发没反应 / 用不了」，last_status=error 但无输出文件。

**诊断**：
```bash
hermes cron runs <job_id> --limit 5   # 看 executions.db 里的具体错误
```
常见错误两类：
- `global inference config drifted ... unpinned` → 未 pin + 全局模型变更
- `[blocked_config] provider credential missing` → 创建时快照的 provider 无有效 key（如 Nous Portal 未登录），预检直接拦下

**修复**（必须用 CLI，cronjob 工具做不到）：
```bash
hermes cron edit <job_id> --model <model> --provider <provider>
```
选一个 .env 里有 key 的稳定 provider（如 `deepseek-v4-flash` / `deepseek`，与现有任务一致）。**创建后立即 pin，别等用户手动触发才发现**。pin 后漂移防护不再对任务生效。

## 投递平台确认

投递前先确认目标平台真的在线，否则任务跑完 delivery 静默失败：

- **QQ**：`.env` 里有 `QQ_APP_ID` / `QQ_CLIENT_SECRET` / `QQBOT_HOME_CHANNEL` → 配置存在；再看 gateway.log 确认 WebSocket 活着。细节见 `references/qqbot-delivery.md`。
- **微信**：`.env` 里有 `WEIXIN_BASE_URL` 等 → 配置存在。已知坑：iLink 发消息有 rate limit，cooldown 期间 delivery 报 `rate limited; cooldown active for 30.0s`（不致命，下次 tick 重试）。
- 日志位置：`$HERMES_HOME/logs/gateway.log`（不要硬编码 `~/.hermes/`，HERMES_HOME 可能已重定向）。

## 诊断命令速查

```bash
hermes cron list                     # 所有任务 + last_status / last_delivery_error
hermes cron runs <id> --limit 5      # 执行历史（executions.db，含具体错误）
ls $HERMES_HOME/cron/output/         # 本地投递的输出文件
hermes gateway status                # gateway 是否在跑（不显示各平台连接详情）
```

## Pitfalls

- 用户改全局默认模型后，**所有未 pin 的 cron 任务都会静默罢工**——不只新建的那个。巡检现有任务时先看有没有 `model: null`。
- `last_delivery_error` 里的 rate limit / 连接错误 ≠ 任务失败：看 `last_status` 区分（ok + delivery error = 报告生成了但没送到；error = 没跑）。
- cron 报告里要求「可追溯、不臆造」（版本号/hash 必须有来源，抓不到标未获取）——复杂巡检类任务的通用约束，直接写进 prompt。
- 手动触发 `hermes cron run` 必须 nohup 后台（`nohup hermes cron run <id> >/dev/null 2>&1 &`）：run 的 owner=当前会话进程，会话被杀（daily reset / 前台超时）→ run 无终态，scheduler 重启后永久 `unknown`。等待/监控**不要轮询 runs 状态文本**（unknown 会挂死 `grep -qv running` 循环，2026-09-06 实证白等 100 分钟），盯 `$HERMES_HOME/cron/output/<job_id>/` 最新 .md 的新增/mtime。unknown 记录本身无害，无需清理。
- **nohup 后台里 PATH 不含 `~/.local/bin`**：`hermes` 会直接 "command not found" 而日志只留一行。用绝对路径 `$HERMES_HOME/hermes-agent/venv/bin/hermes`，或先 `export PATH=$HOME/.local/bin:$PATH`。
- **`already being fired by the scheduler` 先查 history 再重试**：该提示意味着已有实例挂着。`hermes cron history <id>` 看 running 实例——它可能是孤儿（父 shell 退出后仍在跑，正在产出），也可能已被 terminal 的进程清理连带杀死、记录永久卡 `running` 且无产出。区分方法是盯 output 目录 mtime 与管道脚本进程，mtime 不动且无相关进程就是后者。调度器状态不可靠时，直接手动把管道的几步跑完更稳，不要让用户在假 running 上空等。
- **批任务耗时远超预期时，先分清「卡住」和「本来就这么慢」**：前台 `hermes cron run` 超过 180s 会被判超时，长任务（几百个单元、每条一次 LLM 调用）跑十几分钟是正常的。盯 output 目录的 mtime 增量而不是进程树，mtime 不动且无新会话记录才是真卡住。
- **延迟 background notify 是虚警高发区**：早先那批任务退出时 stdout 才整体 flush，会在你以为早已结束的时候弹完成通知。用 `pgrep` 判断存活还会自匹配（命令行里含同样字符串），改 `ps -eo pid,args | grep -E '<脚本名前几字符>\[h\]\.py'` 精确匹配，并看 `/proc/<pid>/cmdline` 确认。收到虚警时先核对产物数据再决定要不要动手——多数时候数据没被动过。
- **一次 LLM 调用一个单元，别指望数组入参一次评一批**：评分/分类模型喂进 JSON 数组时，常见退化行为是只返回单个答案（或返回数组但元素是空串），把整批评成同一个值。逐条请求，并在同一批里做一次措辞扰动对照（换说法再问一次），确认分数稳定性——不稳就说明分差小于噪声，阈值要跟着放大。
- **先量出模型的真实输出分制，再定阈值。** 拿一小批（几十条）跑一遍，打印 min/median/max 和直方图；分制猜错（把 0~2 当 0~1）会让阈值形同虚设、三分之一内容全过。分制确认后，阈值取在「想要的那档」而不是「看起来合理的数」，并在 docstring 里写下分制口径。
- **累积文件每轮全量重跑会重复计费。** `new/<date>.json` 这类按天累积的中间产物，下游若每轮整份送评，已评过的单元会被反复计费。下游只处理「本轮新增」，或维护一份 seen 集在送评前过滤。
- **杀进程别用 `pkill -f <名字>`**：会匹配到发起命令自身所在的 shell 而自杀，把整个命令链带走。用 `ps -eo pid,args | grep -E '<名字>\[h\]\.py' | awk '{print $1}' | xargs -r kill`。
- **本轮新加进管道的脚本，部署位可能还没有。** `dotfiles/mutable/` 靠 stow 软链：已有文件改源即生效，新建文件却要等 `blue home` 才建链。cron 按 `$HERMES_HOME/scripts/...` 调用会直接 `No such file or directory`，而源文件明明存在，极易误判成脚本写错。加完新脚本先 `ls -la` 部署目录确认它是软链；应急可按同款相对路径手工补链，同时提醒用户跑 `blue home` 让 stow 认领（该命令会重启 home shepherd，agent 不自行执行）。
- **凭据别裸放 state 目录**：cookie/token 写进明文文件后，入库、备份、清理都要额外操心。走 age 加密（密文进仓库）+ 运行时解密到 tmpfs，脚本凭据加载做成「加密优先、明文兜底」两级，并存一个 `凭据可用?` 前置检查让抓取类命令在缺凭据时明确报错而不是半路崩。
