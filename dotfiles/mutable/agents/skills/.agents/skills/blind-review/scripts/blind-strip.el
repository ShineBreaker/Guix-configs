;; blind-strip.el — 用 Emacs syntax-ppss 把注释字符替换为等长空白，输出到 stdout。
;; 行号与列号完全守恒（只替换字符、不动换行），因此审查报告的 file:line
;; 可以直接对回原文件，不需要映射表。
;;
;; 用法：emacs --batch -l blind-strip.el -- <file> <major-mode>
;; 例：emacs --batch -l blind-strip.el -- foo.ts js-mode
;;
;; mode 映射：.py→python-mode  .el→emacs-lisp-mode  .scm→scheme-mode
;;           .js/.mjs/.cjs/.ts/.tsx→js-mode  .sh→sh-mode
;; typescript-mode 不随 Emacs 分发，.ts 用 js-mode（TypeScript 是 JS 超集，
;; 注释语法相同）。
;;
;; 判据：
;; syntax-ppss 的 nth 4 表示「当前位置是否在注释内」。逐字符推进，该格为
;; 非 nil 就替换为空格。注释定界符那一格 nth4 仍为 nil，所以定界符本身会
;; 残留 —— 这恰恰是有用的：它保留了「这里原本有条注释」的位置标记，reviewer
;; 看不到内容但看得到位置。
;;
;; 不自己判断字符串/正则/heredoc/字符字面量边界，全部交给 Emacs 语法表：
;; JS 模板串 ${}、Scheme `sym'、正则字面量里的引号、bash heredoc，都是手写
;; 字符级扫描器必然翻车的地方。

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

;; ponytail: argv 在 --batch -l 下含 "--" 分隔符，直接按索引取并过滤掉它。
;; mode 名由调用方给出；typescript-mode 未随 Emacs 分发，.ts/.tsx 传 js-mode
;; （TypeScript 是 JS 超集，注释语法相同）。
(let* ((args (seq-filter (lambda (s) (not (string= s "--"))) argv))
       (file (nth 0 args))
       (mode-name (nth 1 args)))
  (when (and file mode-name)
    (princ (strip:blank file (intern mode-name)))))
