# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

function __fish_appimage_run_apps
    set -l root (string join "" -- $XDG_DATA_HOME /appimages 2>/dev/null; or echo $HOME/.local/share/appimages)
    if test -z "$root"
        set root $HOME/.local/share/appimages
    end
    if not set -q XDG_DATA_HOME; or test -z "$XDG_DATA_HOME"
        set root $HOME/.local/share/appimages
    end
    if test -d "$root"
        for d in $root/*/
            set -l name (basename $d)
            if test -f "$d/meta.scm"
                echo $name
            end
        end
    end
end

complete -c appimage-run -f

complete -c appimage-run -n "not __fish_seen_subcommand_from install run try uninstall diagnose diagnose-gpu list check-updates setup" -l debug -d "输出详细调试信息到 stderr"

complete -c appimage-run -n "__fish_use_subcommand" -f -a install -d "安装 AppImage"
complete -c appimage-run -n "__fish_use_subcommand" -f -a run -d "运行已安装应用"
complete -c appimage-run -n "__fish_use_subcommand" -f -a try -d "临时运行 AppImage"
complete -c appimage-run -n "__fish_use_subcommand" -f -a uninstall -d "卸载应用"
complete -c appimage-run -n "__fish_use_subcommand" -f -a diagnose -d "诊断缺失动态库"
complete -c appimage-run -n "__fish_use_subcommand" -f -a diagnose-gpu -d "诊断 GPU 渲染路径"
complete -c appimage-run -n "__fish_use_subcommand" -f -a list -d "列出已安装的 AppImage"
complete -c appimage-run -n "__fish_use_subcommand" -f -a check-updates -d "检查更新"
complete -c appimage-run -n "__fish_use_subcommand" -f -a setup -d "注册 MIME 类型"

complete -c appimage-run -n "__fish_seen_subcommand_from install" -l yes -d "非交互，自动确认"
complete -c appimage-run -n "__fish_seen_subcommand_from install" -l debug -d "保留临时目录用于调试"
complete -c appimage-run -n "__fish_seen_subcommand_from install" -F

complete -c appimage-run -n "__fish_seen_subcommand_from uninstall" -l yes -d "非交互，自动确认"
complete -c appimage-run -n "__fish_seen_subcommand_from uninstall" -xa "(__fish_appimage_run_apps)"

complete -c appimage-run -n "__fish_seen_subcommand_from run" -l debug-shell -d "失败时保留容器 shell 调试"
complete -c appimage-run -n "__fish_seen_subcommand_from run" -l repair -d "自动修复缺失依赖后重试"
complete -c appimage-run -n "__fish_seen_subcommand_from run" -l rebuild-profile -d "强制重建 profile"
complete -c appimage-run -n "__fish_seen_subcommand_from run" -n "__fish_is_first_token" -xa "(__fish_appimage_run_apps)"

complete -c appimage-run -n "__fish_seen_subcommand_from diagnose" -l repair -d "自动修复"
complete -c appimage-run -n "__fish_seen_subcommand_from diagnose" -xa "(__fish_appimage_run_apps)"

complete -c appimage-run -n "__fish_seen_subcommand_from diagnose-gpu" -xa "(__fish_appimage_run_apps)"

complete -c appimage-run -n "__fish_seen_subcommand_from check-updates" -xa "(__fish_appimage_run_apps)"

complete -c appimage-run -n "__fish_seen_subcommand_from try" -l debug -d "保留临时目录"
complete -c appimage-run -n "__fish_seen_subcommand_from try" -F
