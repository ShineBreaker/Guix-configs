记忆分工：MEMORY.md/USER.md 只保留跨仓库稳定规范、用户偏好和跨项目环境约束；项目事实、调试结论、部署拓扑、命令诀窍写 agenote，按需检索。判断标准是换一个仓库是否仍有意义。
§
Skill 资产自包含：不复制上游长文档，按需查权威源；不跨 skill 依赖；重构清理失效引用并核对 Frontmatter。
§
涉及进程 PATH/环境时只读 /proc 与真实 namespace；验证必须落在真实交付物和实际使用路径，不能用替身或源码自校验替代现场。
§
缺陷优先用结构/抽象让错误不可发生；测试是兜底，不以“看起来完成”代替真实验证。
§
Hermes QQ Bot 已接入，QQ_APP_ID=1904112724，deliver=qqbot；provider registry 的 ready/available 不等于 active。
§
Qt QSS 调 Adwaita 迭代（2026-08-22 rounded.qss 实战）：①QSS 里 CSS 式 border 三角画箭头会被 Qt 渲染成实心方块——箭头必须走 chevron 线条 SVG + image:url()；且一旦用 QSS 样式化 ::up-button/::down-button，Fusion 不再自动画箭头，须自备箭头图。②QDialogButtonBox 大药丸圆角(16 px)不符 libadwaita，GNOME 全局统一小圆角。③QSS 圆角 > 短边一半则背景坍缩成纺锤形。④部署副本 ~/.config/qt6ct/qss/ 可能领先仓库源（上轮改完没回传是常态），动手前 md5sum 双向比对、以更新一方为基线。⑤快速迭代路径：cp 到 qt6ct/qss 实体文件即生效；qt5ct 侧常是只读 store 软链（cp 报只读文件系统），定稿统一走 blue home。⑥控件审验窗：guix package -p 临时 profile 装 python-pyqt + QT_QPA_PLATFORMTHEME=qt6ct QT_QPA_PLATFORM=xcb 启动全控件测试脚本；细小元素（箭头/指示器）用 PIL 裁剪放大再 vision，vision 对小元素偶发漏检时用深色像素扫描兜底确认画没画出来。
§
验证需真机或真实路径，并做独立复核；部署未执行时写“源码已落地、待部署”，不能把源代码当运行态。
§
本机缺 CLI 工具（如 zsh）时用 `guix shell <pkg> -- <cmd>` 临时提供再验证，不得因缺工具直接标 UNVERIFIED。zsh 补全可非交互验证：`zsh -f -i` 内 zmodload zsh/zpty，写 `命令 + \t` 后抓候选列表（`_arguments` 值列表必须写 `:消息:(a b c)`，`:{a,b,c}` 会被当 shell 代码执行而静默失效）。
§
Hermes 有写入 hook 拦截 ~/.config/ 与 ~/.local/ 下的写操作（报错提示「禁止直接修改已部署位置，请修改 dotfiles/ 源文件后运行 just home」）；一次性脚本与产出落 ~/Projects/ 或 /tmp，别写 hermes scratch 目录（也在 ~/.local 下，同样被拦）。
§
无头 Wayland 下启动 quickshell 打包产出验证：必须显式 export WAYLAND_DISPLAY（取 $XDG_RUNTIME_DIR/wayland-* 的 basename）+ QT_QPA_PLATFORM=wayland，否则 Qt 回落 xcb 报 failed to create display；截图前轮询 swaymsg -t get_tree 出现 layer_shell/quickshell 再 grim，固定 sleep 会因首跑初始化慢截到黑屏。
§
pgrep -f 自匹配陷阱：terminal 工具下 bash -c 命令行本身含有匹配串，`pgrep -f <pattern>` 恒命中自己，存活检查恒报 ALIVE。查进程必须排除自身（如用 `[q]s` bracket 写法或二次过滤），下存活结论前先看日志与崩溃报告。quickshell 崩溃现场固定在 ~/.cache/quickshell/crashes/<id>/：report.txt 看 Signal 与 C++ 栈，log.qslog.log（二进制混杂，用 python 去控制字符后 grep）看死前最后的 QML 警告。
§
Agent 终端调 noctalia msg 等桌面 IPC 前，须从 `pgrep -x noctalia` 对应 /proc/<pid>/environ 读出 DBUS_SESSION_BUS_ADDRESS + WAYLAND_DISPLAY 并 export；本机会话总线在 /tmp/dbus-*（无 /run/user/<uid>/bus）。CLI 报「noctalia is not running」仅指通道不通，不是守护进程死了。