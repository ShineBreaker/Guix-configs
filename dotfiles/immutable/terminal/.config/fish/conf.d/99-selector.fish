# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

# 统一终端会话选择器 — 在 foot 窗口启动时弹出 fzf 选择 tmux / herdr / shell
#
# 设计：tmux 与 herdr 在 session 管理上同构（DEFAULT + 命名 session + 状态），
# 故两者共用同一套 selector 脚本（session-selector <tmux|herdr>）和同一套
# 执行模式。差异仅在具体命令（new-session -s / --session、main / default）。
#
# tmux：日常工作（main = DEFAULT）
# herdr：多 agent 协作（default = DEFAULT，命名 session 相互独立）
# shell：普通 shell，无终端复用器

# ===== tmux 辅助函数（须先定义后调用）=====
# 统一 tmux 的 attach/create 模式：detach 创建（若需）→ set 侧栏选项 →
# follow 建侧栏 → 纯 attach-session（不串联 \;，避免命令链竞态闪退）。
# 侧栏 opt-in：tmux 默认纯净（@sidebar_visible 全局 = 0），用户入口在此
# 用 session 级覆盖为 1。agent 程序化创建的 session 不经此入口 → 纯净。
function __selector_tmux_attach_or_create
    set -l ses_name $argv[1]
    set -l win_name $argv[2]
    set -l cwd $argv[3]

    # 名字冲突预检（tmux new-session 重复名退出码不可靠，用 has-session 预检）
    if tmux has-session -t "$ses_name" 2>/dev/null
        __selector_tmux_attach "$ses_name"
        return
    end

    # detached 新建（启动 server + 创建 session，不 attach，无前台竞态）
    tmux new-session -d -s "$ses_name" -n "$win_name" -c "$cwd"
    __selector_tmux_setup_sidebar "$ses_name"
    exec tmux attach-session -t "$ses_name"
end

# attach 已有 tmux session（设侧栏选项 + follow + 纯 attach）
function __selector_tmux_attach
    set -l ses_name $argv[1]
    __selector_tmux_setup_sidebar "$ses_name"
    exec tmux attach-session -t "$ses_name"
end

# 在 server 端设置侧栏（不与 attach 串联，避免命令链竞态）
function __selector_tmux_setup_sidebar
    set -l ses_name $argv[1]
    tmux set-option -t "$ses_name" @sidebar_visible 1
    ~/.config/tmux/scripts/sidebar-toggle follow >/dev/null 2>&1
end

if status is-interactive
    # 仅 foot 终端弹选择器；已有 tmux/herdr/容器 pane 跳过
    if test "$TERM" = foot; and not set -q TMUX; and not test "$HERDR_ENV" = 1; and not set -q CONTAINER_ID
        set -l cwd (pwd)
        set -l window_name (path basename "$cwd" \
            | string replace -r '[^a-zA-Z0-9_-]' '_' \
            | string sub -l 20)
        if test -z "$window_name"
            set window_name default
        end

        # Fish 双引号中 \t 不是制表符，用 (printf '\t') 生成真正的 TAB
        set -l TAB (printf '\t')

        # ===== 第一层：选择终端复用器 =====
        # session 列表移交给第二层 selector（统一 tmux/herdr 范式），
        # 第一层只做多路复用器选择，保持简洁对称。
        set -l choices
        set -a choices "tmux"$TAB"tmux (默认)"
        if command -q herdr
            set -a choices "herdr"$TAB"herdr"
        end
        set -a choices "shell"$TAB"Shell (无终端复用器)"

        # 第一层选择：ESC / Ctrl-C → fzf 退出非零，choice 为空 → 留普通 shell
        set -l choice (printf '%s\n' $choices \
            | fzf --reverse --no-multi \
                --header="选择会话环境" \
                --height=~50% \
                --with-nth=2.. \
                --delimiter="$TAB" \
            2>/dev/null)

        if test -z "$choice"
            return
        end

        set -l action (string split -f1 $TAB -- $choice)

        # ===== 第二层：按多路复用器执行 =====
        switch "$action"
            case tmux herdr
                # tmux / herdr 共用同一范式：调统一 selector → switch 输出 key。
                # selector 输出：NEW / DEFAULT / <命名 session 名> / (空=ESC)
                set -l selector ~/.config/tmux/scripts/session-selector

                # selector 未部署 → fallback（tmux=main, herdr=default）
                if not test -x "$selector"
                    if test "$action" = tmux
                        __selector_tmux_attach_or_create main "$window_name" "$cwd"
                    else
                        exec herdr
                    end
                end

                set -l key ("$selector" "$action")

                # selector 无输出（ESC/取消/异常）→ 留在普通 shell
                if test -z "$key"
                    return
                end

                switch "$key"
                    case NEW
                        # 新建命名会话：prompt 输入语义名（解决"改名模型烂"——
                        # 不再掉到 term_<pid>，用户可起 work/dev/debug 等语义名）。
                        read -l -P "新 $action 会话名 (回车=用 cwd): " ses_name

                        # 空 → fallback 到 cwd basename，清洗非法字符
                        if test -z "$ses_name"
                            set ses_name (path basename "$cwd" \
                                | string replace -ra '[^a-zA-Z0-9_-]' '_' \
                                | string sub -l 20)
                        else
                            # 用户输入也需清洗（tmux session 名限制）
                            set ses_name (string replace -ra '[^a-zA-Z0-9_-]' '_' -- "$ses_name" \
                                | string sub -l 20)
                        end

                        # 纯数字名加前缀（tmux 拒绝纯数字 session 名）
                        # 注意：fish 里 $ 在正则末尾需双引号 + \$ 转义（单引号会报错）
                        if string match -qr "^[0-9]+\$" -- "$ses_name"
                            set ses_name "s_$ses_name"
                        end

                        if test "$action" = tmux
                            __selector_tmux_attach_or_create "$ses_name" "$window_name" "$cwd"
                        else
                            exec herdr --session "$ses_name"
                        end

                    case DEFAULT
                        # 进入默认/共享会话：tmux=main, herdr=default
                        if test "$action" = tmux
                            __selector_tmux_attach_or_create main "$window_name" "$cwd"
                        else
                            exec herdr
                        end

                    case '*'
                        # attach 已有命名会话
                        if test "$action" = tmux
                            __selector_tmux_attach "$key"
                        else
                            exec herdr --session "$key"
                        end
                end

            case shell
                # 留在普通 shell
                return
        end
    end
end
