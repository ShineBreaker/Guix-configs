# 会话共享：tmux 中介 + RUN_COMMAND 交接

## 能力边界（先告诉用户，再写代码）

- Termux 主程序每个 session 是一个 fork 出的 pty 子进程，`TerminalSession` 对象只活在主进程内存里；pty 属于创建它的进程，fd 不能跨进程迁移。即使插件与主程序同 UID（sharedUserId）也拿不到。
- Termux app 没有「列出/接管已有会话」的 IPC：`TermuxService.onBind` 虽返回 Binder 但无 AIDL；跨 app 的公开 API 只有 RUN_COMMAND / ACTION_SERVICE_EXECUTE，只能新建或切换它自己注册的 session。
- 因此「把主程序已开的普通 shell 搬到悬浮窗显示」不可能；能做的是「两边都 attach 同一个 tmux 会话」。

## tmux 作为共享层

- 两侧都执行 `tmux new-session -A -s <name>`：已存在则 attach，不存在则创建并 attach。单命令、无 `\;` 命令链（attach 后接命令链会竞态闪退）。
- 列会话：`tmux list-sessions -F "#{session_name}|#{session_windows}|#{session_attached}"`，输出形如 `work|1|0`；无 server 时错误写 stderr（`error connecting to ...`），把 stderr 合入 stdout 读取时按「是否为三段 | 分隔」过滤即可，不会误判。
- 在插件进程里跑 tmux（而非终端 session 里）时，用 `ProcessBuilder` + `new TermuxShellEnvironment().getEnvironment(context, false)` 填环境（PATH/HOME/PREFIX/TMPDIR），否则 tmux 找不到 socket 目录。列会话必须在后台线程。
- tmux 二进制路径：`TermuxConstants.TERMUX_BIN_PREFIX_DIR_PATH + "/tmux"`；存在性检查就是 `new File(path).exists()`，不存在时 UI 给 `pkg install tmux` 提示并回退普通 shell。
- 会话名不能含 `.` 和 `:`（tmux 的 target 分隔符），用户输入先 sanitize 再交给 tmux。

## 把会话交给主程序：RUN_COMMAND

```java
Intent intent = new Intent();
intent.setClassName(TermuxConstants.TERMUX_PACKAGE_NAME,
        TermuxConstants.TERMUX_APP.RUN_COMMAND_SERVICE_NAME);        // "com.termux.app.RunCommandService"
intent.setAction(RUN_COMMAND_SERVICE.ACTION_RUN_COMMAND);
intent.putExtra(RUN_COMMAND_SERVICE.EXTRA_COMMAND_PATH, tmuxPath);
intent.putExtra(RUN_COMMAND_SERVICE.EXTRA_ARGUMENTS, new String[]{"new-session", "-A", "-s", name});
intent.putExtra(RUN_COMMAND_SERVICE.EXTRA_WORKDIR, TermuxConstants.TERMUX_HOME_DIR_PATH);
intent.putExtra(RUN_COMMAND_SERVICE.EXTRA_RUNNER, ExecutionCommand.Runner.TERMINAL_SESSION.getName());
intent.putExtra(RUN_COMMAND_SERVICE.EXTRA_SHELL_NAME, "tmux:" + name);
intent.putExtra(RUN_COMMAND_SERVICE.EXTRA_SHELL_CREATE_MODE,
        ExecutionCommand.ShellCreateMode.NO_SHELL_WITH_NAME.getMode());          // 复用同名 session，不堆窗口
intent.putExtra(RUN_COMMAND_SERVICE.EXTRA_SESSION_ACTION,
        String.valueOf(TermuxConstants.TERMUX_APP.TERMUX_SERVICE
                .VALUE_EXTRA_SESSION_ACTION_SWITCH_TO_NEW_SESSION_AND_OPEN_ACTIVITY));
startService(intent);   // 包 try/catch：Termux 未装或策略不允许时会抛
```

要点：

- 常量位置易错：`RUN_COMMAND_SERVICE_NAME` 在 `TERMUX_APP` 层（不在 `RUN_COMMAND_SERVICE` 内）；`VALUE_EXTRA_SESSION_ACTION_*` 在 `TERMUX_APP.TERMUX_SERVICE` 里；`RUN_COMMAND_SERVICE` 类里只有 `EXTRA_*`。写错就是编译错误。
- **`session_action` 要传 String**：`RunCommandService` 用 `intent.getStringExtra` 读它，传 int 会被当成 null。
- **需要 `allow-external-apps=true`**（`TermuxPluginUtils.checkIfAllowExternalAppsPolicyIsViolated` 对同 UID 应用不豁免）。插件侧先 `TermuxAppSharedProperties.init(ctx).shouldAllowExternalApps()` 预检并 Toast 提示——比让 Termux 弹错误通知好。
- 插件 manifest 加 `<uses-permission android:name="com.termux.permission.RUN_COMMAND" />`（同 UID 自动授予）。
- `EXTRA_COMMAND_PATH` 必须指向已存在的可执行文件：`setupShellCommandArguments` 会读文件头部判断 ELF/shebang，tmux 是 ELF 直接执行，不会多套一层 shell。

## 插件内切换会话的顺序坑

1. 先建新 TermuxSession 并 `attachSession` 到 TerminalView，**再** kill 旧 session。
2. `TerminalSessionClient.onSessionFinished` 必须判断「finished 的是不是当前 session」才停服务——否则切换时旧 session 结束会连带关掉整个悬浮窗服务：

```java
public void onSessionFinished(TerminalSession finishedSession) {
    if (finishedSession != mService.getCurrentSession()) return;
    mService.requestStopService();
}
```

3. 悬浮窗从 Service 弹会话列表 Dialog：`getWindow().setType(TYPE_APPLICATION_OVERLAY)`（API<26 用 `TYPE_PHONE`）+ 透明背景 + 显式 `setLayout(width, WRAP_CONTENT)`；列表高度取 `min(内容高, 屏幕高 * 0.4)` 后手动设给 ScrollView（ScrollView 没有 maxHeight 属性）。
