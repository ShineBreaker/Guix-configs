# ISO `blue build-iso` 构建调试实录（2026-07-07）

> 实战沉淀：`blue build-iso` 跑通前的三个真实错误 + 各自根因 + 修复 + 复现命令。
> 配套：SKILL.md §10.6 补遗(a/b) + §10.7 运行范式。

## 0. 运行范式（先读）

`blue build-iso` **不需要 sudo**（与 `blue rebuild` 不同）。Agent 可直接后台跑：

```bash
cd ~/Projects/Config/Guix-configs && blue build-iso          # 全变体
blue build-iso xfce                                        # 只 xfce（先验证）
```

**`blue` 的 `%guix` 封装会吞掉 guix 真实报错**——guix 非零退出时只报：

```
Error while running command build-iso:
 misc-error: 命令执行失败 (256): ("guix" "time-machine" ... "repl" ...)
```

看不到 guix 自己的 backtrace。遇到失败**必须手动复现同一条 guix 命令**抓完整输出：

```bash
cd ~/Projects/Config/Guix-configs
guix time-machine --channels=source/channel.lock -- repl -- \
  scripts/build-image.scm dist/jeans-xfce-<date>.x86_64-linux.iso \
  tmp/live-iso.scm --image-type=iso9660 2>&1 | tee /tmp/iso-xfce-build.log
```

## 1. 错误一：`'services' field must contain a list of services`

**现象**（手动复现后）：

```
/home/brokenshine/Projects/Config/Guix-configs/tmp/live-iso.scm:225:4: 错误：
 'services' field must contain a list of services
```

**根因**：`live-installation-os` 的 `services` 字段用 `cons*` 拼，
`<<guix-substitutes>>` 这个 noweb 块展开后是 `(list 4个 simple-service ...)`,
被 `cons*` 当**单个元素**塞进 services 列表 → services 里嵌了嵌套 list。

**修复**：把 `cons*` 整段改成 `append` 拍平（见 SKILL.md §10.6 (a)）。

**验证**：`blue check` 通过 + `tail tmp/live-iso.scm` 末行是 `%live-installation-os`。
注意 `grep -c '%live-installation-os' tmp/config.scm` 应为 0（§3.1/§3.2 污染检查）。

## 2. 错误二：`no code for module (guix build utils)`

**现象**（手动复现的 drv backtrace，`zcat` 解压 `.drv.gz` 或日志）：

```
Backtrace:
In ice-9/boot-9.scm:
  3935:20  3 (process-use-modules _)
   222:17  2 (map1 (((guix build utils))))
  3936:31  1 (_ ((guix build utils)))
   3330:6  0 (resolve-interface (guix build utils) #:select _ #:hide …)
ice-9/boot-9.scm:3330:6: In procedure resolve-interface:
no code for module (guix build utils)
```

**根因**：`xfce-wayland-session` 用 `trivial-build-system`，其 builder 里写
`(use-modules (guix build utils))` 调 `mkdir-p` / `call-with-output-file`。
`trivial-build-system` 的构建沙箱**默认不**把 `(guix build utils)` 模块编译进去，
gexp 展开后的 builder 找不到该模块。

**修复**：用 `with-imported-modules` 把模块带入 gexp（见 SKILL.md §10.6 (b)）：

```scheme
(arguments
 (list #:builder
  (with-imported-modules '((guix build utils))
    #~(begin
      (use-modules (guix build utils))
      ...))))
```

`(guix gexp)` 已在 `live-modules` 导入，`with-imported-modules` 可用。

**坑中坑（括号平衡）**：加 `with-imported-modules` 那层后，收尾 `)` 数量要同步 +1。
本次手写漏算导致 `blue check` 报 `live-xfce-define: 多余 1 个左括号 (open=42 close=41)`，
`tmp/live-iso.scm` 报 `缺少右括号`。收敛手段：单调调收尾 `)` 数量 + 看 open/close 差值，
不要手算（详见 `references/iso-xfce-on-labwc-fedora-approach.md` §4）。

## 3. 错误三：手写 synthetic package 括号失衡（§10.6 (b) 衍生）

`live-xfce-define` 块（含 `with-imported-modules` + 3 个 `call-with-output-file` +
`(arguments (list #:builder ...))` 多层嵌套），收尾 `))))))))` 极易数错。

**调试命令**：

```bash
blue check 2>&1 | grep -E 'live-xfce-define|FAIL'
# 看 open=N close=M 差值,单调调末尾 ) 数收敛
awk 'NR==<收尾行>{print gsub(/\)/,"")}' source/config.org   # 数某行 ) 个数
```

本次最终平衡：收尾 8 个 `)`（3×call 各收 3 + let* + begin + with-imported +
list #:builder + arguments）。

## 4.5 错误四（最高频根因）：`多余一个类为'X'的目标服务`

> 2026-07-07 把 Live ISO 从 XFCE 改 KDE 时发现的，**掩盖了前面所有
> `services` 字段括号错**。原 XFCE 版（git HEAD 前）其实也踩了同一个坑，只是
> 从没真跑到 `fold-services` 阶段，所以一直没暴露。

**现象**（手动复现 guix repl 后）：

```
&ambiguous-target-service-error
  service: #<<service> type: #<service-type polkit …>>
  target-type: #<service-type account …>
  "多余一个类为'account'的目标服务"
```

把 `live-installation-os` 的 services 一路简化到**纯 base-only**
（`(services (operating-system-services %live-base-os))`，不加任何桌面/DM）
仍然报 `account`；去掉 plasma 加回 sddm 报 `pam`；全加上报 `profile`——
错误类型随"哪个桌面服务的 extend 先触发"变，但根因同一个。

**根因（决定性）**：`operating-system-services`（`gnu/system.scm:890`）的定义是：

```scheme
(define* (operating-system-services os)
  (instantiate-missing-services
   (append (operating-system-user-services os)          ; 用户服务
           (operating-system-essential-services os))))  ; system/pam/account/boot/shepherd-root…
```

它**自动把 `essential-services` 拼到用户服务后面**。而 `operating-system` 这个
record 在求 `operating-system-services` 时**又会再 append 一次 essential**。
所以把 `(operating-system-services %live-base-os)` 的返回值直接写进 `services`
字段，等于让 `system` / `pam` / `account` / `shepherd-root` / `boot` 这些
**单实例核心服务注册了两遍** → `fold-services` 在对应 target-type 上触发
`ambiguous-target-service-error`（"more than one target service of type 'X'"）。

诊断脚本（抓到 `system count=2` / `pam count=2` / `account` 即确诊）：

```scheme
;; 在 guix repl 里 load tmp/live-iso.scm 后跑：
(define svcs (operating-system-services %live-installation-os))
(define names (map (lambda (s) (service-type-name (service-kind s))) svcs))
(for-each (lambda (n)
            (let ((c (length (filter (lambda (x) (eq? x n)) names))))
              (when (> c 1)
                (format #t "DUPLICATE kind: ~a count=~a~%" n c))))
          (delete-duplicates names))
```

**修复**：`services` 字段里**只用 `operating-system-user-services`**（只取用户部分，
不含 essential），让 `operating-system` 自己补 essential 一次：

```scheme
(services
 (append
  <<guix-substitutes>>
  (list (service plasma-desktop-service-type)
        (service sddm-service-type
          (sddm-configuration
            (display-server "x11")
            (auto-login-user "live")
            (auto-login-session "plasma.desktop"))))
  (operating-system-user-services %live-base-os))))   ; ← 不是 operating-system-services
```

**坑中坑**：这个 bug 和 §3.1/§3.2 的"括号污染"会叠加——先修括号让 tangle 产物
能 load，才会暴露本错误。排查顺序：① `blue check` 过 → ② 手动 repl 复现抓
`ambiguous-target` → ③ 改 `user-services`。

## 4. 完整修复后验证路径

```bash
# 1) 括号平衡
blue check 2>&1 | tail -3        # [OK] 全部通过

# 2) 手动复现构建（抓真实报错，确认不再 early fail）
guix time-machine --channels=source/channel.lock -- repl -- \
  scripts/build-image.scm dist/jeans-xfce-<date>.x86_64-linux.iso \
  tmp/live-iso.scm --image-type=iso9660 2>&1 | tee /tmp/iso-xfce-build.log
# 进入 guix-system image 构建 = 成功越过 OS 定义阶段

# 3) 正式后台构建
cd ~/Projects/Config/Guix-configs && blue build-iso xfce
# 产物: dist/jeans-xfce-<YYYYMMDD>.x86_64-linux.iso
```

## 5. 已知遗留问题（非本次错误，另立项）

- `%images` 列了 `("xfce" "minimal")`，但 `minimal` 共用同一份 `live-installation-os`
  （带 xfce 桌面），与"纯 CLI fallback"语义不符。分离 minimal 需 `source/config.org`
  加独立 OS 块（见 `docs/iso-build.md` §7.1）。
