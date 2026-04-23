{ pkgs, ... }:

{
  imports = [ ../programs/00-main.nix ];

  home.packages = with pkgs; [
    ## 娱乐
    bottles

    ## 编程工具
    beekeeper-studio
    bun
    pnpm
    postman

    ## Android
    android-tools
    qtscrcpy
    scrcpy

    ## 工具
    broot
    gamescope
    pmbootstrap
    sunshine

    ## 文本编辑
    apostrophe
    obsidian


    ## AI 工具
    claude-code
    codex
    crush
    llmfit
    ollama-vulkan
    opencode
    #tabby
    #tabby-agent

    ## LSP
    bash-language-server
    kotlin-language-server
    nil
    package-version-server
    typescript-language-server
    vscode-langservers-extracted

    ## 版本管理
    jjui
    lazygit
    lazyjj
  ];
}
