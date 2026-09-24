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
Qt QSS 调 Adwaita 迭代(2026-08-22 rounded.qss 实战)：①QSS 里 CSS 式 border 三角画箭头会被 Qt 渲染成实心方块——箭头必须走 chevron 线条 SVG + image:url()；且一旦用 QSS 样式化 ::up-button/::down-button，Fusion 不再自动画箭头，须自备箭头图。②QDialogButtonBox 大药丸圆角(16px)不符 libadwaita，GNOME 全局统一小圆角。③QSS 圆角 > 短边一半则背景坍缩成纺锤形。④部署副本 ~/.config/qt6ct/qss/ 可能领先仓库源(上轮改完没回传是常态)，动手前 md5sum 双向比对、以更新一方为基线。⑤快速迭代路径：cp 到 qt6ct/qss 实体文件即生效；qt5ct 侧常是只读 store 软链(cp 报只读文件系统)，定稿统一走 blue home。⑥控件审验窗：guix package -p 临时 profile 装 python-pyqt + QT_QPA_PLATFORMTHEME=qt6ct QT_QPA_PLATFORM=xcb 启动全控件测试脚本；细小元素(箭头/指示器)用 PIL 裁剪放大再 vision，vision 对小元素偶发漏检时用深色像素扫描兜底确认画没画出来。
§
验证需真机或真实路径，并做独立复核；部署未执行时写“源码已落地、待部署”，不能把源代码当运行态。