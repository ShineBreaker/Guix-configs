# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

# 终端会话选择器 — 在 foot 窗口启动时弹出一个合并 fzf 列表：
# 所有 tmux 会话 + 所有 herdr 会话 + Shell，一屏选完。
#
# 设计：tmux 与 herdr 完全对称，各自有：
#   ├── 默认会话（tmux=main / herdr=default）
#   └── 其他会话（命名 session，带运行状态）
#       └── 新建会话（fish 侧 prompt 输入语义名）
#
# main / default 不再被特殊跳过——它们就是列表里的普通项。
#
# 容错：mux 命令（tmux/herdr）执行后若异常退出（退出码 ≠ 0，如版本/协议
# 不兼容、session 损坏、socket 异常），不闪退到裸 shell，而是回到选择
# 界面让用户重选。正常退出（退出码 0，含用户主动退出 TUI）则结束选择。

# ===== tmux 辅助函数（须先定义后调用）=====
# 统一 tmux 的 attach/create 模式：detach 创建（若需）→ set 侧栏选项 →
# follow 建侧栏 → 纯 attach-session（不串联 \;，避免命令链竞态闪退）。
# 侧栏 opt-in：tmux 默认纯净（@sidebar_visible 全局 = 0），用户入口在此
# 用 session 级覆盖为 1。agent 程序化创建的 session 不经此入口 → 纯净。
#
# 不用 exec：attach 失败时（如 session 被并发杀掉）退出码 ≠ 0，由外层
# 循环捕获并回选择界面。attach 正常 detach 退出码 0 → 结束。
function __selector_tmux_attach_or_create
    set -l ses_name $argv[1]
    set -l win_name $argv[2]
    set -l cwd $argv[3]

    # 名字冲突预检（tmux new-session 重复名退出码不可靠，用 has-session 预检）
    if tmux has-session -t "$ses_name" 2>/dev/null
        __selector_tmux_attach "$ses_name"
        return $status
    end

    # detached 新建（启动 server + 创建 session，不 attach，无前台竞态）
    tmux new-session -d -s "$ses_name" -n "$win_name" -c "$cwd"
    __selector_tmux_setup_sidebar "$ses_name"
    tmux attach-session -t "$ses_name"
end

# attach 已有 tmux session（设侧栏选项 + follow + 纯 attach）
function __selector_tmux_attach
    set -l ses_name $argv[1]
    __selector_tmux_setup_sidebar "$ses_name"
    tmux attach-session -t "$ses_name"
end

# 在 server 端设置侧栏（不与 attach 串联，避免命令链竞态）
function __selector_tmux_setup_sidebar
    set -l ses_name $argv[1]
    tmux set-option -t "$ses_name" @sidebar_visible 1
    ~/.config/tmux/scripts/sidebar-toggle follow >/dev/null 2>&1
end

# 从用户输入构造一个合法的会话名（清洗非法字符、限长、纯数字加前缀）
function __selector_make_session_name
    set -l raw $argv[1]
    set -l cwd $argv[2]
    if test -z "$raw"
        # 空 → fallback 到 cwd basename
        set raw (path basename "$cwd")
    end
    set -l name (string replace -ra '[^a-zA-Z0-9_-]' '_' -- "$raw" | string sub -l 20)
    if test -z "$name"
        set name default
    end
    # 纯数字名加前缀（tmux 拒绝纯数字 session 名）
    # 注意：fish 里 $ 在正则末尾需双引号 + \$ 转义（单引号会报错）
    if string match -qr "^[0-9]+\$" -- "$name"
        set name "s_$name"
    end
    echo "$name"
end

# 执行某个 mux 动作；返回该命令的退出码（0=正常，≠0=异常）
function __selector_run_mux
    set -l mux $argv[1]
    set -l kind $argv[2]
    set -l window_name $argv[3]
    set -l cwd $argv[4]

    switch "$kind"
        case new
            # 新建命名会话：prompt 输入语义名（解决"改名模型烂"——
            # 不再掉到 term_<pid>，用户可起 work/dev/debug 等语义名）。
            read -l -P "新 $mux 会话名 (回车=用 cwd): " raw_name
            set -l ses_name (__selector_make_session_name "$raw_name" "$cwd")

            if test "$mux" = tmux
                __selector_tmux_attach_or_create "$ses_name" "$window_name" "$cwd"
            else
                herdr --session "$ses_name"
            end

        case default
            # 进入默认/共享会话：tmux=main, herdr=default
            if test "$mux" = tmux
                __selector_tmux_attach_or_create main "$window_name" "$cwd"
            else
                herdr
            end

        case '*'
            # attach 已有命名会话
            if test "$mux" = tmux
                __selector_tmux_attach "$kind"
            else
                herdr --session "$kind"
            end
    end
    return $status
end

if status is-interactive
    # 仅 foot 终端弹选择器；已有 tmux/herdr/容器 pane 跳过
    if test "$TERM" = foot; and not set -q TMUX; and not test "$HERDR_ENV" = 1; and not set -q CONTAINER_ID
        set -l cwd (pwd)
        set -l window_name (__selector_make_session_name "" "$cwd")

        set -l selector ~/.config/tmux/scripts/session-selector

        # selector 未部署 → fallback：直接进 tmux main（带侧栏），无菜单
        if not test -x "$selector"
            __selector_tmux_attach_or_create main "$window_name" "$cwd"
            return
        end

        # ===== 主循环：选择 → 执行；异常退出回选择界面，正常退出结束 =====
        while true
            # 单层选择：弹合并列表
            set -l key ("$selector")

            # 空输出（ESC/取消/异常）→ 留普通 shell
            if test -z "$key"
                return
            end

            # key 格式：<mux>|<kind>  或  shell  或  __header__（误选标题行）
            if test "$key" = shell
                return
            end

            # 误选了分组标题行 → 回循环重弹（等同取消本次选择）
            if test "$key" = __header__
                continue
            end

            # 解析 mux|kind
            set -l parts (string split '|' -- "$key")
            set -l mux $parts[1]
            set -l kind $parts[2]

            __selector_run_mux "$mux" "$kind" "$window_name" "$cwd"

            # 退出码 0（含用户主动退出 TUI）→ 结束选择
            # 退出码 ≠ 0（报错/异常）→ 回循环重弹选择界面
            if test $status -eq 0
                return
            end

            # 异常：提示后回循环（用户能看到错误信息，再选一次）
            echo
            echo ">>> $mux 启动失败（退出码 $status），请重选"
            echo
        end
    end
end
