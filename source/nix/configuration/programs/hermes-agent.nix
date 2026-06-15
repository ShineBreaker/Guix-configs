# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
# SPDX-License-Identifier: MIT
#
# Hermes Agent — Nous Research 出品的自改进 AI 终端代理
# 官方文档: https://hermes-agent.nousresearch.com/
# Nix flake: github:NousResearch/hermes-agent
#
# 实现位置: 包装官方 flake 的 pkgs.hermes-agent（uv2nix 构建的 Python venv + Node TUI），
#           通过 HERMES_HOME 环境变量把数据/配置/状态/记忆/技能全部收容在
#           $XDG_DATA_HOME/hermes-agent（XDG 规范），避免默认的 ~/.hermes/ dotfile。
#
# 决策说明: Hermes Agent 暂未发布官方 home-manager module（PR #9087 仍在 review），
#           本模块自行封装，关键设计参照 nix/nixosModules.nix 的 HERMES_HOME 模式。
#           一旦官方模块合并，可平滑切换到 `hermes-agent.homeManagerModules.default`。
#
# XDG 路径映射:
#   binary  → ~/.nix-profile/bin/hermes（home.packages 注入 PATH）
#   config  → $XDG_DATA_HOME/hermes-agent/config.yaml
#   secrets → $XDG_DATA_HOME/hermes-agent/.env
#   memory  → $XDG_DATA_HOME/hermes-agent/memories/
#   skills  → $XDG_DATA_HOME/hermes-agent/skills/
#   logs    → $XDG_DATA_HOME/hermes-agent/logs/
#   sessions→ $XDG_DATA_HOME/hermes-agent/sessions/
#
# 注意: hermes-agent 把 config/data/state/logs 全部放在单一 HERMES_HOME 下，
#       这是其内部设计（get_hermes_home() 单点寻址），不做 XDG_CONFIG_HOME / STATE_HOME 细分。
{ config, pkgs, lib, inputs, ... }:

let
  # hermes-agent 是 flake input（uv2nix 包，pkgs.* 不可见），从 inputs 取
  hermes-agent-pkg = inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
{
  home.packages = [ hermes-agent-pkg ];

  home.sessionVariables = {
    # hermes-agent 的 get_hermes_home() 读此 env，fallback 到 ~/.hermes/
    # 用 $XDG_DATA_HOME 让 shell 启动时展开为实际路径
    HERMES_HOME = "$XDG_DATA_HOME/hermes-agent";
  };

  # 提前创建 $HERMES_HOME 顶层目录，避免首次运行时 race；
  # hermes-agent 会按需创建子目录（memories/skills/sessions/logs/...）。
  # 用 config.xdg.dataHome 而非 $XDG_DATA_HOME，nix 阶段即可解析为绝对路径。
  home.activation = {
    createHermesHomeDir =
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        $DRY_RUN_CMD mkdir -p "${config.xdg.dataHome}/hermes-agent"
      '';
  };
}
