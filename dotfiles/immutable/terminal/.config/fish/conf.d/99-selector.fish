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

        # 列出已有 tmux session（可快速 attach）。迁移自 session-selector 的
        # BUSY 保护：attached>0 的 session（被其他客户端占用）标 [使用中]，
        # action key 用 tmux-busy-<name> 与可用 session 区分，case '*' 拒绝 attach。
        # tmux 格式串用 | 分隔（session 名不会含 |），避免把 fish 的 TAB 变量
        # 嵌进 #{} 模板——制表符不是合法变量名会被吞掉。
        if tmux has-session 2>/dev/null
            for line in (tmux list-sessions -F '#{session_name}|#{session_attached}' 2>/dev/null)
                set -l parts (string split '|' -- $line)
                set -l s_name $parts[1]
                set -l s_attached $parts[2]
                if test "$s_attached" -gt 0
                    set -a choices "tmux-busy-"$s_name"$TAB  ⬡ "$s_name" [使用中]"
                else
                    set -a choices "tmux-"$s_name"$TAB  ⬡ "$s_name
                end
            end
        end

        if command -q herdr
            set -a choices "herdr"$TAB"herdr"
        end
        set -a choices "shell"$TAB"Shell (无终端复用器)"

        # 第一层选择：ESC / Ctrl-C / 无匹配 → fzf 退出非零，choice 为空。
        # 不用 `|| echo tmux` 兜底——那会把用户取消误当作"默认进 tmux"。
        # 取消即取消：留在普通 shell。
        set -l choice (printf '%s\n' $choices \
            | fzf --reverse --no-multi \
                --header="选择会话环境" \
                --height=~50% \
                --with-nth=2.. \
                --delimiter="$TAB" \
            2>/dev/null)

        # 用户取消（ESC）或 fzf 异常 → 留在普通 shell
        if test -z "$choice"
            return
        end

        set -l action (string split -f1 $TAB -- $choice)

        # ===== 第二层：按选择执行 =====
        switch "$action"
            case tmux
                # 默认项语义：有 main session 则 attach，否则新建 main。
                # 第一层已平铺具体 session（含 BUSY 标记），用户要 attach 别的
                # session 直接在第一层选 tmux-<name>；选默认 tmux 项 = 回到 main。
                # session-selector 已删除，其 BUSY 保护迁移到第一层平铺逻辑。
                #
                # 侧栏 opt-in：tmux 默认纯净（@sidebar_visible 全局 = 0），用户入口在此
                # 用 session 级覆盖为 1。agent 程序化创建的 session 不经此入口 → 纯净。
                #
                # 关键：attach-session / new-session（无 -d）都让 client 接管终端进入
                # 前台交互模式。若在其后用 \; 串联 set-option / run-shell，命令链竞态
                # 会让 client 异常退出 = 闪退。故统一模式：先在 server 端把 session 级
                # 选项设好、侧栏建好（detached，无前台竞态），最后用纯 attach-session
                # （无 \; 串联）接管终端。无 server 时用 new-session -d 启动 server。
                if not tmux has-session -t main 2>/dev/null
                    # 无 main（含无 server 情形）→ detached 新建，先启动 server
                    tmux new-session -d -s main -n "$window_name" -c "$cwd"
                end
                # 此时 server 必在、main session 必在（detached）
                tmux set-option -t main @sidebar_visible 1
                ~/.config/tmux/scripts/sidebar-toggle follow >/dev/null 2>&1
                exec tmux attach-session -t main

            case herdr
                # 调用 herdr-session-selector 选会话。selector 输出单行机器 key：
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
                # 第一层选了具体 session 条目。BUSY 拦截：tmux-busy-<name> 表示该
                # session 正被其他客户端占用，拒绝 attach（保护对方，避免意外断开）；
                # tmux-<name> 为可用 session，直接 attach。
                # attach 前不串联命令（命令链竞态致闪退）：先独立 set-option + follow，
                # 再用纯 attach-session 接管终端（与 case tmux 同模式）。
                if string match -q 'tmux-busy-*' -- "$action"
                    set -l session_name (string replace -r '^tmux-busy-' '' -- "$action")
                    echo "session [$session_name] 正在被其他客户端使用，未 attach。" >&2
                    return
                end
                set -l session_name (string replace -r '^tmux-' '' -- "$action")
                tmux set-option -t "$session_name" @sidebar_visible 1
                ~/.config/tmux/scripts/sidebar-toggle follow >/dev/null 2>&1
                exec tmux attach-session -t "$session_name"
        end
    end
end
