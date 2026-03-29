# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: GPL-3.0

# =============================================================================
# denv - 项目 direnv 环境管理器
#
# 基于 provider 架构，每个 provider 提供三个函数：
#   __denv_provider_<name>_init    - 创建 provider 特有的文件
#   __denv_provider_<name>_envrc   - 输出该 provider 的 .envrc 片段
#   __denv_provider_<name>_files   - 列出该 provider 管理的文件
#
# 新增语言支持时：
#   1. 在下方创建 __denv_provider_<name>_{init,envrc,files} 三个函数
#   2. 在 __denv_all_providers 中注册 provider 名称
#   3. 在 denv 主函数中添加对应的 --flag 处理
# =============================================================================

# ----- Provider Registry -----------------------------------------------------

function __denv_all_providers -d "List all registered provider names"
    echo guix
    echo py
end

# ----- Provider: guix (always active) ----------------------------------------

function __denv_provider_guix_init
    if not test -f manifest.scm
        echo "(specifications->manifest" > manifest.scm
        echo " '(" >> manifest.scm
        echo "   ;; Add your packages here" >> manifest.scm
        echo "   ))" >> manifest.scm
        echo "✔ 已创建 manifest.scm"
    else
        echo "· manifest.scm 已存在，跳过"
    end
end

function __denv_provider_guix_envrc
    echo "use guix shell --manifest=./manifest.scm"
end

function __denv_provider_guix_files
    echo manifest.scm
end

# ----- Provider: py (activated with --py) ------------------------------------

function __denv_provider_py_init
    if not test -f .python-version
        set -l py_version ""
        if command -v python3 >/dev/null 2>&1
            set py_version (python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null)
        end
        if test -z "$py_version"
            set py_version "3"
        end
        echo $py_version > .python-version
        echo "✔ 已创建 .python-version ($py_version)"
    else
        echo "· .python-version 已存在，跳过"
    end
end

function __denv_provider_py_envrc
    echo ""
    echo "# Python environment via uv"
    echo "if [ ! -d .venv ]; then"
    echo "    uv venv --quiet"
    echo "fi"
    echo "source .venv/bin/activate"
end

function __denv_provider_py_files
    echo .python-version
end

# ----- Internal: load ---------------------------------------------------------

function __denv_load -d "Create direnv environment files"
    set -l providers $argv

    # Safety check before overwriting .envrc
    if test -f .envrc
        echo "⚠ .envrc 已存在，是否覆盖？[y/N]"
        read -
l response
        if test "$response" != "y" -a "$response" != "Y"
            echo "已取消"
            return 0
        end
    end

    # Initialize provider-specific files
    for provider in $providers
        __denv_provider_$provider\_init
    end

    # Assemble .envrc content
    set -l envrc_content "# --- denv managed ---"
    for provider in $providers
        set -a envrc_content (__denv_provider_$provider\_envrc)
    end
    set -a envrc_content "# --- end denv managed ---"

    printf "%s\n" $envrc_content > .envrc
    echo "✔ 已创建 .envrc"

    # Allow direnv
    if command -v direnv >/dev/null 2>&1
        direnv allow
        echo "✔ 已执行 direnv allow"
    else
        echo "⚠ direnv 未找到，请手动执行 direnv allow"
    end
end

# ----- Internal: remove -------------------------------------------------------

function __denv_remove -d "Remove direnv environment files"
    # Always scan all known providers so nothing is left behind
    set -l all_providers (__denv_all_providers)

    set -l files .envrc
    for provider in $all_providers
        set -a files (__denv_provider_$provider\_files)
    end

    # Collect existing files
    set -l existing_files
    for f in $files
        if test -f $f
            set -a existing_files $f
        end
    end

    # Check for .venv (managed by uv but created through our workflow)
    set -l has_venv false
    if test -d .venv
        set has_venv true
    end

    if test (count $existing_files) -eq 0; and test "$has_venv" = false
        echo "没有找到 denv 管理的文件"
        return 0
    end

    echo "即将删除以下文件:"
    for f in $existing_files
        echo "  - $f"
    end
    if test "$has_venv" = true
        echo "  - .venv/ (Python 虚拟环境)"
    end

    echo ""
    echo "确认删除？[y/N]"
    read -l response
    if test "$response" != "y" -a "$response" != "Y"
        echo "已取消"
        return 0
    end

    for f in $existing_files
        rm -f $f
        echo "✔ 已删除 $f"
    end

    if test "$has_venv" = true
        rm -rf .venv
        echo "✔ 已删除 .venv/"
    end

    if command -v direnv >/dev/null 2>&1
        direnv deny 2>/dev/null
    end

    echo "✔ 清理完成"
end

# ----- Internal: usage --------------------------------------------------------

function __denv_usage
    echo "用法: denv [load] [OPTIONS]   初始化项目 direnv 环境"
    echo "      denv remove             删除 direnv 相关文件"
    echo ""
    echo "选项:"
    echo "  --py     启用 Python (uv) 环境支持"
    echo "  --help   显示帮助信息"
    echo ""
    echo "示例:"
    echo "  denv              # Guix + direnv"
    echo "  denv load --py    # Guix + Python (uv) + direnv"
    echo "  denv remove       # 清理所有 denv 管理的文件"
end

# ----- Main Entry Point -------------------------------------------------------

function denv -d "Manage project direnv environments with Guix and language support"
    set -l cmd load
    set -l argv_tail $argv

    # Parse subcommand
    if test (count $argv_tail) -gt 0
        switch $argv_tail[1]
            case load remove
                set cmd $argv_tail[1]
                set -e argv_tail[1]
        end
    end

    # Parse flags -> build active providers list
    # guix is always active
    set -l providers guix

    for arg in $argv_tail
        switch $arg
            case --py
                if not contains py $providers
                    set -a providers py
                end
            case --help -h
                __denv_usage
                return 0
            case '*'
                echo "错误：未知选项 '$arg'" >&2
                __denv_usage >&2
                return 1
        end
    end

    switch $cmd
        case load
            __denv_load $providers
        case remove
            __denv_remove
    end
end
