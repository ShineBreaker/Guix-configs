---
name: guix-package-authoring
description: Use when 写 Guix 包定义：guix build -f 内嵌 .scm 或 GTK/Python 适配。
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [guix, packaging]
    related_skills: [jeans-channel-workflow]
category: guix-packaging
---

# Guix Package Authoring

## When to Use

- 为不在受管 channel 仓库里的上游软件写 Guix 包定义，尤其仓库内嵌 `<project>.scm`（`guix build -f <x>.scm`）
- 打包 GTK/PyGObject/meson 应用到 Guix（typelib/PYTHONPATH wrap、测试环境）
- 脚本 FHS-free 适配（shebang、绝对路径假设）
- 不适用：jeans channel 仓库的例行维护（CI、auto-update、lint sweep）→ jeans-channel-workflow

为不在受管 channel 仓库里的软件写 Guix 包定义：上游仓库内嵌打包脚本（`guix build -f <x>.scm`）、为 GTK/Python/meson 应用做 Guix 适配。channel 仓库维护（CI、auto-update、lint sweep）不在本 skill 范围，走 jeans-channel-workflow。

## 流程

### 1. 先核实环境事实，再写定义
- 依赖包名以 `guix show <name>` 为准，别凭其他发行版直觉：**GTK4 的包名是 `gtk`，`gtk+` 是 GTK3**；Python 绑定是 `python-pygobject`。
- 模块归属用 `guix show <pkg> | grep location` 查（给出 `(gnu packages xxx)`），逐个补进 `use-modules`——「未绑定变量」报错会直接点名缺的模块。
- Guix 上游缺的包：`guix import pypi <name>` 拿 version+hash 起点；构建报缺什么再补（scanner 类构建常缺 `pkg-config`、`wayland-protocols`）。

### 2. 骨架先行，增量验证
先写只含最小包定义的文件跑通 `guix build -f`，再逐段补 phases/inputs——大文件一次写完再调，定位成本高数倍。
- **`guix build -f` 要求文件末尾是裸表达式**（包变量名单独一行）；只有 `(define-public ...)` 时报 `` #<unspecified> ``。
- license 导入用 `((guix licenses) #:prefix license:)`。

### 3. 构建失败读 drv 日志
失败输出末尾给日志路径 `/var/log/guix/drvs/<hash前2>/<hash>.drv.gz`；`zcat <log> | grep -B8 error` 直接拿根因，别对 guix build 摘要猜。

### 4. wrap 阶段与验证（GTK/GI/Python 应用）
配方见 [references/gtk-python-wrap-recipe.md](references/gtk-python-wrap-recipe.md)。规则：
- **glib-or-gtk-build-system 不支持 meson**（基于 gnu），且其 wrap 只设 XDG_DATA_DIRS/GTK_PATH/GIO_EXTRA_MODULES，不含 GI_TYPELIB_PATH/PYTHONPATH——meson 应用用 meson-build-system + 自写 wrap 阶段。
- **同名输出标签冲突**：inputs 的 ``(,gtk "out")``（typelib 所在）与 native-inputs 的 ``(,gtk "bin")`` 标签同为 `"gtk"`，合并后只剩一个，wrap 出的 GI_TYPELIB_PATH 丢 Gtk typelib——native 侧用三元素 ``("gtk:bin" ,gtk "bin")``。
- **三元素 tuple 只能活在 quasiquote alist 里**：塞进 `(list ...)` 报「无效输入」，整个 inputs 要改成 `` `(("x" ,pkg) ...) `` 形式。
- **cairo-1.0.typelib 在 gobject-introspection 输出里**（cairo 包本体没有）——GI 导入 Gtk/cairo 的环境必须含它。
- 验证三步缺一不可：① 读 wrapper 内容确认每个预期目录在场；② **清空环境再跑**（agent shell 继承 profile 的 GI_TYPELIB_PATH/GSETTINGS_SCHEMA_DIR，会掩盖 wrapper 缺口，先 unset 再执行真实入口）；③ `guix shell -f x.scm -- <app> --version` 验证 -f 路径。

### 5. 测试
- **meson test 会重置环境变量**：build phase 里 setenv 的 GI_TYPELIB_PATH/PYTHONPATH 不进测试进程，容器内跑需要 typelib 的 pytest 必挂 → 构建侧 `#:tests? #f`。
- 真实测试在源码树跑：`guix shell python-pytest <依赖...> gtk libadwaita gobject-introspection -- pytest -q tests`。
- `guix shell -C` 容器没有裸 `python3`/`sh`——加 `python-wrapper`/`bash`。

### 6. FHS-free 适配（脚本类）
Guix System 的 /bin 只有 sh：入口脚本 shebang 一律 `#!/usr/bin/env bash`；Python fallback 用 `shutil.which("bash") or "/bin/sh"`，不硬编码 /bin/bash。wrap-program 的 wrapper 本身用 store bash，不受影响。

## 独立坑
- **appstreamcli 1.0**：metainfo 缺 `<name>` 是 error 级（挂 meson test 的 Validate appstream 用例，进而挂 distro 构建）；developer id 必须小写 rDNS（`io.github.xxx`）；加 `<launchable type="desktop-id">` 消 warning。
- gnome.post_install 需要 gio-2.0.pc（glib 主输出进 native-inputs）与 gtk4-update-icon-cache（`gtk:bin`）。
