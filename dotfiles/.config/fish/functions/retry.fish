function retry -d "命令失败时自动重试"
    set -l max_retries 5
    set -l attempt 0

    while true
        eval $argv
        if test $status -eq 0
            return 0
        end

        set attempt (math $attempt + 1)

        if test $attempt -ge $max_retries
            echo "已重试 $max_retries 次失败。是否继续重试？(y/n)"
            read -l response
            if test "$response" != "y"
                return 1
            end
            set attempt 0
        else
            echo "命令失败，正在重试 (第 $attempt 次)..."
        end
    end
end
