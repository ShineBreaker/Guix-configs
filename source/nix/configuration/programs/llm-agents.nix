{ pkgs, ... }:
{
  home.packages =
    (with pkgs.llm-agents; [
      claude-agent-acp
      claude-code

      officecli
      skills
    ])
    ++ (with pkgs; [
      devin-cli
      devin-desktop
    ]);
}
