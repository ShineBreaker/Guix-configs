用户偏好:删除文件一律走 XDG trash `trash-cli` 工具, 不用 `rm` / `rm -rf` / `shutil.rmtree`。适用于 skill 目录清理、缓存清理、任何"删除一批文件"场景。
§
用户偏好:在 Guix-configs 仓库的子模块 cwd(典型 `~/Projects/Config/Guix-configs/stow/emacs/.config/emacs/`)里跑 `blue home` 必须先 `cd ~/Projects/Config/Guix-configs` 再执行,否则会报 "&external-error / No command with this name",看起来像命令本身挂了,实际是子模块 cwd 找不到 `blueprint.scm` + `source/config.org`。改 dotfiles 后任何 `blue` 子命令都得在仓库根跑。
§
用户偏好:当主模型自己有 vision 能力(看图、判图)时,直接用主模型的视觉,不要绕道 `vision_analyze` 委派给子模型(audio/vision 子任务)。原话:"其实你是有视觉的,不需要委派 vision"。子模型适合做"有专长优势的任务"(比如 xiaomi mimo 看图有时更准、或更便宜),但**默认优先用主模型的能力**,只有主模型做不了才下沉到子任务。
§
用户偏好:使用 `clarify` 工具时,必须把选项列在 `choices` 数组里作为可勾选的 row,**不要**把选项塞进 `question` 文本里。原话:"重新提问一次,你目前并没有成功显示出选项"。前一次失败的提问把所有候选写进 question 字符串里,UI 渲染成不可选的散文。规则:options only in `choices[]`, never inside `question`. // 风格: 用户回复短、直接、决断 (如"把sops的配置删了, 这些我完全没用过" / 直接选数字选项), 不要"我建议..." + 劝解式; 给选项后立即推进, 不要二次确认细节.
§
Verify code paths before claiming "X is loaded into context". When user asks "is X really injected?" or "does X actually do Y?", do NOT rely on what you "know" or on SOUL.md documentation — grep the actual codebase (build_context_files_prompt, memory_provider, plugin loaders, etc.) and report findings with file:line evidence. The class of error to avoid: implying knowledge of a file/feature is equivalent to knowing it's wired up.