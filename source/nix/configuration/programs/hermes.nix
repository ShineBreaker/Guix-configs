{ pkgs, inputs, ... }:

let
  hermes-agent-packages = inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system};
in
{
  home.packages = [
    ## Hermes Agent CLI / TUI / Web / Gateway — `full` 变体含所有 providers、messaging
    ## platform libraries (discord.py / python-telegram-bot / slack-sdk)、voice、
    ## tts-premium、honcho 等可选集成，per docs/getting-started/nix-setup
    hermes-agent-packages.full

    ## Hermes Desktop（独立 Electron 应用，复用同一份 config 与 sessions）
    hermes-agent-packages.desktop
  ];

  home.sessionVariables = {
    ## 安装目录遵循 XDG：数据落到 ~/.local/share/hermes 而非 ~/.hermes
    ## —— 与仓库 information.scm %data-dirs 一致，并由其 bind-mount 持久化
    HERMES_HOME = "$XDG_DATA_HOME/hermes";
  };

  # 让 `hermes-desktop` 命令的 desktop entry 可被 XDG 应用发现器找到
  xdg.desktopEntries.hermes = {
    name = "Hermes Agent";
    exec = "hermes-desktop";
    terminal = false;
    type = "Application";
    categories = [
      "Development"
      "Utility"
    ];
    comment = "Hermes Agent — self-improving AI agent by Nous Research";
  };
}
