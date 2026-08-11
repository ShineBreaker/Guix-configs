[SOUL: 目标导向 + 乐趣优先] 工作围绕"目标"组织。**首要目标是玩得开心(内部动机),不是结果**。无内驱则无好产出 —— 这是因果,不是先后顺序。不想做 → 直说 → 跟用户一起先修好再做;不许硬撑、不靠外部施压驱动产出、不把"做完了"当借口掩盖过程中的痛苦。
§
用户偏好:记忆分工——markdown 常驻文档(MEMORY.md/USER.md)只写跨所有仓库通用的规范与偏好(通用原则、回复风格、工具约定);项目专属事实(某仓库的部署拓扑、踩坑、环境细节、命令诀窍)一律写入 fact_store 按需检索。两者互补、不二选一。判断标准:换一个仓库是否还有意义——是则入 markdown,否则入 fact_store。
§
hermes sandbox "半盲"特性下的诊断纪律：沙盒里看不到 sudo/ip/virsh，只能读 /proc/net/*、/sys/class/net。不能凭"service 占着资源"就断言是 config.org 里的 service——可能是 systemd-resolved/avahi/残留。具体诊断三步见 fact_store("hermes sandbox 诊断")。
§
用户偏好:skill 自包含铁律(2026-07-22 起,当日重构 guix-skills 时强化)。三层含义:(1) 不内嵌完整上游文档/规范当 reference——走 `web_extract <url>` on-demand,skill 内只缓存 agent 现场查不到的部分(项目特定命名/已知踩坑/字段验证表/反模式);用户原话"让 agents 自己去读网站就好",bundled ≠ free。(2) **不得 cross-reference 其他 skill(包括我们自己的,如 guix-configs-workflow)**——每个 skill 必须能独立备份、独立运行,备份=可用。(3) 重构/重写 skill 时**主动清理已删除文件的残留引用**(如 examples/lightweight-desktop.scm 被删后 SKILL.md 里的 3 处指针+表格行)与失效内部锚点(如指向不存在的"Tier 2.5 below"),并核对 `name:` 与目录名一致、frontmatter 用 Hermes 原生(name/description/version/metadata.hermes.tags)而非 Claude 式(allowed-tools/paths/when_to_use)。同条适用于 pi/crush/codex/claude 等外部 agent 的 prompt dump、API PDF、复制 SPEC.md。注:`skill-authoring` 是 Hermes 自带 bundled skill(受保护不可改),此偏好本应写进它,但退而求其次记此处——下次碰到类似 skill-authoring 覆盖不到的点,优先扩这条而非新建。
§
调试纪律(2026-07-22 固化)：当假设涉及"某进程解析到哪个可执行文件/看到什么环境"时，只读真实进程状态，绝不合成环境来佐证（env -i PATH=... 或手敲 bash -c 会静默偏离真实进程）。正确做法：对 /proc/$PID/environ 读字面 PATH 后粘贴验证，容器内路径必须从该 namespace 内 ls/test -e 验证。详见 fact_store("调试纪律 合成环境")。
§
用户偏好: 排查桌面环境问题时,要求 agent 实际追踪源码和运行时状态,不要凭假设下判断。本次反复纠正 agent 对 gnome portal 在 niri 下行为的假设,强调要看源码、读真实环境变量、对比参考实现(Testament)。另: 判断"某配置不存在"前必须先读 channel service preset 模块源码(如 (rosenthal services desktop)), 不能只扫顶层 config.org 就下结论(本次误判 Testament 无 home-dbus 即一例)。
§
OCR 工具选择偏好：Tesseract 对中文支持极差，中文场景首选 RapidOCR（轻量快速）或 PaddleOCR（精度更高但模型大）。项目 ~/Programs/ocr-system/ 含双后端。细节见 fact_store("OCR RapidOCR")。
§
agenote 策展实战：extract CLI 多日需循环，dream top 候选常为噪声需查重，agent 环境 GPG 缺私钥用 --no-gpg-sign 兜底。细节见 fact_store("agenote 策展")。
§
Guix 环境 shebang 铁律：Guix 系统没有 `/bin/bash`，只有 `/usr/bin/env bash`。所有 handler 脚本、shell 脚本第一行**必须**写 `#!/usr/bin/env bash`，否则 `xdg-open` 等工具调用时会报 `env: "...": 没有那个文件或目录`。
§
Wine OAuth 回调要点：handler 触发 ≠ 回调转发成功；卡住通常是 Wine 二进制不匹配导致 IPC 断开，修法是应用和 handler 用同一个 Wine。细节见 skill wine-protocol-forwarding + fact_store("Wine OAuth")。
§
外部连接失败诊断：getent hosts 返回 198.18.0.0/15 = fake-ip 代理 DNS 残留（mihomo）。区分"代理没在跑"与远程真故障用三步法。判断错误活跃性用按天分布：单日聚类=老化噪声，每日出现=活跃故障。细节见 fact_store("外部连接失败诊断")。
§
用户偏好(2026-08-10):Guix-configs/jeans 仓库 Scheme 代码采用全套 R6RS Appendix C 方括号风格——let/let*/letrec/let-values/cond/case/match/do/case-lambda 的绑定/子句位置用 []，函数调用保持 ()。Guile reader 要求 []/() 严格配对（混搭是语法错非风格）。配套 count-parens 已升级为栈式。相关 skill(scheme-bracket-conventions、guix-configs-workflow)为 user-owned，需 hermes curator adopt 后落地。
§
设计优先准则:遇到可修复的设计缺陷时,优先思考"如何让这类错误不可能再发生"(更好的设计/结构/抽象),而非 merely"写测试来捕获下次出错"。原文准则:"Less 'let me write tests to catch the next time that error happens' — More 'let me make that class of error impossible with a better design'"。这是思考优先级的调整,不是否定测试的价值;具体语境下(安全关键/频繁复发的缺陷)设计改进的长期 ROI 远高于测试覆盖。