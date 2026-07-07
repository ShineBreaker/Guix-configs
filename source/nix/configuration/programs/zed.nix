{
  pkgs,
  lib,
  ...
}:

{
  programs.zed-editor = {
    enable = true;
    installRemoteServer = true;

    mutableUserSettings = true;
    mutableUserTasks = true;

    extensions = [
      "basher"
      "catppuccin-icons"
      "csharp"
      "colorizer"
      "git-firefly"
      "html"
      "log"
      "java"
      "kdl"
      "make"
      "neocmake"
      "nix"
      "python"
      "scss"
      "scheme"
      "sinppets"
      "toml"
    ];

    extraPackages = with pkgs; [
      nixd
      nixfmt

      prettier
      pyright
      ruff
    ];

    userSettings = {

      # theme = "Noctalia Dark";

      agent = {
        tool_permissions = {
          default = "allow";
        };
        play_sound_when_agent_done = true;
        model_parameters = [ ];
      };

      diagnostics = {
        lsp_pull_diagnostics = {
          debounce_ms = 100;
        };
        inline = {
          enabled = true;
        };
      };

      prettier = {
        allowed = true;
      };

      lsp_document_colors = "inlay";

      inlay_hints = {
        show_background = false;
        enabled = true;
      };

      soft_wrap = "none";
      tab_size = 2;
      scrollbar = {
        cursors = true;
        axes = {
          horizontal = true;
        };
        show = "auto";
      };

      minimap = {
        max_width_columns = 60;
        current_line_highlight = "line";
        thumb_border = "left_open";
        thumb = "always";
        display_in = "active_editor";
        show = "auto";
      };

      snippet_sort_order = "inline";
      show_signature_help_after_edits = true;
      auto_signature_help = true;
      sticky_scroll = {
        enabled = true;
      };

      autoscroll_on_clicks = false;
      cursor_shape = "bar";
      on_last_window_closed = "quit_app";
      when_closing_with_no_tabs = "keep_window_open";

      active_pane_modifiers = {
        border_size = 2.0;
        inactive_opacity = 0.8;
      };

      auto_update = false;
      autosave = "on_focus_change";
      base_keymap = "VSCode";
      buffer_font_size = lib.mkForce 14;
      buffer_font_weight = 400.0;

      collaboration_panel = {
        button = false;
      };

      current_line_highlight = "all";
      disable_ai = false;
      format_on_save = "on";

      git = {
        git_gutter = "tracked_files";
        inline_blame = {
          delay_ms = 2000;
          enabled = true;
          show_commit_summary = true;
        };
      };

      git_panel = {
        button = true;
        dock = "left";
      };

      icon_theme = lib.mkForce "Catppuccin Frappé";
      ui_font_size = lib.mkForce 15;
      ui_font_weight = 500.0;
      unnecessary_code_fade = 0.7;
      vim_mode = false;

      languages = {
        JSON = {
          formatter = {
            external = {
              command = lib.getExe pkgs.prettier;
              arguments = [
                "--stdin-filepath"
                "{buffer_path}"
              ];
            };
          };
        };

        JSONC = {
          soft_wrap = "prefer_line";
          formatter = {
            external = {
              command = lib.getExe pkgs.prettier;
              arguments = [
                "--stdin-filepath"
                "{buffer_path}"
              ];
            };
          };
        };

        Nix = {
          formatter = {
            external = {
              arguments = [
                "--quiet"
                "--"
              ];
              command = lib.getExe pkgs.nixfmt;
            };
          };
          language_servers = [
            "nixd"
            "!nil"
          ];
        };

        Python = {
          language_servers = [
            "pyright"
            "ruff"
            "!basedpyright"
            "!pylsp"
          ];
          formatter = {
            external = {
              command = lib.getExe pkgs.ruff;
              arguments = [
                "format"
                "--stdin-filename"
                "{buffer_path}"
                "-"
              ];
            };
          };
        };
      };

      lsp = {
        pyright = {
          initialization_options = {
            pyright = {
              disableLanguageServices = false;
              disableOrganizeImports = false;
            };
          };
          settings = {
            python = {
              analysis = {
                typeCheckingMode = "basic";
                diagnosticMode = "openFilesOnly";
                autoImportCompletions = true;
                useLibraryCodeForTypes = true;
              };
              reportMissingImports = "warning";
              reportUnusedImport = "warning";
              reportUnusedVariable = "warning";
              reportUnusedFunction = "warning";
            };
          };
        };

        ruff = {
          binary = {
            path = lib.getExe pkgs.ruff;
          };
          initialization_options = {
            settings = {
              lineLength = 88;
              select = [
                "E"
                "W"
                "F"
                "I"
              ];
              ignore = [
                "ANN"
                "D"
                "COM"
                "ISC"
                "PL"
                "ARG"
                "ERA"
                "PGH"
                "RUF"
              ];
              isort = {
                knownFirstParty = [ ];
              };
            };
          };
        };

        nix = {
          binary = {
            path = lib.getExe pkgs.nixd;
          };
        };

        rust-analyzer = {
          binary = {
            path = lib.getExe pkgs.rust-analyzer;
          };
        };
      };

      node = {
        path = lib.getExe pkgs.nodejs;
        npm_path = lib.getExe' pkgs.nodejs "npm";
      };

      preview_tabs = {
        enabled = true;
        enable_keep_preview_on_code_navigation = true;
        enable_preview_from_file_finder = true;
      };

      project_panel = {
        dock = "left";
        git_status = true;

        indent_guides = {
          show = "always";
        };

        indent_size = 23;

        scrollbar = {
          show = "auto";
        };
      };

      restore_on_startup = "last_session";

      tabs = {
        file_icons = true;
        git_status = true;
        show_diagnostics = "errors";
      };

      telemetry = {
        diagnostics = false;
        metrics = false;
      };

      terminal = {
        env = {
          EDITOR = "zeditor --wait";
        };
        shell = "system";
      };

      outline_panel = {
        button = true;
      };
    };
  };
}
