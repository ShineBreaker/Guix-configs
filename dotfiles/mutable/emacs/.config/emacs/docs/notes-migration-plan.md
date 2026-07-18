# notes/ 历史目录迁移方案

**状态**:草案,待你审查后手工执行
**生成时间**:2026-07-19
**关联**:
- Commit 4 (87365ab) Phase 2.1:notes/ 标记为历史迁移区
- Commit 12 (753ebe7) Phase 7.2 manifest 决策:Deft 是否删
- `scripts/migrate-notes`:Commit 4 写的自动分类脚本(本方案替代它,见 §5)

## 1. 现状

```
~/Documents/Org/notes/      (大小:40K,7 个 .org + 1 个 .py)
├── ai.org          7.4K    AI 对话段子(5 条)
├── creation.org    11.8K   创意/小说 prompt(8+ 条)
├── game.org        9.9K    游戏灵感/服务器配置(7 条)
├── life.org        12.0K   生活段子/密码草稿(10+ 条)
├── meme.org        30.4K   梗图/段子(最大)
├── nsfw.org        11.7K   NSFW 内容(7+ 条)
├── tech.org        6.2K    技术片段(脚本/命令记录)
└── generate_titles.py     Python 标题生成脚本
```

`inbox.org` 是 syncthing 同步软链(`→ ~/Documents/Syncthing/note/org/inbox.org`),
任何写入操作必须用 append 模式,不得覆盖。

## 2. 内容画像(逐文件审查)

### 2.1 `tech.org` — **建议拆分保留**

唯一结构化技术内容,5 个独立条目:

| 行号 | 标题 | 内容类型 | 建议去向 |
|------|------|---------|---------|
| 1 | 备份与恢复脚本备份函... | Flatpak 备份脚本 | → `experiences/devops/<date>-flatpak-backup.org`(经验卡) |
| 51 | 元时代偶然发现了偶尔... | dedomil.net 一句话记忆 | → 删除(太碎片化) |
| 58 | 内存消耗应该是中间两... | JVM AOT 参数笔记 | → `experiences/devops/<date>-jvm-aot-memory.org` |
| 65 | networking... | NixOS 屏蔽 QQ 域名 | → `experiences/guix/<date>-nix-block-domain.org` |
| 75 | 升级版新增语法临时脚... | bubblewrap 沙盒脚本 | → `experiences/devops/<date>-bbox-bwrap.org`(独立卡片) |
| 169 | 位天翼云盘访问码百度... | 系统镜像下载链接 | → 删除(链接可能已失效;如需要再查) |
| 186 | bash-c"$(c... | 一行安装脚本 | → 删除(快照式,无复用价值) |
| 193 | 可以添加在中打开这个... | iOS 越狱证书配置 | → `experiences/tooling/<date>-ios-jailbreak-cert.org`(若仍需要) |
| 218 | 可期版链接 | Imagine UI 百度网盘 | → 删除(链接过期概率高) |

**保留:5 条**;**删除:4 条**;**迁入 experiences:5 条**

### 2.2 `ai.org` / `creation.org` / `game.org` / `life.org` / `meme.org` / `nsfw.org` — **建议整体归档**

这 6 个文件的内容画像高度一致:
- 短句/段子/梗图配文,**非结构化**
- 没有可执行的 TODO/任务
- 没有双向链接 / Roam ID
- 没有 DEADLINE / SCHEDULED
- 内容快照性质,不像长期知识

**建议**:整体移到 `archive/notes-legacy/`,不进 Roam DB,不进 agenda,不进 Dashboard 索引。
Deft 可配置为只读检索这个目录(若你想保留检索能力),或直接删除。

### 2.3 `generate_titles.py` — **建议删除**

独立 Python 脚本,与 Org 工作流无关,也无文档说明用途。
若你仍需要,移到 `~/Projects/Scripts/` 或类似代码目录,不属于 Org 知识库。

## 3. 目标目录结构(迁移后)

```
~/Documents/Org/
├── inbox.org                ← syncthing 同步,不动
├── agenda/                  ← 任务/日程/习惯/.clock
├── roam/                    ← 长期笔记(3 个 Emacs 教程 + 可能新增)
├── experiences/             ← 经验卡片(已有,本方案迁入 5 条)
│   ├── devops/
│   │   ├── <date>-flatpak-backup.org      ← from tech.org L1
│   │   ├── <date>-jvm-aot-memory.org      ← from tech.org L58
│   │   └── <date>-bbox-bwrap.org          ← from tech.org L75
│   ├── guix/
│   │   └── <date>-nix-block-domain.org    ← from tech.org L65
│   └── tooling/
│       └── <date>-ios-jailbreak-cert.org  ← from tech.org L193 (可选)
└── archive/
    └── notes-legacy/        ← 新建,只读归档
        ├── ai.org
        ├── creation.org
        ├── game.org
        ├── life.org
        ├── meme.org
        ├── nsfw.org
        └── README.org       ← 说明归档原因 + 来源 + 迁移日期
```

## 4. 迁移步骤(手工执行,每步可独立验证)

### Step 1:备份(强烈建议)

```bash
cp -r ~/Documents/Org/notes ~/Documents/Org/notes.backup-$(date +%Y%m%d)
```

### Step 2:创建目标目录

```bash
mkdir -p ~/Documents/Org/archive/notes-legacy
mkdir -p ~/Documents/Org/experiences/{devops,guix,tooling}
```

### Step 3:整体归档非结构化文件(6 个)

```bash
cd ~/Documents/Org
git mv notes/ai.org notes/creation.org notes/game.org \
       notes/life.org notes/meme.org notes/nsfw.org \
       archive/notes-legacy/
# 若 notes/ 不在 git 跟踪:
# mv notes/{ai,creation,game,life,meme,nsfw}.org archive/notes-legacy/
```

### Step 4:迁移 tech.org 结构化条目(5 条,每条单独操作)

每个条目用 `org-cut-subtree` 切到新文件。Emacs 内手工操作:

```elisp
;; 在 tech.org buffer 内,光标放到 * 标题行,执行:
;; M-x org-cut-subtree  → 切到 kill-ring
;; C-x C-f ~/Documents/Org/experiences/devops/<date>-flatpak-backup.org
;; C-y                   → 粘贴 subtree
;; 补 PROPERTIES(CATEGORY / TECH / TYPE / ENTRY_TYPE / ID)
;; C-x C-s
```

**目标文件命名**:用今天日期作为 ID 前缀(对齐 agenote-base 惯例):
- `20260719-<slug>.org`

### Step 5:删除剩余 tech.org 条目(4 条)

```bash
# 在 Emacs 中,光标移到要删的条目上 M-x org-cut-subtree
# 或直接在 tech.org 文件里删除对应 * 标题块
```

应删除的条目(本方案 §2.1 表格中标记"删除"的 4 条):
- L51 元时代偶然发现了偶尔...
- L169 位天翼云盘访问码百度...
- L186 bash-c"$(c...
- L218 可期版链接

### Step 6:清理空 tech.org + generate_titles.py

```bash
# 若 tech.org 所有条目都已迁移/删除:
rm ~/Documents/Org/notes/tech.org
# generate_titles.py:确认无用后删除
rm ~/Documents/Org/notes/generate_titles.py
# 删除空的 notes/ 目录(若已无内容)
rmdir ~/Documents/Org/notes
```

### Step 7:重建知识库索引

```bash
agenote reindex   # 在 ~/Documents/Org/ 目录执行
```

### Step 8:写 archive/notes-legacy/README.org

```org
#+title: notes-legacy 归档说明
#+date: [2026-07-19]

* 来源

历史 ~/Documents/Org/notes/ 目录(Phase 2.1 标记为迁移区),
2026-07-19 整体归档。

* 为什么归档而非删除

- 内容为 2020-2026 年积累的段子/灵感/梗图配文,非结构化
- 无 TODO / DEADLINE / Roam ID,不参与 agenda / Dashboard
- 保留只读检索能力,以备偶尔查阅

* 为什么不进 Roam DB

- 内容碎片化,无双向链接价值
- 会污染 Roam 网络的关联密度

* 文件清单

- ai.org         AI 对话段子
- creation.org   创意/小说 prompt
- game.org       游戏灵感
- life.org       生活段子
- meme.org       梗图/段子(最大)
- nsfw.org       NSFW 内容
```

### Step 9:更新 emacs 配置(Phase 7.2 后续 commit)

- 删除 `literal/note-new`(Commit 4 已标 DEPRECATED)
- 删除 `literal:org-default-notes-file` 常量
- 删除 `use-package deft`(本方案完成后)
- manifest 删 `emacs-deft`(已建议)

## 5. 关于 scripts/migrate-notes(替代方案)

Commit 4 写的 `scripts/migrate-notes` 用启发式分类(TODO/DEADLINE/ROAM_REFS/文件大小),
**对本例不适用**:
- notes/ 内容没有任何 Org 结构(TODO/DEADLINE/ROAM_REFS 全是 false negative)
- "短文件 → inbox"启发式会把 meme.org 之类也塞进 inbox(30K 不是短文件,但内容碎片)

**建议**:本方案的手工分类(§2.1 + §2.2)比启发式更准确,因为只有你能判断:
- 哪些 tech.org 条目仍值得长期保留
- 梗图/段子是否要保留只读检索

`scripts/migrate-notes` 可在更结构化的 notes/(若有 Roam ID / DEADLINE 的)
场景下使用,本方案完成后可考虑删除或保留作为通用工具。

## 6. 验证清单(迁移完成后)

- [ ] `find ~/Documents/Org/notes -type f` 返回空
- [ ] `ls ~/Documents/Org/archive/notes-legacy/*.org` 返回 6 个文件 + README
- [ ] `ls ~/Documents/Org/experiences/{devops,guix,tooling}/*.org` 包含迁入的卡片
- [ ] `agenote stats` 卡片数增加 5(迁入的 5 条经验卡)
- [ ] `agenote search "flatpak"` 能搜到 flatpak-backup 卡片
- [ ] Agenda 不出现归档内容(`org-agenda-files` 应只指向 agenda/)
- [ ] Dashboard 最近知识条目不出现归档文件
- [ ] `C-c o d` (deft) 已无目标目录(若已删 Deft 配置)

## 7. 回退方案

若迁移后发现问题:

```bash
# 从备份恢复
rm -rf ~/Documents/Org/notes
cp -r ~/Documents/Org/notes.backup-<日期> ~/Documents/Org/notes
# 删除新迁入的经验卡(逐个,需手动确认)
# 删除 archive/notes-legacy/ 目录
```

迁移本身不修改 inbox.org / agenda/ / roam/,这些目录不受影响。

## 8. 风险评估

| 风险 | 概率 | 影响 | 缓解 |
|------|------|------|------|
| 误删 tech.org 中有价值条目 | 中 | 中 | Step 1 全量备份;Step 4 每条单独迁移 |
| 归档文件被 syncthing 同步冲突 | 低 | 低 | archive/ 不在 syncthing 同步路径(inbox.org 才是) |
| Roam DB 残留旧文件引用 | 中 | 低 | `org-roam-db-sync` 重建;归档文件不进 DB |
| Deft 配置仍指向不存在的 notes/ | 高 | 极低 | Deft 启动时找不到目录会报错但不崩溃;Step 9 同步删配置 |

## 9. 后续工作(不在本方案范围)

- **Deft 配置删除**:迁移完成后,在 emacs 配置中删 `use-package deft`,
  manifest 中删 `emacs-deft`(下一个 commit 处理)
- **scripts/migrate-notes 处置**:保留作为通用迁移工具,或删除
- **notes-migration-plan.md 处置**:迁移完成后可删,或归档到
  `archive/notes-legacy/` 作为操作记录
