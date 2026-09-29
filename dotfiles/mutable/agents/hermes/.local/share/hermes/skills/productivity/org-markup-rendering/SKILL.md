---
name: org-markup-rendering
description: 修复 org 标记不渲染：= foo =、：=cmd=、**X* *、双星混写。
version: 0.1.0
author: brokenshine
license: MIT
metadata:
  hermes:
    tags: [org-mode, emacs, markup, rendering, documentation]
    related_skills: [cjk-doc-normalization, agenote-base]
---

# org-markup-rendering — org 行内标记渲染的修复与验收

## When to Use

- 用户报「org 格式不渲染 / 标记没生效 / 检查 org 渲染」，或贴出 `= foo =`、`：=cmd=`、`**X* *` 这类写法。
- 修改 emacs.org / README.org 等 org 文档后，需要验收渲染效果（真机 tmux 方法见 §4）。
- 维护 / 修正 orgfmt 等 org 格式化器：误修、漏修、块内标记被跳过、双星混写。
- 交付前要保证「所有格式都能正常渲染」时。

Emacs org-mode 的行内强调（`*bold*` `/italic/` `_underline_` `=verbatim=` `~code~` `+strike+`）有严格的字符邻接规则，违反其一即**静默失效**：不报错、不警告，只是不渲染、显示为字面符号。中文技术文档最常踩两类——全角标点/汉字紧贴标记、Markdown 双星习惯混入。

**正确性标准是 Emacs 真机渲染**，正则/文本检查只是手段；用户明确要求以真机渲染为准（方法见 §4）。

## 1. 渲染失效规则（全部实测得出）

| 写法 | Emacs 渲染 | 修复 |
|---|---|---|
| `：=foo=`、`（=X=）`、`，*X*。` —— 标记外侧紧贴全角标点/汉字 | **失效**（显示字面符号） | 外侧补空格：`： =foo=`、`（ =X= ）` |
| `= foo =` —— 内侧首尾带空格 | **失效**（不识别为标记） | 内侧去空格 `=foo=`；**仅当内容为单一无空白 token 时安全**，含空格/中文的叙述性内容保守保留 |
| `**X**`、`**X* *` —— Markdown 双星混写 | **失效**（org 无 `**` 语法，`**X**` 也一样不渲染） | 收敛为单星 ` *X* ` |
| `= *X* =` —— 两层包裹混用（等号内夹星号） | 混乱（外层不渲染，内层语义不明） | 禁止在同一内容上混用两种标记；按意图归一——内容本身含星号（如 buffer 名）写 `=*X*=`（verbatim 内字面星号，合法）；只想要加粗就写 `*X*` |
| `： =cmd=`（外侧有空格） | **正常** | 保持 |
| `=*Help*=`（verbatim 内容含星号） | **正常**（星号是内容） | 保持 |

用户规则（原话，照此执行）：**「不管是什么格式，都要求包裹用的符号两侧为空格，包裹内紧贴符号」**；**「混用了两个格式在一个字符上，这个是不允许的」**。

判据补充：

- **外侧补空格只在中文语境**（全角标点或 CJK 邻接）。ASCII 邻接（`word=foo=`、`x=1`）不补——那可能是程序文本，不是强调。
- **错配（非真标记）的签名**——修复器据此拒绝改动：配对端点紧邻另一标记字符；配对内容含 CJK 句读（，。、；：？！）；内容纯空白。典型来源是 finditer 式非重叠扫描把「甲对右界 + 中间文本 + 乙对左界」撞成一个对，跨段吞并会改坏正文。
- 真机判读基线：`-Q` 下 `org-hide-emphasis-markers` 默认 nil——**标记符号本身仍显示**；「渲染正常」的判据是**内容带 face**（bold / verbatim），不是符号消失。渲染是否发生由 org 语法决定，与主题无关；face 外观则受配置影响。

## 2. 块上下文——哪些区域要修

行级块状态机最常见的 bug：把**所有** `#+begin_xxx` 当代码块跳过 → note / tip / quote / verse 等富文本块里的正文标记全部漏修（而这些块常承载文档的说明主干）。正解：**只有 `src`、`example`、`comment`、`export` 是代码块**（内容原样不动）；其余 `#+begin_*` 块内容按正文档照常检查。

## 3. 诊断：找到不渲染的标记

**单点探针**（判一个片段/位置是否产生渲染对象）：

```bash
emacs --batch -q --eval '
(progn
  (require (quote org)) (require (quote org-element))
  (with-temp-buffer
    (insert "（=C-<tab>=）")
    (org-mode) (font-lock-ensure)
    (org-element-map (org-element-parse-buffer)
        (quote (bold italic underline verbatim code strike-through))
      (lambda (o) (message "%s: %S" (org-element-type o)
                   (buffer-substring-no-properties
                    (org-element-property :begin o)
                    (org-element-property :end o)))))))' 2>&1
```

不渲染的标记**不产生任何对象**（对象数 0）——这就是判据。要点：先 `(org-mode)` + `(font-lock-ensure)` 再 `org-element-parse-buffer`；对象 `:end` 含尾随空白（范围判定时记得）。

**全文扫描**：收集所有强调对象的 `:begin`/`:end` 区间 → 对全文每个标记字符位置（`=` `~` `*` 等）查是否落在某区间内 → 未被覆盖者为候选。排除项：行首 `*`（标题/列表）、`#+begin_src` 等真代码块内容、转义语法。修复后重扫，候响应明显收敛；残余逐条给出理由（有意保守保留的项要能说明为什么）。

## 4. 真机渲染验收（tmux；用户指定的验证方式）

独立 socket + 干净配置（`-Q`），**不碰用户正在跑的 daemon/会话**：

```bash
tmux -L orgver new-session -d -s v -x 220 -y 50
tmux -L orgver send-keys -t v 'emacs -nw -Q --eval "(progn (find-file \"/abs/path/file.org\") (goto-line 576) (recenter 5))"' Enter
sleep 6
tmux -L orgver capture-pane -t v -p | sed -n '1,20p'            # 文本
tmux -L orgver capture-pane -t v -p -e | sed -n '23p' | cat -v   # 带转义
```

三个已踩的坑（都有解）：

1. **`emacs -nw FILE --eval EXPR` 里 EXPR 的执行上下文不是文件 buffer**（实为 scratch，`goto-line`/`recenter` 落空）。把 `find-file` 写进 eval 内：`--eval "(progn (find-file \"...\") (goto-line N) (recenter 5))"`。
2. **文件带折叠设置（`#+STARTUP: content` 等）**：goto 到位后屏幕可能仍显示折叠区，「看起来没跳」。先发 `C-u C-u C-u TAB` 全展开再跳；mode-line 的 `L<n>` 字段可确认真实行号。
3. **超长行在窄终端被物理截断**：220 列看不全目标文字时，另起更宽的 session（`-x 400`）打开同一行再 capture。

跳转/滚动按键：`send-keys M-g` → 稍候 `g` → 行号 → `Enter`（分开发送、带间隔，整串一次发会丢）；`C-l` recenter。目标行停在屏幕下缘外时，跳转后屏面可能不动——改跳其下方几行再 `C-l` 居中即可。取转义先在 capture 上用 `grep -n` 现找目标词所在屏面行号（≠ 文件行号）再 `sed -n '<行>p'` 截取；无命中说明不在可见范围（未滚到，或超长行被终端宽度截断，见上条 3）——先解决可见性再判读。转义判读：

| 转义 | 含义 |
|---|---|
| `^[[1m…^[[0m` | bold（`*X*` 渲染生效） |
| `^[[38;2;179;179;179m…^[[39m` | verbatim face（`=X=` 生效，灰色 RGB 179） |
| `^[[38;2;238;221;130m…` | org 标题 face（用于确认落对区域） |

清理：`tmux -L orgver kill-session -t v`；`kill-server` 可能被安全 hook 拦截，杀掉 session 即够。

**抽查要求**：每类修复（外侧补空、内侧去空、双星、块内修复）至少选一个代表点真机看，转义证据留进汇报。

## 5. 修复流程

1. **备份与基线**：`cp file.org /tmp/file.org.orig` + `sha256sum` 记录。
2. **修复产物先落 /tmp**（绝不直改源文件），`diff -u` **逐条审查每条变更**——重点抓两类误伤：多标记行的跨段错配、ASCII 邻接处误插空格。
3. **幂等校验**：对产物再跑一次修复，应 0 变更。
4. **落盘**：`sha256sum` 复核源文件未被并发修改（哈希一致才 `cp /tmp/产物 源文件`）。
5. **重扫**（§3）：候选收敛、残余逐条解释。

修复器实现（`orgfmt`，agenote 项目 `~/Projects/agenote/agenote/` 的 `src/agenote/orgfmt.py`）的设计要点：外侧补空仅中文邻接；内侧去空仅 `=` 且单一 token；双星规则加前视 `(?<![=~*])` 保护 verbatim 内字面星号、首字符排除空白/星号以保护 `** ` 标题；§1 的错配签名内置为拒绝条件。用 `--check` 只读报告；**只应用标记类变更**（其它规则是别的口径，见 `cjk-doc-normalization`）。

**教训（真实踩过）**：修复函数「单行测试通过」≠「全文档生效」——块状态误判会让整个 note/tip 段静默漏修（函数单跑正确、跑全文件没改）。**验收必须跑整个真实文件并对比输出**，单测只算一半。

## 6. 交付清单

- [ ] diff 每条变更可解释（无跨段错配、无 ASCII 邻接误插）
- [ ] 幂等（二次运行 0 变更）
- [ ] 全文扫描候选收敛，残余有理由
- [ ] tmux 真机抽查 ≥3 类修复点，转义证据在手
- [ ] 落盘前 sha256 一致；`git status` 复核工作区只含本任务文件
- [ ] 汇报三态：已验证（附命令/证据）｜未验证（说原因）｜保守保留（说理由）

## 7. 提交与发版（orgfmt 修复的收尾，agenote 仓库）

修复过 §6 验收后收尾；发布口径以仓库 AGENTS.md 为准，以下为实操要点与其补充：

1. **提交消息用 `-m` 传**：本环境 hook 拦截 `git commit -F -`/heredoc 形式（报「git commit 必须使用 -m 指定提交信息」，且整条命令被拒——同一命令链里的 `git add` 也不会执行，重试前先 `git status --short` 复核暂存）；多行消息直接写在 `-m` 字符串内。行为改动在同一提交内同步 CHANGELOG 条目。
2. **`Co-authored-by` 按当前宿主/模型现填**：模型从会话环境读，勿照抄先例字面量（先例常属别的 agent，宿主名/模型/邮箱域均不同）；Hermes 会话的既定邮箱域是 `noreply@nousresearch.com`。不确定时反查先例：`git log --format='%B' | grep 'Co-authored-by: <宿主名>'`。
3. **签名**：仓库 `commit.gpgsign=true`，提交即自动签名；提交后 `git log -1 --format='%G?'` 应为 `G`（GPG 不可用时退回 `--no-gpg-sign`）。
4. **发版 = 一个独立 release commit**（`chore(release): 发布 vX.Y.Z`）：同时含 `pyproject.toml` 版本、`uv lock` 刷新后的 `uv.lock`（输出 `Updated agenote v旧 -> v新` 即同步）、CHANGELOG；提交前 `uv run pytest tests/ -q` 全绿。
5. **CHANGELOG 滚动**：把 `## [Unreleased]` 的累计内容整体转为新段 `## [X.Y.Z] - <date>`（日期用 `date +%F`），保留空的 `## [Unreleased]` 标题；每段以一行导语开头，再接 `### Added`/`### Fixed`。惯例存疑先对比先例：`git show <先例提交> -- CHANGELOG.md` 与其 `^` 版本。
6. **边界**：bump 做到 release commit 为止；annotated tag（`git tag -a vX.Y.Z`）与推送（`git push origin main vX.Y.Z`，推后 `git ls-remote --tags` 自查）属对外发布——等用户明确指示再做。

## Related

- 格式化器嵌入、标点口径、整仓批处理安全 → `cjk-doc-normalization` skill（§6 与其 formatter-integration 参考文件）
- agenote 卡片 org 格式对照 → `agenote-base` skill 的 markdown-to-org 参考文件
