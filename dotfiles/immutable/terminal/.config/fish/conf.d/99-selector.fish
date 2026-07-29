# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

# 统一终端会话选择器 — 在 foot 窗口启动时弹出 fzf 选择 tmux / herdr / shell
#
# tmux：日常工作（默认）
# herdr：多 agent 协作（共享会话 / 独立会话）
# shell：普通 shell，无终端复用器
#
# 历史：99-tmux.fish（2026-07 前）→ 99-herdr.fish（2026-07 迁移）
# → 统一为 99-tmux.fish（2026-07 合并）

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
        set -l choices
        set -a choices "tmux"$TAB"tmux (默认)"

        # 列出已有 tmux session（可快速 attach）
        if tmux has-session 2>/dev/null
            for s in (tmux list-sessions -F '#{session_name}' 2>/dev/null)
                set -a choices "tmux-"$s"$TAB  ⬡ $s"
            end
        end

        if command -q herdr
            set -a choices "herdr"$TAB"herdr"
        end
        set -a choices "shell"$TAB"Shell (无终端复用器)"

        set -l choice (printf '%s\n' $choices \
            | fzf --reverse --no-multi \
                --header="选择会话环境" \
                --height=~50% \
                --with-nth=2.. \
                --delimiter="$TAB" \
            2>/dev/null || echo "tmux")

        set -l action (string split -f1 $TAB -- $choice)

        # ===== 第二层：按选择执行 =====
        switch "$action"
            case tmux
                # 默认 tmux → 新建或 attach 已有 session
                if tmux has-session 2>/dev/null
                    set -l ses (~/.config/tmux/scripts/session-selector)
                    switch "$ses"
                        case ESC
                            return
                        case NEW
                            exec tmux new-session -s main -n "$window_name" -c "$cwd"
                        case '*'
                            exec tmux attach-session -t "$ses"
                    end
                else
                    exec tmux new-session -s main -n "$window_name" -c "$cwd"
                end

            case herdr
                # 调用 herdr-session-selector 选会话，与 tmux 分支调
                # session-selector 对称。selector 输出单行机器 key：
                #   NEW / DEFAULT / ESC / <命名 session 名>
                # 命名 session 多为自动生成的 term_<pid>，故不在第一层平铺，
                # 而在此以"运行中 / 已停止·可重连"状态呈现。
                set -l selector ~/.config/herdr/scripts/herdr-session-selector

                # selector 未部署 → fallback 进 default 共享会话
                if not test -x "$selector"
                    exec herdr
                end

                set -l h_choice ("$selector")

                # selector 无输出（异常）→ 留在普通 shell
                if test -z "$h_choice"
                    return
                end

                # 输出是纯 key（无 tab），直接 switch，无需 string split
                switch "$h_choice"
                    case ESC
                        # 用户取消 → 留在普通 shell
                        return
                    case NEW
                        # 新建独立会话（唯一名，互不同步）
                        exec herdr --session "term_$fish_pid"
                    case DEFAULT
                        # 进入 default 共享会话（多窗口同步）
                        exec herdr
                    case '*'
                        # attach 已有命名会话
                        exec herdr --session "$h_choice"
                end

            case shell
                # 留在普通 shell
                return

            case '*'
                # attach 已有 tmux session（action 模式 tmux-<name>）
                set -l session_name (string replace -r '^tmux-' '' -- "$action")
                exec tmux attach-session -t "$session_name"
        end
    end
end
