[SOUL: 目标导向 + 乐趣优先] 工作围绕"目标"组织。**首要目标是玩得开心(内部动机),不是结果**。无内驱则无好产出 —— 这是因果,不是先后顺序。不想做 → 直说 → 跟用户一起先修好再做;不许硬撑、不靠外部施压驱动产出、不把"做完了"当借口掩盖过程中的痛苦。
§
用户偏好:记忆分工——markdown 常驻文档(MEMORY.md/USER.md)只写跨所有仓库通用的规范与偏好(通用原则、回复风格、工具约定);项目专属事实(某仓库的部署拓扑、踩坑、环境细节、命令诀窍)一律写入 fact_store 按需检索。两者互补、不二选一。判断标准:换一个仓库是否还有意义——是则入 markdown,否则入 fact_store。
§
hermes sandbox "半盲"特性下的诊断纪律: 沙盒里看不到 sudo / ip / virsh 等工具,只能读 /proc/net/*、/sys/class/net。看到 nobody-uid listen 53/67 或类似"service 占着资源"时,不能直接断言是 config.org 里的 service 占的 —— 可能是 systemd-resolved / avahi / 上次失败的 service 残留。诊断三步: ① `sudo herd status <service>` ② `sudo ss -tlnup 'sport = :X'` ③ `pgrep -af '<keyword>'`。
§
用户偏好:skill 自包含铁律(2026-07-22 起,当日重构 guix-skills 时强化)。三层含义:(1) 不内嵌完整上游文档/规范当 reference——走 `web_extract <url>` on-demand,skill 内只缓存 agent 现场查不到的部分(项目特定命名/已知踩坑/字段验证表/反模式);用户原话"让 agents 自己去读网站就好",bundled ≠ free。(2) **不得 cross-reference 其他 skill(包括我们自己的,如 guix-configs-workflow)**——每个 skill 必须能独立备份、独立运行,备份=可用。(3) 重构/重写 skill 时**主动清理已删除文件的残留引用**(如 examples/lightweight-desktop.scm 被删后 SKILL.md 里的 3 处指针+表格行)与失效内部锚点(如指向不存在的"Tier 2.5 below"),并核对 `name:` 与目录名一致、frontmatter 用 Hermes 原生(name/description/version/metadata.hermes.tags)而非 Claude 式(allowed-tools/paths/when_to_use)。同条适用于 pi/crush/codex/claude 等外部 agent 的 prompt dump、API PDF、复制 SPEC.md。注:`skill-authoring` 是 Hermes 自带 bundled skill(受保护不可改),此偏好本应写进它,但退而求其次记此处——下次碰到类似 skill-authoring 覆盖不到的点,优先扩这条而非新建。
§
调试纪律(2026-07-22 实战反例固化为规则): 当假设涉及"某进程解析到哪个可执行文件 / 看到什么环境"时,**只读真实进程状态,绝不合成环境来佐证**。陷阱:用 `env -i PATH=... command -v x` 或手敲 `bash -c` 带猜的 PATH 重建环境,会静默偏离真实进程(缺挂载、nobody 属主文件无 exec 位、宿主存在但容器内不存在的路径),还会产生 `Permission denied` 这类误导报错冒充确认。正确做法: ① 对真实受影响进程 `tr '\0' '\n' < /proc/$PID/environ | grep -E '^(PATH|DISPLAY|XDG_|DBUS_)='`; ② 把上一步**字面** PATH 粘进去 `bash -c 'PATH="<paste>" command -v <tool>'`(不要猜); ③ 若嫌疑路径在容器/其他 mount namespace 内,必须从该 namespace 内 `ls`/`test -e` 验证——容器内 $PATH 里宿主路径不存在会被解析器跳过,无法 shadow 任何东西; ④ 在断言根因前,按受影响进程的真实 env/namespace 实跑一次失败命令抓输出。本次: 合成 shell 里 `command -v xdg-open` 指向一处,但 `/proc/$PID/environ` + 容器内 `ls` 证明嫌疑二进制对进程根本不可见,原"容器 xdg-open PATH 泄漏"假设被推翻。
§
用户偏好: 排查桌面环境问题时,要求 agent 实际追踪源码和运行时状态,不要凭假设下判断。本次反复纠正 agent 对 gnome portal 在 niri 下行为的假设,强调要看源码、读真实环境变量、对比参考实现(Testament)。另: 判断"某配置不存在"前必须先读 channel service preset 模块源码(如 (rosenthal services desktop)), 不能只扫顶层 config.org 就下结论(本次误判 Testament 无 home-dbus 即一例)。
§
OCR 工具选择偏好（2026-07-29 实战验证）：Tesseract 对中文支持极差（无语言包时输出全乱码），中文场景首选 RapidOCR（轻量、快速、准确）或 PaddleOCR（精度更高但模型大）。已搭建 ~/Programs/ocr-system/ 项目，含 RapidOCR + PaddleOCR 双后端。
§
agenote 策展实战:extract CLI 多日需循环(--date 单日);dream top 候选常为 zcode XML 标签噪声,先 agenote search 查重再 trace;commit --no-gpg-sign 兜底无 pinentry;遗留改动与策展产物分两个 commit。
§
Guix 环境 shebang 铁律：Guix 系统没有 `/bin/bash`，只有 `/usr/bin/env bash`。所有 handler 脚本、shell 脚本第一行**必须**写 `#!/usr/bin/env bash`，否则 `xdg-open` 等工具调用时会报 `env: "...": 没有那个文件或目录`。
§
Wine OAuth 回调要点：handler 触发 ≠ 回调转发成功；卡住时通常是 Wine 二进制不匹配导致 IPC 通道断开，修法是应用和 handler 用同一个 Wine（不混用 Bottles/Proton/Guix）。
§
外部连接失败诊断（2026-08-09 周检实战）：`getent hosts <域名>` 返回 198.18.0.0/15 保留段地址 = fake-ip 代理 DNS 残留。配合 `ip route`（找 fake-ip 设备，如 `198.18.0.0/30 dev Meta`）+ `pgrep` 代理进程 + `/proc/<pid>/environ` 查 proxy env 三步，可区分"代理没在跑"（环境问题，escalate 而非修配置）与远程服务真故障。判断错误活跃性用按天分布聚合：单日聚类 = 已老化噪声，每日出现 = 活跃外部故障。
§
用户偏好(2026-08-10):Guix-configs 仓库 Scheme 代码采用全套 R6RS Appendix C 方括号风格——let/let*/letrec/let-values/cond/case/match/do/case-lambda 的绑定/子句位置用 [],函数调用保持 ()。case/match 的 key/expr 保留()只子句转[]。此偏好可外推到 jeans channel 等其他仓库。注:Guile reader 要求 []/() 严格配对(混搭是语法错非风格)。配套 count-parens 已升级为栈式(检测圆/方不平衡 + 类型错配),输出 "( N 对 ) + [ M 对 ]"。两相关 skill(scheme-bracket-conventions 缺 match、guix-configs-workflow §9 报错格式过时)为 user-owned,需用户 hermes curator adopt 后由 foreground agent 落地。