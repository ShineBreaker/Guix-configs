# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: GPL-3.0

# JDK 版本管理
set -g JDK_VERSION_FILE $XDG_CONFIG_HOME/fish/.jdk_version
set -g JDK_PATH_FILE $XDG_CONFIG_HOME/fish/.jdk_path
set -g JDK_DEFAULT_VERSION 25

# 设置 JDK 环境
function __set_jdk -d "Set JDK environment"
    set -l ver $argv[1]

    # 验证版本号
    if not string match -rq '^\d+$' $ver
        echo "错误：版本号必须是数字" >&2
        return 1
    end

    # 查找 JDK 路径
    set -l jdk_path $(guix build openjdk@$ver | grep '\-jdk$')

    if test -z "$jdk_path"
        echo "错误：找不到 openjdk@$ver" >&2
        return 1
    end

    # 更新环境变量
    set -gx JAVA_HOME $jdk_path
    fish_add_path -gP $JAVA_HOME/bin

    # 保存版本和路径
    mkdir -p (dirname $JDK_VERSION_FILE)
    echo $ver >$JDK_VERSION_FILE
    echo $jdk_path >$JDK_PATH_FILE

    echo "✓ JDK $ver"
end

# 启动初始化
if test -f $JDK_PATH_FILE
    set -gx JAVA_HOME (cat $JDK_PATH_FILE)
    fish_add_path -gP $JAVA_HOME/bin
else if test -f $JDK_VERSION_FILE
    set -l ver (cat $JDK_VERSION_FILE)
    __set_jdk $ver >/dev/null 2>&1
else if test -n "$JDK_DEFAULT_VERSION"
    __set_jdk $JDK_DEFAULT_VERSION >/dev/null 2>&1
end
