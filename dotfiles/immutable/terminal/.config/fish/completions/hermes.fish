# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

hermes completion fish 2>/dev/null | source

function __fish_hermes_runtime -d "installed hermes apps for completion (fallback empty)"
    set -l root $HERMES_HOME/hermes-agent
    if test -z "$HERMES_HOME"
        set root $HOME/.local/share/hermes/hermes-agent
    end
    if test -z "$root"
        return
    end
    # hermes desktop needs no arg; hermes update delegates to upstream
end

complete -c hermes-update -f -l branch -d "跟随分支 (默认 main)" -r
complete -c hermes-update -f -l check -d "仅检查是否可更新"
complete -c hermes-update -f -l backup -d "强制完整备份"
complete -c hermes-update -f -l no-backup -d "跳过所有备份"
complete -c hermes-update -f -s y -l yes -d "跳过交互确认"
complete -c hermes-update -f -l force -d "Windows: 忽略并发 hermes.exe"
complete -c hermes-update -f -l force-venv -d "Windows: 强制改写运行中 venv"
