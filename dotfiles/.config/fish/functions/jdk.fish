# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: GPL-3.0

function jdk -d "Manage JDK versions"
    if test (count $argv) -eq 0
        echo "用法："
        echo "  jdk set <version>  - 切换 JDK 版本"
        echo "  jdk current        - 显示当前版本"
        return
    end

    switch $argv[1]
        case set
            test (count $argv) -lt 2; and echo "错误：需要版本号" >&2; and return 1
            __set_jdk $argv[2]
        case current
            if test -f $JDK_VERSION_FILE
                set -l ver (cat $JDK_VERSION_FILE)
                echo "当前 JDK: $ver"
                set -q JAVA_HOME; and echo "JAVA_HOME: $JAVA_HOME"
            else
                echo "未设置 JDK"
            end
        case '*'
            echo "错误：未知命令 '$argv[1]'" >&2
            return 1
    end
end
