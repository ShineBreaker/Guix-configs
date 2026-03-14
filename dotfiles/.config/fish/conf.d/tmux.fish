if status is-interactive

    # ========== 场景A：Foot 终端自动 Tmux ==========
    # 条件：在 Foot 中 + 不在 Tmux 内 + 不在容器内
    if test "$TERM" = "foot"
        and not set -q TMUX
        and not set -q CONTAINER_ID

        # 生成会话名：目录名，特殊字符替换
        set -l cwd (pwd)
        set -l session_name (basename $cwd | string replace -r '[^a-zA-Z0-9_-]' '_')

        # 防止空名称
        if test -z "$session_name"
            set session_name "default"
        end

        # 限制长度
        if test (string length $session_name) -gt 20
            set session_name (string sub -l 20 $session_name)
        end

        # 尝试附加现有会话，否则创建
        tmux attach-session -t $session_name 2>/dev/null

        if test $status -ne 0
            # 新会话，保持当前目录
            tmux new-session -s $session_name -c $cwd
        end

        # 退出后停止执行（防止继续加载 fish 提示符）
        exit
    end

    # ========== 其他终端：普通 Fish ==========
    # 这里放你的其他 fish 配置（starship、abbr 等）

end
