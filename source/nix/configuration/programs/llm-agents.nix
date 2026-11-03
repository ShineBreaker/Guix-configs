{ pkgs, ... }:
{
  home.packages =
    (with pkgs.llm-agents; [
      claude-agent-acp
      claude-code
      cursor-agent
      grok

      officecli
      skills
    ])
    ++ (with pkgs; [
      code-cursor-fhs

      devin-cli
      devin-desktop
    ]);
}
