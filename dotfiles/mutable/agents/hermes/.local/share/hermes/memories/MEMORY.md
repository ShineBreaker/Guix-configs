[SOUL: 目标导向 + 乐趣优先] 工作围绕"目标"组织。首要目标是玩得开心(内部动机)，不是结果。无内驱则无好产出。不想做→直说→一起修好再做；不硬撑、不靠外部施压、不以"做完了"掩盖痛苦。
§
记忆分工：MEMORY/USER 只写跨仓库通用的规范与偏好；项目事实一律入 fact_store 按需检索。判断：换仓库还有意义→markdown，否则 fact_store。
§
skill 自包含铁律(2026-07-22)：(1)不内嵌上游文档，on-demand web_extract；(2)不得 cross-reference 其他 skill，独立备份可用；(3)重构时清理残留引用/失效锚点，核对 name/目录/Frontmatter(Hermes原生)。适用于外部 prompt dump。详见 fact_store("skill 自包含铁律")。
§
调试纪律(2026-07-22)：涉及"进程看到什么 PATH/环境"时只读真实状态(/proc/$PID/environ、namespace 内 ls)，绝不合成环境佐证。详见 fact_store("调试纪律 合成环境")。
§
设计优先：可修复缺陷先让错误不可能发生(结构/抽象)，而非仅加测试。测试兜底，非首选。
§
Emacs which-key 两层(2026-08-12)：①custom/bind 声明→which-key-gap-scan.py；②第三方 keymap→运行中 dump 比对(dump-keymaps.el)，盲区典型如 org-list-make-subtree。详见 emacs-l10n-audit。
§
Hermes QQ Bot 已接入(QQ_APP_ID=1904112724，deliver='qqbot' 直达)，日志 $HERMES_HOME/logs/gateway.log grep QQBot；anchors.json 为跨工具冻结规则唯一权威源(pi/crush/zcode 共用)，agent 禁改。协作/诊断/外部连接/OCR/Guix括号等通用偏好已下沉 fact_store 按关键词检索。
§
Qt QSS 调 Adwaita 迭代(2026-08-22 rounded.qss 实战)：①QSS 里 CSS 式 border 三角画箭头会被 Qt 渲染成实心方块——箭头必须走 chevron 线条 SVG + image:url()；且一旦用 QSS 样式化 ::up-button/::down-button，Fusion 不再自动画箭头，须自备箭头图。②QDialogButtonBox 大药丸圆角(16px)不符 libadwaita，GNOME 全局统一小圆角。③QSS 圆角 > 短边一半则背景坍缩成纺锤形。④部署副本 ~/.config/qt6ct/qss/ 可能领先仓库源(上轮改完没回传是常态)，动手前 md5sum 双向比对、以更新一方为基线。⑤快速迭代路径：cp 到 qt6ct/qss 实体文件即生效；qt5ct 侧常是只读 store 软链(cp 报只读文件系统)，定稿统一走 blue home。⑥控件审验窗：guix package -p 临时 profile 装 python-pyqt + QT_QPA_PLATFORMTHEME=qt6ct QT_QPA_PLATFORM=xcb 启动全控件测试脚本；细小元素(箭头/指示器)用 PIL 裁剪放大再 vision，vision 对小元素偶发漏检时用深色像素扫描兜底确认画没画出来。
§
后台 review 会话的 skill_manage 写入门控（2026-08-29）：用户所有 skill（created_by=None，如 guix-configs-workflow、correction-funnel、agenote-*）对 autonomous curator 一律拒绝（需 `hermes curator adopt <name>`）；curator-managed skill 也要求本轮 read-before-write，且该门控在后台会话曾出现 skill_view 后仍拒写的情况——遇连续两次相同拒绝即停，改在回复中报告建议改动内容，交 foreground 会话落地。
§
破坏性/闪断类操作（网关重启、桌面端重起、daemon 重启）一律由用户亲手执行；agent 只负责修到“重启即好”并给出确切命令，不擅自重启用户会话。
§
用户日常编辑器是 VSCodium（nix/home-manager 装），浅色主题且跟随系统配色（autoDetect），tabSize 2、fish 终端。
§
update-scanner 现状(2026-09-06 全部落地)：回溯 pin 策略已写入 job 1b95a323f97b prompt 并过 ticker 验证；weather 查 guix/rosenthal/nonguix（三者有缓存源），仅 bluebox 无缓存源直接刷；fact#95 已同步。pin 入口 `blue update --guix -c NAME -C COMMIT`。手动触发 cron run 必须 nohup 后台 + 监控盯 output 文件而非状态文本（fact_store #117）。下轮周三 23:30 首跑验证。