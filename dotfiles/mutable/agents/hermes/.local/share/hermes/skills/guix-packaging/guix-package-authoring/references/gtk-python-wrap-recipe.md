# GTK + Python + meson 应用的 Guix 打包配方

适用：PyGObject/GTK4/libadwaita 应用，入口由 meson configure_file 生成（`#!@PYTHON@` 替换为构建用 python 的 store 路径，天然合规）。实例形态：上游仓库内嵌 `<project>.scm`，`guix build -f <project>.scm`。

## 包定义要点

- build-system: `meson-build-system`（glib-or-gtk 不支持 meson）
- configure-flags: 按需传空关闭宿主特有安装位（`-Dsystemd-system-unit-dir=` 等——Guix 无 systemd，相关 dependency() 自然找不到）
- `#:tests? #f`：容器内 meson test 跑不了需要 typelib 的用例（meson test 重置环境变量）
- 输入三层：
  - native-inputs: gettext-minimal、python-wrapper、glib（gio-2.0.pc）、`("glib:bin" ,glib "bin")`、`("gtk:bin" ,gtk "bin")`、desktop-file-utils、pytest（可选）
  - inputs（GI 库，供 wrap 收 typelib）: gtk(=out)、libadwaita、vte、graphene、gdk-pixbuf、**gobject-introspection**（cairo typelib 在这）、glib、pango、harfbuzz
  - inputs（python 绑定 + 脚本 PATH 工具）: python-pygobject、python-pycairo、…按应用 import 清单；bash-minimal、coreutils、grep、sed、tar、pciutils 等

## wrap 阶段模板

```scheme
#:phases
#~(let ((py-site
         (string-append "/lib/python"
                        #$(version-major+minor (package-version python))
                        "/site-packages"))
        (gi-labels '("gtk" "libadwaita" "vte" "graphene"
                     "gdk-pixbuf" "gobject-introspection"
                     "pango" "harfbuzz" "cairo" "glib"))
        (py-labels '("python-pygobject" "python-pycairo" ...))
        (bin-labels '("bash" "coreutils" "grep" "sed" ...)))
    (define (existing-dirs inputs labels suffix)
      (filter (lambda (d) d)
              (map (lambda (label)
                     (let ((dir (and=> (assoc-ref inputs label)
                                       (lambda (d) (string-append d suffix)))))
                       (and dir (file-exists? dir) dir)))
                   labels)))
    (modify-phases %standard-phases
      (add-after 'install 'wrap-program-paths
        (lambda* (#:key inputs outputs #:allow-other-keys)
          (let* ((out (assoc-ref outputs "out")) ...)
            ;; GUI 入口：全量环境
            (wrap-program (string-append out "/bin/<app>")
              `(,"PATH" ":" prefix ,path-dirs)
              `(,"GI_TYPELIB_PATH" ":" prefix ,gi-dirs)
              `(,"PYTHONPATH" ":" prefix ,py-dirs)
              `(,"GSETTINGS_SCHEMA_DIR" ":" prefix
                (,(string-append out "/share/glib-2.0/schemas")))
              `(,"XDG_DATA_DIRS" ":" prefix (,(string-append out "/share"))))
            ;; 特权 CLI（pkexec 调用）：只 wrap PATH——pkexec 环境极简
            (wrap-program (string-append out "/bin/<app>-cli")
              `(,"PATH" ":" prefix ,path-dirs)))))))
```

关键点：
- `existing-dirs` 只收真实存在的目录，inputs 增减不用改 wrap 代码。
- site-packages 后缀用 `(version-major+minor (package-version python))` 算，别硬编码 3.11/3.12。
- PATH 用 `prefix` 语义保留会话 PATH（用户 profile 里的外部工具如 waydroid 仍可见）。
- gexp 里收集逻辑要包在 `#~(let ...)` 里（不是 `#(...)` 向量字面量——后者把 ungexp 结构原样送进构建侧，modify-phases 报 wrong-type）。

## 验证命令

```bash
out=$(guix build -f x.scm)
# 1. wrapper 内容检查（每个预期目录在场）
grep -o 'GI_TYPELIB_PATH="[^"]*' $out/bin/<app> | tr ':' '\n'
# 2. 清空环境跑真实入口（GUI 短冒烟 + CLI 无副作用子命令）
unset GI_TYPELIB_PATH GSETTINGS_SCHEMA_DIR XDG_DATA_DIRS PYTHONPATH
export WAYLAND_DISPLAY=wayland-1 XDG_RUNTIME_DIR=/run/user/$(id -u)
export DBUS_SESSION_BUS_ADDRESS=$(tr '\0' '\n' < /proc/$(pgrep -n niri)/environ | grep DBUS_SESSION | cut -d= -f2-)
timeout -s TERM 5 $out/bin/<app>            # 期望干净退出、无 Gtk/GLib 报错
$out/bin/<app>-cli <无副作用子命令>
# 3. -f 用法路径
guix shell -f x.scm -- <app> --version
```

GUI 冒烟的 DBUS 地址从合成器进程 environ 取（dbus-run-session 的 socket 路径非标准，`/run/user/<uid>/bus` 不存在）。
