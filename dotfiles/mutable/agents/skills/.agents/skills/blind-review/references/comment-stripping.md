# 注释剥离：按语言接真实解析器

位置保留式剥离的目标：副本的行号 / 列号与原文件一致，注释字符换成等长空白。

## 首选：Emacs `syntax-ppss`（覆盖 py / el / scm / js / ts / sh）

一条命令覆盖本机全部主流语言，比按语言接解析器省事。`syntax-ppss` 的第 5 个元素
（`nth 4`）表示「当前位置是否在注释内」，字符串、正则字面量、模板串插值、
heredoc、Scheme 的 `` `symbol' `` 和 `#\;` 字符字面量，全部由 Emacs 语法表判定，
不需要手写引号配对。

```elisp
(defun strip:blank (file mode)
  "返回 FILE 的注释被替换为等长空白后的文本。

「等长」按字符数计：每个非换行的注释字符替换为一个空格字符，行数与每行
字符数都和原文一致，因此审查报告的 file:line 可以直接对回原文件。"
  (let ((buf (find-file-noselect file)))
    (with-current-buffer buf
      (funcall mode)
      (syntax-ppss-flush-cache (point-min))
      (goto-char (point-min))
      ;; 先收集要清空的字符位置，再统一替换。
      ;; ponytail: 不能边遍历边改 —— 修改文本会让 syntax-ppss 缓存失效，
      ;; 块注释闭合后 nth4 仍报非 nil，后半文件被误清空。
      (let (targets)
        (while (not (eobp))
          (let ((c (char-after)))
            (when (and (nth 4 (syntax-ppss))
                       (not (memq c '(?\n ?\r))))
              (push (point) targets)))
          (forward-char 1))
        ;; 从后往前替换，避免前面的插入移动后面的位置。
        ;; 不用 subst-char-in-region：它要求新旧字符字节长度相同，注释里的
        ;; 中文与制表符会让它直接报错。
        (dolist (p (sort targets #'>))
          (goto-char p)
          (delete-char 1)
          (insert " ")))
      (buffer-substring-no-properties (point-min) (point-max)))))
```

用法：`emacs --batch -l blind-strip.el -- <file> <major-mode>`，输出到 stdout。

mode 映射：`.py`→`python-mode`、`.el`→`emacs-lisp-mode`、`.scm`→`scheme-mode`、
`.js`/`.mjs`/`.cjs`/`.ts`/`.tsx`→`js-mode`、`.sh`→`sh-mode`。

`typescript-mode` 不随 Emacs 分发，`.ts` 用 `js-mode`（TypeScript 是 JS 超集，
注释语法相同）。**mode 未加载时 `funcall` 报错，输出被 backtrace 截断成十几行，
看起来像剥离成功但内容几乎全丢** —— 批量跑时必须检查 `'Error:' in stderr`。

## Python —— stdlib `tokenize`（备选）

`tokenize` 直接给出每个 COMMENT 的精确 row/col，按区间替换为空格即可。

```python
import tokenize

def blank_ranges(path):
    """返回 [(row, col_start, col_end), ...]，按原样替换为等长空格。"""
    out = []
    with open(path, 'rb') as f:
        for tok in tokenize.tokenize(f.readline):
            if tok.type == tokenize.COMMENT:
                out.append((tok.start[0], tok.start[1], tok.end[1]))
    return out
```

`tok.start` / `tok.end` 是 (row, col)，1-indexed。字符串字面量与 f-string 由 tokenize 自己处理，不需要手写引号配对。

## Scheme —— `guile` 的 `read`（备选）

`read` 逐 token 读，注释被自动跳过，字符串（含 `;;`）作为一个 datum 返回。实测：

```scheme
;; 注释
(display "串里有 ;; 不是注释")
(newline)
```

`read` 只返回两个 datum，注释从未出现——说明它能正确区分注释与字符串内容。

用法是包一层 `with-input-from-file` + `let loop` 读到 eof；要拿注释的行列则改用 `read-syntax` 取 source location。

## 不支持的怎么办

Emacs 没有对应 major-mode 的语言（YAML / TOML / C 系 / Go / Rust 等）：

1. 查是否有语言自带的官方工具能吐注释位置（如 clang 的 token 接口）。
2. 没有就**标记该语言不支持**，副本里不放这类文件。
3. 不要用字符级引号配对顶替——它的错法是静默吞掉错位点之后的所有注释，比不剥更危险。

## 自检要断言的不变量

| 不变量 | 断言方式 |
| --- | --- |
| 行数守恒 | `len(src.splitlines()) == len(out.splitlines())` |
| 逐行宽度守恒 | 每行 `len` 相等 |
| 注释内容消失 | 指定注释子串 `not in out` |
| 字符串内容不动 | 含注释符号的字符串子串 `in out` |
| 未闭合块注释 | 剥到文末且不越界 |

只断言这些，不写 `assert out == 'x = 1        \n'` 这类字面量。

## 残留检测的校准

`^\s*(#|//|;)` 会误报：CSS `#id` 选择器、`#include`、shebang、heredoc 内的 `;;`、Scheme `#f` / `#t`。

校准方法：构造一个**已知答案**的样本（几条注释 + 几条含注释符号的字符串），先证明检测规则在该样本上零误报零漏报，再拿它去扫真实仓库。扫完逐个人工定性，不要只信计数。
