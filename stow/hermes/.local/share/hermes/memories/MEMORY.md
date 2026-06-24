[Guix-configs] 本系统所有服务、软件以及部分配置文件被声明式的管理在此，需要改相关配置的时候必须在此修改， `guix-configs-workflow` skill 内有操作方法。
§
[hermes 部署拓扑] hermes-agent 通过Guix-configs 内部的 Nix 配置部署:$HERMES_HOME=$HOME/.local/share/hermes(非 ~/.hermes/),Nix flake 在 source/nix/flake.nix,模块在 source/nix/configuration/programs/hermes.nix,$HERMES_HOME/config.yaml 是软链 → Guix-configs/stow/hermes/。
