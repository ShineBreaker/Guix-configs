function fish_command_not_found
    set -l cmd $argv[1]
    
    # 1. 告诉用户发生了什么 (模仿 Zsh 的反馈)
    echo "fish: '$cmd' not found. Searching in Guix..." >&2

    # 2. 尝试用 guix locate 查找包
    # 使用 string split 和 list 操作来处理结果，比 cut 更 Fish 化，但 grep/head 组合依然高效
    set -l pkg (guix locate "$cmd" 2>/dev/null | grep /bin/ | head -1 | cut -d@ -f1)

    # 3. 如果找不到包，调用 Fish 默认的 handler (通常是报错或建议安装)
    if test -z "$pkg"
        __fish_default_command_not_found_handler $cmd
        return $status
    end

    # 4. 找到了包，准备执行
    # 【关键 hack】: 因为 Fish handler 不传参数，我们需要从历史记录拿完整命令
    # 注意：这会将当前输入的整个命令行作为参数传给 guix shell
    set -l full_cmd_str $history[1]
    
    # 将字符串分割成列表，以便 guix 正确解析参数
    set -l full_cmd_list (string split " " -- $full_cmd_str)

    echo "Found '$cmd' in package '$pkg'. Executing..." >&2
    
    # 5. 执行
    # 使用 -- 确保后续内容被视为命令而非 guix 的参数
    guix shell $pkg -- $full_cmd_list
end

# 在 config.fish 中
function try
    set -l cmd $argv[1]
    # 查找包
    set -l pkg (guix locate "$cmd" 2>/dev/null | grep /bin/ | head -1 | cut -d@ -f1)
    
    if test -n "$pkg"
        echo "Running via guix shell $pkg..." >&2
        # 这里 $argv 是完整的参数，非常安全
        guix shell $pkg -- $argv
    else
        echo "Guix: Package for '$cmd' not found." >&2
        return 127
    end
end
