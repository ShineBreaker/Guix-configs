用户偏好:删除文件一律走 XDG trash `trash-cli` 工具, 不用 `rm` / `rm -rf` / `shutil.rmtree`。适用于 skill 目录清理、缓存清理、任何"删除一批文件"场景。
用户偏好:在 Guix-configs 仓库的子模块 cwd(典型 `~/Projects/Config/Guix-configs/stow/emacs/.config/emacs/`)里跑 `blue home` 必须先 `cd ~/Projects/Config/Guix-configs` 再执行,否则会报 "&external-error / No command with this name",看起来像命令本身挂了,实际是子模块 cwd 找不到 `blueprint.scm` + `source/config.org`。改 dotfiles 后任何 `blue` 子命令都得在仓库根跑。
§
用户偏好:当主模型自己有 vision 能力(看图、判图)时,直接用主模型的视觉,不要绕道 `vision_analyze` 委派给子模型(audio/vision 子任务)。原话:"其实你是有视觉的,不需要委派 vision"。子模型适合做"有专长优势的任务"(比如 xiaomi mimo 看图有时更准、或更便宜),但**默认优先用主模型的能力**,只有主模型做不了才下沉到子任务。
