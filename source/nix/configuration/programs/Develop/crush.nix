{ pkgs, lib, ... }:

{
  home.packages = with pkgs; [
    context7-mcp
    mcp-server-memory
    mcp-server-sequential-thinking
  ];

  programs.crush = {
    enable = true;
    settings = {
      "$schema" = "https://charm.land/crush.json";

      tools = {
        ls = {
          max_depth = 6;
          max_items = 400;
        };
        grep = {
          timeout = 15;
        };
      };

      permissions = {
        allowed_tools = [
          "agent"
          "edit"
          "glob"
          "grep"
          "job_kill"
          "job_output"
          "ls"
          "lsp_diagnostics"
          "lsp_references"
          "mcp_context7"
          "sequential"
          "sourcegraph"
          "todos"
          "view"
          "write"
          "multiedit"
          "fetch"
        ];
      };

      options = {
        context_paths = [
          "~/.config/crush/context/01-language.md"
          "~/.config/crush/context/02-style.md"
          "~/.config/crush/context/03-tools.md"
        ];
        tui = {
          compact_mode = true;
          diff_mode = "split";
          transparent = true;
          completions = {
            max_depth = 3;
            max_items = 200;
          };
        };
        initialize_as = "AGENTS.md";
        auto_lsp = true;
        progress = true;
        disable_notifications = false;
        disable_provider_auto_update = false;
      };

      providers = {
        zhipu = {
          id = "Zhipu";
          name = "Zhipu Provider";
          base_url = "https://open.bigmodel.cn/api/coding/paas/v4";
          api_key = "$ZAI_API_KEY";
        };
      };

      models = {
        large = {
          provider = "zhipu";
          model = "glm-5.1";
          think = true;
          max_tokens = 65536;
        };
        small = {
          provider = "zhipu";
          model = "glm-5";
          think = true;
          max_tokens = 65536;
        };
        quick = {
          provider = "zhipu";
          model = "glm-4.7-flash";
          max_tokens = 32768;
        };
      };

      lsp = {
        c_cpp = {
          command = "ccls";
          filetypes = [ "c" "cc" "cpp" "cxx" "h" "hpp" ];
          root_markers = [
            ".ccls"
            "compile_commands.json"
            "compile_flags.txt"
            "CMakeLists.txt"
            "meson.build"
            "Makefile"
          ];
          timeout = 30;
        };
        python = {
          command = "pylsp";
          filetypes = [ "py" ];
          root_markers = [
            "pyproject.toml"
            "setup.py"
            "setup.cfg"
            "requirements.txt"
            "uv.lock"
            ".venv"
          ];
          options = {
            pylsp = {
              plugins = {
                black.enabled = true;
                pylsp_mypy = {
                  enabled = true;
                  live_mode = false;
                };
                rope.enabled = true;
                pycodestyle.enabled = false;
                mccabe.enabled = false;
                pyflakes.enabled = false;
              };
            };
          };
          timeout = 30;
        };
        rust = {
          command = "rust-analyzer";
          filetypes = [ "rs" ];
          root_markers = [ "Cargo.toml" "rust-project.json" ];
          timeout = 30;
        };
        java = {
          command = "jdtls";
          filetypes = [ "java" ];
          root_markers = [
            "pom.xml"
            "build.gradle"
            "build.gradle.kts"
            "settings.gradle"
            "settings.gradle.kts"
          ];
          timeout = 60;
        };
        typescript = {
          command = "typescript-language-server";
          args = [ "--stdio" ];
          filetypes = [ "js" "jsx" "ts" "tsx" ];
          root_markers = [
            "package.json"
            "tsconfig.json"
            "jsconfig.json"
            "deno.json"
            "deno.jsonc"
            "bun.lock"
            "pnpm-lock.yaml"
            "yarn.lock"
          ];
          timeout = 60;
        };
        html = {
          command = "vscode-html-language-server";
          args = [ "--stdio" ];
          filetypes = [ "html" "htm" ];
          root_markers = [ "package.json" ".git" ];
          timeout = 60;
        };
        css = {
          command = "vscode-css-language-server";
          args = [ "--stdio" ];
          filetypes = [ "css" "scss" "less" ];
          root_markers = [ "package.json" ".git" ];
          timeout = 60;
        };
        json = {
          command = "vscode-json-language-server";
          args = [ "--stdio" ];
          filetypes = [ "json" "jsonc" ];
          root_markers = [ "package.json" ".git" ];
          timeout = 60;
        };
        markdown = {
          command = "vscode-markdown-language-server";
          args = [ "--stdio" ];
          filetypes = [ "md" "markdown" ];
          root_markers = [ ".git" ];
          timeout = 60;
        };
        eslint = {
          command = "vscode-eslint-language-server";
          args = [ "--stdio" ];
          filetypes = [ "js" "jsx" "ts" "tsx" ];
          root_markers = [
            "package.json"
            ".eslintrc"
            ".eslintrc.json"
            ".eslintrc.js"
            "eslint.config.js"
            "eslint.config.mjs"
            "eslint.config.cjs"
            "eslint.config.ts"
          ];
          timeout = 60;
        };
        bash = {
          command = "bash-language-server";
          args = [ "start" ];
          filetypes = [ "sh" "bash" "zsh" ];
          root_markers = [ ".git" ];
          timeout = 60;
        };
        nix = {
          disabled = true;
          command = "nil";
          filetypes = [ "nix" ];
          root_markers = [ "flake.nix" "shell.nix" "default.nix" ];
          timeout = 30;
        };
        zig = {
          disabled = true;
          command = "zls";
          filetypes = [ "zig" ];
          root_markers = [ "build.zig" "build.zig.zon" ];
          timeout = 30;
        };
        kotlin = {
          disabled = true;
          command = "kotlin-language-server";
          filetypes = [ "kt" "kts" ];
          root_markers = [
            "build.gradle"
            "build.gradle.kts"
            "settings.gradle"
            "settings.gradle.kts"
          ];
          timeout = 60;
        };
      };

      mcp = {
        context7 = {
          type = "stdio";
          command = lib.getExe pkgs.context7-mcp;
          timeout = 45;
        };
        memory = {
          type = "stdio";
          command = lib.getExe pkgs.mcp-server-memory;
          timeout = 30;
        };
        sequential_thinking = {
          type = "stdio";
          command = lib.getExe pkgs.mcp-server-sequential-thinking;
          timeout = 30;
        };
      };
    };
  };

  # Context files for Crush
  xdg.configFile = {
    "crush/context/01-language.md".text = ''
      <critical>
      **以下要求不可忽略！**

      - 无论用户使用什么语言提问，默认使用中文思考、规划和回答。
      - 除非用户明确要求输出英文原文、英文代码注释或英文文档，否则优先使用中文。
      - 如果需要展示命令、标识符、错误消息或协议字段，保持其原文，不要翻译代码字面量。

      </critical>
    '';
    "crush/context/02-style.md".text = ''
      <critical>
      **工作原则**

      - 先思考，后行动。写代码前先阅读现有文件。
      - 输出从简，推理从详。
      - 能改则不重写。
      - 文件已读过就别再读，除非它可能有变化。
      - 声明完成前先测试。
      - 去掉谄媚开场和废话结尾。
      - 方案简洁直接。
      - 用户指令永远优先。

      </critical>
    '';
    "crush/context/03-tools.md".text = ''
      <critical>
      你不是单独在这个仓库里工作。
      可能还有其他 agent 或人工编辑者同时修改文件。
      </critical>

      你的行为约束如下：

      - 把当前任务视为 **共享工作区协作任务** ，不是单人重构任务。
      - 开始前必须读取 `git status --short`，并向用户说明当前工作区是否干净。
      - 只允许对当前任务直接相关的文件做 **最小补丁**。
      - 如果某个文件已经被修改，**必须** 先读取最新内容，再决定如何合并你的改动。
      - 如果发现你的改动消失，先做 **差异定位** 和 **最小恢复** ，不要回滚整个仓库。
      - 在完成前必须再次检查 `git status --short`，并确认提交内容仅包含本次任务。
      - commit 的相关规范必须遵守 `gitmassage` 中的描述。
      - **禁止** 通过整文件重写来实现小功能。
      - **禁止** 清理、格式化、重排与你任务无关的内容。
      - **禁止** 提交无关文件。

      如果出现以下情况，必须停止并汇报，而不是继续硬改：

      - 同一文件中存在明显的并行改动冲突
      - 你无法判断某段改动是否来自用户还是其他 agent
      - 你需要使用破坏性 git 命令才能继续

      同时，你需要注意以下问题：

      1. 项目重度依赖各种虚拟环境以及项目环境的创建，所以请你务必要：

      - 用 **pnpm** 来替代 **npm**
      - 用 **uv** 来替代 **pip**
      - 在其他情况下：善于利用 `guix shell` ，通过撰写 `manifest.scm` 来完成环境的配置
    '';
  };
}
