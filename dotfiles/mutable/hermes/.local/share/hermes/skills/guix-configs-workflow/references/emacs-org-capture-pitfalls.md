# Emacs org-capture 模板调试经验

提炼自 2026-06-21 知识库改造过程中 `C-c o k c` 报错修复。

## org-capture-expand-file 不对内嵌 form 求值

**症状**：`org-capture-expand-file: Invalid file location: nil`

**根因**：`org-capture-expand-file` 在处理 `(file <spec>)` 目标时，对 `<spec>` 的处理逻辑：

- `stringp` → 直接作为文件名
- `functionp` → `(funcall <spec>)` 获取返回值
- 其他 list/consp（如 `(expand-file-name ...)`）→ **不执行**，原样返回 list 本身

当返回的是 list 而非 string 时，`org-capture-expand-file` 抛出 `Invalid file location: nil`（部分版本报 `<spec>` 原文）。

**错误写法**（内嵌 form，不会被执行）：

```elisp
;; ❌ (expand-file-name ...) 是 list，org-capture-expand-file 不执行它
(file (expand-file-name
       (format-time-string "experiences/%Y%m%d-%H%M%S.org")
       custom:org-directory))
```

**正确写法**（lambda 函数，org-capture-expand-file 会用 funcall 调用）：

```elisp
;; ✅ lambda 是 functionp，被 funcall 后返回 string
(file ,(lambda ()
         (expand-file-name
          (format-time-string "experiences/%Y%m%d-%H%M%S.org")
          custom:org-directory)))
```

注意 `,` 是 backquote 语法——在 `add-to-list` 的 backquote 模板中，`,` 使 lambda 在注册时求值，嵌入的是闭包对象而非源码 form。

## 为什么不用 function target

`entry` 类型的 `(function f)` target 语义不同：它直接 set-buffer + goto-char，不是返回文件路径。动态文件路径只能用 `file` target + lambda。

## 验证方法

```elisp
;; batch 验证 lambda 返回值
(let* ((tmpl (assoc "k" org-capture-templates))
       (target-arg (cadr (nth 3 tmpl))))
  (when (functionp target-arg)
    (princ (funcall target-arg))))  ; 应输出有效路径
```
