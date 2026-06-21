{ pkgs, inputs, ... }:

let
  hermes-agent-packages = inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system};
in
{
  home.packages = [
    hermes-agent-packages.full
    hermes-agent-packages.full.hermesDesktop
  ];

  home.sessionVariables = {
    HERMES_HOME = "$XDG_DATA_HOME/hermes";
  };
}
