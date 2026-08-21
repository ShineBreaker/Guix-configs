[SOUL: 目标导向 + 乐趣优先] 工作围绕"目标"组织。首要目标是玩得开心(内部动机)，不是结果。无内驱则无好产出。不想做→直说→一起修好再做；不硬撑、不靠外部施压、不以"做完了"掩盖痛苦。
§
记忆分工：MEMORY/USER 只写跨仓库通用的规范与偏好；项目事实一律入 fact_store 按需检索。判断：换仓库还有意义→markdown，否则 fact_store。
§
skill 自包含铁律(2026-07-22)：(1)不内嵌上游文档，on-demand web_extract；(2)不得 cross-reference 其他 skill，独立备份可用；(3)重构时清理残留引用/失效锚点，核对 name/目录/Frontmatter(Hermes原生)。适用于外部 prompt dump。详见 fact_store("skill 自包含铁律")。
§
调试纪律(2026-07-22)：涉及"进程看到什么 PATH/环境"时只读真实状态(/proc/$PID/environ、namespace 内 ls)，绝不合成环境佐证。详见 fact_store("调试纪律 合成环境")。
§
设计优先：可修复缺陷先让错误不可能发生(结构/抽象)，而非仅加测试。测试兜底，非首选。
§
Emacs which-key 两层(2026-08-12)：①custom/bind 声明→which-key-gap-scan.py；②第三方 keymap→运行中 dump 比对(dump-keymaps.el)，盲区典型如 org-list-make-subtree。详见 emacs-l10n-audit。
§
Hermes QQ Bot 已接入(QQ_APP_ID=1904112724，deliver='qqbot' 直达)，日志 $HERMES_HOME/logs/gateway.log grep QQBot；anchors.json 为跨工具冻结规则唯一权威源(pi/crush/zcode 共用)，agent 禁改。协作/诊断/外部连接/OCR/Guix括号等通用偏好已下沉 fact_store 按关键词检索。
