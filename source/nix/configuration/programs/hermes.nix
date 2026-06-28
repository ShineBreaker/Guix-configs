{ pkgs, inputs, ... }:

let
  hermes-agent-packages = inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system};
in
{
  home.packages = [
    hermes-agent-packages.default
  ];

  home.sessionVariables = {
    HERMES_HOME = "$XDG_DATA_HOME/hermes";
  };

  xdg.desktopEntries.hermes = {
    name = "Hermes Agent";
    exec = "${hermes-agent-packages.default.hermesDesktop}/bin/hermes-desktop --ozone-platform=wayland --enable-features=UseOzonePlatform,WaylandWindowDecorations %U";
    icon = "${hermes-agent-packages.default.hermesDesktop}/share/hermes-desktop/dist/apple-touch-icon.png";
    terminal = false;
    type = "Application";
    categories = [
      "Development"
      "Utility"
    ];
    comment = "Hermes Agent — self-improving AI agent by Nous Research";
    mimeType = [ "x-scheme-handler/hermes" ];
  };
}
