# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: GPL-3.0

# =============================================================================
# denv - 项目环境管理器 (direnv + Guix + 语言支持)
#
# 子命令:
#   denv init [FLAGS]    初始化项目文件夹结构 + direnv 环境
#   denv load [FLAGS]    仅创建 direnv 相关文件
#   denv remove          删除 denv 管理的所有文件
#
# 扩展新语言:
#   1. 在 "Provider 定义" 区域创建以下函数:
#      __denv_provider_<name>_init       创建 provider 特有文件
#      __denv_provider_<name>_envrc      输出 .envrc 片段
#      __denv_provider_<name>_files      列出管理的文件 (用于 remove)
#      __denv_provider_<name>_dirs       列出要创建的目录 (用于 init)
#      __denv_provider_<name>_gitignore  输出 .gitignore 片段 (用于 init)
#   2. 在 __denv_all_providers 中注册名称
#   3. 在 denv 主函数的 flag 解析中添加对应的 --flag
# =============================================================================


# =============================================================================
# 全局配置 — 修改此区域以自定义默认行为
# =============================================================================

# ----- 基础项目结构 -----------------------------------------------------------

function __denv_config_base_dirs -d "每个项目都创建的目录"
    echo src
    echo doc
end

function __denv_config_base_gitignore -d "每个项目都写入 .gitignore 的基础内容"
    echo "# direnv"
    echo ".direnv/"
    echo ""
    echo "# Editor"
    echo "*~"
    echo ""
    echo "# OS"
    echo ".DS_Store"
    echo "Thumbs.db"
end

function __denv_config_init_git -d "init 时是否自动执行 git init (true/false)"
    echo true
end

# ----- Provider 注册表 --------------------------------------------------------

function __denv_all_providers -d "所有已注册的 provider 名称"
    echo guix
    echo py
end


# =============================================================================
# Provider 定义 — 每个语言/工具一个区块
# =============================================================================

# ----- Provider: guix (始终激活) ----------------------------------------------

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
    echo "use guix"
end

function __denv_provider_guix_files
    echo manifest.scm
end

function __denv_provider_guix_dirs
    # guix 不需要额外目录
end

function __denv_provider_guix_gitignore
    # guix 不需要额外 gitignore 规则
end

# ----- Provider: py (通过 --py 激活) ------------------------------------------

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

    uv init
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

function __denv_provider_py_dirs
    echo tests
end

function __denv_provider_py_gitignore
    echo ""
    echo "# Python"
    echo ".venv/"
    echo "__pycache__/"
    echo "*.pyc"
    echo "*.egg-info/"
end


# =============================================================================
# 内部逻辑 — 一般不需要修改
# =============================================================================

# ----- init -------------------------------------------------------------------

function __denv_init -d "Initialize project directory structure and direnv environment"
    set -l providers $argv

    # --- Collect all directories ---
    set -l dirs (__denv_config_base_dirs)
    for provider in $providers
        set -a dirs (__denv_provider_$provider\_dirs)
    end

    for dir in $dirs
        if not test -d "$dir"
            mkdir -p "$dir"
            echo "✔ 已创建目录 $dir/"
        else
            echo "· 目录 $dir/ 已存在，跳过"
        end
    end

    # --- Assemble .gitignore ---
    set -l gitignore_content (__denv_config_base_gitignore)
    for provider in $providers
        set -a gitignore_content (__denv_provider_$provider\_gitignore)
    end

    if not test -f .gitignore
        printf "%s\n" $gitignore_content > .gitignore
        echo "✔ 已创建 .gitignore"
    else
        echo "· .gitignore 已存在，跳过"
    end

    # --- Git init ---
    if test (__denv_config_init_git) = "true"
        if not test -d .git
            git init --quiet
            echo "✔ 已初始化 Git 仓库"
        else
            echo "· Git 仓库已存在，跳过"
        end
    end

    # --- Delegate to load for direnv setup ---
    echo ""
    __denv_load $providers
end

# ----- load -------------------------------------------------------------------

function __denv_load -d "Create direnv environment files"
    set -l providers $argv

    # Safety check before overwriting .envrc
    if test -f .envrc
        echo "⚠ .envrc 已存在，是否覆盖？[y/N]"
        read -l response
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

# ----- remove -----------------------------------------------------------------

function __denv_remove -d "Remove direnv environment files"
    # Scan all known providers so nothing is left behind
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

    # Check for .venv (created through py provider workflow)
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

# ----- usage ------------------------------------------------------------------

function __denv_usage
    echo "用法:"
    echo "  denv init [FLAGS]    初始化项目文件夹结构 + direnv 环境"
    echo "  denv load [FLAGS]    仅创建 direnv 相关文件"
    echo "  denv remove          删除 denv 管理的所有文件"
    echo ""
    echo "FLAGS:"
    echo "  --py     启用 Python (uv) 环境支持"
    echo "  --help   显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  denv init          # 初始化通用项目 (src/ + doc/ + Guix + direnv)"
    echo "  denv init --py     # 初始化 Python 项目 (额外 tests/ + uv + venv)"
    echo "  denv load          # 仅配置 direnv (不创建目录结构)"
    echo "  denv load --py     # 仅配置 direnv + Python"
    echo "  denv remove        # 清理所有 denv 管理的文件"
end

# ----- 主入口 -----------------------------------------------------------------

function denv -d "Manage project environments with Guix, direnv and language support"
    set -l cmd load
    set -l argv_tail $argv

    # Parse subcommand
    if test (count $argv_tail) -gt 0
        switch $argv_tail[1]
            case init load remove
                set cmd $argv_tail[1]
                set -e argv_tail[1]
        end
    end

    # Parse flags -> build providers list (guix always active)
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
        case init
            __denv_init $providers
        case load
            __denv_load $providers
        case remove
            __denv_remove
    end
end
