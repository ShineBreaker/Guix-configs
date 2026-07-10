---
name: cross-system-borrow-design
description: 跨系统借鉴设计 —— 当用户说"用 X 系统的成熟设计改 Y / 借鉴上游参考实现 / 把 Y 的 Z 机制搬过来 / 跨 agent 升级 / 上游设计 port 到本机"时触发。覆盖"先深度对位(现状摸底 × 上游 reference × 缺口矩阵)→ 提炼设计原则(每条标上游 file:line)→ 产出 1000+ 行 PLAN.md(分阶段 + schema 草稿 + 验收清单 + 协同点)"这个 class 的工作。
tags: [design-borrow, cross-system, port, architecture-migration, plan-doc]
metadata:
  hermes:
    tags: [design-borrow, cross-system, port, architecture-migration, plan-doc]
    related_skills: [codebase-scout, task-planner, architecture-advisor]
---

# cross-system-borrow-design — 跨系统借鉴设计

你负责**把上游参考实现(可能是另一个 agent、另一个工具、另一个 fork)的
成熟设计,有结构、有取舍地借鉴到本机目标系统**。这不是简单的"抄一抄",
而是经过对位分析、缺口识别、原则提炼、阶段拆解,产出一份 1000+ 行的
设计文档 + 可执行的分阶段实施计划。

## 风格定调

- **深度对位,不空想** —— 任何"应该这样做"的建议,都必须有上游 file:line
  引用 + 本机现状 file:line 引用。**没看过的代码不许评**。
- **"借鉴"不是"复制"** —— 上游的设计原则要提炼成"为什么",本机的
  实现细节要因地制宜(简化、调整、保留)。
- **大文档,小改动** —— 文档可能 1000-2000 行,但每个 PR 改动要小、
  可独立验收,按"先跑通再漂亮"切分。
- **诚实引用** —— 所有 file:line 引用必须能被 grep 验证存在。**杜撰
  路径 = 文档作废**。写完文档后用 `grep` 或 `find` 校验所有引用。

## 典型触发场景

| 场景 | 上游参考 | 本机目标 |
|---|---|---|
| 借鉴 agent 体系 | `MiMoCode/actor/` | 本机 `atelier` 扩展 |
| 借鉴记忆体系 | `MiMoCode/memory/` | 本机 `agenote` + `kb` |
| 借鉴 skill 注册 | MiMoCode `skill/discovery.ts` 远端 pull | 本机 `~/.config/agents/skills/` |
| 借鉴 review 流程 | opencode superpowers `code-reviewer` skill | 本机 `code-reviewer` skill |
| 借鉴 patch 工作流 | opencode `patch.ts` 工具 | 本机某个 patch 工具 |

**通用判定**:当用户说"X 系统的设计很好,把它搬过来 / 借鉴过来 / 升级本机的 Y",
而不是"重做 Y"或"看 X 怎么做的"时,触发本 skill。

## 五步工作流

### Step 1: 双方都摸清楚(双向侦察)

用 `codebase-scout` 风格深度读,先上游后本机,**两边都要"看代码"而不是
"看 README"**。

- **上游**:核心子系统的入口、`*.ts` 接口、关键算法(50-500 行/文件)。
  至少读:入口 + schema + 主要实现 + 一个测试。**看真实实现**,
  别只信 README 里的"5 大原则"。
- **本机**:对应子系统(本机可能叫别的名)的当前实现 + README +
  最近 commit 记录的痛点。

**侦察产出**:对本机每个子系统,给出一份"能力 × 现状 × 已知痛点"
的三栏表(每栏 1-2 行)。不是文件列表,是"能做什么 / 怎么做的 / 缺什么"。

### Step 2: 缺口矩阵(核心对位工具)

画一张二维表:**行 = 上游能力 × 列 = 本机能力 × 单元格 = 三态(✅/⚠/❌)**。

每个 ❌ 项必须有具体出处:
- 上游:`packages/xxx/yyy.ts:行号-行号`
- 本机:`本机路径:行号-行号`
- 现象(本机实际怎么表现的)
- 痛点(为什么这是问题)

**反模式**:只说"上游有 X,本机缺 X"——必须说出 X 具体是什么、出处在哪、
本机的 workaround 是什么、缺它的具体损失是什么。

### Step 3: 提炼设计原则(从对位到抽象)

不是直接照搬实现,而是提炼**原则**——"为什么上游这样做"。

每条原则结构:
- **名称**(动词性短语,如 "Actor is a first-class persisted entity")
- **正文**(3-5 句,讲"为什么这样设计")
- **上游参考**:`file:line`(具体哪段代码体现了这个原则)
- **本机适用性**(本机是否适用、要不要调整)

**原则数量控制在 5-9 条**。多了记不住,少了对位不够。

### Step 4: 写 PLAN.md(骨架 + 节数固定)

骨架(每节标题固定,不要创新):

```
0. 现状摸底(日期标注)
1. 目标(Outcome) — 4-7 项
2. 设计原则(从上游提炼,5-9 条)
3. 架构图(目标态,ASCII art 即可)
4. 实施阶段(每阶段独立可交付,5-11 阶段)
5. 改动清单(具体文件路径,新增/改动/不动)
6. 风险与缓解
7. 上游参考实现索引(file:line 分类)
8. 落地步骤(PR 粒度,每 PR 可独立验收)
9. 暂不做(防 scope creep)
10. 审核检查清单
11. 变更日志
```

如果文档很大(如本机会话中的 PLAN.md 后续追加了 12-23 节),用
"# 第二部分" / "# 第三部分" 切分,每部分独立"现状摸底 / 实施阶段 / 改动清单"。

**每阶段固定结构**:
- 目标(2-3 句)
- 新增文件(表格,路径 + 作用)
- 改动文件(表格,路径 + 改动内容)
- schema / 协议 / JSON 草稿(代码块,完整可拷贝)
- 关键设计决策(3-5 条,带理由)
- 上游参考(具体 file:line)
- 验收(3-5 条,可命令行实跑)

### Step 5: 写完必须校验(硬约束)

```bash
# 1. 提取所有 file:line 引用,逐个验证存在
grep -oE '/path/to/[A-Za-z0-9./_-]+:[0-9-]+' PLAN.md | sort -u | while read line; do
  path="${line%:*}"
  test -e "$path" || echo "MISSING: $line"
done

# 2. 验证行号范围真实存在(找最大行号)
file_lines=$(wc -l < "$path")
[[ $max_line -le $file_lines ]] || echo "BAD LINE: $line"

# 3. 反引号包裹的"整段路径"是文档语义,不是真的路径(grep 要去掉反引号内的)
```

**反模式**:
- ❌ "凭印象" 写 `file.ts:42` —— 可能是 43 或 44
- ❌ 引用一个不存在的文件路径(常因上游重命名)
- ❌ 引用一个文件但行号超出文件实际行数(常因 git 改动未刷新)
- ❌ 把 markdown 代码块里的"示例路径"当真实引用 grep(会被反引号污染)

## 关键产出物(本 skill 的交付清单)

一次完整的 cross-system-borrow-design 会话,产出 4 件东西:

1. **PLAN.md / DESIGN.md** —— 主文档,1000+ 行,固定骨架
2. **缺口矩阵 + 设计原则** —— 可独立发表的 2-3 页精华摘要
3. **改动清单 + PR 拆分** —— 给执行者的 task list(每 PR 独立验收)
4. **协同点** —— 如果借鉴目标同时支持多个子系统(本机会话里
   "agenote 平台" + "atelier subagent" 两部分),明确标出**联动点**,
   避免实施时顾此失彼

## 反模式(本会话学到的)

- ❌ **杜撰 file:line** —— 用户极其重视"基于真实代码"而非"凭印象"。
  任何无法 grep 验证的引用,都不要写进文档
- ❌ **一次性大爆炸** —— 一份 PLAN.md 包含 11 阶段但一次性实施,
  等于没有计划。**阶段必须可独立 PR、独立验收**
- ❌ **缺协同点分析** —— 改造一个子系统时如果还涉及其他子系统,
  必须在文档里明确标"协同点 1/2/3",否则实施到一半才发现对不上
- ❌ **上游全盘照抄** —— 上游的 11 节 checkpoint 模板,在本机用
  4 节简化版就够用。**借鉴原则,简化实现**
- ❌ **"零产物即成功"被遗忘** —— distill/dream 这类工具如果没找到
  值得留下的,应该明说"没找到",不允许凑数(上游 MiMoCode 的硬约束)
- ❌ **同步 agent 进程触发** —— 长期任务(consolidation / packaging)
  用 cron 而非 agent 进程触发,避免被 agent 生命周期绑架
- ❌ **缺 dry_run 默认** —— 任何"改 KB / 改 memory"的批量操作,默认
  `dry_run=true`,首次跑给用户审核
- ❌ **没看上游代码就读 README 出设计** —— README 是宣传，代码是
  真相。1500 行的 `checkpoint.ts` 不会在 README 里讲清楚
- ❌ **不尊重目标系统的硬约束** —— 目标系统的 `AGENTS.md` /
  `CLAUDE.md` / `CONTRIBUTING.md` 里写明的硬约束（如"禁止跨模块
  require"、"零脚本混进 skills 目录"、"分类目录下放、不允许顶层"）
  必须**最先于借鉴方案被读取**，并在 PLAN.md「目标 Outcome」节列出，
  否则改造到一半发现违反硬约束要全返工。例:literal-config 的
  `lisp/AGENTS.md`「禁止跨模块 require」会**强制**你解耦上游耦合代码
  （`(require 'lib)` → 按需函数内联 / 改注入点 / `defvar` 占位），而
  不是按上游原貌搬运

## 跨库依赖三类映射法（实施阶段借用）

借鉴 + 移植过程中，经常需要把上游的「跨库/跨模块依赖」改成本机可接
受的形态。emacs lisp 移植场景（搬 `general-config` 的 `completion.el`
到 literal-config 的 `lisp/literal-completion.el`）实测出三段映射决策
表，其他语言按对位套用：

| 上游依赖形态 | 检测 | 本机改造 |
|---|---|---|
| 整库 `(require 'xxx)` | 模块文件内 `require 'xxx` | 删除。移植后模块必须**自包含可单文件加载**，按需函数内联进模块 |
| 私有常量 `<prefix>:<const>` | `<prefix>:[a-z-]+` 模式 | 顶部 `defvar literal:<const> nil`，**用注入点机制接住**：bootstrap / 编排块的 defconst 自动生效，模块加载时变量已 bound |
| 私有函数调用 `<prefix>/<fn>` | 直接调用 + 无显式 provide | `(when (fboundp '<prefix>/<fn>) (funcall '<prefix>/<fn> args))` 间接调用。注入点 nil / fboundp 不命中时降级静默 |

**核对时机**：在 Step 4 写 PLAN.md 第 5 节「改动清单」时**先列「跨库
依赖表」**（上游有哪些 require / 常量 / 函数调用 → 本机要不要 / 怎么
接），不要图快直接搬运；PR 落地前再 grep 验证一遍：

```bash
rg "^[^;]*require '" 模块文件          # 应该为零或仅有本仓库自身 require
rg "<prefix>:[a-z-]+" 模块文件          # 应该全部被 defvar 改造
rg "(<prefix>)/<fn>" 模块文件          # 应该全部被 fboundp 检查包住
```

详细范例（搬运 general-config `completion.el` 的完整 require /
常量前缀 / frame-hook 三个改造实例）见
`references/cross-library-dependency-mapping.md`。

## 借用时段的 commit 边界控制

Plan 交付后逐步实施成多个 PR。每个 PR 的 commit 必须**只含本 PR 范围
内的文件改动**，不混进同 session 内的其他任务改动（用户硬偏好，多次
在 `Guix-configs` 等仓库的 commit 动作上明确强调「不要碰其他的
uncommit 更改」）。具体三步法见
`/skill agenote-curator` 第 9a 节「Commit 边界三步法」：

1. `git add -- <本任务精确路径...>` 精准 stage（绝不用 `-A` / `-u`）
2. `git diff --cached --name-only` 核对 staged 列表
3. 提交后 `git status --short` 复查：其他目录的 uncommit 改动**原样保留**

这条与「PR 拆分独立验收」组合使用，共同保证实施时不被混入无关改动
污染 git 历史。

## 与其他 skill 的协作

- **scout 在前**:`/skill codebase-scout` 先扫双方现状(本 skill 的 Step 1)
- **planner 在中**:`/skill task-planner` 给本 skill 的 Step 4 套骨架
  (本 skill 已给出固定 11 节骨架,直接套用)
- **advisor 可选**:`/skill architecture-advisor` 在 Stage 3 原则提炼
  之后做一次"原则是否合理"的二次审视
- **不在本 skill 范围**:本 skill 写完 PLAN.md 后,**实施** PR 是
  另一次会话,不在本 skill 范围

## 边界

- **不写代码** —— 本 skill 产出的是设计文档,不是 PR
- **不写 KB 卡片** —— 上游/本机对位有持久价值的部分,用户决定要不要
  写进 `~/Documents/Org/experiences/`,本 skill 不主动写
- **不决定实施顺序** —— 文档列了 PR 1-N 顺序,但是否真的按这个顺序、
  跳过哪个、合并哪个,留给用户拍板

## 配套 references

- `references/plan-md-skeleton.md` —— 完整的 11 节骨架 + 字段约定,
  copy-paste 即可起新文档
- `references/capability-matrix-template.md` —— 缺口矩阵的 markdown 模板
- `references/file-line-validation.md` —— grep 校验脚本片段
- `references/cross-library-dependency-mapping.md` —— 跨库依赖三类映射法详细范例（emacs lisp 移植真实案例:从 general-config 的 completion.el 搬出）
