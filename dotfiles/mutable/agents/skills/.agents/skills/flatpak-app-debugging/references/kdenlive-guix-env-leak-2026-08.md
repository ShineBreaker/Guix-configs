# 案例：Guix 宿主 QML 环境变量泄漏致 flatpak kdenlive 启动即崩（2026-08-01）

## 环境
- 宿主：Guix（`~/.guix-home/setup-environment` 设置 Qt 环境变量）
- 应用：org.kde.kdenlive 26.04.3（flathub, user 安装）
- 运行时：org.kde.Platform/x86_64/6.10
- flatpak 1.16.6（Guix 打包，`/run/current-system/profile/bin/flatpak`）

## 症状
- 用户报告 kdenlive 打不开（桌面启动闪退）
- `timeout 30 flatpak run --verbose org.kde.kdenlive` 抓到：
  ```
  ::::: SHOWING WELCOME!!!!!!
  :::::::::: CREATING SPLASH SCREEN SPLASH
  QQmlApplicationEngine failed to load component
  qrc:/qt/qml/org/kde/kdenlive/Splash.qml:9:1: module "QtQuick.Controls" version 6.10 cannot be imported because:
  module "QtQuick.Controls.IndirectBasic" version 6.10 cannot be imported because:
  module "QtQuick.Controls.Basic" version 6.10 is not installed
  ```

## 排查过程
1. 检查运行时文件：`~/.local/share/flatpak/runtime/org.kde.Platform/x86_64/6.10/<commit>/files/lib/qml/QtQuick/Controls/`
   - Basic/Fusion/Material/Universal/... 都在，qmldir 齐全 → 初看不像运行时损坏
   - 但**没有 IndirectBasic 目录**（6.9 运行时同样没有）
2. 查 Controls/qmldir 内容：无 IndirectBasic 引用 → 报错源头不在运行时 qmldir
3. `QML_IMPORT_TRACE=1 flatpak run org.kde.kdenlive` 追踪关键行：
   ```
   addImportPath: "/usr/lib/qml"                                  # 运行时（正常）
   addImportPath: "/home/brokenshine/.guix-home/profile/lib/qt6/qml"  # 宿主泄漏！
   importExtension: loaded "/gnu/store/lgm591...-profile/lib/qt6/qml/QtQuick/Controls/qmldir"  # 宿主 qmldir 被加载
   loading dependent import "QtQuick.Controls.IndirectBasic" version 6.10  # 宿主 qmldir 声明的依赖
   locateLocalQmldir: QtQuick.Controls.IndirectBasic module's qmldir found at ""  # 沙箱内没有 → 解析失败
   ```
4. 确认泄漏源：`env | grep -E "^QML|^QT_"`
   ```
   QML_IMPORT_PATH=/home/brokenshine/.guix-home/profile/lib/qt6/qml:...(重复5次)
   QT_PLUGIN_PATH=/run/current-system/profile/lib/qt5/plugins:...
   ```
   来源：`/gnu/store/*-profile/etc/profile:48` 的 `export QML_IMPORT_PATH=...` 被多个 Guix profile 叠加。

## 根因
宿主 `QML_IMPORT_PATH`（指向 Guix profile 的 Qt 6.10 qml 树）被 flatpak 沙箱继承。沙箱内 QML 引擎解析 QtQuick.Controls 时先命中宿主 qmldir——它声明了 `QtQuick.Controls.IndirectBasic` 依赖（Qt 6.10 宿主侧结构），而 flatpak 运行时（KDE Platform 6.10）的 QtQuick/Controls 没有 IndirectBasic 子目录 → 嵌套依赖解析失败 → Splash.qml 加载失败 → 启动即退。

## 修复
```bash
flatpak override --user \
  --unset-env=QML_IMPORT_PATH \
  --unset-env=QML2_IMPORT_PATH \
  --unset-env=QT_PLUGIN_PATH \
  org.kde.kdenlive
```
验证：`flatpak override --user --show org.kde.kdenlive` 显示 `[Context] unset-environment=...`。

## 验证
- 清变量后（env -u 或 override）kdenlive 正常显示 welcome、Splash 加载成功
- 后台启动 + `sleep 40; pgrep -x kdenlive` → ALIVE，日志无 QML 报错
- 残留 `Can't get document portal` / `FileChooser version failed` 警告：agent 终端不在桌面 D-Bus 会话所致；桌面 tty7 上 xdg-desktop-portal-gnome/gtk 正常运行，不影响用户桌面使用

## 可复用要点
- 报错链读链尾：`...IndirectBasic... cannot be imported because: ...Basic... is not installed` 中的 "not installed" 是最终事实，链头只是传播路径
- 判断运行时是否损坏 vs 环境泄漏：qmldir 齐全 + 模块目录存在 → 优先怀疑泄漏；qmldir 里根本没有报错提到的依赖 → 泄漏源实锤
- `flatpak override --unset-env` 是 Guix 宿主上所有 Qt/QML flatpak 应用的通用修法（OBS、Krita 等同理会中招）
