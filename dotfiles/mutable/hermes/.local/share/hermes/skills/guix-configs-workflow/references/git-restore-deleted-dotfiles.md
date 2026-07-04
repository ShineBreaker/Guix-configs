# 从 git history 恢复已删除的 dotfiles 到 stow/ 或 dotfiles/enable/

> 适用场景:用户说"把 XXX 配置从仓库里找出来放到 `stow/<pkg>/`(或 `dotfiles/enable/<app>/`)",但仓库**当前目录里找不到**——大概率是某次重构 commit 整体删除了那批文件,要从 history 恢复。这是 §7(GNU Stow 二轨)与 §3(多行编辑)、§5(AGENTS.md structor)的**交汇点**,本文档给可复用剧本。

## 前置三检(避免无效恢复)

恢复前**必须**做这三步,任一步异常都先停下来确认意图,不要直接动文件:

### 1. `git status` 起步 + 看工作区是否有未提交线索

```bash
git status --short                          # 存量改动(M 状态)可能是用户当前任务的合法改动,不能 git checkout 抹掉
git log --all --oneline -- '<可疑路径>' | head -20   # 看历史提交
```

### 2. 文档/树是否过期 — 关键信号

`README.org` / `AGENTS.md` 里如果还引用着**已不存在的目录**,100% 指向"曾经被删":

```bash
# 例:README.org 还在列 agents/.config/pi/ → ~/.config/pi/,但目录已经没了
grep -rn 'agents/\.config/pi/' --include='*.org' --include='*.md' .
git ls-files | grep -F '.config/pi/'        # 空 = 已删
```

`AGENTS.md` 树图与 `tree` 输出对不上、文档列的路径在仓库里没有——这些**过期文档就是恢复目标的目录地址**。

### 3. 找删除 commit(两种方式)

```bash
# A. 找包含 "remove" / "delete" / "cleanup" 的 commit message
git log --all --oneline --grep -E '(REMOVE|REMOVED|delete|cleanup|move out)' | head -10

# B. 已知某文件曾经存在,找删除它的 commit
git log --all --diff-filter=D --name-only --pretty=format:'%H %s' -- '<可疑路径>' | head -30
```

拿到 commit hash 后**先看一眼范围**再动手:

```bash
git show --stat <commit> | head -60         # 删了多少文件、多少行
```

## 恢复模式 — `git archive` 批量导出(首选)

比 `git show <rev>:<path> > <file>` 逐文件恢复快得多,特别是几十个文件时。

```bash
# 1) 准备临时恢复区(不用 /tmp/pi-restore 也行,任何不冲突路径即可)
mkdir -p /tmp/restore-<name>

# 2) 从删除 commit 的**父提交**(<rev>^)导出多个路径到临时区
git archive <rev>^ -- \
    'dotfiles/enable/<app>/.config/<svc>' \
    'dotfiles/enable/<app>/.local/bin/<cmd>' \
    'dotfiles/enable/<app>/.config/<app>/adapters/<svc>.json' \
    | tar -x -C /tmp/restore-<name>

# 3) 看清单对不对
find /tmp/restore-<name> -type f | sort
```

**关键细节**:

- 用 **`<rev>^`** 而不是 `<rev>` —— 因为删除 commit 的 tree 里**已经没有这些文件**了,要拿父提交(删除前)的 tree
- 路径必须相对仓库根,带 `dotfiles/enable/...` 或 `stow/...` 前缀
- 一次 `git archive` 命令可以列多个路径,用空格分隔

## 决定目标位置 — `stow/` 还是 `dotfiles/enable/`

这一步最容易被绕晕,因为两套机制都在用。在恢复前问清(也用 `clarify` 给选项):

| 目标位置 | 适合内容 | 部署命令 |
|---------|---------|---------|
| `stow/<pkg>/` | **频繁改动、需要 git 备份追踪**的配置文件(agent context、SOUL.md、prompt 模板、用户自定义脚本) | `blue stow <pkg>` 软链接到仓库源,改源即生效 |
| `dotfiles/enable/<app>/` | **静态/稳定**配置文件(模板、默认设置、跨机器统一) | `blue home` 经 store 副本,改源后要重新构建 |

**判断准则**(从 `AGENTS.md` 顶级导引):
- 改源即生效(无需 `blue home`) → `stow/`
- 改源需 `blue home` 重建软链 → `dotfiles/enable/`

如果用户原话是"放到 `stow/<pkg>/`"或"放到 `stow/` 内某个新包",就遵循用户意图——其他情况下 `clarify` 给出选项。

## 移动到目标位置

```bash
# 例:把恢复出来的 .config/<svc>/ 搬到 stow/<pkg>/.config/<svc>/
mkdir -p stow/<pkg>/.config/<svc>
cp -r /tmp/restore-<name>/<原路径>/. stow/<pkg>/.config/<svc>/

# 恢复可执行权限(从 git archive 出来可能掉 +x)
chmod +x stow/<pkg>/.local/bin/<cmd>  stow/<pkg>/.local/bin/<cmd>-*
```

**注意路径嵌套**:从 `git archive` 出来的目录结构和仓库里一致,搬的时候要把**目录内容**(`.`)搬过去,不是把整个外层目录搬过来。

## 写 `.stow-local-ignore`(仅 `stow/<pkg>/` 路径需要)

恢复回来的目录里通常**混着运行时产物**:`node_modules/`、`*.db`、`pnpm-lock.yaml`、`__pycache__/` 等。这些绝不能进 `~/.config/`,否则被应用写入会污染仓库。

模板(放在 `stow/<pkg>/.stow-local-ignore`,Perl 正则,逐行匹配路径尾部):

```
# 来源:上游 .gitignore 里已有的(若恢复时一并带回了 .gitignore,直接照抄)
node_modules$
\.pnpm-store$

# 额外:你识别出的运行时产物
npm/pnpm-lock\.yaml$
sessions/.*\.db(-shm|-wal)?$
models\.db(-shm|-wal)?$
```

## 更新文档 + AGENTS.md 树图

恢复回来后,**两处文档必须同步**:

1. **`stow/AGENTS.md` 的"当前纳管的包"表 + 目录结构图**
   - 包表新增一行(部署目标 + 包含文件清单)
   - 目录结构图**用 `blue structor` 重写**(用户偏好,见 §5)
2. **`README.org`(如果有引用过期路径)**:把过期的目录条目替换成新的 `stow/<pkg>/` 路径
3. **同包相关的 `dotfiles/enable/<app>/AGENTS.md`**:如果之前在那个目录的措辞要更新(典型:从"OMP 不再从此目录部署"扩展到"OMP + pi 都迁走了")

```bash
# 一次性刷新所有 AGENTS.md 树图
blue structor 2>&1 | grep -E '(WRITE|ERROR)'
```

## 协同改动 — `loopctl/adapters/` 之类配套恢复

如果删除 commit **顺带改了 adapter 配置文件**(典型:把 `pi.json` 改名 `omp.json`),用户意图是"恢复 pi"时可能也希望恢复 adapter:

```bash
# 1) 看出 diff(只改 name/bin 字段,arg template 通常通用)
diff -u <restored-pi>.json <existing-omp>.json

# 2) 恢复 pi.json 后,让 loopctl 同时支持两套 adapter
cp <restored-pi>.json dotfiles/enable/<app>/.config/loopctl/adapters/
```

这一步**必须 clarify 用户**:adapter 恢复会改变 loopctl 的命令空间(`/loop --adapter pi|omp`),用户可能只想保留 omp 不想要 pi。

## 多版本候选决策 — 同一文件被多次重构过的场景

实战中比"找一个删除 commit 然后恢复"更棘手的情况:**用户说"恢复到当时的版本",但同一类文件在 git history 里被多个 commit 反复改写过**(典型:`atelier/` 从合并单文件 → 拆 13 个 `.ts` → 又合回单文件)。此时 commit message 的字面含义经常误导决策。

### 反模式 — 用 commit message 直觉选 commit

`d5ec299f REVERT: (kb) revert kb-mcp` 的标题里既有 `REVERT` 又有 `kb-mcp`,agent 容易直觉选"`kb-mcp` 还存在的版本"(即 `d5ec299f^`)。但**该 commit 同时做了三件事**:

1. 删除 `kb-mcp/`(用户已不想要)
2. 完整恢复 `knowledge-base` skill(含 references)
3. 给 `self-improving` 做减负

所以"`d5ec299f` 本身的版本"才是用户要的(只删 kb-mcp,但保留完整 skill)。

**禁止**只用 commit message 选 commit。

### 正确做法 — 先 diff 候选 commit 的真实文件清单

```bash
# 1) 列出 2-3 个候选 commit 的目标路径文件清单
for rev in d5ec299f^ d5ec299f; do
  echo "=== $rev ==="
  git ls-tree -r $rev --name-only -- '<可疑路径>' | sort
done

# 2) diff 看差异(diff 的不是 commit message,是文件清单)
diff <(git ls-tree -r <rev_A> --name-only -- '<path>' | sort) \
     <(git ls-tree -r <rev_B> --name-only -- '<path>' | sort)
```

差异列出来后,**把每个文件的"在/不在"列给用户看**,让用户选——而不是让用户选 commit hash。

### granularity 陷阱 — 同一目录在不同 commit 是不同粒度

`pi/extensions/atelier/` 在 `9b720b6e^` 是单文件 `index.ts` (61336 字节),在 `d5ec299f` 已拆成 13 个 `.ts`。**两个恢复源点出来的文件粒度不一样**,直接影响 `stow/pi/` 内的最终形态(单文件 vs 多文件),且 pi 运行时启动加载逻辑对两者可能有差异。

**恢复前必查**:`git ls-tree -r <候选 rev> --name-only -- <目录>` 看**真实文件数与每个文件大小**,再决定源点。

### gitlink 子模块不能 cp -r

`skillsets/` 在 `d5ec299f` 是 4 个 gitlink(`160000 commit` 模式,即 `.git/modules/<path>` 引用)。用 `cp -r` 会变成普通目录,**丢失 gitlink 语义**——后续 `git submodule update` 失效。

```bash
# 1) 看出是不是 gitlink
git ls-tree <rev> -- <可疑路径>
# 输出: 160000 commit <hash>   <path>     ← gitlink
# 或:    040000 tree <hash>     <path>     ← 普通目录,可 cp

# 2) 恢复 gitlink 只能用 git submodule add <url> <path>(需要知道 URL)
#    或 .gitmodules 里有 [submodule <path>] url = ...
```

如果 URL 不可追溯(`.gitmodules` 历史里被删了),**直接跳过**这些 gitlink,告诉用户"4 个子模块暂不恢复,URL 来源已不可追溯",让用户后续手动 `git submodule add`。

### 用户已明确范围时,不要再追问子选项

`clarify` 协议边界:用户说"包含 X、Y、Z"或"所有相关文件都需要恢复"时,**直接执行全部**,不要把子选项再列给用户挑。把"风险点"标在结果里(典型:"npm/pnpm-lock.yaml 是 4142 行锁文件,跑本地 npm i 可重新生成")。

**反例**(本次踩过):用户已说"包含了 self-improving 那个 skill 的提交中的知识库体系,包括相关的所有 skill 以及本体",agent 仍追问子选项,被用户用"所有相关文件都需要恢复"打回。

什么时候才用 `clarify`:

- 用户原话只给一个模糊方向(例:"把以前的 pi-agent 配置找出来"),不确定是路径/版本/范围
- 几个走法差异巨大且不可逆(例:删除整个 dotfile 包)
- 用户原话有内部矛盾需要澄清

什么时候**不用** `clarify`:

- 用户已明确范围/版本/路径(直接执行)
- 风险点可逆、可在结果里说明(直接执行 + 标注)
- 多个选项本质等价(选一个默认即可)

## 完整剧本 — 本次实战(pi-coding-agent 恢复,2026-06-24)

**触发**:用户说"从仓库的 git history 里面找出来被删除掉了的相关文件,复原到 `stow/pi` 里"。

**步骤**:

1. `git log --all --oneline --grep='REMOVE: (pi)'` → 找到 `9b720b6e REMOVE: (pi) using omp as a replacement.`
2. `git show --stat 9b720b6e` → 38 文件 / 10983 行删除,目录树包含 `.config/pi/`、`.local/bin/{pi,pi-acp,pi-update}`、`.local/share/pi/`、以及 loopctl adapter 重命名
3. **clarify 两个决策点**:
   - 运行时锁文件 `npm/pnpm-lock.yaml`(4142 行)是否恢复
   - `loopctl/adapters/pi.json` 是否恢复(让 loopctl 同时支持两套 adapter)
4. 用户回答:1.B 全部恢复 / 2.B 恢复 adapter
5. `git archive 9b720b6e^ -- <5 个路径>` → /tmp/pi-restore
6. `cp -r` + `chmod +x` 搬到 `stow/pi/.config/pi/`、`stow/pi/.local/bin/`、`stow/pi/.local/share/pi/`
7. `cp /tmp/.../loopctl/adapters/pi.json dotfiles/enable/agents/.config/loopctl/adapters/`
8. 写 `stow/pi/.stow-local-ignore`(排除 `node_modules$` / `\.pnpm-store$` / `npm/pnpm-lock\.yaml$`)
9. `blue structor` 刷新 5 个 AGENTS.md 的树图(stow/AGENTS.md、agents/AGENTS.md、dotfiles/AGENTS.md、source/AGENTS.md、utilities/AGENTS.md)
10. patch `README.org` 删除过期 `agents/.config/pi/ → ~/.config/pi/` 那行,补上 `stow/{hermes,emacs,pi}/` 三包
11. patch `dotfiles/enable/agents/AGENTS.md` 在 OMP 段落后补"pi 已迁到 `stow/pi/`、loopctl 双 adapter 共存"
12. `git add` 全部 36 个新文件 + 5 个相关 AGENTS.md 改动,**不 commit**(等用户确认)
13. 给用户讲:下一步跑 `blue stow pi` 验证(预先 `ls -la ~/.config/pi/` 检查会与 stow 软链冲突的实际文件)

**关键教训**:

- **过期的 `README.org:220` 是任务起点的金矿**——一行字就告诉我在哪里、怎么部署
- **commit message `9b720b6e REMOVE: (pi) using omp as a replacement.` 的 grep 词不要只 grep "remove"**——它写的是 "REMOVE" 大写,git 默认 case-sensitive,会漏
- **`git archive <rev>^`** 拿删除前的 tree 是关键,不是 `<rev>`
- **不能动会话开始前就存在的 M 状态文件**(本次 `blueprint.scm`),否则会覆盖用户合法改动

## 反模式

- ❌ **`git checkout <rev>^ -- <path>`** —— 这会把删除的文件恢复到**工作区当前路径**(可能就是 `dotfiles/enable/<app>/` 而不是你想要的 `stow/<pkg>/`)。如果用户意图是搬到 stow/,要先 archive 到临时区,再 cp 到目标
- ❌ **`rm -rf /tmp/restore-<name>` 在最后没清** —— 残留临时区会成为下次误操作的源头。完成后 `rm -rf`
- ❌ **patch 工具的 fuzzy match 在多文件大改时漏行** —— 整个目录搬迁应该用 `cp -r`,不是逐文件 patch
- ❌ **改 `stow/<pkg>/` 之外的所有文档树图手动维护** —— `blue structor` 会顺手刷 `stow/`、`dotfiles/`、`source/` 等所有带 `structor:begin` 标记的 AGENTS.md,别忘了跑

## 与 §5 (structor)、§7 (GNU Stow) 的交叉

- §5.3 强调"`blue structor` 只重写标记对,不动其他内容"——恢复后跑 structor 是刷新树图的安全范式
- §7.5 强调"`stow/` 不进 `dotfile-services`"——恢复 pi 到 `stow/pi/` **不需要**改 `source/config.org` 的 `dotfile-services` packages 列表
- §7.7 反模式"在 `~/.local/share/hermes/` 下直接编辑后 git commit"——同样适用于 `~/.config/pi/`:`blue stow pi` 前编辑 `~/.config/pi/` 是野配置;先 `blue stow --adopt pi` 把文件纳入源