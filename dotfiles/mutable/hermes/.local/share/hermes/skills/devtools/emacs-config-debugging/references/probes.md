# 调试 Emacs 配置用的 emacsclient 探针模板

所有探针默认假设 Emacs daemon 在跑，能直接 `emacsclient --eval '...'`。返回统一走 `json-encode` 避免 stdout 被截断。

## 1. 当前 buffer 某键位的实际绑定

查某键在 global-map 和 current-local-map 里分别被绑到什么：

```bash
emacsclient --eval "(json-encode
  (list (cons \"global\" (symbol-name (lookup-key global-map (kbd \"<KEY>\"))))
        (cons \"local\"  (let ((m (current-local-map)))
                          (if m (symbol-name (lookup-key m (kbd \"<KEY>\"))) \"nil\")))
        (cons \"major\" (symbol-name major-mode))
        (cons \"mmodes\" (format \"%S\" minor-mode-list))))"
```

把 `<KEY>` 换成实际键位（C-j、M-x、<tab> 等）。返回 JSON 里如果 `local` 不是 nil，那一层就是劫持源。

## 2. 某命令被绑到哪些键

反向查：我想知道 `next-line` 到底被绑在哪些键上：

```bash
emacsclient --eval "(require 'seq)
(mapconcat #'key-description (where-is-internal #'next-line) \" | \")"
```

注意 `where-is-internal` 只接收 symbol 形式的命令名，不能传字符串。

## 3. 重载配置文件并对比 before/after

修改文件后想立刻在运行中的 daemon 里验证：

```bash
emacsclient --eval "(progn
  (require 'org)
  (let ((before (symbol-name (lookup-key org-mode-map (kbd \"C-j\")))))
    (load-file (locate-user-emacs-file \"configs/org/org-mode.el\"))
    (let ((after (symbol-name (lookup-key org-mode-map (kbd \"C-j\")))))
      (json-encode (list (cons \"before\" before) (cons \"after\" after))))))"
```

"before" 应该是劫持层原本的函数，"after" 应该是新加的 dispatch 函数。如果两者一样，说明 reload 没生效（用了别的 keymap 名 / 路径不对）。

## 4. dispatch 函数行为实测

在 temp buffer 里模拟两种上下文，看 dispatch 真的分流：

```elisp
(with-temp-buffer
  (insert "* Test\n\n| a | b |\n| 1 | 2 |\n| 3 | 4 |\n\nafter-table line\n")
  (goto-char (point-min))
  (org-mode)
  (let ((dispatch (lookup-key org-mode-map (kbd "C-j")))
        (inside-result nil)
        (outside-result nil))
    ;; 表格内
    (re-search-forward "| 1 | 2 |")
    (beginning-of-line) (forward-char 3)
    (let ((line-before (line-number-at-pos)))
      (funcall dispatch)
      (setq inside-result (format "%d -> %d" line-before (line-number-at-pos))))
    ;; 表格外
    (goto-char (point-max))
    (re-search-backward "after-table line")
    (beginning-of-line)
    (let ((line-before (line-number-at-pos)))
      (funcall dispatch)
      (setq outside-result (format "%d -> %d" line-before (line-number-at-pos))))
    (concat "INSIDE: " inside-result " | OUTSIDE: " outside-result)))
```

两个上下文都按预期跳行（一个跳到表格下一行、一个下移光标），才算真的修好。

## 5. byte-compile 检查

```bash
emacsclient --eval "(condition-case err
  (byte-compile-file (locate-user-emacs-file \"configs/<FILE>.el\"))
  (error (format \"ERR: %s\" err)))"
```

返回 `t` 通过；返回字符串则解析错误信息。

## 6. 让用户跑 describe-key 并贴输出

最快的第一步不是发探针——**直接让用户按 `C-h k <问题键>` 然后把 help buffer 内容贴过来**。`describe-key` 的输出格式：

```
<command-name> is an interactive and byte-compiled function defined in <file>.

Signature
  (<command-name>)

Documentation
  ...

Key Bindings
  <keymap-name> <KEY>      ← 这一行直接告诉你劫持来自哪一层

References
  ...

Source Code
  ...
```

读这一段时，**只用盯 "Key Bindings" 一行**。例如：

- `org-mode-map C-j` → Org 内置 buffer-local keymap 在劫持
- `global-map C-x C-s` → 是你/其他人的全局绑定
- `text-scale-mode-map C-=` → text-scale-mode 的 minor-mode map

## 7. face 调试探针

face 类问题没有 `describe-key` 这种 ground truth 工具，需要按 face 名逐个探测。

### 读某 face 的当前属性

```bash
emacsclient --eval "(json-encode
  (list (cons 'family  (face-attribute 'line-number :family))
        (cons 'width   (face-attribute 'line-number :width))
        (cons 'height  (face-attribute 'line-number :height))
        (cons 'foreground (face-attribute 'line-number :foreground))))"
```

返回 `"unspecified"` 表示 face 没被显式设置（继承自父 face 或默认）。

### 探测当前 Emacs 版本支持哪些 face 属性

逐个尝试 `(set-face-attribute F nil ATTR nil)`（nil = 重置语义），看哪些不报错：

```bash
emacsclient --eval "(let (ok bad)
  (dolist (p '(:foreground :background :height :width :weight :slant :underline :box :strike-through :inverse-video :stipple :extend :family :foundry :italic :bold :inherit))
    (push (condition-case nil
            (progn (set-face-attribute 'line-number nil p nil) p)
          (error (cons p 'bad))) ok))
  ok)"
```

**坑**：返回 `bad` 的属性不一定真的"不能用"——可能是**重置（nil 值）**这个动作不被支持，但**作为值传入**（如 `:width 'ultra-condensed`）通常是可以的。所以看到 `bad` 时换传具体值再试。

### 设 + 读回验证 face 改动生效

```bash
emacsclient --eval "(progn
  (set-face-attribute 'line-number nil :width 'ultra-condensed)
  (set-face-attribute 'line-number-current-line nil :width 'ultra-condensed)
  (json-encode
    (list (cons 'ln-width (face-attribute 'line-number :width))
          (cons 'ln-current-width (face-attribute 'line-number-current-line :width)))))"
```

返回都应该是 `"ultra-condensed"`。

**⚠ 重要**：返回 `"ultra-condensed"` 只说明 face 属性被设进去了——**不等于视觉上能看到变化**。在 fontconfig 后端 + Nerd Font 字族（Maple Mono NF CN、JetBrainsMono Nerd Font 等）下，`:width` 属性被接受且能读回正确值，但渲染层只做字符级 glyph 缩放、不压缩等宽字符列宽，肉眼**看不出**行号列变窄。任何 face 视觉调整都必须让用户看实际 buffer 效果，不能只看 `(face-attribute ...)` 的返回值。具体路径见 SKILL.md "Case: 行号列与正文之间留白过大"。

### 主题会覆盖 face —— 确认是不是主题导致的"改完又恢复"

切完主题后立即读：

```bash
emacsclient --eval "(face-attribute 'line-number :width)"
```

如果切主题后变回 `"normal"` 或 `"unspecified"`，说明主题重置了 face。要么用 `:custom` 块在 use-package 里设，要么挂 `after-load-theme-hook` 钩子确保主题加载后再覆盖。

### GUI / TTY 区分 —— face :width 在终端无效

```bash
emacsclient --eval "(display-graphic-p)"
```

返回 `t` 是 GUI，`nil` 是 TTY。终端走 ANSI 字体，`:width` 等价物不存在。如果当前 frame 是 TTY，`:width 'ultra-condensed` 设上去也不会有任何视觉变化。

## Pitfalls

- 探针里的 `(kbd "<KEY>")` 必须用正确的键位语法：`<tab>`、`<return>`、`<f1>`、`<C-tab>`（不是 `C-TAB`）。
- `(current-local-map)` 在没有 buffer-local keymap 时返回 nil；测试时先确认 major-mode 是预期的（比如不是 fallback 到 fundamental-mode）。
- 不要相信 `(lookup-key global-map <key>)` 是 ground truth——它只看 global-map 这层。
- daemon 重载只对当次 session 生效。要让修改"永久"生效还得改源文件 + 重启 daemon。
- face 属性探测时**传 nil 是重置**（有的 Emacs 版本会拒绝），传具体值（如 `'ultra-condensed`）才是设置——看到 `bad` 优先换具体值再试。
- `:kerning` / `:spacing` 这类字体微调属性**不一定在 face 上支持**（取决于 Emacs 构建的字体后端），报错 `Invalid face attribute name` 时换 `:width` 或 `:height`。
