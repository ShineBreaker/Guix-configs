用户偏好:删除文件一律走 XDG trash `trash-cli` 工具, 不用 `rm` / `rm -rf` / `shutil.rmtree`。适用于 skill 目录清理、缓存清理、任何"删除一批文件"场景。
§
用户偏好:主模型有 vision 能力时直接用,不绕道 vision_analyze 委派子模型。子模型仅用于有专长优势的任务。
§
用户偏好: 新建 skill 必须进现有 11 分类之一(`<category>/<skill-name>/`), 全装不下才新建分类且需先确认; 绝不在 `skills/` 顶层建; 不动 `~/.config/agents/skills/`(Guix Home immutable)。决策树见 `skill-authoring` §9。
§
用户偏好:用户拍板的事实不猜/不复议,直接照做且全仓清掉相关误导表述。低频—用户说「自主完成」「我去休息了」即转自主模式,推到 commit+报告。commit 时严格边界控制("不要碰其他的 uncommit 更改"):`git add -- <精确路径>` + `git diff --cached --name-only` 核对 + 提交后 `git status --short` 复查;agent 环境 GPG 缺私钥时 `--no-gpg-sign` 兜底。
§
用户偏好:大型迁移/批量操作先拿代表性样本做端到端验证,估算效果再决定放量。原话:"先试着迁 1 个中等 session 做端到端验证,过了再说"。
§
工具/库安装偏好：任务需要某 CLI 工具或 Python 库而环境里没有时，先用 `guix search <关键字>` 在 Guix channel 里找，列给用户由用户用 `guix install` 装——不要默认走 `pip install`。（Guix Home 环境）
§
用户偏好: 系统已设的环境变量(如 HERMES_HOME)直接读取使用, 不要默认当未设置或硬编码默认值; fallback 仅变量确实读不到时兜底。原话: '你就直接读变量啊, 这个我是在系统里设置了的, 你可以加一个读不到的fallback'。
§
用户确实需 hermes 的 Electron desktop GUI(独立窗口/系统托盘/hermes://), 不接受纯 TUI 替代。迁移 hermes 时勿默认丢 desktop; Guix 跑 Electron 需额外容器/库, 用户愿付该维护成本。
§
用户偏好:拒绝 Org→Markdown 转换路线(2026-08-09)。Org 语义(ID/CUSTOM_ID/property drawer/org-roam 链接)在 Markdown 化时丢失。可行方向:让 Hexo 直接消费 Org 语义,或换原生理解 Org 的方案。
§
用户博客环境: Hexo 8.1.1 + 完全自写的"ASCII Orbit / just"主题(EJS模板 + TypeScript + Vite + ASCII globe动画 + Pagefind搜索 + 6套配色 + Playwright e2e测试),部署在 Codeberg Pages(repo: BrokenShine/pages)。博客仓库 ~/Documents/Blog/。这是用户大量投入的工程项目,任何博客方案变更都应优先考虑保留这套主题资产。
§
用户偏好:commit message 遵循 Conventional Commits 规范 —— <type>[optional scope]: <description>。标准类型:build/chore/ci/docs/feat/fix/perf/refactor/revert/style/test。描述用祈使句、小写开头、句末无句号。Body 解释 what/why 而非 how。Footer 放 BREAKING CHANGE: 或 Refs #123。