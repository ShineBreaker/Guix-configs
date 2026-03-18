if status is-interactive

    # ========== Foot 终端自动 Tmux ==========
    # 条件：在 Foot 中 + 不在 Tmux 内 + 不在容器内
    if test "$TERM" = "foot"; and not set -q TMUX; and not set -q CONTAINER_ID

        # 统一会话组名（所有终端共享窗口列表）
        set -l session_group "main"

        # 生成唯一的会话名（基于 fish 的 %self，每个终端进程不同）
        set -l session_name "term_"(echo %self)

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

        # 检查会话组是否存在
        if tmux has-session -t $session_group 2>/dev/null
            # 会话组已存在，创建链接会话（分组会话）
            # 这样每个终端可以独立切换窗口，但共享窗口列表
            tmux new-session -t $session_group -s $session_name -c $cwd
        else
            # 会话组不存在，创建主会话
            tmux new-session -s $session_group -n $window_name -c $cwd
        end

        # 退出后停止执行（防止继续加载 fish 提示符）
        exit
    end

end
