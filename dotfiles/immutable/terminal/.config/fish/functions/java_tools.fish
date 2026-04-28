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

function jbuild --description 'Compile Java source file from src/ to bin/'
    if test (count $argv) -eq 0
        echo "Usage: jbuild <filename>"
        echo "Example: jbuild MyClass"
        return 1
    end

    set filename $argv[1]
    set src_file "src/$filename.java"
    set bin_dir "bin"

    if not test -f "$src_file"
        echo "Error: Source file '$src_file' not found"
        return 1
    end

    if not test -d "$bin_dir"
        mkdir -p "$bin_dir"
    end

    javac -d "$bin_dir" "$src_file"

    if test $status -eq 0
        echo "Successfully compiled $filename.java -> $bin_dir/"
    end
end

function jrun --description 'Run compiled Java class from bin/'
    if test (count $argv) -eq 0
        echo "Usage: jrun <filename>"
        echo "Example: jrun MyClass"
        return 1
    end

    set filename $argv[1]
    set bin_dir "bin"

    if not test -d "$bin_dir"
        echo "Error: bin/ directory not found. Compile first with jbuild"
        return 1
    end

    if not test -f "$bin_dir/$filename.class"
        echo "Error: Compiled class '$bin_dir/$filename.class' not found"
        echo "Compile first with: jbuild $filename"
        return 1
    end

    java -cp "$bin_dir" "$filename"
end
