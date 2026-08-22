# rounded.qss 迭代会话记录（2026-08-22）

四张用户截图的问题定位与修复结果。

## 截图问题 → 修复

1. **qt6ct 图标主题页按钮背景异常**（蓝色碎块戳出）：旧版 qss 的 `QAbstractItemView::item:selected` 用 accent 蓝所致。改中性灰后用 IconMode 复现窗验证，已不复现。
2. **SpinBox 上下按钮方形背景戳出胶囊圆角**（图二/三）：Fusion 默认画的深色方块。修复 = up/down-button 设 `background: transparent` + 圆角跟随轮廓。
3. **SpinBox 箭头渲染**：border 三角 → 实心方块（QSS 不支持）；删掉后 Fusion 又不画箭头；最终 chevron SVG/PNG 图 + `subcontrol-position` 显式定位解决。
4. **对话框按钮药丸圆角过大**（图四）：16px 削到 8px，libadwaita 全局统一小圆角不做药丸。

## 额外调优

- 输入控件从「灰底无边框胶囊」改为 Adwaita 实际形态：`base` 底 + 1px `mid` 边框 + 8px 圆角 + hover/focus 态。
- 列表选中态 `alternate-base` → `palette(mid)`（中性灰）。
- GTK 参照应用选 Thunar/GIMP；pavucontrol 是旧式 GTK3 渲染不能当基准（用户纠正）。

## 环境事实

- qt6ct 部署副本 `~/.config/qt6ct/qss/` 可写；qt5ct 是 store 软链只读。
- 测试 profile：`/tmp/qttest-profile`（python-pyqt + wtype），测试窗脚本 `/tmp/qttest.py`、图标列表复现 `/tmp/iconlist.py`。
- qtsvg 插件路径（本机）：`/gnu/store/ccya3gvspir1d51j1y3r2m0cshjx9m1q-qtsvg-6.9.2/lib/qt6/plugins`——注意拼 QT_PLUGIN_PATH 时要带上 qtbase 的 plugins 目录，否则 QSS 整体失效。
- darkman 无 `status` 子命令，用 `darkman get` / `darkman toggle`。

## 未竟事项（会话中断时）

- 定稿回传仓库 + config.org 补 PNG/SVG 资源部署条目未做。
- 暗色模式下重启应用后仍显示 light 界面的现象待查（疑似进程读到旧 palette 或 Noctalia 写入时机问题）。
