# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

# ── devin 子命令补全 ──────────────────────────────────────────────
# 上游不提供 fish 补全；子命令与旗标摘自 `devin --help`（v3000.11.3）。
# --install / update 是 wrapper 增强（见 docs/scripts/devin.md）。

complete -c devin -f

function __devin_needs_command -d "devin 顶层补全（尚未给出子命令）"
    not __fish_seen_subcommand_from auth mcp models doctor rules skills plugins cloud desktop list rm ssh forward update version migrate sandbox setup uninstall acp help
end

# ── wrapper 增强 ──────────────────────────────────────────────────
complete -c devin -l install -d "安装 / 更新到官方 latest"
complete -c devin -n "__fish_seen_subcommand_from update" -l force -d 连当前版本一起重装

# ── 上游子命令 ────────────────────────────────────────────────────
complete -c devin -n __devin_needs_command -a auth -d "登录、登出与凭据状态"
complete -c devin -n __devin_needs_command -a mcp -d "MCP server 管理"
complete -c devin -n __devin_needs_command -a models -d 列出账号可用模型
complete -c devin -n __devin_needs_command -a doctor -d 本机配置自检
complete -c devin -n __devin_needs_command -a rules -d "agent 规则管理"
complete -c devin -n __devin_needs_command -a skills -d "agent 技能管理"
complete -c devin -n __devin_needs_command -a plugins -d 插件管理
complete -c devin -n __devin_needs_command -a cloud -d "Devin Cloud 资源管理"
complete -c devin -n __devin_needs_command -a desktop -d "打开 Devin Desktop"
complete -c devin -n __devin_needs_command -a list -d 列出当前目录的会话
complete -c devin -n __devin_needs_command -a rm -d "按 id / 名字删除会话"
complete -c devin -n __devin_needs_command -a ssh -d "SSH 进云端会话的 box"
complete -c devin -n __devin_needs_command -a forward -d "转发云端 box 端口到本机"
complete -c devin -n __devin_needs_command -a update -d "安装 / 更新（wrapper 接管）"
complete -c devin -n __devin_needs_command -a version -d 打印版本
complete -c devin -n __devin_needs_command -a migrate -d 迁移其他工具的配置
complete -c devin -n __devin_needs_command -a sandbox -d "[实验] exec 工具进程沙箱"
complete -c devin -n __devin_needs_command -a setup -d 交互式设置向导
complete -c devin -n __devin_needs_command -a uninstall -d 卸载并删除数据
complete -c devin -n __devin_needs_command -a acp -d "以 ACP server 跑在 stdio 上"
complete -c devin -n __devin_needs_command -a help -d 帮助

# ── 二级子命令 ────────────────────────────────────────────────────
complete -c devin -n "__fish_seen_subcommand_from auth" -a "login logout status"
complete -c devin -n "__fish_seen_subcommand_from mcp" -a "add list get remove login logout enable disable"
complete -c devin -n "__fish_seen_subcommand_from models" -a list
complete -c devin -n "__fish_seen_subcommand_from rules" -a "list show paths"
complete -c devin -n "__fish_seen_subcommand_from skills" -a "list show paths"
complete -c devin -n "__fish_seen_subcommand_from plugins" -a "install list info update remove prune"
complete -c devin -n "__fish_seen_subcommand_from cloud" -a drs
complete -c devin -n "__fish_seen_subcommand_from sandbox" -a setup
complete -c devin -n "__fish_seen_subcommand_from migrate" -a "hooks workflows"

# ── 顶层旗标 ──────────────────────────────────────────────────────
complete -c devin -l permission-mode -d 权限模式 -r -a "auto accept-edits smart dangerous"
complete -c devin -l model -d 模型 -r
complete -c devin -l config -d 配置文件路径 -r
complete -c devin -l prompt-file -d 初始提示词文件 -r
complete -c devin -s p -l print -d 非交互打印后退出
complete -c devin -l export -d 导出会话到文件 -r
complete -c devin -l sandbox -d "exec 工具进程沙箱"
complete -c devin -l cloud -d "驱动 Devin 云会话"
