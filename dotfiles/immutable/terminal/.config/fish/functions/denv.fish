# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

# =============================================================================
# denv - 项目环境管理器 (direnv + Guix + 语言支持 + LLM 脚手架)
#
# 子命令:
#   denv init   [FLAGS]    初始化项目结构 + direnv 环境
#   denv load   [FLAGS]    仅创建 direnv 相关文件（无参回放 .denv）
#   denv remove [--all] [-f]  删除 denv 管理的文件
#   denv status             查看当前 denv 状态
#   denv doctor [--fix]     诊断并可选修复
#
# FLAGS (init / load):
#   -l, --lang <langs>   语言列表，逗号分隔或多次出现 (python,node,rust,java,c,cpp,csharp)
#   -L, --LLM            启用 LLM 脚手架 (AGENTS.md + .agents/skills + 软链)
#       --full           配合 -L，使用完整 AGENTS.md 模板
#       --no-guix        不注入 guix (manifest.scm / use guix)
#   -f, --force          强制覆盖已存在文件，跳过交互确认
#
# FLAGS (remove):
#       --all            连同项目内容一起删除（AGENTS.md / .agents/skills / .denv 等）
#   -f, --force          跳过确认
#
# FLAGS (doctor):
#       --fix            自动修复可修复项（断裂软链 / 缺失 .gitkeep 等）
#
# 扩展新语言:
#   1. 在 Provider 定义区创建 7 个函数:
#      __denv_provider_<name>_init          创建 provider 特有文件
#      __denv_provider_<name>_envrc         输出 .envrc 片段
#      __denv_provider_<name>_files         列出管理的文件 (用于 remove)
#      __denv_provider_<name>_dirs          列出要创建的目录 (用于 init)
#      __denv_provider_<name>_gitignore     输出 .gitignore 片段
#      __denv_provider_<name>_guix_packages 输出 Guix spec 列表 (用于 manifest.scm)
#      __denv_provider_<name>_check         状态检查输出 (用于 status/doctor)
#   2. 在 __denv_all_providers / __denv_all_langs 中注册
#   3. 在 __denv_lang_aliases 中登记别名
#   4. 在 __denv_resolve_lang 的白名单中加入 canonical
# =============================================================================


# =============================================================================
# 全局配置 — 修改此区域以自定义默认行为
# =============================================================================

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

function __denv_all_providers -d "所有已注册的 provider 名称"
    echo guix
    echo python
    echo node
    echo rust
    echo java
    echo c
    echo cpp
    echo csharp
    echo llm
end

function __denv_all_langs -d "可供 --lang 选择的语言 canonical 列表"
    echo python
    echo node
    echo rust
    echo java
    echo c
    echo cpp
    echo csharp
end

function __denv_lang_aliases -d "别名 -> canonical 映射，每行 'alias canonical'"
    echo "py python"
    echo "js node"
    echo "ts node"
    echo "rs rust"
    echo "jvm java"
    echo "gradle java"
    echo "maven java"
    echo "cc cpp"
    echo "c++ cpp"
    echo "cpp cpp"
    echo "cs csharp"
    echo "c# csharp"
    echo "csharp csharp"
    echo "dotnet csharp"
end

function __denv_config_file -d ".denv 声明式配置路径"
    echo .denv
end


# =============================================================================
# 辅助 — 语言归一、manifest 渲染、.denv 读写
# =============================================================================

function __denv_resolve_lang -d "归一单个语言输入，输出 canonical 或报错"
    set -l raw $argv[1]
    set -l lower (string lower -- $raw)
    # 去除首尾空白
    set lower (string trim -- $lower)
    if test -z "$lower"
        return 1
    end

    # 查别名表
    for entry in (__denv_lang_aliases)
        set -l parts (string split " " -- $entry)
        if test "$lower" = "$parts[1]"
            echo $parts[2]
            return 0
        end
    end

    # 已是 canonical
    for lang in (__denv_all_langs)
        if test "$lower" = "$lang"
            echo $lower
            return 0
        end
    end

    echo "错误：未知语言 '$raw'，可用: "(string join ", " -- (__denv_all_langs)) >&2
    return 1
end

function __denv_render_manifest -d "聚合所有 active providers 的 guix_packages 去重渲染 manifest.scm"
    set -l providers $argv

    # 收集所有 spec
    set -l specs
    for p in $providers
        if functions -q __denv_provider_$p\_guix_packages
            for s in (__denv_provider_$p\_guix_packages)
                if test -n "$s"
                    set -a specs $s
                end
            end
        end
    end

    if test (count $specs) -eq 0
        return 0
    end

    # 去重保持顺序
    set -l uniq_specs
    for s in $specs
        if not contains -- $s $uniq_specs
            set -a uniq_specs $s
        end
    end

    # 若已存在 manifest.scm，提取已有包并合并，避免覆盖手写包
    set -l existing_specs
    if test -f manifest.scm
        # 抽取形如 "pkg" 的条目
        set -l content (cat manifest.scm 2>/dev/null)
        for token in (string match -ra '"[^"]+"' -- $content)
            set -l pkg (string trim -c '"' -- $token)
            if test -n "$pkg"
                set -a existing_specs $pkg
            end
        end
        for s in $existing_specs
            if not contains -- $s $uniq_specs
                set -a uniq_specs $s
            end
        end
    end

    # 渲染
    echo "(specifications->manifest" > manifest.scm
    echo " '(" >> manifest.scm
    for s in $uniq_specs
        echo "   \"$s\"" >> manifest.scm
    end
    echo "   ))" >> manifest.scm
    echo "✔ 已更新 manifest.scm ("(string join ", " -- $uniq_specs)")"
end

function __denv_write_config -d "写入 .denv 声明式配置"
    set -l langs $argv
    # 最后一个参数约定为 llm/guix 标记，通过全局变量传递更清晰；这里用辅助变量
    # 调用方需设置 __denv_cfg_llm / __denv_cfg_guix / __denv_cfg_full
    set -l cfg_file (__denv_config_file)
    echo "# denv managed — 由 denv 自动生成，记录项目声明式配置" > $cfg_file
    echo "# 修改后运行 denv load 即可回放" >> $cfg_file
    if test (count $langs) -gt 0
        echo "langs="(string join "," -- $langs) >> $cfg_file
    else
        echo "langs=" >> $cfg_file
    end
    if set -q __denv_cfg_llm
        echo "llm=$__denv_cfg_llm" >> $cfg_file
    else
        echo "llm=false" >> $cfg_file
    end
    if set -q __denv_cfg_guix
        echo "guix=$__denv_cfg_guix" >> $cfg_file
    else
        echo "guix=true" >> $cfg_file
    end
    if set -q __denv_cfg_full
        echo "full=$__denv_cfg_full" >> $cfg_file
    end
end

function __denv_read_config -d "读取 .denv，回填 __denv_restore_langs / __denv_restore_llm / __denv_restore_guix"
    set -g __denv_restore_langs
    set -g __denv_restore_llm false
    set -g __denv_restore_guix true
    set -g __denv_restore_full false
    set -l cfg_file (__denv_config_file)
    if not test -f $cfg_file
        return 1
    end
    for line in (cat $cfg_file 2>/dev/null)
        set -l trimmed (string trim -- $line)
        if test -z "$trimmed"; or string match -qr "^#" -- $trimmed
            continue
        end
        set -l kv (string split -m 1 "=" -- $trimmed)
        if test (count $kv) -lt 2
            continue
        end
        set -l k (string trim -- $kv[1])
        set -l v (string trim -- $kv[2])
        switch $k
            case langs
                if test -n "$v"
                    set -g __denv_restore_langs (string split "," -- $v)
                end
            case llm
                set -g __denv_restore_llm $v
            case guix
                set -g __denv_restore_guix $v
            case full
                set -g __denv_restore_full $v
        end
    end
    return 0
end


# =============================================================================
# Provider 定义
# =============================================================================

# ----- guix (默认激活，可 --no-guix 关闭) ------------------------------------

function __denv_provider_guix_init
    # 实际写入由 __denv_render_manifest 统一负责
end

function __denv_provider_guix_envrc
    echo "use guix"
end

function __denv_provider_guix_files
    echo manifest.scm
end

function __denv_provider_guix_dirs
end

function __denv_provider_guix_gitignore
end

function __denv_provider_guix_guix_packages
end

function __denv_provider_guix_check
    if test -f manifest.scm
        echo "  ✔ manifest.scm"
    else
        echo "  ✘ manifest.scm 缺失"
    end
end

# ----- python ----------------------------------------------------------------

function __denv_provider_python_init
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

    if test -f pyproject.toml
        echo "· pyproject.toml 已存在，跳过 uv init"
    else if command -v uv >/dev/null 2>&1
        uv init --no-readme 2>/dev/null; or uv init 2>/dev/null
        echo "✔ 已执行 uv init"
    else
        # 离线最小 pyproject
        set -l proj_name (basename $PWD)
        printf '[project]\nname = "%s"\nversion = "0.1.0"\nrequires-python = ">=3.10"\ndependencies = []\n' $proj_name > pyproject.toml
        echo "✔ 已创建 pyproject.toml (uv 未找到，手写最小模板)"
    end
end

function __denv_provider_python_envrc
    echo ""
    echo "# Python environment via uv"
    echo "if [ ! -d .venv ]; then"
    echo "    uv venv --quiet"
    echo "fi"
    echo "source .venv/bin/activate"
end

function __denv_provider_python_files
    echo .python-version
    echo pyproject.toml
end

function __denv_provider_python_dirs
    echo tests
end

function __denv_provider_python_gitignore
    echo ""
    echo "# Python"
    echo ".venv/"
    echo "__pycache__/"
    echo "*.pyc"
    echo "*.egg-info/"
    echo ".pytest_cache/"
end

function __denv_provider_python_guix_packages
    echo python
    echo uv
end

function __denv_provider_python_check
    if test -f .python-version
        echo "  ✔ .python-version"
    else
        echo "  ✘ .python-version 缺失"
    end
    if test -f pyproject.toml
        echo "  ✔ pyproject.toml"
    else
        echo "  ✘ pyproject.toml 缺失"
    end
end

# ----- node ------------------------------------------------------------------

function __denv_provider_node_init
    if test -f package.json
        echo "· package.json 已存在，跳过"
        return 0
    end
    set -l proj_name (basename $PWD)
    if command -v npm >/dev/null 2>&1
        npm init -y >/dev/null 2>&1
        echo "✔ 已创建 package.json (npm init -y)"
    else
        printf '{\n  "name": "%s",\n  "version": "0.1.0",\n  "type": "module",\n  "scripts": {\n    "start": "node src/index.js"\n  }\n}\n' $proj_name > package.json
        echo "✔ 已创建 package.json (手写最小模板)"
    end
    if not test -f src/index.js
        mkdir -p src
        echo 'console.log("hello from denv");' > src/index.js
        echo "✔ 已创建 src/index.js"
    end
end

function __denv_provider_node_envrc
    echo ""
    echo "# Node"
    echo "# guix shell 已提供 node；如需 pnpm 可在 manifest.scm 中追加"
end

function __denv_provider_node_files
    echo package.json
end

function __denv_provider_node_dirs
end

function __denv_provider_node_gitignore
    echo ""
    echo "# Node"
    echo "node_modules/"
    echo "dist/"
end

function __denv_provider_node_guix_packages
    echo node
end

function __denv_provider_node_check
    if test -f package.json
        echo "  ✔ package.json"
    else
        echo "  ✘ package.json 缺失"
    end
end

# ----- rust ------------------------------------------------------------------

function __denv_provider_rust_init
    if test -f Cargo.toml
        echo "· Cargo.toml 已存在，跳过"
        return 0
    end
    set -l proj_name (basename $PWD)
    # 规范化为合法 crate 名
    set proj_name (string lower -- $proj_name | string replace -ra '[^a-z0-9_-]' '-')
    if command -v cargo >/dev/null 2>&1
        cargo init --name $proj_name --quiet 2>/dev/null
        if test $status -eq 0
            echo "✔ 已执行 cargo init --name $proj_name"
            return 0
        end
    end
    printf '[package]\nname = "%s"\nversion = "0.1.0"\nedition = "2021"\n\n[dependencies]\n' $proj_name > Cargo.toml
    mkdir -p src
    if not test -f src/main.rs
        echo 'fn main() { println!("hello from denv"); }' > src/main.rs
    end
    echo "✔ 已创建 Cargo.toml (手写最小模板)"
end

function __denv_provider_rust_envrc
    echo ""
    echo "# Rust — guix shell 已提供 cargo/rustc"
end

function __denv_provider_rust_files
    echo Cargo.toml
end

function __denv_provider_rust_dirs
end

function __denv_provider_rust_gitignore
    echo ""
    echo "# Rust"
    echo "target/"
end

function __denv_provider_rust_guix_packages
    echo rust
end

function __denv_provider_rust_check
    if test -f Cargo.toml
        echo "  ✔ Cargo.toml"
    else
        echo "  ✘ Cargo.toml 缺失"
    end
end

# ----- java (gradle) ---------------------------------------------------------

function __denv_provider_java_init
    set -l has_build false
    if test -f build.gradle.kts; or test -f build.gradle; or test -f pom.xml
        set has_build true
    end
    if test "$has_build" = true
        echo "· Java 构建文件已存在，跳过"
        return 0
    end
    if not test -f settings.gradle.kts
        echo 'rootProject.name = "'(basename $PWD)'"' > settings.gradle.kts
        echo "✔ 已创建 settings.gradle.kts"
    end
    if not test -f build.gradle.kts
        printf 'plugins {\n    java\n}\n\nrepositories {\n    mavenCentral()\n}\n\njava {\n    toolchain { languageVersion.set(JavaLanguageVersion.of(25)) }\n}\n' > build.gradle.kts
        echo "✔ 已创建 build.gradle.kts"
    end
    mkdir -p src/main/java src/test/java
    if not test -f src/main/java/App.java
        printf 'public class App {\n    public static void main(String[] args) {\n        System.out.println("hello from denv");\n    }\n}\n' > src/main/java/App.java
        echo "✔ 已创建 src/main/java/App.java"
    end
end

function __denv_provider_java_envrc
    echo ""
    echo "# Java — guix shell 已提供 openjdk/gradle"
end

function __denv_provider_java_files
    echo build.gradle.kts
    echo settings.gradle.kts
end

function __denv_provider_java_dirs
    echo src/main/java
    echo src/test/java
end

function __denv_provider_java_gitignore
    echo ""
    echo "# Java"
    echo "target/"
    echo "build/"
    echo ".gradle/"
    echo "*.class"
    echo "bin/"
end

function __denv_provider_java_guix_packages
    echo openjdk@25
    echo gradle
end

function __denv_provider_java_check
    if test -f build.gradle.kts; or test -f build.gradle; or test -f pom.xml
        echo "  ✔ Java 构建文件存在"
    else
        echo "  ✘ Java 构建文件缺失"
    end
end

# ----- c ---------------------------------------------------------------------

function __denv_provider_c_init
    if test -f CMakeLists.txt
        echo "· CMakeLists.txt 已存在，跳过"
        return 0
    end
    set -l proj_name (basename $PWD)
    printf 'cmake_minimum_required(VERSION 3.16)\nproject(%s C)\nset(CMAKE_C_STANDARD 11)\nadd_executable(%s src/main.c)\n' $proj_name $proj_name > CMakeLists.txt
    echo "✔ 已创建 CMakeLists.txt (C)"
    if not test -f src/main.c
        mkdir -p src
        printf '#include <stdio.h>\nint main(void) { printf("hello from denv\\n"); return 0; }\n' > src/main.c
        echo "✔ 已创建 src/main.c"
    end
end

function __denv_provider_c_envrc
    echo ""
    echo "# C — guix shell 已提供 gcc-toolchain/cmake"
end

function __denv_provider_c_files
    echo CMakeLists.txt
end

function __denv_provider_c_dirs
end

function __denv_provider_c_gitignore
    echo ""
    echo "# C/C++"
    echo "build/"
    echo "cmake-build-*/"
    echo "*.o"
    echo "*.a"
end

function __denv_provider_c_guix_packages
    echo gcc-toolchain
    echo cmake
end

function __denv_provider_c_check
    if test -f CMakeLists.txt
        echo "  ✔ CMakeLists.txt"
    else
        echo "  ✘ CMakeLists.txt 缺失"
    end
end

# ----- cpp -------------------------------------------------------------------

function __denv_provider_cpp_init
    if test -f CMakeLists.txt
        echo "· CMakeLists.txt 已存在，跳过"
        return 0
    end
    set -l proj_name (basename $PWD)
    printf 'cmake_minimum_required(VERSION 3.16)\nproject(%s CXX)\nset(CMAKE_CXX_STANDARD 20)\nadd_executable(%s src/main.cpp)\n' $proj_name $proj_name > CMakeLists.txt
    echo "✔ 已创建 CMakeLists.txt (C++)"
    if not test -f src/main.cpp
        mkdir -p src
        printf '#include <iostream>\nint main() { std::cout << "hello from denv" << std::endl; return 0; }\n' > src/main.cpp
        echo "✔ 已创建 src/main.cpp"
    end
end

function __denv_provider_cpp_envrc
    echo ""
    echo "# C++ — guix shell 已提供 gcc-toolchain/cmake"
end

function __denv_provider_cpp_files
    echo CMakeLists.txt
end

function __denv_provider_cpp_dirs
end

function __denv_provider_cpp_gitignore
    echo ""
    echo "# C/C++"
    echo "build/"
    echo "cmake-build-*/"
    echo "*.o"
    echo "*.a"
end

function __denv_provider_cpp_guix_packages
    echo gcc-toolchain
    echo cmake
end

function __denv_provider_cpp_check
    if test -f CMakeLists.txt
        echo "  ✔ CMakeLists.txt"
    else
        echo "  ✘ CMakeLists.txt 缺失"
    end
end

# ----- csharp ----------------------------------------------------------------

function __denv_provider_csharp_init
    set -l existing_csproj (find . -maxdepth 1 -name '*.csproj' -type f 2>/dev/null | head -n 1)
    if test -n "$existing_csproj"
        echo "· $existing_csproj 已存在，跳过"
        return 0
    end
    set -l proj_name (basename $PWD)
    if command -v dotnet >/dev/null 2>&1
        dotnet new console -n $proj_name --no-restore 2>/dev/null
        if test $status -eq 0
            # dotnet 会创建子目录，尝试扁平化到当前目录
            if test -d $proj_name
                for f in $proj_name/*
                    mv $f ./ 2>/dev/null
                end
                rmdir $proj_name 2>/dev/null
            end
            echo "✔ 已执行 dotnet new console -n $proj_name"
            return 0
        end
    end
    printf '<Project Sdk="Microsoft.NET.Sdk">\n  <PropertyGroup>\n    <OutputType>Exe</OutputType>\n    <TargetFramework>net8.0</TargetFramework>\n    <ImplicitUsings>enable</ImplicitUsings>\n    <Nullable>enable</Nullable>\n  </PropertyGroup>\n</Project>\n' > $proj_name.csproj
    if not test -f Program.cs
        echo 'Console.WriteLine("hello from denv");' > Program.cs
    end
    echo "✔ 已创建 $proj_name.csproj (手写最小模板)"
end

function __denv_provider_csharp_envrc
    echo ""
    echo "# C# — guix shell 已提供 dotnet"
    echo "export DOTNET_CLI_TELEMETRY_OPTOUT=1"
end

function __denv_provider_csharp_files
    # 动态，remove 时扫描 *.csproj / Program.cs
end

function __denv_provider_csharp_dirs
end

function __denv_provider_csharp_gitignore
    echo ""
    echo "# C#"
    echo "bin/"
    echo "obj/"
    echo "*.user"
end

function __denv_provider_csharp_guix_packages
    echo dotnet
end

function __denv_provider_csharp_check
    set -l found false
    for f in (find . -maxdepth 1 -name '*.csproj' -type f 2>/dev/null)
        if test -f "$f"
            echo "  ✔ "(basename $f)
            set found true
            break
        end
    end
    if test "$found" = false
        echo "  ✘ *.csproj 缺失"
    end
end

# ----- llm (AGENTS.md + .agents/skills + 软链) -------------------------------

function __denv_provider_llm_init -d "创建 AGENTS.md / .agents/skills / 软链"
    # 标记是否使用完整模板，由全局 __denv_llm_full 控制
    set -l use_full false
    if set -q __denv_llm_full; and test "$__denv_llm_full" = true
        set use_full true
    end

    # 1. AGENTS.md
    if not test -e AGENTS.md
        if test "$use_full" = true
            printf '# AGENTS.md\n\n> 项目协作约定（由 denv --LLM 生成，--full 完整模板）\n\n## 概述\n\n一句话描述本项目。\n\n## 工作准则\n\n- 先想清楚再动手：动手前写假设，没把握就提问。\n- 简单至上：能删代码就删，不做未被要求的功能。\n- 外科手术式修改：只动必须改的，沿用现有风格。\n- 目标驱动：先定义成功标准，循环验证。\n\n## 结构\n\n```\nproject/\n├── src/\n├── doc/\n├── tests/\n└── AGENTS.md\n```\n\n## 构建与验证\n\n```bash\ndirenv allow\n# 按语言补充构建命令\n```\n\n## 提交规范\n\n- Conventional Commits: `type(scope): desc`\n- type: feat / fix / refactor / docs / chore / build\n\n## 风险点\n\n- 改源后需重建环境（如 guix shell / direnv reload）\n' > AGENTS.md
        else
            printf '# AGENTS.md\n\n> 由 denv --LLM 生成的最小协作约定\n\n## 概述\n\n一句话描述本项目。\n\n## 协作约定\n\n- 修改前先读本文件与 README。\n- 保持改动最小化，沿用现有风格。\n\n## 技能索引\n\n- `.agents/skills/` — 项目技能与工作流\n' > AGENTS.md
        end
        echo "✔ 已创建 AGENTS.md"
    else
        echo "· AGENTS.md 已存在，跳过"
    end

    # 2. .agents/skills
    if not test -d .agents/skills
        mkdir -p .agents/skills
        echo "✔ 已创建 .agents/skills/"
    else
        echo "· .agents/skills/ 已存在，跳过"
    end
    if not test -f .agents/skills/.gitkeep
        # 仅当目录为空时加 .gitkeep
        set -l count (ls -A .agents/skills 2>/dev/null | count)
        if test $count -eq 0
            touch .agents/skills/.gitkeep
        end
    end

    # 3. CLAUDE.md -> AGENTS.md
    if test -L CLAUDE.md
        set -l target (readlink CLAUDE.md 2>/dev/null)
        if test "$target" = "AGENTS.md" -o "$target" = "./AGENTS.md"
            echo "· CLAUDE.md 软链已正确，跳过"
        else
            echo "· CLAUDE.md 已是软链但指向 $target，跳过（请手动检查）"
        end
    else if test -e CLAUDE.md
        echo "⚠ CLAUDE.md 已存在且为普通文件，跳过软链创建"
    else
        ln -s AGENTS.md CLAUDE.md
        echo "✔ 已创建 CLAUDE.md -> AGENTS.md"
    end

    # 4. .claude/skills -> ../.agents/skills
    if not test -d .claude
        mkdir -p .claude
    end
    if test -L .claude/skills
        set -l target (readlink .claude/skills 2>/dev/null)
        if test "$target" = "../.agents/skills"
            echo "· .claude/skills 软链已正确，跳过"
        else
            echo "· .claude/skills 已是软链但指向 $target，跳过"
        end
    else if test -e .claude/skills
        echo "⚠ .claude/skills 已存在且非软链，跳过"
    else
        ln -s ../.agents/skills .claude/skills
        echo "✔ 已创建 .claude/skills -> ../.agents/skills"
    end
end

function __denv_provider_llm_envrc
    # LLM 不注入 .envrc
end

function __denv_provider_llm_files
    # remove 默认不删 AGENTS.md 内容，仅删软链；此处不列入 files
end

function __denv_provider_llm_dirs
end

function __denv_provider_llm_gitignore
end

function __denv_provider_llm_guix_packages
end

function __denv_provider_llm_check
    if test -f AGENTS.md
        echo "  ✔ AGENTS.md"
    else
        echo "  ✘ AGENTS.md 缺失"
    end
    if test -d .agents/skills
        echo "  ✔ .agents/skills/"
    else
        echo "  ✘ .agents/skills/ 缺失"
    end
    if test -L CLAUDE.md
        echo "  ✔ CLAUDE.md -> "(readlink CLAUDE.md 2>/dev/null)
    else if test -e CLAUDE.md
        echo "  ⚠ CLAUDE.md 存在但非软链"
    else
        echo "  ✘ CLAUDE.md 缺失"
    end
    if test -L .claude/skills
        echo "  ✔ .claude/skills -> "(readlink .claude/skills 2>/dev/null)
    else
        echo "  ✘ .claude/skills 软链缺失"
    end
end


# =============================================================================
# 内部逻辑
# =============================================================================

function __denv_init -d "Initialize project directory structure and direnv environment"
    set -l providers $argv

    # --- Collect all directories ---
    set -l dirs (__denv_config_base_dirs)
    for provider in $providers
        if functions -q __denv_provider_$provider\_dirs
            set -a dirs (__denv_provider_$provider\_dirs)
        end
    end

    for dir in $dirs
        if test -z "$dir"
            continue
        end
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
        if functions -q __denv_provider_$provider\_gitignore
            set -a gitignore_content (__denv_provider_$provider\_gitignore)
        end
    end

    # 去除空字符串条目后决定是否写入/追加
    set -l filtered_gitignore
    for line in $gitignore_content
        # 保留空行用于分隔，直接加入；后续通过 git diff 判断
        set -a filtered_gitignore $line
    end

    if not test -f .gitignore
        printf "%s\n" $filtered_gitignore > .gitignore
        echo "✔ 已创建 .gitignore"
    else
        # 已存在时追加缺失行（幂等），--force 场景由 load 的 force 覆盖 .envrc，这里仅追加
        set -l existing (cat .gitignore 2>/dev/null)
        set -l appended false
        for line in $filtered_gitignore
            if test -z "$line"
                continue
            end
            if not string match -q -- "*$line*" "$existing"
                # 仅当整行未出现时追加
                set -l found false
                for el in $existing
                    if test "$el" = "$line"
                        set found true
                        break
                    end
                end
                if test "$found" = false
                    echo $line >> .gitignore
                    set appended true
                end
            end
        end
        if test "$appended" = true
            echo "✔ 已更新 .gitignore (追加缺失规则)"
        else
            echo "· .gitignore 已存在且规则齐全，跳过"
        end
    end

    # --- Git init ---
    if test (__denv_config_init_git) = "true"
        if not test -d .git
            git init --quiet 2>/dev/null
            if test $status -eq 0
                echo "✔ 已初始化 Git 仓库"
            end
        else
            echo "· Git 仓库已存在，跳过"
        end
    end

    echo ""
    __denv_load $providers
end

function __denv_load -d "Create direnv environment files"
    set -l providers $argv

    # 提取全局 force 标记
    set -l force false
    if set -q __denv_force; and test "$__denv_force" = true
        set force true
    end

    # Safety check before overwriting .envrc
    if test -f .envrc; and test "$force" = false
        echo "⚠ .envrc 已存在，是否覆盖？[y/N]"
        read -l response
        if test "$response" != "y" -a "$response" != "Y"
            echo "已取消"
            return 0
        end
    end

    # Initialize provider-specific files
    for provider in $providers
        if functions -q __denv_provider_$provider\_init
            __denv_provider_$provider\_init
        end
    end

    # Render manifest.scm if guix is active
    set -l has_guix false
    for p in $providers
        if test "$p" = "guix"
            set has_guix true
            break
        end
    end
    if test "$has_guix" = true
        __denv_render_manifest $providers
    end

    # Assemble .envrc content
    set -l envrc_content "# --- denv managed ---"
    for provider in $providers
        if functions -q __denv_provider_$provider\_envrc
            set -a envrc_content (__denv_provider_$provider\_envrc)
        end
    end
    set -a envrc_content "# --- end denv managed ---"

    printf "%s\n" $envrc_content > .envrc
    echo "✔ 已创建 .envrc"

    # Write .denv declarative config
    set -l langs_only
    for p in $providers
        if test "$p" != "guix" -a "$p" != "llm"
            set -a langs_only $p
        end
    end
    set -l llm_flag false
    if contains llm $providers
        set llm_flag true
    end
    set -g __denv_cfg_llm $llm_flag
    if test "$has_guix" = true
        set -g __denv_cfg_guix true
    else
        set -g __denv_cfg_guix false
    end
    if set -q __denv_llm_full
        set -g __denv_cfg_full $__denv_llm_full
    else
        set -g __denv_cfg_full false
    end
    __denv_write_config $langs_only
    echo "✔ 已写入 "( __denv_config_file)

    # Allow direnv
    if command -v direnv >/dev/null 2>&1
        direnv allow 2>/dev/null
        echo "✔ 已执行 direnv allow"
    else
        echo "⚠ direnv 未找到，请手动执行 direnv allow"
    end
end

function __denv_remove -d "Remove denv managed files"
    set -l all_flag false
    set -l force false
    for arg in $argv
        switch $arg
            case --all
                set all_flag true
            case --force -f
                set force true
        end
    end

    set -l all_providers (__denv_all_providers)

    set -l files .envrc
    for provider in $all_providers
        if functions -q __denv_provider_$provider\_files
            set -a files (__denv_provider_$provider\_files)
        end
    end
    # .denv 声明式配置
    set -a files (__denv_config_file)
    # csharp 动态产物（避免 fish 通配符未匹配报错，用 find）
    for f in (find . -maxdepth 1 -name '*.csproj' -type f 2>/dev/null)
        if test -f "$f"
            set -a files (basename $f)
        end
    end
    if test -f Program.cs
        set -l has_csproj (find . -maxdepth 1 -name '*.csproj' -type f 2>/dev/null | head -n 1)
        if test -n "$has_csproj"
            set -a files Program.cs
        end
    end

    # Collect existing files
    set -l existing_files
    for f in $files
        if test -f $f
            set -a existing_files $f
        end
    end

    # Check for .venv
    set -l has_venv false
    if test -d .venv
        set has_venv true
    end

    # LLM 软链与内容
    set -l llm_links
    set -l llm_content
    if test -L CLAUDE.md
        set -l target (readlink CLAUDE.md 2>/dev/null)
        if test "$target" = "AGENTS.md" -o "$target" = "./AGENTS.md"
            set -a llm_links CLAUDE.md
        end
    end
    if test -L .claude/skills
        set -l target (readlink .claude/skills 2>/dev/null)
        if test "$target" = "../.agents/skills"
            set -a llm_links .claude/skills
        end
    end
    if test "$all_flag" = true
        if test -f AGENTS.md
            set -a llm_content AGENTS.md
        end
        if test -d .agents/skills
            set -a llm_content .agents/skills
        end
        if test -f .agents/skills/.gitkeep
            # 已包含在目录中
        end
    end

    if test (count $existing_files) -eq 0; and test "$has_venv" = false; and test (count $llm_links) -eq 0; and test (count $llm_content) -eq 0
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
    for l in $llm_links
        echo "  - $l (软链)"
    end
    for c in $llm_content
        echo "  - $c"
    end
    if test "$all_flag" = false; and begin test -f AGENTS.md; or test -d .agents/skills; end
        echo ""
        echo "提示: AGENTS.md / .agents/skills 将保留，使用 denv remove --all 连同内容一起删除"
    end

    if test "$force" = false
        echo ""
        echo "确认删除？[y/N]"
        read -l response
        if test "$response" != "y" -a "$response" != "Y"
            echo "已取消"
            return 0
        end
    end

    for f in $existing_files
        rm -f $f
        echo "✔ 已删除 $f"
    end

    if test "$has_venv" = true
        rm -rf .venv
        echo "✔ 已删除 .venv/"
    end

    for l in $llm_links
        rm -f $l
        echo "✔ 已删除 $l"
        # 清理空的 .claude 目录
        if test "$l" = ".claude/skills"; and test -d .claude
            set -l remaining (ls -A .claude 2>/dev/null | count)
            if test $remaining -eq 0
                rmdir .claude 2>/dev/null
            end
        end
    end

    for c in $llm_content
        rm -rf $c
        echo "✔ 已删除 $c"
        if test "$c" = ".agents/skills"; and test -d .agents
            set -l remaining (ls -A .agents 2>/dev/null | count)
            if test $remaining -eq 0
                rmdir .agents 2>/dev/null
            end
        end
    end

    if command -v direnv >/dev/null 2>&1
        direnv deny 2>/dev/null
    end

    echo "✔ 清理完成"
end

function __denv_status -d "Show denv status"
    echo "== denv status =="
    echo ""

    # .denv
    set -l cfg_file (__denv_config_file)
    if test -f $cfg_file
        echo "配置: $cfg_file"
        cat $cfg_file 2>/dev/null | sed 's/^/  /'
    else
        echo "配置: $cfg_file 不存在（未记录声明式配置）"
    end
    echo ""

    # .envrc
    if test -f .envrc
        echo ".envrc: 存在"
        # 提取 providers 痕迹
        if string match -q "*use guix*" -- (cat .envrc 2>/dev/null)
            echo "  · 含 use guix"
        end
        if string match -q "*uv venv*" -- (cat .envrc 2>/dev/null)
            echo "  · 含 Python (uv venv)"
        end
    else
        echo ".envrc: 缺失"
    end
    echo ""

    # manifest
    if test -f manifest.scm
        echo "manifest.scm: 存在"
        cat manifest.scm 2>/dev/null | sed 's/^/  /'
    else
        echo "manifest.scm: 缺失"
    end
    echo ""

    # providers — status 展示活跃项高亮，其余折叠为概要
    echo "Providers 检查:"
    set -l active_status_providers
    if __denv_read_config 2>/dev/null
        if test "$__denv_restore_guix" = true
            set -a active_status_providers guix
        end
        for lang in $__denv_restore_langs
            if test -n "$lang"
                set -a active_status_providers $lang
            end
        end
        if test "$__denv_restore_llm" = true
            set -a active_status_providers llm
        end
    end
    if test (count $active_status_providers) -eq 0
        # 无 .denv 时展示全量
        set active_status_providers guix python node rust java c cpp csharp llm
    end
    set -l check_providers guix python node rust java c cpp csharp llm
    for p in $check_providers
        if functions -q __denv_provider_$p\_check
            if contains $p $active_status_providers
                echo "  [$p] *"
            else
                echo "  [$p]"
            end
            __denv_provider_$p\_check
        end
    end
    if test (count $active_status_providers) -gt 0
        echo "  (* 为 .denv 活跃项)"
    end
    echo ""

    # .gitignore
    if test -f .gitignore
        echo ".gitignore: 存在"
    else
        echo ".gitignore: 缺失"
    end
    echo ""

    # direnv
    if command -v direnv >/dev/null 2>&1
        echo "direnv: 已安装"
        if test -f .envrc
            direnv status 2>/dev/null | head -n 20 | sed 's/^/  /'
        end
    else
        echo "direnv: 未安装"
    end
end

function __denv_doctor -d "Diagnose and optionally fix denv setup"
    set -l fix false
    for arg in $argv
        if test "$arg" = "--fix"
            set fix true
        end
    end

    set -l issues 0
    set -l fixed 0
    echo "== denv doctor =="
    echo ""

    # 检查 .envrc 是否存在
    if not test -f .envrc
        echo "✘ .envrc 缺失 — 运行 denv load 重建"
        set issues (math $issues + 1)
    else
        echo "✔ .envrc 存在"
    end

    # 检查各 provider 声明文件 — 仅对 .denv 中记录的活跃 providers 计为问题
    # 避免未启用的语言一直报 ✘ 噪声；无 .denv 时回退为全量扫描但仅提示
    set -l active_check_providers
    if __denv_read_config 2>/dev/null
        if test "$__denv_restore_guix" = true
            set -a active_check_providers guix
        end
        for lang in $__denv_restore_langs
            if test -n "$lang"
                set -a active_check_providers $lang
            end
        end
        if test "$__denv_restore_llm" = true
            set -a active_check_providers llm
        end
        # 无活跃记录时至少检查 guix / llm 的基础存在性
        if test (count $active_check_providers) -eq 0
            set active_check_providers (__denv_all_providers)
        end
    else
        set active_check_providers (__denv_all_providers)
    end
    for p in $active_check_providers
        if functions -q __denv_provider_$p\_check
            set -l out (__denv_provider_$p\_check 2>&1)
            for line in $out
                if string match -q "*✘*" -- $line
                    echo "[$p] $line"
                    set issues (math $issues + 1)
                end
            end
        end
    end

    # 检查软链完整性
    if test -L CLAUDE.md
        set -l target (readlink CLAUDE.md 2>/dev/null)
        if not test -e CLAUDE.md
            echo "✘ CLAUDE.md 断裂软链 -> $target"
            set issues (math $issues + 1)
            if test "$fix" = true
                rm -f CLAUDE.md
                if test -f AGENTS.md
                    ln -s AGENTS.md CLAUDE.md
                    echo "  → 已修复 CLAUDE.md -> AGENTS.md"
                    set fixed (math $fixed + 1)
                end
            end
        end
    end
    if test -L .claude/skills
        if not test -e .claude/skills
            echo "✘ .claude/skills 断裂软链"
            set issues (math $issues + 1)
            if test "$fix" = true
                rm -f .claude/skills
                mkdir -p .agents/skills
                ln -s ../.agents/skills .claude/skills
                echo "  → 已修复 .claude/skills"
                set fixed (math $fixed + 1)
            end
        end
    end

    # 检查 .agents/skills/.gitkeep
    if test -d .agents/skills
        set -l count (ls -A .agents/skills 2>/dev/null | count)
        if test $count -eq 0; and not test -f .agents/skills/.gitkeep
            echo "✘ .agents/skills 为空且缺 .gitkeep"
            set issues (math $issues + 1)
            if test "$fix" = true
                touch .agents/skills/.gitkeep
                echo "  → 已创建 .agents/skills/.gitkeep"
                set fixed (math $fixed + 1)
            end
        end
    end

    # 检查 manifest 与 .envrc 一致性
    if test -f .envrc; and not test -f manifest.scm
        if string match -q "*use guix*" -- (cat .envrc 2>/dev/null)
            echo "✘ .envrc 含 use guix 但 manifest.scm 缺失"
            set issues (math $issues + 1)
        end
    end

    echo ""
    if test $issues -eq 0
        echo "✔ 未发现问题"
    else
        echo "发现 $issues 个问题"
        if test "$fix" = true; and test $fixed -gt 0
            echo "已修复 $fixed 个"
        else if test "$fix" = false
            echo "运行 denv doctor --fix 自动修复"
        end
    end
end

function __denv_usage
    echo "用法:"
    echo "  denv init   [FLAGS]    初始化项目结构 + direnv 环境"
    echo "  denv load   [FLAGS]    仅创建 direnv 相关文件（无参回放 .denv）"
    echo "  denv remove [--all] [-f]  删除 denv 管理的文件"
    echo "  denv status             查看当前 denv 状态"
    echo "  denv doctor [--fix]     诊断并可选修复"
    echo ""
    echo "FLAGS (init / load):"
    echo "  -l, --lang <langs>   语言列表，逗号分隔或多次出现"
    echo "                       可用: python, node, rust, java, c, cpp, csharp"
    echo "                       别名: py→python, js/ts→node, rs→rust, jvm/gradle/maven→java,"
    echo "                             cc/c++→cpp, cs/c#/dotnet→csharp"
    echo "  -L, --LLM            启用 LLM 脚手架 (AGENTS.md + .agents/skills + 软链)"
    echo "      --full           配合 -L，使用完整 AGENTS.md 模板"
    echo "      --no-guix        不注入 guix (manifest.scm / use guix)"
    echo "  -f, --force          强制覆盖已存在文件，跳过确认"
    echo "  -h, --help           显示此帮助"
    echo ""
    echo "FLAGS (remove):"
    echo "      --all            连同 AGENTS.md / .agents/skills / .denv 一起删除"
    echo "  -f, --force          跳过确认"
    echo ""
    echo "FLAGS (doctor):"
    echo "      --fix            自动修复可修复项"
    echo ""
    echo "示例:"
    echo "  denv init -l python               # Python 项目"
    echo "  denv init -l python,node -L       # Python + Node + LLM 脚手架"
    echo "  denv init -l rust --no-guix -f    # Rust 项目，无 guix，强制覆盖"
    echo "  denv load -L --full               # 追加 LLM 完整模板"
    echo "  denv load                         # 回放 .denv 记录的配置"
    echo "  denv status                       # 查看状态"
    echo "  denv doctor --fix                 # 诊断并修复"
    echo "  denv remove --all -f              # 彻底清理"
end


# =============================================================================
# 主入口
# =============================================================================

function denv -d "Manage project environments with Guix, direnv and language support"
    # 无参默认走 load（回放 .denv）
    if test (count $argv) -eq 0
        __denv_dispatch_load_with_config
        return $status
    end

    # 子命令分发
    set -l cmd ""
    set -l rest $argv
    switch $rest[1]
        case init load remove status doctor
            set cmd $rest[1]
            set -e rest[1]
        case --help -h help
            __denv_usage
            return 0
        case '-*'
            # 未指定子命令但以 flag 开头，默认 load
            set cmd load
        case '*'
            echo "错误：未知子命令 '$rest[1]'" >&2
            __denv_usage >&2
            return 1
    end

    if test -z "$cmd"
        set cmd load
    end

    switch $cmd
        case status
            # status 不接受多余参数
            for arg in $rest
                switch $arg
                    case --help -h
                        __denv_usage
                        return 0
                    case '*'
                        echo "错误：status 不接受参数 '$arg'" >&2
                        return 1
                end
            end
            __denv_status

        case doctor
            set -l doctor_fix false
            for arg in $rest
                switch $arg
                    case --fix
                        set doctor_fix true
                    case --help -h
                        __denv_usage
                        return 0
                    case '*'
                        echo "错误：未知选项 '$arg'" >&2
                        return 1
                end
            end
            if test "$doctor_fix" = true
                __denv_doctor --fix
            else
                __denv_doctor
            end

        case remove
            __denv_remove $rest

        case init
            __denv_parse_and_run init $rest

        case load
            __denv_parse_and_run load $rest
    end
end

function __denv_dispatch_load_with_config -d "无参 load：尝试回放 .denv"
    if __denv_read_config
        # 回放成功，构造 providers 列表
        set -l providers
        if test "$__denv_restore_guix" = true
            set -a providers guix
        end
        for lang in $__denv_restore_langs
            if test -n "$lang"
                set -a providers $lang
            end
        end
        if test "$__denv_restore_llm" = true
            set -a providers llm
        end
        if test "$__denv_restore_full" = true
            set -g __denv_llm_full true
        end
        if test (count $providers) -eq 0
            # .denv 存在但无 provider，仍保证 guix 默认？按记录为准，不强加
        end
        __denv_load $providers
    else
        # 无 .denv，默认 guix
        __denv_load guix
    end
end

function __denv_parse_and_run -d "解析 init/load 的 flags 并执行"
    set -l mode $argv[1]
    set -e argv[1]
    set -l args $argv

    set -l langs
    set -l enable_llm false
    set -l llm_full false
    set -l no_guix false
    set -l force false

    # 手写 while 解析，处理 -l python / -l=python / --lang python / --lang=python / 逗号分隔
    set -l i 1
    while test $i -le (count $args)
        set -l arg $args[$i]
        set -l next ""
        if test (math $i + 1) -le (count $args)
            set next $args[(math $i + 1)]
        end

        switch $arg
            case '-l'
                if test -z "$next"; or string match -qr "^-" -- $next
                    echo "错误：-l 需要参数" >&2
                    return 1
                end
                for raw in (string split "," -- $next)
                    set -l resolved (__denv_resolve_lang $raw)
                    if test $status -ne 0
                        return 1
                    end
                    if not contains -- $resolved $langs
                        set -a langs $resolved
                    end
                end
                set i (math $i + 2)
                continue

            case '-l=*'
                set -l val (string replace -r '^-l=' '' -- "$arg")
                if test -z "$val"
                    echo "错误：-l 需要参数" >&2
                    return 1
                end
                for raw in (string split "," -- $val)
                    set -l resolved (__denv_resolve_lang $raw)
                    if test $status -ne 0
                        return 1
                    end
                    if not contains -- $resolved $langs
                        set -a langs $resolved
                    end
                end

            case --lang
                if test -z "$next"; or string match -qr "^-" -- $next
                    echo "错误：--lang 需要参数" >&2
                    return 1
                end
                for raw in (string split "," -- $next)
                    set -l resolved (__denv_resolve_lang $raw)
                    if test $status -ne 0
                        return 1
                    end
                    if not contains -- $resolved $langs
                        set -a langs $resolved
                    end
                end
                set i (math $i + 2)
                continue

            case '--lang=*'
                set -l val (string replace -r '^--lang=' '' -- $arg)
                if test -z "$val"
                    echo "错误：--lang 需要参数" >&2
                    return 1
                end
                for raw in (string split "," -- $val)
                    set -l resolved (__denv_resolve_lang $raw)
                    if test $status -ne 0
                        return 1
                    end
                    if not contains -- $resolved $langs
                        set -a langs $resolved
                    end
                end

            case -L --LLM --llm
                set enable_llm true

            case --full
                set llm_full true

            case --no-guix
                set no_guix true

            case -f --force
                set force true

            case --help -h
                __denv_usage
                return 0

            case '-*'
                echo "错误：未知选项 '$arg'" >&2
                __denv_usage >&2
                return 1

            case '*'
                echo "错误：未知参数 '$arg'" >&2
                __denv_usage >&2
                return 1
        end
        set i (math $i + 1)
    end

    # --full 必须配合 -L
    if test "$llm_full" = true; and test "$enable_llm" = false
        echo "错误：--full 需配合 -L/--LLM 使用" >&2
        return 1
    end

    # c 与 cpp 互斥提示（同时指定则保留两者，CMakeLists 会冲突，已存在则跳过）
    if contains c $langs; and contains cpp $langs
        echo "⚠ 同时指定 c 与 cpp，将以先创建的 CMakeLists.txt 为准，另一 provider 跳过" >&2
    end

    # 构造 providers 列表
    set -l providers
    if test "$no_guix" = false
        set -a providers guix
    end
    for lang in $langs
        set -a providers $lang
    end
    if test "$enable_llm" = true
        set -a providers llm
    end

    # 全局标记供 downstream 使用
    if test "$force" = true
        set -g __denv_force true
    else
        set -e __denv_force 2>/dev/null
    end
    if test "$llm_full" = true
        set -g __denv_llm_full true
    else
        set -e __denv_llm_full 2>/dev/null
    end

    # 配置回放：若未显式指定任何 lang/llm/guix 且存在 .denv，合并 .denv 的 langs
    # 仅当本次未指定任何语言且未指定 --no-guix 且未显式 -L 时，认为是增量追加场景，不自动合
    # 简化：本次以显式参数为准，不自动合并历史 .denv（避免意外膨胀）

    if test "$mode" = "init"
        __denv_init $providers
    else
        __denv_load $providers
    end

    # 清理全局标记
    set -e __denv_force 2>/dev/null
    set -e __denv_llm_full 2>/dev/null
    set -e __denv_cfg_llm 2>/dev/null
    set -e __denv_cfg_guix 2>/dev/null
    set -e __denv_cfg_full 2>/dev/null
end
