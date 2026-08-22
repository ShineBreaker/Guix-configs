---
name: qt-qss-adwaita-iteration
description: Use when iterating a Qt QSS stylesheet to match Adwaita.
---

# Qt QSS Adwaita 贴合迭代（rounded.qss 实战）

对 Qt 全局样式表（qt5ct/qt6ct 消费的 `rounded.qss`）做视觉打磨的完整工作流与踩坑。
适用：任何「让 Qt 应用贴合 GTK Adwaita 外观」的 QSS 迭代任务。

## 1. 快速迭代循环（不 rebuild）

```
改 ~/.config/qt6ct/qss/rounded.qss（部署副本是真实文件，可直接写）
→ 重启被测 Qt 应用（QSS 只在启动时加载）
→ grim 截图 → PIL 裁剪放大 → vision_analyze
→ 定稿后复制回 source/files/qt/rounded.qss + blue home
```

- **qt6ct 的 `~/.config/qt6ct/qss/` 是可写真实文件**（历史遗留，非 store 软链），重启应用即生效。
- **qt5ct 侧是 store 只读软链**，`cp` 报只读文件系统是预期行为——迭代只走 qt6ct，定稿统一 `blue home` 恢复两侧。
- **部署副本可能领先仓库源**（上轮改完没回传）：动手前先 diff 仓库源 vs 部署副本，以更新的一方为新基线。
- GUI 循环里每条命令都带 `timeout`——命令卡死会阻塞整个会话（用户明确要求过自动 kill 机制）。

## 2. 测试环境搭建

```bash
# PyQt6 + wtype（wayland 键盘注入）装到临时 profile，不动 home 配置
guix package -p /tmp/qttest-profile -i python-pyqt wtype --no-grafts
# PyQt6 包不带解释器：用系统 python3 + PYTHONPATH 指向临时 profile site-packages
export QT_QPA_PLATFORMTHEME=qt6ct QT_QPA_PLATFORM=xcb DISPLAY=:0 \
       XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-1
PYTHONPATH=<profile>/lib/python3.12/site-packages python3 <测试窗脚本>
```

测试窗要一次覆盖全部样式目标：普通/禁用/checked 按钮、QToolButton、输入四件套（QLineEdit/QComboBox/QSpinBox/QDoubleSpinBox）、复选/单选两态、滑块+进度条、列表+表格、文本域、标签页+分组框、QDialogButtonBox（含 default 按钮）、菜单栏。

窗口管理：
```bash
niri msg windows | grep -B4 'App ID: "xxx"'   # 查 Window ID（每次启动会变）
niri msg action focus-window --id <N>
/tmp/input-profile/bin/wtype -M ctrl -P Tab -m ctrl   # 键盘注入（无需 daemon）
```

## 3. 截图审验要点

- `grim -t png` 后用 PIL 裁剪 + 3~6 倍 LANCZOS 放大再分析；箭头/对勾等小元素全图看不清。
- **vision_analyze 挂载的图是自己看的**（原生视觉）——回答经常为空，直接看图，不要干等文字描述。
- 客观兜底：PIL 像素扫描（找特定颜色像素的分布范围）验证「画没画出来」。
- **pkill -f 会误伤自己**：`pkill -f qttest.py` 能匹配到 Hermes 包裹命令的 bash 行并杀死当前 shell。先 `pgrep -af` 拿 PID 再精确 `kill <pid>`。

## 4. QSS 踩坑（实证）

1. **border 三角必翻车**：在 `::up-arrow` 等子控件上用 transparent border + colored border 画 CSS 三角，Qt 渲染成实心方块。箭头一律走 `image: url(...)` 引用 chevron 线条图。
2. **arrow 子控件必须显式定位**：只写 `image:` + `width/height` 什么都不画；需加 `subcontrol-origin: border; subcontrol-position: top right;`（down 为 bottom right）。
3. **SVG 引用需要 qtsvg 的 libqsvg 插件**：缺失时 `image:` 静默不渲染（无报错）。真实应用是否可用查 closure：`guix gc --references <app-store-path> | grep qtsvg`。零依赖兜底：PIL 画超采样 PNG。
4. **QT_PLUGIN_PATH 覆盖陷阱（最阴）**：把 `QT_PLUGIN_PATH` 只设成 qtsvg 的 plugins 目录会挤掉默认搜索路径 → qt6ct platformtheme 加载失败 → **QSS 整个静默失效退回原生 Fusion 方块脸**。补路径时必须把 qtbase 的 plugins 目录一起拼上。
5. **判断 QSS 是否加载**：看胶囊输入框/圆角按钮在不在。截图突然变 Fusion = 先查环境变量，再怀疑样式表。
6. **选中态用中性灰**：列表/图标选中用 `palette(mid)`（Adwaita 中性灰）；`palette(alternate-base)` 在白底上几乎不可见且偏蓝。蓝色只留给开关/聚焦/进度/default 按钮语义。
7. **Adwaita 输入控件形态**：`base` 底 + 1px `mid` 边框 + 8px 圆角；hover 变 `dark` 边框；focus 变 2px `highlight` 且 padding 补偿防布局跳动。对话框按钮与普通按钮同形（不做药丸形）。

## 5. 日夜双模式验证

```bash
darkman get      # 查当前模式（没有 status 子命令）
darkman toggle   # Noctalia 重写 ~/.config/qt6ct/colors/noctalia.conf
```

调色板切换后已开的应用不会跟着变（启动时读一次），必须重启被测应用再截图。两态各截一轮全控件图，核对 chevron/对勾对比度、选中灰、禁用态。

## 6. 定稿收尾

1. 复制部署副本回仓库源 `source/files/qt/rounded.qss`。
2. 新增图片资源（chevron/check-white 等）进仓库 + `source/config.org` 的 `home-files-service-type` 补部署条目（qt6ct + qt5ct 两份）。
3. `blue home` + md5sum 校验同步。
