if status is-interactive

    # ========== Foot 终端自动 Tmux ==========
    # 条件：在 Foot 中 + 不在 Tmux 内 + 不在容器内
    if test "$TERM" = "foot"; and not set -q TMUX; and not set -q CONTAINER_ID

        # 统一会话名
        set -l session_name "main"

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

        # 检查会话是否存在
        if tmux has-session -t $session_name 2>/dev/null
            # 会话已存在，创建新窗口并附加
            tmux new-window -t $session_name -c $cwd
            tmux attach-session -t $session_name
        else
            # 会话不存在，创建新会话
            tmux new-session -s $session_name -n $window_name -c $cwd
        end

        # 退出后停止执行（防止继续加载 fish 提示符）
        exit
    end

end
