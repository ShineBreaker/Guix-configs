{ pkgs, ... }:

{
  home.packages = with pkgs.llm-agents; [
    claude-agent-acp
    claude-code

    codex
    codex-acp

    grok
    kimi-code
    omp
    opencode
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
