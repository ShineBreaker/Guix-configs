if status is-interactive

    # ========== Foot 终端自动 Tmux ==========
    # 条件：在 Foot 中 + 不在 Tmux 内 + 不在容器内
    if test "$TERM" = "foot"; and not set -q TMUX; and not set -q CONTAINER_ID

        # 主 session 作为会话组锚点；每个终端仍有自己的 session 视图
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

        # 第一个终端创建主 session；后续终端加入同一 session group，
        # 这样窗口列表共享，但每个终端的当前窗口可以独立切换。
        # 新终端的行为等价于先加入组，再执行一次 Ctrl+b c。
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
