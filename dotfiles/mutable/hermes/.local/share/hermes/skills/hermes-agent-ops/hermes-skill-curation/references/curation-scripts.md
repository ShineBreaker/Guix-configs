# Hermes skill 精简配套脚本

> 配合 SKILL.md 使用。三个脚本是 2026-06-21 精简会话验证过的范式,
> 改 `KEEP_NAMES` / `TO_DELETE` 即可复用。

## 1. builtin skill 批量 trash 脚本

```python
#!/usr/bin/env python3
"""trash 模式清理 Hermes builtin skill(0555 权限位 → chmod → XDG trash)。"""
import os, shutil, datetime, pathlib

SKILLS_ROOT = pathlib.Path.home() / ".local/share/hermes/skills"
TRASH_FILES = SKILLS_ROOT.parent / "Trash/files"  # ~/.local/share/hermes/Trash/files
TRASH_INFO = SKILLS_ROOT.parent / "Trash/info"

KEEP_NAMES = {
    # 改这里:你决定保留的 skill name
    "agent-browser", "claude-code", "hermes-agent",
    "dogfood", "find-skills", "guix-configs-workflow",
    "pack-guix", "emacs-config", "knowledge-base",
}

# 全局加写权限(bundled skill 0555 → 0755)
os.system(f"chmod -R u+w {SKILLS_ROOT} 2>/dev/null")

# 收集磁盘上真实存在的 skill(Path.rglob 处理 mlops/evaluation/ 等嵌套)
existing = set()
for skill_md in SKILLS_ROOT.rglob("SKILL.md"):
    parts = skill_md.relative_to(SKILLS_ROOT).parts
    if len(parts) >= 2:
        existing.add(parts[-2])
for top in SKILLS_ROOT.iterdir():
    if top.is_dir() and (top / "SKILL.md").exists():
        existing.add(top.name)

to_delete = sorted(existing - KEEP_NAMES)
print(f"保留 {len(KEEP_NAMES & existing)}, 待删 {len(to_delete)}")
for n in to_delete:
    print(f"  - {n}")

import sys
if "--dry-run" in sys.argv:
    sys.exit(0)

moved, skipped = [], []
for name in to_delete:
    candidates = list(SKILLS_ROOT.glob(f"*/{name}")) + [SKILLS_ROOT / name]
    for src in candidates:
        if not src.exists() or not src.is_dir():
            continue
        if not os.access(src, os.W_OK):
            skipped.append((src, "read-only")); continue
        ts = datetime.datetime.now().strftime("%Y%m%d%H%M%S")
        dest = TRASH_FILES / f"{ts}-{src.name}"
        i = 1
        while dest.exists():
            dest = TRASH_FILES / f"{ts}-{i}-{src.name}"; i += 1
        info = TRASH_INFO / f"{dest.name}.trashinfo"
        info.write_text(
            f"[Trash Info]\nPath={src}\n"
            f"DeletionDate={datetime.datetime.now().isoformat()}\n"
        )
        shutil.move(str(src), str(dest))
        moved.append((src, dest))

print(f"trash {len(moved)} / 跳过(read-only) {len(skipped)}")
for s, d in moved: print(f"  {s} -> {d}")
```

**用法**:`python3 cleanup.py --dry-run` 预览,`python3 cleanup.py` 执行。

**关键点**:
- `chmod -R u+w` 必加(否则所有 builtin 都 read-only)
- `Path.rglob("SKILL.md")` 抓嵌套(mlops/evaluation/*、mlops/inference/*、mlops/models/*)
- 用 `<skills_root>.parent / "Trash"` 不是 `~/.local/share/Trash`(两个位置不同)

## 2. local skill 批量 trash 脚本(支持 symlink/regular dir 区分)

```python
#!/usr/bin/env python3
"""local skill 批量清理。处理 3 种类型:regular dir / symlink / git submodule。"""
import os, shutil, datetime, pathlib

SKILLS_DIR = pathlib.Path.home() / ".config/agents/skills"
TRASH_FILES = pathlib.Path.home() / ".local/share/hermes/Trash/files"
TRASH_INFO = pathlib.Path.home() / ".local/share/hermes/Trash/info"

TO_DELETE = [
    # 改这里:你决定删除的 local skill name
    "animejs", "figma-use", "hyperframes", "kami",
    # ...
]

moved, symlink_removed, not_found = [], [], []
for name in TO_DELETE:
    src = SKILLS_DIR / name
    if not src.exists():
        not_found.append(name); continue
    is_symlink = src.is_symlink()
    ts = datetime.datetime.now().strftime("%Y%m%d%H%M%S")
    dest = TRASH_FILES / f"{ts}-{name}"
    i = 1
    while dest.exists():
        dest = TRASH_FILES / f"{ts}-{i}-{name}"; i += 1
    info = TRASH_INFO / f"{dest.name}.trashinfo"
    if is_symlink:
        link_target = os.readlink(src)
        info.write_text(
            f"[Trash Info]\nPath={src}\n"
            f"LinkTarget={link_target}\n"   # 关键:记 link target
            f"DeletionDate={datetime.datetime.now().isoformat()}\n"
        )
        src.unlink()
        symlink_removed.append((src, link_target))
    else:
        info.write_text(
            f"[Trash Info]\nPath={src}\n"
            f"DeletionDate={datetime.datetime.now().isoformat()}\n"
        )
        shutil.move(str(src), str(dest))
        moved.append((src, dest))

print(f"moved {len(moved)} | unlink {len(symlink_removed)} | missing {len(not_found)}")
for s, d in moved: print(f"  moved: {s.name}")
for s, t in symlink_removed: print(f"  unlink: {s.name} (was -> {t})")
```

**关键点**:
- `is_symlink()` 检查要早于 `is_dir()`(symlink 也能 is_dir 为 True)
- 软链接(cc-switch 类型)记 `LinkTarget=` 到 trashinfo
- regular dir 用 `shutil.move` 整目录

## 3. 精简完成后的标准验证

```bash
# 1) Hermes 状态
~/.nix-profile/bin/hermes skills list 2>&1 | tail -3
# 期望:"X hub-installed, N builtin, M local — Total enabled"

# 2) builtin marker
ls -la ~/.local/share/hermes/.no-bundled-skills
# 期望:存在,说明 opt-out 写好了

# 3) trash 里的 skill(可恢复)
ls ~/.local/share/hermes/Trash/files/ | grep -E "20[0-9]{12}-" | wc -l
# 期望:刚 trashed 的数量

# 4) 残留空 category 目录
find ~/.local/share/hermes/skills/ -mindepth 1 -maxdepth 1 -type d -empty
# 这些是清空后的 category 目录;下次 blue rebuild 会清,或手动 rmdir
```

## 4. 用户咨询模板(已验证)

不要问"留什么"——给**具体数字预期**:

```
Q1: 内容创作(PPT/视频/设计/音乐)占多少比重?
   1. 不做 → 删 ~50 个,留 47
   2. 偶尔做 PPT → 删 ~68 个,留 29
   3. 偶尔做视觉 → 删 ~50 个,留 47
   4. 经常做 → 删 ~0 个,留 97

Q2: 知识管理用什么?(可多选)
   Obsidian / Notion / Airtable / 纯 Org-mode(全删)

Q3: 是否跑本地 LLM/ComfyUI/HF?
   不用 / 偶尔下 HF / 经常跑 / 只 ComfyUI

Q4: AI agent CLI 委派?
   都不用(留 hermes-agent) / 只 Claude Code / 都用

Q5: 社交/通讯 CLI(X/邮件/Teams)?(可多选)
   几乎不发 / 需要发 X / 需要发邮件 / 都删
```

**经验**:5 大类打包问,先给数量预期;Q1 是最大头,问清楚能省 50% 后续问题。

## 5. 分类重组(reorganize)配套脚本

> 配合 SKILL.md §2.5 使用。把"1 目录 = 1 skill"的散沙重组为"<category>/<skill>"官方 layout。提炼自 2026-07-05 重组 31 → 12 分类那次会话。

### 5.1 盘点 + 分类识别脚本

```bash
#!/usr/bin/env bash
# reorganize-survey.sh — 跑之前先摸清结构 + git 状态
# 用法: ./reorganize-survey.sh

set -e
SKILLS="$HOME/Projects/Config/Guix-configs/dotfiles/mutable/hermes/.local/share/hermes/skills"

echo "=== 1. SKILL.md 总数基线 ==="
find "$SKILLS" -name SKILL.md -not -path "*/.curator_backups/*" | wc -l

echo ""
echo "=== 2. 顶层目录(分类)状态 ==="
for d in "$SKILLS"/*/; do
  d=${d%/}
  name=$(basename "$d")
  has_skill="N"; [ -f "$d/SKILL.md" ] && has_skill="Y"
  has_subdirs=$(find "$d" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
  has_desc="N"; [ -f "$d/DESCRIPTION.md" ] && has_desc="Y"
  printf "  %-30s  SKILL.md=%s  sub-skill=%2d  DESCRIPTION=%s\n" \
    "$name" "$has_skill" "$has_subdirs" "$has_desc"
done

echo ""
echo "=== 3. 伪分类(目录名=skill 名,无 nested)==="
for d in "$SKILLS"/*/; do
  d=${d%/}
  name=$(basename "$d")
  if [ -f "$d/SKILL.md" ] && [ "$(find "$d" -mindepth 1 -maxdepth 1 -type d | wc -l)" = "0" ]; then
    echo "  $name"
  fi
done

echo ""
echo "=== 4. 空分类(只有 DESCRIPTION.md,无 skill)==="
for d in "$SKILLS"/*/; do
  d=${d%/}
  name=$(basename "$d")
  if [ ! -f "$d/SKILL.md" ] && [ "$(find "$d" -name SKILL.md | wc -l)" = "0" ]; then
    echo "  $name"
  fi
done

echo ""
echo "=== 5. git 索引状态基线 ==="
cd ~/Projects/Config/Guix-configs
git status -s dotfiles/mutable/hermes/.local/share/hermes/skills/
```

### 5.2 重组执行脚本(PLAN → 执行)

```bash
#!/usr/bin/env bash
# reorganize-execute.sh — 搬运 skill 到新分类,处理 git 未跟踪目录
# 用法: 编辑下面的 PLAN,确认后 ./reorganize-execute.sh

set -euo pipefail
REPO="$HOME/Projects/Config/Guix-configs"
SKILLS_REL="dotfiles/mutable/hermes/.local/share/hermes/skills"
SKILLS="$REPO/$SKILLS_REL"

declare -A MOVE_MAP=(
  ["agent-history-importer"]="autonomous-ai-agents"
  ["crush-session-extract"]="autonomous-ai-agents"
  ["worker-handoff"]="autonomous-ai-agents"
  ["architecture-advisor"]="planning"
  ["task-planner"]="planning"
  ["codebase-scout"]="devtools"
)
NEW_CATEGORIES=("planning" "guix-configs")
EMPTY_TO_TRASH=("data-science" "email" "github" "note-taking" "smart-home" "social-media")

cd "$SKILLS"
chmod -R u+w "$SKILLS"

# Step 2: 创建新分类
for c in "${NEW_CATEGORIES[@]}"; do
  if [ ! -d "$c" ]; then
    mkdir "$c"
    cd "$REPO" && git add "$SKILLS_REL/$c/" && cd "$SKILLS"
    echo "  ✓ 新建分类: $c"
  fi
done

# Step 3: 处理 git 未跟踪的源(避免 §1.8 那个 "source directory is empty" 错)
for skill in "${!MOVE_MAP[@]}"; do
  cd "$REPO"
  if git status -s "$SKILLS_REL/$skill/" 2>/dev/null | grep -q "^??"; then
    git add "$SKILLS_REL/$skill/"
    echo "  ✓ git add 未跟踪: $skill"
  fi
  cd "$SKILLS"
done

# Step 4: git mv 搬迁
for skill in "${!MOVE_MAP[@]}"; do
  tgt="${MOVE_MAP[$skill]}"
  if [ -d "$skill" ] && [ -d "$tgt" ]; then
    cd "$REPO"
    git mv "$SKILLS_REL/$skill" "$SKILLS_REL/$tgt/" 2>/dev/null \
      && echo "  ✓ git mv $skill → $tgt/" \
      || echo "  ✗ 失败: $skill"
    cd "$SKILLS"
  fi
done

# Step 5: 删空分类走 XDG trash
mkdir -p "$HOME/.local/share/hermes/Trash/files" "$HOME/.local/share/hermes/Trash/info"
TS=$(date +%Y%m%d%H%M%S)
for c in "${EMPTY_TO_TRASH[@]}"; do
  src_rel="$SKILLS_REL/$c"
  src_abs="$SKILLS/$c"
  [ ! -d "$src_abs" ] && continue
  cd "$REPO"
  git rm -r "$src_rel" >/dev/null 2>&1 || continue
  dest="$HOME/.local/share/hermes/Trash/files/${TS}-$c"
  cat > "$HOME/.local/share/hermes/Trash/info/${TS}-$c.trashinfo" <<EOF
[Trash Info]
Path=$REPO/$src_rel
DeletionDate=$(date -Iseconds)
EOF
  mv "$src_abs" "$dest"
  echo "  ✓ trash $c/ → ${TS}-$c/"
  cd "$SKILLS"
done

# Step 6: 验证
echo ""
echo "=== SKILL.md 总数(应与基线一致)==="
find "$SKILLS" -name SKILL.md -not -path "*/.curator_backups/*" | wc -l
echo ""
echo "=== Hermes 端 discover(0 disabled 即成功)==="
~/.nix-profile/bin/hermes skills list 2>&1 | tail -3
echo ""
echo "=== 作用域边界:其他源未碰 ==="
echo "  ~/.config/agents/skills/ 数: $(ls ~/.config/agents/skills/ | wc -l)"
```

**关键点**:
- **Step 3 必须有**:不先 `git add` 就 `git mv` 会报"fatal: source directory is empty"(§1.8)
- **Step 5 trash 用 `<skills_root>.parent / "Trash"`**(注意是 hermes 的 Trash 不是 ~/.local/share/Trash)
- **Step 6 验证 `0 disabled`**:hermes 端读到新分类但有任何 skill disabled = 部署失败

### 5.3 重组前 cross-check 必问

把 PLAN 整表展示给用户**等拍板**再执行:

| skill 名 | 当前顶层 | 目标分类 | 理由 | 操作 |
|---|---|---|---|---|
| agent-history-importer | top-level | autonomous-ai-agents | 外部 agent schema 侦察 | git mv |
| architecture-advisor | top-level | planning 🆕 | 战略咨询 ≠ agent 编排 | mkdir + git mv |
| data-science | empty | (删除) | 只有顶层 DESCRIPTION,无具体 skill | trash |
| mlops | empty-with-nested | (保留) | 有 evaluation/inference/models 三个 nested placeholder | 不动 |

如果用户说"先压现有"或"可以新建",再执行 5.2 脚本。
