{ pkgs, ... }:

{
  home.packages = with pkgs.llm-agents; [
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
}
