删除一律 trash-cli (trash-put)，不用 rm/shutil.rmtree，含 skill 清理。
§
新建 skill 必须进现有 11 分类之一(<category>/<skill-name>/)，装不下才新建且需确认；不动 ~/.config/agents/skills/(Guix Home immutable)。决策树见 skill-authoring §9。
§
commit 边界(2026-08-29 精化)：git add -- <精确路径>；diff --cached 核对必须是**独立调用**、确认文件数=预期后才 commit（核对与 commit 串同一管道会拦不住 index 遗留混入）；commit 后 git show --stat HEAD 复查文件数；无 GPG 时 --no-gpg-sign。
§
大型迁移/批量先拿中等样本端到端验证再放量。
§
需 CLI/库时先 guix search，列给用户 guix install 装；不默认 pip。环境变量(HERMES_HOME 等)直接读，读不到才 fallback。
§
commit 遵循 Conventional Commits：<type>[scope]: <description> (祈使句/小写/无句号)，Body 讲 what/why，Footer 放 BREAKING CHANGE/Refs。vision 优先直用、Electron desktop 必留、Org→Markdown 拒绝、博客 Hexo 资产等见 fact_store。
§
§
计划审批流程偏好(2026-08-29)：大型计划走「v1→外派审查→复核裁决→v2→二审→v3→grilling 批量提问(一次问全,不逐题)→终稿落盘→用户过目同意→零提问实施到底」。实施期内任何问题提前在 grilling 阶段问完；期内小缺陷当场修并标注、需拍板的跳过进待裁决清单、绝不扩范围。重要配置/补丁/脚本资产一律入 Guix-configs 仓库 stow 源(用户:"所有重要配置都存入到仓库中")。审查报告(含外派 harness 的)的新主张逐条实证后才并入——审查权不豁免举证责任。
§
汇报口径(2026-09-07 用户质问后确立)：Guix 系统级改动 agent 不能执行时，必须显式标注「源码已落地、待部署」，不得让「已落地」读成「已生效」；热点/S 服务类改动要区分「决策链在工作」与「端用户可感知」。
§
验证要求：不接受「看起来做完了」——UI/鼠标/行为类任务要求真机反复操作验证，并会追问「你确定一下」「你再确认一下呢」；关键结论要独立复核（点名派 reviewer/oracle）。
§
反过度设计：当自动化/决策链被判断为过度设计时，倾向整体删除只保留最小能力（2026-09-13 可信 WiFi 热点链全删，只留一键启停 + 端口可达），不用继续修补。
§
模型渠道硬约束：只用 z-ai 与 opencode-go 供应的模型，禁 openrouter（价格扛不住）；调模型组合要方便。
§
文档信息架构：信息只在一处、各文件职责分明不重复、可信源统一；README 定位成「导读」（链接引导到权威文档，不重写一遍）；易腐的技术结论写进带日期的卡片，AGENTS.md 只留稳定约束 + 指针。