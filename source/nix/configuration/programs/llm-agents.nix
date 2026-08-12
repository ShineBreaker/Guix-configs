{ pkgs, ... }:

{
  home.packages = with pkgs.llm-agents; [
    aionui
    officecli

    claude-agent-acp
    claude-code

    codex
    codex-acp

    grok
    kimi-code
    opencode2
    pi
    skills
  ];

  programs.codexDesktopLinux = {
    enable = true;
    computerUseUi.enable = true;
    remoteMobileControl.enable = true;
    linuxFeatures = [
      "appshots"
      "open-target-discovery"
    ];
    remoteControl.enable = true;
  };
}
