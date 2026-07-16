用户偏好:删除文件一律走 XDG trash `trash-cli` 工具, 不用 `rm` / `rm -rf` / `shutil.rmtree`。适用于 skill 目录清理、缓存清理、任何"删除一批文件"场景。
§
用户偏好:当主模型自己有 vision 能力(看图、判图)时,直接用主模型的视觉,不要绕道 `vision_analyze` 委派给子模型(audio/vision 子任务)。原话:"其实你是有视觉的,不需要委派 vision"。子模型适合做"有专长优势的任务"(比如 xiaomi mimo 看图有时更准、或更便宜),但**默认优先用主模型的能力**,只有主模型做不了才下沉到子任务。
§
用户偏好:`clarify` 选项**只能**放在 `choices[]` 数组(可选 row),**绝不**塞进 `question` 文本(UI 渲染为不可选的散文)。原话:"重新提问一次,你目前并没有成功显示出选项"。回复风格短、直接、决断(直接选数字选项),给选项后立即推进,不二次确认细节。
§
用户偏好:在 `~/.local/share/hermes/skills/` 新建 skill 必须放进现有 12 个分类之一(成为 `<category>/<skill-name>/`),只有现有分类全装不下时才能新建分类(且必须先与用户确认)。不允许直接在 `skills/` 顶层创建 `<skill-name>/`(把分类当 skill 名是反模式)。**不动 `~/.config/agents/skills/`**(那是 Guix Home immutable 部署)。12 个分类名 + 决策树见 `skill-authoring` skill §9。
§
用户偏好:用户拍板的事实不猜/不复议,直接照做且全仓清掉相关误导表述。低频—用户说「自主完成」「我去休息了」即转自主模式,推到 commit+报告。commit 时严格边界控制("不要碰其他的 uncommit 更改"):`git add -- <精确路径>` + `git diff --cached --name-only` 核对 + 提交后 `git status --short` 复查;agent 环境 GPG 缺私钥时 `--no-gpg-sign` 兜底。
§
用户偏好:大型迁移/批量灌数据/多仓库同步等,先拿一个代表性样本做端到端验证,估算好迁移后 hermes session_search / memory / DB 体积等实际效果再决定"要不要继续 / 怎么扩展"。原话:"先试着迁 1 个中等 session 做端到端验证,过了再说"。给包含预估影响的选项优于直接问"全量还是部分";汇报进度时主动报"已验证 X,待你决定是否放量"。
§
工具/库安装偏好：任务需要某 CLI 工具或 Python 库而环境里没有时，先用 `guix search <关键字>` 在 Guix channel 里找，列给用户由用户用 `guix install` 装——不要默认走 `pip install`。（Guix Home 环境）