{ pkgs, ... }:

{
  home.packages = with pkgs.llm-agents; [
    claude-agent-acp
    claude-code

    codex
    codex-acp

    freebuff
    omp
    opencode2
    skills
  ];
}
