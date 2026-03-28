{
  pkgs,
  lib,
  ...
}:

{
  home.packages = [ pkgs.nixd ];

  programs.vscode = {
    enable = true;
    package = pkgs.vscodium;

    profiles.default = {
      enableExtensionUpdateCheck = false;
      enableUpdateCheck = false;
      extensions = with pkgs.vscode-extensions; [
        ms-azuretools.vscode-docker
        ms-vscode-remote.remote-ssh
        ms-python.python
        ms-vscode.cpptools
        ms-toolsai.jupyter
        ms-pyright.pyright
        ms-vscode.cmake-tools
        ms-dotnettools.csharp
        ms-dotnettools.csdevkit
        ms-dotnettools.vscode-dotnet-runtime
        ms-vscode.makefile-tools
        ms-ceintl.vscode-language-pack-zh-hans

        bbenoist.nix
        brettm12345.nixfmt-vscode
        ecmel.vscode-html-css
        gencer.html-slim-scss-css-class-completion
        jnoortheen.nix-ide
        rust-lang.rust-analyzer
        stylelint.vscode-stylelint
        skyapps.fish-vscode
        shopify.ruby-lsp
        tamasfe.even-better-toml
        techtheawesome.rust-yew
        tekumara.typos-vscode
        xaver.clang-format
        yzhang.markdown-all-in-one
        yzhang.dictionary-completion
        zainchen.json
      ];

      userSettings = {
        "C_Cpp.autocompleteAddParentheses" = true;
        "files.autoSave" = "onFocusChange";
        "editor.autoIndentOnPaste" = true;
        "editor.formatOnSave" = true;
        "editor.tabSize" = "2";
        "git.confirmSync" = false;
        "git.enableSmartCommit" = true;
        "locale" = "zh-cn";
        "nix.enableLanguageServer" = true;
        "nix.formatterPath" = lib.getExe pkgs.nixfmt-rfc-style;
        "nix.hiddenLanguageServerErrors" = [
          "textDocument/definition"
        ];
        "nix.serverPath" = "${pkgs.nixd}/bin/nixd";
        "nixfmt.path" = lib.getExe pkgs.nixfmt-rfc-style;
        "terminal.integrated.defaultProfile.linux" = "fish (2)";
        "terminal.integrated.inheritEnv" = false;
        "window.autoDetectColorScheme" = true;
        "workbench.preferredDarkColorTheme" = "Stylix";
        "workbench.iconTheme" = "vs-seti";
      };
    };
  };
}
