# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

# 终端会话选择器：foot/kitty 启动时弹 tmux+herdr+shell 合并 fzf 列表。
# 完整设计与容错语义见 docs/scripts/fish-conf-d.md 与 docs/scripts/session-selector.md。
#
# 关键契约：
# - selector 输出协议为单行 <mux>|<kind> | shell | __header__，kind 本身可含 |。
# - mux 异常退出（≠0）回选择界面重选；0（含用户主动退出 TUI）结束。
# - tmux 侧一律经 attach-entry：detached 创建 → @sidebar_visible 置 1 →
#   follow 建侧栏 → exec attach（退出码透传）。agent 创建的 session 不经此
#   入口，保持 @sidebar_visible 默认 0。
function __selector_tmux_attach_or_create
    set -l ses_name $argv[1]
    set -l win_name $argv[2]
    set -l cwd $argv[3]
    ~/.config/tmux/scripts/attach-entry "$ses_name" --create -n "$win_name" -c "$cwd"
end

# 已有 session 走同一入口（无 --create，缺失时 attach-entry 非零退出 → 外层回环）
function __selector_tmux_attach
    set -l ses_name $argv[1]
    ~/.config/tmux/scripts/attach-entry "$ses_name"
end

# 从用户输入构造一个合法的会话名（清洗非法字符、限长、纯数字加前缀）
function __selector_make_session_name
    set -l raw $argv[1]
    set -l cwd $argv[2]
    if test -z "$raw"
        set raw (path basename "$cwd")
    end
    set -l name (string replace -ra '[^a-zA-Z0-9_-]' '_' -- "$raw" | string sub -l 20)
    if test -z "$name"
        set name default
    end
    # tmux 拒绝纯数字 session 名 → 加前缀。注意 fish 陷阱：正则末尾 $ 须
    # 写双引号 + \$（单引号里 '\$' 不是锚点）
    if string match -qr "^[0-9]+\$" -- "$name"
        set name "s_$name"
    end
    echo "$name"
end

# 执行某个 mux 动作；返回该命令的退出码（0=正常，≠0=异常）
function __selector_run_mux
    set -l mux $argv[1]
    set -l kind $argv[2]
    set -l window_name $argv[3]
    set -l cwd $argv[4]

    switch "$kind"
        case new
            read -l -P "新 $mux 会话名 (回车=用 cwd): " raw_name
            set -l ses_name (__selector_make_session_name "$raw_name" "$cwd")

            if test "$mux" = tmux
                __selector_tmux_attach_or_create "$ses_name" "$window_name" "$cwd"
            else
                herdr --session "$ses_name"
            end

        case default
            if test "$mux" = tmux
                __selector_tmux_attach_or_create main "$window_name" "$cwd"
            else
                herdr
            end

        case '*'
            if test "$mux" = tmux
                __selector_tmux_attach "$kind"
            else
                herdr --session "$kind"
            end
    end
    return $status
end

if status is-interactive
    # 仅 foot/kitty 顶层终端弹选择器；tmux/herdr/容器会话内跳过
    if contains -- "$TERM" foot xterm-kitty; and not set -q TMUX; and not test "$HERDR_ENV" = 1; and not set -q CONTAINER_ID
        set -l cwd (pwd)
        set -l window_name (__selector_make_session_name "" "$cwd")

        set -l selector ~/.config/tmux/scripts/session-selector

        # selector 缺失（如 blue home 未跑）→ 直接进 tmux main，不闪退裸 shell
        if not test -x "$selector"
            __selector_tmux_attach_or_create main "$window_name" "$cwd"
            return
        end

        while true
            set -l key ("$selector")

            # ESC/取消/异常 → 空输出，留普通 shell
            if test -z "$key"
                return
            end

            if test "$key" = shell
                return
            end

            # 误选分组标题行 → 重弹
            if test "$key" = __header__
                continue
            end

            # -m 1 只切第一刀：kind 段本身允许含 |（会话名分隔符即协议符）
            set -l parts (string split -m 1 '|' -- "$key")
            set -l mux $parts[1]
            set -l kind ""
            if test (count $parts) -ge 2
                set kind (string join '|' -- $parts[2..-1])
            end

            __selector_run_mux "$mux" "$kind" "$window_name" "$cwd"
            set -l rc $status

            if test $rc -eq 0
                return
            end

            echo
            echo ">>> $mux 启动失败（退出码 $rc），请重选"
            echo
        end
    end
end
