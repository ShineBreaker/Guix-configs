{ pkgs, ... }:

let
  # omp 与 pi 同名同义地读 PI_CODING_AGENT_DIR / PI_CODING_AGENT_SESSION_DIR，
  # 不能被同一套全局值指向同一份 agent 目录（omp 首次启动还会把 pi 的
  # settings.json 改名成 .bak）。omp 由 nix 提供，这里包一层 wrapper 注入它
  # 自己的配置/会话目录并清掉继承值；pi 走 ~/.local/bin 下的自管理 wrapper
  # （dotfiles/mutable/agents/pi/.local/bin/pi，随 pnpm 自更新）。
  mkOmp =
    pkg:
    pkgs.writeShellScriptBin "omp" ''
      unset PI_CONFIG_DIR PI_CODING_AGENT_DIR PI_CODING_AGENT_SESSION_DIR
      export PI_CONFIG_DIR=".config/omp"
      export PI_CODING_AGENT_DIR="$HOME/.config/omp"
      export PI_CODING_AGENT_SESSION_DIR="''${XDG_DATA_HOME:-$HOME/.local/share}/omp/sessions"
      exec ${pkg}/bin/omp "$@"
    '';
in
{
  home.packages =
    (with pkgs.llm-agents; [
      claude-agent-acp
      claude-code

      codex
      codex-acp

      freebuff
      jcode
      omo-ai
      opencode2
      opencode2-desktop
      skills
    ])
    ++ (with pkgs; [
      devin-cli
      devin-desktop
    ])
    ++ [
      (mkOmp pkgs.llm-agents.omp)
    ];
}
