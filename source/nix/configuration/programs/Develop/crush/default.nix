{ pkgs, lib, ... }:

{
  programs.crush = {
    enable = true;
    settings = {
      tools = {
        ls = {
          max_depth = 6;
          max_items = 400;
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
          completions = {
            max_depth = 3;
            max_items = 200;
          };
        };
        initialize_as = "AGENTS.md";
        disable_provider_auto_update = false;
      };

      providers = {
        zhipu = {
          id = "Zhipu";
          name = "Zhipu Provider";
          base_url = "https://open.bigmodel.cn/api/coding/paas/v4";
          api_key = "$ZAI_API_KEY";
          models = [ ];
        };
        deepseek = {
          id = "deepseek";
          type = "openai-compat";
          base_url = "https://api.deepseek.com";
          api_key = "$DEEPSEEK_API_KEY";
          models = [
            {
              id = "deepseek-v4-pro";
              name = "DeepSeek-V4-Pro";
              context_window = 1048576;
              default_max_tokens = 32768;
              can_reason = true;
            }
            {
              id = "deepseek-v4-flash";
              name = "DeepSeek-V4-Flash";
              context_window = 1048576;
              default_max_tokens = 32768;
              can_reason = true;
            }
          ];
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
        };
        rust = {
          command = "rust-analyzer";
          filetypes = [ "rs" ];
          root_markers = [ "Cargo.toml" "rust-project.json" ];
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
        };
        html = {
          command = "vscode-html-language-server";
          args = [ "--stdio" ];
          filetypes = [ "html" "htm" ];
          root_markers = [ "package.json" ".git" ];
        };
        css = {
          command = "vscode-css-language-server";
          args = [ "--stdio" ];
          filetypes = [ "css" "scss" "less" ];
          root_markers = [ "package.json" ".git" ];
        };
        json = {
          command = "vscode-json-language-server";
          args = [ "--stdio" ];
          filetypes = [ "json" "jsonc" ];
          root_markers = [ "package.json" ".git" ];
        };
        markdown = {
          command = "vscode-markdown-language-server";
          args = [ "--stdio" ];
          filetypes = [ "md" "markdown" ];
          root_markers = [ ".git" ];
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
        };
        bash = {
          command = "bash-language-server";
          args = [ "start" ];
          filetypes = [ "sh" "bash" "zsh" ];
          root_markers = [ ".git" ];
        };
        nix = {
          disabled = true;
          command = "nil";
          filetypes = [ "nix" ];
          root_markers = [ "flake.nix" "shell.nix" "default.nix" ];
        };
        zig = {
          disabled = true;
          command = "zls";
          filetypes = [ "zig" ];
          root_markers = [ "build.zig" "build.zig.zon" ];
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
          command = lib.getExe' pkgs.mcp-server-sequential-thinking
            "mcp-server-sequential-thinking";
          timeout = 30;
        };
      };
    };
  };

  xdg.configFile = {
    "crush/context/01-language.md".source = ./dotfiles/01-language.md;
    "crush/context/02-style.md".source = ./dotfiles/02-style.md;
    "crush/context/03-tools.md".source = ./dotfiles/03-tools.md;
  };
}
