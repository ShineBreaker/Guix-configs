{ pkgs, ... }:
{
  home.packages =
    (with pkgs.llm-agents; [
      claude-agent-acp
      claude-code

      freebuff
      jcode
      omo-ai
      opencode2-desktop
      skills
    ])
    ++ (with pkgs; [
      devin-cli
      devin-desktop
    ]);
}
