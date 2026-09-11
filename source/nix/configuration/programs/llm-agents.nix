{ pkgs, ... }:

let
  # pi 与 omp 同名同义地读 PI_CODING_AGENT_DIR / PI_CODING_AGENT_SESSION_DIR，
  # 全局只设一套会让两个 CLI 指向同一份 agent 目录（omp 首次启动还会把 pi 的
  # settings.json 改名成 .bak）。这里给每个 CLI 包一层 wrapper 注入各自独立的
  # 配置与会话目录，并先清掉可能从环境继承来的对方变量。
  mkAgent = name: pkg: pkgs.writeShellScriptBin name ''
    unset PI_CONFIG_DIR PI_CODING_AGENT_DIR PI_CODING_AGENT_SESSION_DIR
    export PI_CONFIG_DIR=".config/${name}"
    export PI_CODING_AGENT_DIR="$HOME/.config/${name}"
    export PI_CODING_AGENT_SESSION_DIR="''${XDG_DATA_HOME:-$HOME/.local/share}/${name}/sessions"
    exec ${pkg}/bin/${name} "$@"
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
      opencode2
      skills
    ])
    ++ (with pkgs; [
      devin-cli
      devin-desktop
    ])
    ++ [
      (mkAgent "omp" pkgs.llm-agents.omp)
      (mkAgent "pi" pkgs.llm-agents.pi)
    ];
}
