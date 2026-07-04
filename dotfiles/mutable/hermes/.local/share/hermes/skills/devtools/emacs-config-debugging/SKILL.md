---
name: emacs-config-debugging
description: 调试用户的 Emacs Lisp 配置 —— 当用户报告"我绑的快捷键不生效 / 按键行为不符合配置 / mode 下行为怪异 / face 视觉调整出问题"等 Emacs 配置层问题时使用。覆盖 keymap 优先级链（global → minor-mode → buffer-local → text/overlay）、描述 `describe-key` / `C-h k` / `where-is-internal` 的输出如何解读、如何用 `emacsclient --eval` 实测运行中 daemon 的键位与 face、如何定位"包内置绑定覆盖了我的配置"或"主题覆盖了我的 face"这类典型坑。触发：「按键不生效」「C-x 在 X mode 下行为不对」「我绑了 Y 但是按下去还是 Z」「describe-key 告诉我绑到了 A 但我要的是 B」「global-set-key 没生效」「buffer-local keymap 抢了全局键」「major-mode 覆盖了我的键位」「行号列与正文之间留白过大」「face 颜色/间距被主题改回去了」「配置改完 reload 不生效」等。
---

# emacs-config-debugging

调试用户 Emacs Lisp 配置问题的标准流程。

## 核心心智模型

Emacs 键位查找不是"全局表"，而是一张**优先级链**。任何"我绑了 X 不生效"的问题，99% 是某个更高优先级的层把它劫持了。

按优先级从低到高：

```
1. global-map                              ; global-set-key / custom/bind!
2. minor-mode-map-alist (按 minor-mode 列表顺序)
3. buffer-local keymap (current-local-map)
4. text / overlay keymap                   ; 最低粒度，通常不是问题源
```

每一层都会**先**被查找。一旦某一层命中，后面的层不再看。

`describe-key`（`C-h k`）的输出里有一行 **"Key Bindings"** 直接告诉你某条键位在**哪一层**生效。例如：

```
Key Bindings
  org-mode-map C-j      ← buffer-local (org-mode-map)
  global-map C-x C-s    ← global
```

**看到 `xxx-mode-map <key>` 就说明那一层在劫持。** 这是定位问题的最直接证据。

## 调试流程（按顺序）

### Step 1: 让用户跑 `C-h k <key>` 并贴输出

如果用户没主动跑，主动请他跑。**这是最快的一步**，90% 的 keymap 问题在这一步就能定位。

读输出时关注三个字段：

| 字段              | 含义                                                    |
| ----------------- | ------------------------------------------------------- |
| "Key Bindings"    | 该命令实际生效的位置（keymap 名 + 键位）               |
| "References"      | 该命令在源码里的定义位置（用于确认是不是预期内）        |
| 末尾的源文件路径  | 用来判断是内置包、第三方包、还是用户配置                |

如果输出在 "Key Bindings" 一行写的是 `xxx-mode-map <key>`，说明是更高优先级的层在绑——**问题不在你的配置里，而在那个 mode-map 的定义处**。

### Step 2: 用 emacsclient 实测运行中 daemon 的键位

如果用户当前 Emacs 正在跑（daemon/client 模式），可以直接发 elisp 探针过去，不用让他手动复现：

```bash
emacsclient --eval '(json-encode (list
  (cons "global-c-j" (symbol-name (lookup-key global-map (kbd "C-j"))))
  (cons "local-c-j"  (symbol-name (lookup-key (current-local-map) (kbd "C-j"))))
  (cons "major-mode" (symbol-name major-mode))
  (cons "mm-list"    minor-mode-list)))'
```

返回里如果 `local-c-j` 不是 nil，那一层就在抢。

要查某个命令实际被绑到哪些键：

```bash
emacsclient --eval '(mapconcat #'key-description (where-is-internal #'my-command) ", ")'
```

注意 `where-is-internal` 的第三参数（KEYMAP）必须是 vector，不能传 nil 时省略——它默认返回所有 keymap 里的位置（正是我们想要的）。

### Step 3: 找到劫持层的定义位置

根据 `describe-key` 输出的源文件路径，分三种情况：

| 源文件位置                          | 含义                                  | 修复方向                                              |
| ----------------------------------- | ------------------------------------- | ----------------------------------------------------- |
| `.../site-lisp/<pkg>-<ver>/<file>.el` | 内置包默认绑定（org-mode, magit, ...） | 在用户的 `configs/<pkg>.el` 加 buffer-local 覆盖     |
| `.../straight/build/<pkg>/<file>.el`  | 第三方包源码（用户通过 straight/elpaca 等装） | 在 `use-package :bind` 块里覆盖，或在配置文件中显式 define-key |
| 用户仓库内的 `configs/...`          | 用户自己的配置                        | 优先级顺序错了（后加载的反而被前面的覆盖了）         |

**最常见的坑是第一种**：Org 内置把 `C-j` 绑给 `org-return-and-maybe-indent`，magit 把 `C-c C-c` 绑给 `magit-commit`，company / corfu / yasnippet 各自劫持 `<tab>` 和 `M-TAB`——这些都不会报错，你的配置"看起来"生效了，运行时却被压住。

### Step 4: 设计修复策略

按 buffer-local 覆盖的精细度分三档：

1. **粗暴覆盖**：`define-key <mode>-map (kbd "<key>") #'my-cmd`。所有该 mode 下都用同一个行为。简单但会丢掉 mode 原本的语义（如表格里跳行）。
2. **条件分发**：写一个 dispatch 函数，根据上下文决定走哪个命令。例：

   ```elisp
   (defun custom/org-c-j-dispatch ()
     (interactive)
     (call-interactively
      (if (org-at-table-p)
          #'org-return-and-maybe-indent
        #'next-line)))
   (define-key org-mode-map (kbd "C-j") #'custom/org-c-j-dispatch)
   ```

   保留 mode 在特定上下文里的有用语义，其余位置走你的约定。
3. **完整接管**：用 `:bind (:map <mode>-map ...)` 在 use-package 块里集中覆盖所有冲突键。适合该 mode 完全不符合你的工作流的情况。

**默认推荐档 2**：花 5 行代码换来 mode 在表格/代码块等特殊上下文里的原生智能行为。

### Step 5: 把修复落进正确文件

修改原则（见各 emacs 配置仓库的 AGENTS.md，硬约束通常写在那里）：

- **键位绑定走 `custom/bind!` 宏**（如果仓库定义了它），不要裸 `global-set-key`——宏会同时注册 which-key 描述。
- **buffer-local 覆盖落在该 mode 对应的 `configs/<pkg>.el`**——而不是 `keybindings.el`。这样以后删除该 mode 时不会留下孤儿配置。
- **修改 `;;; Commentary:`**（顶部说明块）加一笔历史踩坑，避免下次调试时再走一遍同样的弯路。

## 验证

修改完**两件事必须做**：

1. **byte-compile 语法检查**：
   ```bash
   emacsclient --eval '(byte-compile-file (locate-user-emacs-file "configs/<file>.el"))'
   ```
   返回 `t` 即通过；返回错误则立即看。

2. **运行中 daemon 实测 reload + 重测键位**：
   ```bash
   emacsclient --eval '(progn
     (require '\''<pkg>)
     (load-file (locate-user-emacs-file "configs/<file>.el"))
     (json-encode (list
       (cons "before" (symbol-name (lookup-key <mode>-map (kbd "<key>"))))
       (cons "after"  (symbol-name (lookup-key <mode>-map (kbd "<key>")))))))'
   ```

   "before" 应该显示劫持层原本的函数，"after" 应该显示你的 dispatch 函数。

3. **行为实测**（最关键）：模拟两种上下文，验证 dispatch 真的分流。
   ```elisp
   (with-temp-buffer
     (insert "实际触发样本")
     (<mode>)
     (let ((dispatch (lookup-key <mode>-map (kbd "<key>"))))
       ;; 上下文 A
       (goto-char <位置A>) (funcall dispatch) (line-number-at-pos)
       ;; 上下文 B
       (goto-char <位置B>) (funcall dispatch) (line-number-at-pos)))
   ```
   看到两个上下文的行号按预期变化（一个跳到下一行、一个光标下移），才算真的修好。

## 典型案例

### Case: 包内置 buffer-local binding 覆盖全局约定

**症状**：用户报告 `C-j` 在 Org buffer 里"创建新行"而不是"下移光标"。

**调查路径**：
1. 查全局 `keybindings.el` → 已绑 `next-line`，看起来正常。
2. `C-h k C-j` 在 Org buffer → 输出 "Key Bindings: `org-mode-map C-j`"。
3. 定位：Org 内置 `org-return-and-maybe-indent` 绑在 `org-mode-map`。
4. 修复：在 `configs/org/org-mode.el` 用 dispatch 函数分表格内外。
5. 验证：表格内 line 4→5（Org 原语义），表格外 line 7→8（next-line 语义）。

**经验**：不要只看 `global-map`，**`describe-key` 的 "Key Bindings" 一行是金标准**。

### Case: minor-mode-alist 顺序导致全局键被劫持

**症状**：某些 buffer 里 `C-x C-s` 不保存而是干别的。

**调查路径**：`describe-key` 看是不是 `magit-mode-map` / `company-mode-map` 等劫持。然后看该 minor-mode 是哪个 hook 启动的，是不是 hook 顺序错了。

### Case: use-package :bind 的位置问题

**症状**：`use-package foo :bind (("C-c f" . foo-function))` 写了但 `C-c f` 没生效。

**调查路径**：检查 `:bind` 是放在 `:init` / `:config` / 顶层？`:bind` 默认在 load 时执行，如果 use-package 因为 `:disabled t` 或依赖未满足没 load，键位就没注册。

## Pitfalls

- **不要被 `lookup-key global-map` 的结果误导**——它只能告诉你 global-map 写了什么，不能告诉你当前 buffer 实际生效的是哪一层。**始终用 `describe-key` / `C-h k` 当 ground truth**。
- **`where-is-internal` 的输出顺序**就是查找优先级，找到第一个匹配就返回。如果输出里既有 global 又有 local-map，先看 local-map 那个——它就是当前真正生效的。
- **`with-temp-buffer` 测试时要手动 `(insert "...")` 然后 `(major-mode)`**——temp buffer 默认是 fundamental-mode，直接 dispatch 测的是 global 而不是 local-map。
- **daemon 模式下修改了 `~/.config/emacs/` 不等于 reload**——运行中的 daemon 持有旧的 byte-code。要么重启 daemon，要么用 `emacsclient --eval '(load-file ...)'` 显式 reload（只对当次 session 有效，新文件还要重启）。
- **修复后 byte-compile 报错不要忽略**——常见的是括号不匹配、变量未定义、use-package 写错位置。Lint 比 runtime error 容易定位得多。
- **不要把覆盖写在 `keybindings.el` 里**——它是全局约定层，buffer-local 覆盖应该靠近对应的 mode 配置，否则以后读 keybindings.el 会被一堆 mode-specific 异常搞糊涂。
- **看到用户截图不要用 `browser_vision`**——`browser_vision` 是 `browser_navigate` 之后给当前页面截图的，无法处理图片附件。处理图片附件应该用 `vision_analyze(image_url=...)`（主模型有视觉时直接 attach 到上下文，没有时回退到辅助 vision 模型）。
- **`clarify` 的选项只能写在 `choices[]` 数组里**——把选项枚举进 `question` 字符串里会被渲染成死文本，用户无法勾选。question 字段只放问题本身，options 全部独立成 `choices[]` 的元素（最多 4 个 + 自动追加 Other）。
- **face 调整时不要假设 `:width` / `:height` / `:kerning` 都生效**——某些版本的 Emacs（特别是无 GUI 的 daemon）`set-face-attribute` 会拒绝 `:width nil`（重置语义），但接受 `:width 'ultra-condensed`。改动前先用 `(face-attribute 'foo :width)` 探一下当前值再设。
- **face `:width 'ultra-condensed` 在 fontconfig 后端 + Nerd Font 字族（如 Maple Mono NF CN、JetBrainsMono Nerd Font）下视觉上不生效**——`set-face-attribute` 接受这个值、`face-attribute` 也能查回正确的值，但渲染层只做字符级 glyph 缩放、不压缩等宽字符列宽，肉眼看不出区别。修复行号列宽度这类问题不要走 face `:width`，改用 `display-line-numbers-width` 减 1 + `set-window-fringes 0` 之类直接控制列宽 / gutter 的手段（见下面"典型 Case: 行号列与正文之间留白过大"的修订版修复）。
- **GUI 视觉调整必须先实测再固化配置**——遇到用户报告"行号列太宽"之类问题时，**第一动作不是改配置**。先用 `emacsclient --eval` 在运行中的 daemon 上试调 `display-line-numbers-width` / `set-window-fringes` / face 属性，让用户看当前 buffer 效果；用户确认方向后再写进文件。否则可能改了一堆、视觉无变化、甚至改错地方（如本会话曾先在配置里加 `custom/tune-line-number-faces` 用 `:width 'ultra-condensed`，结果 reload 后视觉无变化才回退）。
- **处理用户图片附件不要用 `browser_vision`**——`browser_vision` 是 `browser_navigate` 之后给当前浏览器页面截图用的，处理图片附件应该用 `vision_analyze(image_url=...)`。主模型有视觉时直接 attach 到上下文主模型自己看，没有时回退到辅助 vision 模型。判断依据：用户截图、引用本地文件路径（`~/.config/Hermes/composer-images/...`）的图片，都是 `vision_analyze` 而非 `browser_vision`。
- **`clarify` 工具的 `choices[]` 数组不要嵌进 `question` 字符串**——工具会把 `question` 渲染成纯文本标题、把 `choices[]` 渲染成可勾选 row。把"1) A 2) B 3) C"塞进 `question` 字段，用户看到的就是一段散文，没有 row 可勾。正确做法：`question="你想用哪种方式？"`，`choices=["A. 方式一描述", "B. 方式二描述", ...]`，最多 4 个 + 自动追加"Other"。本会话曾两次把空 `choices` 传出去（只放 `[""]` 占位），UI 仍然渲染不出选项——这种"看起来传了 choices 实际没传"的 bug 不容易被抓到，每次发完澄清都要回头看返回的 `choices_offered` 字段确认 UI 真的收到了选项。
- **buffer-local 覆盖放在 mode-map 已有的同源块旁边**——比如 Org 的 `org-mode-map` 在 `configs/org/org-mode.el` 已经有 TAB / S-TAB 的显式覆盖块，新加的 C-j 覆盖应该紧跟其后、共享同一段注释说明；不要散到文件其他位置或别的 mode 配置文件里——以后删 mode 时能一起删，读起来也容易知道哪些键是"mode 内显式覆盖"。

## 视觉 / face 调试工作流

face 类问题（行号列间距过大、高亮颜色不对、字体宽度不统一）和 keymap 类问题的诊断路径**完全不同**——没有 `describe-key` 这种"一键 ground truth"，需要按 face 名逐个探测。

### 通用诊断步骤

1. **先确认 face 在当前 Emacs 版本下支持的属性**。逐个探测：

   ```bash
   emacsclient --eval "(let (ok bad)
     (dolist (p '(:foreground :background :height :width :weight :slant :underline :box))
       (push (condition-case nil
               (progn (set-face-attribute 'line-number nil p nil) p)
             (error (cons p 'bad))) ok))
     ok)"
   ```

   看到 `:width` 出现在 `bad` 列表里，说明这个 Emacs 不支持 face :width 直接重置——但接受**作为值**（如 `'ultra-condensed`）。

2. **读当前值，确认是不是默认值（unspecified）**：

   ```bash
   emacsclient --eval '(face-attribute '\''line-number :width)'
   emacsclient --eval '(face-attribute '\''line-number :family)'
   ```

   返回 `"unspecified"` 说明 face 没被显式设置，继承自父 face 或默认。

3. **用 `set-face-attribute` 改；改完立即用同一表达式读回**——避免"我以为改了但其实没生效"的盲区。

4. **主题会覆盖 face**——`set-face-attribute` 改完后用户切换主题，新主题会重置 face。要么用 `:custom` 在 use-package 里设，要么挂 `after-load-theme-hook` 钩子确保主题加载后再覆盖一次。

5. **daemon 模式下修改配置文件 ≠ 立即生效**——跟 keymap 类问题一样，daemon 持有旧 byte-code。要么重启 daemon，要么 `load-file` 改了的 .el 文件。**纯 face 改动也跑一遍 reload 流程**，不要假定 daemon 会自动重读。

### 典型 Case: 行号列与正文之间留白过大

**症状**：4 位数行号 + Emacs 默认 `line-number` face 的 normal 宽度 → 行号与正文之间有 ~5 个字符的留白，看起来松散。

**根因**：两层叠加——
- `display-line-numbers-mode` 在每个行号**末尾硬编码加 1 个空格**（避免数字紧贴正文，渲染层行为，没有变量能关）。
- 默认 `line-number` face 的字符宽度 = normal，等宽数字本身就比较宽。
- **加上 buffer 左边的 8px fringe gutter**，这是视觉留白的主要来源之一（很多人会漏掉这一层）。

**⚠ 常见错误修复**：调 `(set-face-attribute 'line-number nil :width 'ultra-condensed)`——`set-face-attribute` 会接受这个值、`face-attribute` 也能查回正确值，但**在 fontconfig 后端 + Nerd Font 字族下视觉上无效**。这条路径走过、走过、走过，三次验证都是无效。如果用户用了 Nerd Font，方向就是错的。

**正确修复**（按贡献从大到小叠加）：

```elisp
;; 1. 去掉左侧 fringe gutter（视觉留白的主要来源之一）
(set-window-fringes (selected-window) 0 nil nil)

;; 2. 减少行号列宽度（比最大行号少 1 位，永远少 1 位避免滚动时整列跳变）
(setq display-line-numbers-width
      (max 2 (1- (length (number-to-string
                          (line-number-at-pos (point-max) 'absolute))))))

;; 3. 挂回 find-file-hook 让每个文件打开时自动生效
(add-hook 'find-file-hook
          (lambda ()
            (when (and buffer-file-name global-display-line-numbers-mode)
              (setq display-line-numbers-width
                    (max 2 (1- (length (number-to-string
                                        (line-number-at-pos (point-max) 'absolute))))))
              (set-window-fringes (selected-window) 0 nil nil))))
```

**为什么是 `位数 - 1` 而不是 `位数`**：Emacs 默认 `display-line-numbers-width = nil` 时会按可见最大行号决定列宽，跨千行/万行时整列"跳一下"。固定宽度消除了跳变；少 1 位是因为 `display-line-numbers` 已经在每个行号末尾硬编码加了 1 个空格，那个空格会占掉一格宽度，所以列宽设 `位数 - 1` 时视觉上刚好对齐。

**调试流程**（强调实测再固化）：

1. **不要直接改配置**。先用 `emacsclient --eval` 在运行中的 daemon 上对当前 buffer 试调：
   ```bash
   emacsclient --eval "(progn
     (setq-local display-line-numbers-width 3)
     (set-window-fringes (selected-window) 0 nil nil)
     (json-encode (list (cons \"w\" display-line-numbers-width)
                        (cons \"f\" (window-fringes (selected-window))))))"
   ```
2. **让用户看当前 buffer** 确认方向。用户确认后再写进 `configs/ui/appearance.el` 之类的文件。
3. 写完同样用 `load-file` reload 验证；确认 byte-compile 无误。

**注意**：终端（TTY）模式下 `set-window-fringes` 对 ANSI 字体也有意义，但 `display-line-numbers-width` 本身是按 frame 参数工作的，TTY 下要不要收紧看仓库约定。

**验证**：

```bash
emacsclient --eval '(face-attribute '\''line-number :width)'
# 不再期望 "ultra-condensed"，而是期望 unspecified（因为正确方案不走 face :width）

emacsclient --eval '(window-fringes (selected-window))'
# 期望 [0, 8, nil, nil] 或 [0, 0, nil, nil]

emacsclient --eval 'display-line-numbers-width'
# 期望比 buffer 实际行号位数少 1
```

## Related

- 用户 Emasc 配置的具体修改流程（哪些文件、改完怎么 reload）由各 emacs 配置仓库的 AGENTS.md 规定——这个 skill 只管"怎么定位问题"和"修复该写在哪里"，不重复仓内维护协议。
- 测试用的 `emacsclient --eval` 表达式模板见 `references/probes.md`。
