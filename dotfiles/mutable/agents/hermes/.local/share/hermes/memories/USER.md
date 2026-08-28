删除一律 trash-cli (trash-put)，不用 rm/shutil.rmtree，含 skill 清理。
§
新建 skill 必须进现有 11 分类之一(<category>/<skill-name>/)，装不下才新建且需确认；不动 ~/.config/agents/skills/(Guix Home immutable)。决策树见 skill-authoring §9。
§
用户拍板即执行不复议，全仓清误导表述；"自主完成/去休息"即转自主模式推到 commit+报告。commit 边界：git add -- <精确路径> + diff --cached 核对 + status 复查；无 GPG 时 --no-gpg-sign。
§
大型迁移/批量先拿中等样本端到端验证再放量。
§
需 CLI/库时先 guix search，列给用户 guix install 装；不默认 pip。环境变量(HERMES_HOME 等)直接读，读不到才 fallback。
§
commit 遵循 Conventional Commits：<type>[scope]: <description> (祈使句/小写/无句号)，Body 讲 what/why，Footer 放 BREAKING CHANGE/Refs。vision 优先直用、Electron desktop 必留、Org→Markdown 拒绝、博客 Hexo 资产等见 fact_store。
§
§
计划审批流程偏好(2026-08-29)：大型计划走「v1→外派审查→复核裁决→v2→二审→v3→grilling 批量提问(一次问全,不逐题)→终稿落盘→用户过目同意→零提问实施到底」。实施期内任何问题提前在 grilling 阶段问完；期内小缺陷当场修并标注、需拍板的跳过进待裁决清单、绝不扩范围。重要配置/补丁/脚本资产一律入 Guix-configs 仓库 stow 源(用户:"所有重要配置都存入到仓库中")。审查报告(含外派 harness 的)的新主张逐条实证后才并入——审查权不豁免举证责任。