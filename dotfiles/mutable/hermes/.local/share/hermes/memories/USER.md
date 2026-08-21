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
