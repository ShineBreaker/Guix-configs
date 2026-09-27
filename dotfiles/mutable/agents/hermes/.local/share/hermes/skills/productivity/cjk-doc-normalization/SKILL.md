---
name: cjk-doc-normalization
description: "Normalize punctuation across a Chinese doc set. 去 AI 味。"
version: 0.1.0
license: MIT
metadata:
  hermes:
    tags: [chinese, documentation, punctuation, style-guide, batch-rewrite, cjk]
    related_skills: [doc-engineering, zh-tech-doc-style-guide, unslop]
---

# 中文技术文档规范化（整仓批处理）

Applies a punctuation/writing standard across many files at once. Use when the
ask is "按某个写作规范重写所有文档 / 标点规范化 / 去 AI 味", or when auditing a
doc set's punctuation conventions.

The work is **mostly mechanical**, which is exactly why the failure mode is
silent mass corruption: a regex that looks right rewrites 77 Scheme code blocks
and the build breaks hours later.

**Sibling skills**: `zh-tech-doc-style-guide` = the rules (which punctuation is
correct). `unslop` = the English AI-tell patterns. `doc-engineering` owns
drift-checking and structural rewrites. This skill = how to apply any of them
across a whole repo safely.

## 1. Workflow

### Step 1 — Inventory before touching anything

**先确认工具的目标格式。** 宿主格式化器往往只对自己的原生格式安全：把它作用在
另一种格式（如把 org 格式化器跑在 Markdown）上，写盘模式会静默破坏内容。判定动作
是**在临时副本上跑一次写盘模式并读 diff**：

```bash
cp README.zh.md /tmp/probe.md && orgfmt /tmp/probe.md && diff README.zh.md /tmp/probe.md
```

若 diff 出现「`**加粗**` 变 `*加粗* *`」「中文标题 `—` 前后空格被删」「多出空行」
这类改写，说明该工具对目标格式**只读安全、写盘不安全**。此时的正确姿势：

- 只跑 `--check` 读诊断，且只采纳**格式无关的行内规则**（「中英文之间补空格」
  「全角标点旁多余空格」）。
- 丢弃按宿主原生格式算出来的诊断：表格列对齐、空行规范化、`*bold* 后缺空格`
  （后者是把 Markdown 的 `**` 误认成 Org 粗体）。
- 另有一类固有误报：Markdown 锚点链接（`#知识库根kb_root`）会被判为「中英文之间
  补空格」，那是 Markdown 语法本身，不能改。
- 把这条限制写进任务委派（subagent）的前置说明，不要等它跑完再纠正。

这个判定要在 Step 1 做，因为它决定后面每一步能不能写盘。

**先定文档的职贵，再定排版。** 同一批文档里 README 与 `docs/usage.md` 是两类东西：
前者回答「这东西解决什么问题、值不值得用」，后者回答「怎么操作」。命令面、键位表、
配置项只应在后者出现一份。若 README 里的「为什么用 X」每条都是机制描述，说明
它被写成了使用手册：先改结构（产品定位 → 不适合谁 → 能力），再谈标点。反过来，
`docs/usage.md` 不需要「不适合谁」这类市场判断，别把它搬过去。

Count violations per file per pattern, so you know the blast radius and can
tell "one file is dirty" from "the repo has no convention":

```python
import re
HAN = r"一-鿿"
pats = [("半角逗号夹中文", r"[\u4e00-\u9fff],|,\s*[\u4e00-\u9fff]"),
        ("半角冒号夹中文", r"[\u4e00-\u9fff]:|:\s*[\u4e00-\u9fff]"),
        ("破折号空格", r" ?—— ?"),
        ("英文省略号",   r"\.\.\."),
        ("中英无空格",   r"[\u4e00-\u9fff][A-Za-z0-9]|[A-Za-z0-9][\u4e00-\u9fff]"),
        ("斜杠并列",     r"[A-Za-z\u4e00-\u9fff] / [A-Za-z]")]
```

Exclude vendored trees (third-party dirs shipped inside the repo), agent skill
libraries, and session scratch (workfile/plans) — rewriting those corrupts other
people's content and shows up as unrelated diff noise.

**Separate code blocks from prose before counting.** A repo-wide count over raw
text tells you nothing, because in a literate-programming `.org` file most
Chinese-looking lines sit inside `#+begin_src`. Counting prose separately is what
makes the number actionable.

**Enumerate with `git ls-files` and compare against the script's own walker**
before trusting the file count — see §4 for why glob under-reports.

### Step 2 — Write the script BEFORE running it on real files

Ship a `--check` mode that reports-and-does-not-write as the first invocation
against real files. Never make the first run a mutation.

### Step 3 — Self-check with fixtures, then run the suite

The script must ship a self-check asserting both directions: what MUST change and
what MUST NOT. Minimum fixture set:

```bash
python3 tools/cjk-punct.py --self-test
```

Required cases (each one is a false positive someone will hit):

| Fixture | Asserts |
| ------- | ------- |
| `中文,后面` | half-width comma → full-width |
| `a,b,c 全是英文` | English list untouched |
| `This is pure english, no CJK` | whole-English line untouched |
| `` `a,b` 和 c,d `` | inline-code span untouched |
| `参见 https://x.cn/a,b` | URL untouched |
| `版本 v1.2.3 发布` | version number not treated as ellipsis |
| `\| a \| b... \|` | table truncation marker not treated as ellipsis |
| `概念 —— 说明` | em-dash spaces removed |
| `概念—说明` | single 一字线 (连接号) left alone |
| `#:NAME: 块: 值` | org block name untouched |
| `主:次 root` | field-format spec untouched |
| `0=NM默认 2=disable省电` | compact enum untouched |
| `` 在 NM `[connection]` 段写 `` | config-key name untouched |
| `#+begin_src … 中文,原样 … #+end_src` | **entire code block byte-identical** |

The last one is load-bearing. If the self-check doesn't assert code blocks
survive, the script is not ready to run.

### Step 4 — Run, then independently verify code blocks by hash

Mechanical edits report symmetric insert/delete counts; that is necessary but not
sufficient. Prove the code blocks are untouched:

```python
def blocks(text):          # org; same shape for ``` fences
    out, cur = [], None
    for l in text.split("\n"):
        s = l.strip()
        if s.lower().startswith("#+begin_"): cur = [l]; out.append(cur); continue
        if cur is not None:
            cur.append(l)
            if s.lower().startswith("#+end_"): cur = None
    return out
# compare sha256 of joined blocks before vs after; must be identical
```

Run the repo's own validator too (`blue check`, `make check`, whatever the
project has) — but see §4 on when its own tooling is unavailable.

## 2. CJK-vs-English boundary (the part that decides correctness)

Most apparent "violations" in a technical doc are English, not Chinese, and
converting them corrupts meaning. The judgement per construct:

| Construct | Rule | Trap |
| --------- | ---- | ---- |
| `, ; : ? !` | Full-width **only when it separates Chinese**. Judge by "is one side a 汉字", not "is the line mostly Chinese" — a Chinese sentence routinely holds a long English fragment. | Line-level ratio converts `a,b` inside a Chinese line |
| `(` `)` | Full-width iff the **contents** contain a 汉字. Contents are English → keep half-width even inside a Chinese sentence. | Line-level judgement converts `(c,d)` and `(only english)` |
| `……` vs `...` | `...` → `……` only when neither neighbour is alnum and it's not a table-truncation marker. | Version numbers, `find . -exec …` idioms |
| `——` vs `—` | Strip spaces around `——` only. `—` is a 连接号 (range / compound-noun); its spacing is correct. | Converting `—` to `——` |
| 中文标题里的一字线 | 一字线前后**不**加空格。`# 项目 — 说明` 违规，但删空格得到 `# 项目—说明` 粘连，正确写法是换冒号：`# 项目：说明`（英文 `# project: description`）。 | 只删空格不换标点，得到粘连标题 |
| 全角空格 U+3000 | 它是全角空格不是半角。拿它做「加粗标签 + 内容」分隔（`**卡片**\u3000内容`）会被判违规，要分隔就用普通空格加句号或独立小标题。 | 当成合规的排版间隔保留下来 |
| ` / ` | 顿号 for **natural-language** parallel items only. Slash-separated **identifier lists** are the industry norm. | Turning `electron / qt5 / gtk` into `electron、qt5 和 gtk` |
| 粗体标签 `**X**：` | **Keep.** See §3. | Deleting every bold lead-in |
| `![图](x.png)` 的 `!` | Never convert. The half-width `!` is markdown image syntax, not prose punctuation. | `![` → `！[` breaks every image in the file |
| `： =cmd=` / `： *粗体*` 的空格 | **Keep.** Spacing after full-width punctuation before an inline-markup opener (`=`, `` ` ``, `*`, `_`, `~`) is typesetting convention; gluing punctuation to markup reads worse. | A blanket "no space beside full-width punctuation" rule mangles every org gloss `： =C-c g s=` |

## 3. Do not port English rules to Chinese unchanged

Two English rules are correct in English and wrong in Chinese. Applying them
blindly damages compliant documents:

- **unslop #13 (ban em dash).** Chinese `——` is a GB-standard punctuation mark
  with its own rule (no space before/after). A repo with 89 `——` uses is already
  correct. The English rule targets overuse as a crutch separator.
- **unslop #16 (ban `**Label:** text`).** The tell is a label that *restates* the
  line (`**Performance:** Performance improved…`). A Chinese label that *names*
  the item and is followed by new information (`**部署方式**：软链到仓库源`) is the
  dominant convention in Chinese technical writing and is the opposite of a tell.

Verify before assuming a doc set is dirty: run the pattern counts and check
whether the "AI tells" are near zero. A repo whose prose carries concrete numbers,
measured evidence, and no puffery needs punctuation work, not a voice rewrite.

## 4. Pitfalls

- **`startswith("")` is always true.** A fence state machine that stores an empty
  sentinel for org blocks (`#+begin_src` has no closing fence token, only
  `#+end_src`) silently treats every following line as inside a block — or,
  inverted, processes block contents as prose. Symptom: the report shows dozens of
  "violations" inside Scheme code. Use a distinct sentinel and match the *end*
  keyword.
- **Never mutate on first run.** `--check` first, read the report, then write.
- **Don't treat a project's own validator as the only check.** If it is
  unavailable (build tooling broken independently of your change), say so in the
  report rather than implying it passed — and supply the independent evidence
  (block hashes) that you did verify.
- **Expect to iterate the self-check.** Each failed assertion is a real over-broad
  rule; fix the rule, not the expectation — unless the expectation was simply wrong
  about the standard, which happens when you misremember a rule's scope. Verify
  the standard before weakening an assertion.
- **Distinguish your diff from pre-existing dirt.** `git status` at session start
  may show submodule bumps and unrelated edits. Re-check before staging so the
  commit contains only your work.
- **Don't rewrite vendored third-party trees** (e.g. an input-method dictionary
  bundle's upstream READMEs) even when they are the worst offenders in the tree.
- **Enumerate the host format's non-prose lines BEFORE writing rules.** `:EFFORT:
  8h` gets `8 h` inserted, `DEADLINE: <... +1w>` gets its repeat cookie flagged as
  a bad abbreviation, and inline `$x^2$` gets treated as prose — all from one
  class of miss: the line filter only knew "code block / table / blank". Walk the
  real files once and list every non-prose line kind (org metadata
  `DEADLINE/SCHEDULED/CLOCK`, `#+KEYWORD`, property lines *with* values, `$$`
  math) as explicit guards. One missing guard is one real-file false positive.
- **Scan per-position, never `re.sub` a whole line, when the rule needs
  position-dependent skipping.** `[connection]段`, `0=disable省电`, and text
  right after a leading `- **` / `#` / `[` / `=` / `~` marker all need "no space
  here" — a line-wide substitution inserts spaces in every one of them.
  Per-position scanning also means matching characters with `.match()`, since
  `ch in compiled_pattern` is not valid.
- **Recompute protected spans after every length-changing stage.** A rule that
  inserts or deletes characters inside a line (full-width conversion, space
  deletion, `...` → `……`) shifts the indices of every span computed before it, so
  the next rule's "is this position inside code" test passes on the wrong bytes
  and edits inside inline code — the corruption is silent and non-idempotent (a
  second run deletes more). Route all length-changing rules through one rebuild
  helper that re-runs span detection after each edit, and make the position guard
  mandatory for every space-deletion rule: inside `=monospace=` or `` `code` `` a
  space is content, never punctuation.
- **Enumerate files with `git ls-files`, not `glob('**/*.md')`.** Glob does not
  descend into dot directories (`.config`, `.local`, `.agents`), so it silently
  skips most of a dotfiles repo — agent contexts, skills, deployed configs all
  live there. Compare the two lists once and reconcile before trusting any
  count or "repo is clean" claim.
- **Adding a skip guard requires a test that the guard still admits the primary
  case.** A version-number guard written as `isalnum()` silently blocks
  `so...that...` (English ellipsis idiom) along with `v1.2.3`; tighten to
  `isdigit()`. An over-broad guard fails exactly like having no guard, just
  later.
- **A stage's reported line numbers cannot index the original file.** Earlier
  stages insert/remove lines, so the numbering is already shifted; trace a
  reported line back with `difflib` against the stage's own input, not by line
  number.
- **Audit a word-level traditional-Chinese list for 繁简同形 entries.**
  Single-character detection is unusable (行/化/文/表 are valid in both
  scripts), but even word lists ship false positives: 修改, 警告, 伺服器, 滑鼠,
  新增, 排序, 支援, 同步, 循序, 功能表, 工具列, 核取 are identical in both
  scripts. Verify each entry's simplified form differs before it earns a place in
  the table.
- **Capability lists are not product statements.** A section headed 「为什么用
  X」 whose every bullet is a mechanism (zero-drift, zero-spawn, idempotent)
  tells the reader what the code does, not what problem it solves. Before
  normalizing prose, ask what the doc is *for*: if a reader could finish it and
  still not know whether to use the product, the structure is the defect and
  punctuation work is beside the point. The differentiating claim usually goes
  unmentioned — check the repo's own artifacts (sample data files, config
  defaults) for the real differentiator and state it with evidence rather than
  adjectives.
- **A capability table in README duplicates the usage doc.** When the command /
  keybinding surface lives in `docs/`, the README table is a second copy that
  drifts. Delete it from the README and point at the usage doc; if the user
  wants a table gone entirely rather than moved, take that option too.
- **Subagent self-reports are claims, not facts.** When fanning out doc rewrites,
  independently verify each child's factual claims against the source of truth —
  grep the constants, run the command, read the function signature. A summary
  saying "all facts cross-check" is worth only what your own grep is. Confirm at
  minimum every number, version, absolute path, and API shape that reaches the
  commit, and re-read the files before committing: a child may have written to
  paths you already reviewed.
- **Don't hardcode machine-specific paths in public docs.** `~/.local/bin/tool`
  and private wrapper-script names are only true on the author's machine. Check
  what actually resolves (`command -v tool`) and write path-agnostic phrasing
  ("the `tool` on your PATH") unless the path is genuinely universal. External
  readers cannot run internal deployment tooling.
- **When fanning out per-repo rewrites, put the shared trap in the delegation
  brief, not just in your own head.** A child that discovers the orgfmt write
  hazard independently still wastes a run, and a child that doesn't will corrupt
  files you then have to detect. State the read-only rule up front.
- **Patch with a whole section as `old_string` and a partial `new_string`
  silently deletes that section.** Re-read the file after any large
  `old_string` before running the suite.

## 5. Reporting

State per-file counts before and after, and separate three outcomes honestly:

- **Verified**: self-check passes; block hashes identical; project validator run.
- **Unverified**: the project's validator could not run (say why — and whether the
  failure predates your change).
- **Skipped**: what you deliberately left alone and the one-line reason (e.g.
  "identifier slash-lists are industry convention, left as-is").

Call out explicitly when a style guide was applied **not** literally, and why — a
future reader otherwise assumes the document complies with the whole guide when it
complies with a defensible subset.

## 6. 规则落在哪：独立脚本 vs 嵌进已有格式化器

写独立脚本（本文 §1-§5）只在宿主没有格式化器时是对的。用户点名「补到 X 里」
就扩展 X——另起工具的代价是两套规则口径漂移，同一条规则两个结果。

嵌进宿主后的固定动作，按序：

1. 读宿主「按块状态迭代行」的那个函数，确认它已同时识别两种格式的块（org
   `#+begin_*` 与 ``` fence）。规则写一次，`.md` / `.org` 共用。
- 把只改行内容的阶段插在**表格对齐之前**——列宽按改后文本算。
2b. **同一行内的每条长度变化规则都要重算保护区间。** 全角标点转换、删空格、
    `...`→`……` 都改变行长，先前算好的「行内代码 / org 等宽 / 粗体」span 下标
    全部错位，后续规则按陈旧下标判断，改的就是 span 外的字符。做法：所有
    长度变化规则共用一个 rebuild 帮助函数，每改一次就重跑一次 span 检测；
    每条删空格规则都强制查 span（等宽/行内代码里的空格是内容，不是标点）。
    症状是静默且不幂等的：第二遍扫描还会继续删。
3. 按 §4 枚举非正文行，逐个加守卫。
4. 语义级规则一律只报不改。

落地后的验证阶梯（每级都要过，不能跳）：自检 fixtures → 全量测试套件（查既有
阶段回归）→ 真实文件 `--check`（这一步才抓得到守卫漏项）→ 幂等（连跑两次比
哈希）→ 评估能不能当 CI 门禁。

**最后一级的评估标准不是「退出码非零」，而是「诊断信噪比」。** 宿主格式化器在非
原生格式上的诊断里，表格列对齐 / 空行 / `*bold*` 间距这类项永远是噪声，接进 CI
只会养成忽略警告的习惯。判据：噪声项占比高、且无法用格式开关关掉，就不进 CI；
只保留格式无关的行内规则，并把丢弃清单写进 skill 本身。

与另一个已存在的工具重叠时：构造同一份样本让两边都跑，出**能力矩阵**，只对齐
重叠行的口径（守卫条件、跳过范围），不合并代码库。完整决策表见
`references/formatter-integration.md`。

## 7. 接入仓库命令派发器（把独立脚本变成 `blue format`）

脚本验收后，用户通常要一个仓库内命令递归跑全仓。落点是仓库**已有的**命令派发器
（Guix-configs 的 `blueprint.scm` `case` 分支、`justfile`、`Makefile`），不要新写
入口——又一个入口就是又一处会漂移的规则副本。固定动作：

1. 新分支挂进既有命令分类（如 `maintenance`），不改派发结构。
2. dry-run 透传给 `--check`：派发层已有 dry-run 概念时，让 `blue --dry-run format`
   变成 `python3 tools/doc-punct.py --check`，脚本不自己猜模式。
3. 无参 = 全仓，带参 = 指定文件；排除清单（vendored、skill 库、session scratch）
   写进命令本身，不靠调用方记得。
4. 文件枚举走 `git ls-files`（glob 漏点号目录，见 §4）。
5. 验收阶梯跑完再接：自检 → 全仓 `--check` → 实跑 → 二次 `--check` 必须 0 处
   （幂等）→ 跑仓库自己的校验器（tangle / `blue check`）确认结构化工件没被碰坏。
6. 命令跑不起来时，先 `git stash` 掉自己的改动重跑一次，区分「既有环境问题」与
   「自己引入的回归」再下结论；用仓库文档指定的环境（如 `guix shell <tool> --
   <cmd>`）验证，不要据此宣布宿主坏了。

## References

- `scripts/cjk-punct.py` — the runnable normalizer. Copy it into the target repo
  (e.g. `tools/`) and run `--self-test` → `--check` → write, in that order. The
  self-check asserts 21 fixtures covering every row of the §2 table plus
  code-block survival. Extend by adding a fixture first, then relaxing
  `convert()`.
- `references/formatter-integration.md` — load when embedding rules into an
  existing formatter (orgfmt / prettier / a repo's own tool) instead of writing
  a standalone script, or when reconciling two overlapping doc tools: the
  placement decision, the non-prose-line guard table per format, the
  auto-fix vs report-only split, and the verification ladder.
