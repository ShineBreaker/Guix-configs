{ pkgs, ... }:

{
  home.packages = with pkgs.llm-agents; [
    claude-agent-acp
    claude-code
    claude-desktop

    codex
    codex-acp

    kimi-code

    omp

    opencode2
  ];
}
