---
name: flatpak-app-debugging
description: "诊断 flatpak 应用启动失败/启动即退/闪退：verbose 抓错、QML 模块追踪、宿主环境变量泄漏、运行时完整性检查。触发信号：flatpak 安装的 GUI 应用打不开、秒退、报 Qt/QML 模块缺失错误。"
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [flatpak, guix, qt, qml, debugging, desktop]
---

# Flatpak 应用启动失败诊断

## 触发条件
- flatpak 安装的 GUI 应用打不开、启动即退、闪退
- 报错涉及 Qt/QML 模块缺失、运行时问题
- 桌面点击图标无反应或闪一下消失

## 诊断流程

1. **确认安装与运行时**
   ```bash
   flatpak info <app-id>
   flatpak list --runtime | grep -iE "kde|freedesktop"
   ```
   记下应用的 runtime（如 org.kde.Platform/x86_64/6.10），确认对应运行时已安装。

2. **verbose 抓错**（GUI 应用必须包 timeout，否则挂住）
   ```bash
   timeout 30 flatpak run --verbose <app-id> 2>&1 | head -80
   ```
   按报错分流：
   - QML 模块错误（`module "X" version Y is not installed`）→ 走步骤 3
   - portal 警告（FileChooser 等）→ 先忽略，agent 终端环境通常拿不到 portal，不代表桌面环境有问题（见 Pitfalls）

3. **QML 导入追踪**（QML 相关报错时）
   ```bash
   QML_IMPORT_TRACE=1 flatpak run <app-id> 2>&1 | grep -iE "import|qml|module"
   ```
   关键观察点：
   - `addImportPath` 列表：正常只有 `/usr/lib/qml`（运行时）、`/app/lib/qml`、`qrc:/...`
   - 若出现宿主路径（`/gnu/store/...`、`~/.guix-home/profile/...`）→ 环境变量泄漏，这是首要怀疑对象
   - `locateLocalQmldir: ... found at ""` → 模块实体在沙箱内缺失

4. **检查宿主环境变量泄漏源**
   ```bash
   env | grep -E "^QML|^QT_"
   ```
   Guix 下 `QML_IMPORT_PATH` / `QT_PLUGIN_PATH` 由 `~/.guix-home/setup-environment` 设置（可能被多个 profile 叠加重复多次）。flatpak 沙箱会继承这些变量。

5. **检查运行时文件完整性**（排除运行时损坏）
   ```bash
   ls ~/.local/share/flatpak/runtime/<runtime>/x86_64/<branch>/<commit>/files/lib/qml/QtQuick/Controls/
   ```
   对比报错中缺失的模块目录是否存在。

## 根因模式：宿主环境变量泄漏进沙箱（Guix 最常见）

- **症状**：Qt/QML flatpak 应用启动即崩，报 `module ... is not installed`，但运行时文件看起来齐全
- **机制**：宿主 `QML_IMPORT_PATH` 指向 Guix profile 的 qml 目录，沙箱内 QML 引擎按路径顺序先命中宿主 qmldir（声明了 flatpak 运行时没有的依赖，如 Qt 6.10 的 `QtQuick.Controls.IndirectBasic`），模块树解析失败 → 应用 splash 加载失败 → 启动即退
- **修复**（永久生效，flatpak ≥ 1.15 支持 --unset-env）：
  ```bash
  flatpak override --user \
    --unset-env=QML_IMPORT_PATH \
    --unset-env=QML2_IMPORT_PATH \
    --unset-env=QT_PLUGIN_PATH \
    <app-id>
  ```
- **验证**：后台启动 + 等待 + 确认进程存活 + 日志无新报错
  ```bash
  flatpak run <app-id> > /tmp/app.log 2>&1 &   # 或 terminal background
  sleep 20; pgrep -x <binary-name> && echo ALIVE
  ```

## Pitfalls
- **不要直接运行沙箱内二进制**（`~/.local/share/flatpak/app/<id>/.../files/bin/<app>`）：缺运行时库报 `error while loading shared libraries` 是假象，flatpak 沙箱才提供运行时环境。
- QML_IMPORT_TRACE 输出量巨大，务必 grep 过滤后再看。
- portal 报错（`Can't get document portal` / `FileChooser version failed`）在 agent 终端会话里出现是正常的——agent 环境不在桌面 D-Bus 会话内。验证桌面环境是否正常应查 `ps aux | grep xdg-desktop-portal`（桌面会话 tty7 上有 xdg-desktop-portal-gnome/gtk 即正常）。
- 报错链是嵌套的（`A cannot be imported because B cannot be imported because C`），读链尾的最终缺失项，别在链头浪费时间。
- 修复后先清变量手动验证，再写 override 固化；`flatpak override --user --show <app-id>` 可确认 override 已写入。

## 支持文件
- `references/kdenlive-guix-env-leak-2026-08.md` — kdenlive 26.04.3 案例全文（完整报错链、trace 关键行、诊断步骤回放）
