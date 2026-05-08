if status is-interactive

    # ========== Foot 终端自动 Tmux ==========
    # 条件：在 Foot 中 + 不在 Tmux 内 + 不在容器内
    if test "$TERM" = "foot"; and not set -q TMUX; and not set -q CONTAINER_ID

        set -l session_group "main"
        set -l session_name "term_"$fish_pid

        # 生成窗口名：目录名，特殊字符替换
        set -l cwd (pwd)
        set -l window_name (basename $cwd | string replace -r '[^a-zA-Z0-9_-]' '_')

        # 防止空名称
        if test -z "$window_name"
            set window_name "default"
        end

        # 限制长度
        if test (string length $window_name) -gt 20
            set window_name (string sub -l 20 $window_name)
        end

        # === 会话选择器 ===
        # 检测是否有 tmux session 存在
        if tmux has-session 2>/dev/null
            # 有 session 存在，调用选择器
            set -l choice (~/.config/tmux/scripts/session-selector)

            switch "$choice"
                case "ESC"
                    # 用户取消，回到普通 shell
                    return
                case "NEW"
                    # 用户选择新建，继续执行下面的 group 逻辑
                case '*'
                    # 用户选择了已有 session，attach
                    tmux attach-session -t $choice
                    exit
            end
        end

        # === 原有 session group 逻辑 ===
        if tmux has-session -t $session_group 2>/dev/null
            tmux new-session -d -t $session_group -s $session_name -c $cwd
            tmux new-window -t "$session_name:" -n $window_name -c $cwd
            tmux attach-session -t $session_name
        else
            tmux new-session -s $session_group -n $window_name -c $cwd
        end

        # 退出后停止执行（防止继续加载 fish 提示符）
        exit
    end

end
