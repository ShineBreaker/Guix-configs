{ pkgs, inputs, ... }:

let
  system = pkgs.stdenv.hostPlatform.system;

  # ---- 本地补丁 ---------------------------------------------------
  # Upstream hermes-agent@e4ea0a0e 的 nix/desktop.nix 在
  # `electronHeaders = pkgs.fetchurl { url = ".../node-v${electron.version}-headers.tar.gz";
  #                                    sha256 = "sha256-zi/QMwRZ0+..."; }`
  # 处硬编码了一个已经过期的 sha256。
  #
  # Electron 团队在 2026-06-29 重新发布了 v41.9.1 的 headers tarball，
  # 导致 URL 当前实际返回的内容哈希变成
  #   sha256-cce97caf1eb0a1687b69e4543a591332f88a73f1004105fa9ebfccc40c7564f2
  # 与上游 pin 不一致，blue nix 在构建 hermes-desktop-renderer 时因此报错：
  #   error: hash mismatch in fixed-output derivation
  #   '/nix/store/...-node-v41.9.1-headers.tar.gz.drv':
  #     specified: sha256-zi/QMwRZ0+FwE9XTE+DiSIeJXAwxmLKEaBWD5W3pMOI=
  #     got:      sha256-zOl8rx6woWh7aeRUOlkTMviKc/EAQQX6nr/MxAx1ZPI
  #
  # 修复策略：在 user-side 给 pkgs 加一个 overlay，对该特定 URL 的 fetchurl
  # 调用强行改用正确 hash。上游合并修复后即可移除本段。
  #
  # 只精确匹配 v41.9.1 这一个版本：未来 Electron 升级（v42+）时 URL 不再
  # 匹配，overlay 自动失效，回退到上游 hash，避免本地补丁误伤其他版本。
  fixedElectronHeadersHash = "sha256-zOl8rx6woWh7aeRUOlkTMviKc/EAQQX6nr/MxAx1ZPI";
  patchedPkgs = pkgs.appendOverlays [
    (final: prev: {
      fetchurl = args:
        if (args ? url)
           && args.url
              == "https://artifacts.electronjs.org/headers/dist/v41.9.1/node-v41.9.1-headers.tar.gz"
        then prev.fetchurl (args // { sha256 = fixedElectronHeadersHash; })
        else prev.fetchurl args;
    })
  ];

  hermes-agent-packages = inputs.hermes-agent.packages.${system};

  # 用 patchedPkgs 重新实例化 hermes-agent 自带的 desktop.nix。
  # desktop.nix 的 src = ../.; 因此相对路径仍指向 hermes-agent 仓库根。
  fixedHermesDesktop = patchedPkgs.callPackage
    (inputs.hermes-agent + "/nix/desktop.nix")
    {
      hermesNpmLib = patchedPkgs.callPackage
        (inputs.hermes-agent + "/nix/lib.nix")
        {
# npm-lockfile-fix is a transitive input of hermes-agent, not a direct one in this flake.
          npm-lockfile-fix = inputs.hermes-agent.inputs.npm-lockfile-fix.packages.${system}.default;
        };
      hermesAgent = hermes-agent-packages.default;
    };
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
    exec = "${fixedHermesDesktop}/bin/hermes-desktop --ozone-platform=wayland --enable-features=UseOzonePlatform,WaylandWindowDecorations %U";
    icon = "${fixedHermesDesktop}/share/hermes-desktop/dist/apple-touch-icon.png";
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