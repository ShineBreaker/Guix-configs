---
name: hermes-skill-curation
description: "Use when the user wants to add, remove, prune, audit, or curate the Hermes Agent skill library on disk (~/.local/share/hermes/skills/, ~/.hermes/skills/, bundled vs. dotfile-managed skills). Triggers: '精简 skill', '删掉 XX skill', 'skill 太多', '哪些 skill 在用', '清理 Hermes skill', 'skill 审计', 'trash skill 目录', 'bundled skill 删不掉', 'skills_list 跟磁盘对不上', 'hermes skill 库维护', 'curator 暂停', 'archiving skills', or any bulk add/remove of skill directories. Covers: skills_list 视图 vs 磁盘真实存在的差异、bundled skill 的 read-only 0555 权限位破解、XDG trash 范式(用户偏好 rm→trash)、用户 dotfile 源(Guix stow)与 Hermes 安装源(bundle)边界。"
---

# hermes-skill-curation — Hermes skill 库精简

> 一次会话内"Hermes skill 批量增删"类工作的协议。源数据在 ~/Documents/Org/ 由人类维护;本 skill 是缓存层,提炼自 2026-06-21 精简 73 → 15 那次会话。

## 1. 关键不变量(开始任何精简前必读)

1. **三种 skill 源,不要混**:
   - **Hermes bundled**:`~/.local/share/hermes/skills/<category>/<name>/` —— Hermes 安装包自带,read-only 权限位 `0555`,**不在任何仓库源里**。`blue home` 不会回滚它(它走 `source/nix/configuration/programs/hermes.nix` 装 `full` 输出)。精简它就是直接动磁盘。**正确卸载路径**:`hermes skills opt-out --yes` 写 `~/.local/share/hermes/.no-bundled-skills` marker,后续 `hermes update`/`skills sync` 不会 seed;`opt-out --remove --yes` 还会**删所有未修改的 bundled 副本**(user-edited 和 local/hub 不动)。**不要直接 trash builtin**——marker 不写,下次 self-update 仍会从 upstream 拉回。
   - **用户 dotfile 源**:`~/.config/agents/skills/<name>/` —— Guix Home 的 `home-dotfiles-service-type` 软链接到 `/gnu/store` 只读副本。**不在** `~/.local/share/hermes/skills/` 下,但**会**被 `skills_list` 报出来。要精简必须改 `dotfiles/immutable/agents/.config/agents/skills/<name>/` 源 + `blue home`,**不**直接 rm 部署位置(被 `blue home` 软链接覆盖回来)。详细不变量见 `guix-configs-workflow` skill 不变量 #2。**local skill 三种子类型**:
     - **直接目录** (e.g. `agent-browser/`、`emacs-config/`) — `Path.is_dir()` True,trash 即可
     - **git submodule** (e.g. `md2html/`, `.config/agents/skills/<sub>/`) — `Path.is_dir()` 且有 `.git/`;trash 目录 OK,但仓库源要 `git submodule deinit <path>` + 从 `.gitmodules`/`git config` 删条目
     - **cc-switch 软链接** (e.g. `docx -> ~/.config/cc-switch/skills/docx`) — `Path.is_symlink()` True;**只 unlink 软链接,不动 cc-switch 那边的源目录**(cc-switch 自己用 SQLite 状态管理,删它会破坏 cc-switch 切换)
   - **Hub 安装** `~/.hermes/skills/<name>/` —— `hermes skills install <hub-id>` 装的,跟 bundled 同级,受 `hermes skills uninstall` 管理。精简用 CLI,**不**直接动磁盘。**注意**:`hermes skills uninstall <name>` **只接受 hub-installed**;对 local/bundled 报 `"is not a hub-installed skill (may be a builtin)"` 并拒绝。`hermes skills config` **必须 PTY**(报 `'requires an interactive terminal'`),AI 跑不了。
2. **删文件一律走 trash,不用 rm**。用户明确偏好:`hermes-skill-curation` 范围内所有"删除 skill 目录"必须 `mv` 到 `~/.local/share/Trash/files/`,**不**用 `rm`/`rm -rf`;同时写 `~/.local/share/Trash/info/<name>.trashinfo`(XDG 规范)以便恢复。
3. **bundled skill 看似 read-only,实际可写**。`0555` 是文件权限位不是 mount 选项,`chmod -R u+w` 后即可 `mv`/`rm`。不要被"看起来是只读"骗到,绕远路去改 Hermes 安装源或用 sudo。
4. **skills_list 视图 ≠ 磁盘真实存在**。`skills_list` 返回 97 个,但磁盘上 bundled 目录只有 ~73 个,其余 24 个(agent-browser、guix-configs-workflow、kami、hyperframes 全套等)在你 Guix 部署里,**`find` 不到**。精简前用 `find ~/.local/share/hermes/skills -name SKILL.md | wc -l` 拿到真实数量,再用 `KEEP` 集合做 `existing - KEEP`,别信 `skills_list` 的返回数。

5. **`hermes_cli.skills_hub.do_list` 是 hermes 端的 source of truth**(光 `ls` 不算)。当用户说"我刚刚把 skill 备份/部署好了,看看 hermes 认不认"时,正确探针不是 `ls ~/.local/share/hermes/skills/<name>/`,而是**直接调 hermes 的 discover API**。它读 `_find_all_skills` + `HubLockFile` + `get_disabled_skill_names`,把 builtin/local/hub 三类合起来报,**还会**标出 disable 状态(`0 disabled` 才是部署成功):

   ```python
   import os
   os.environ.setdefault('HERMES_HOME', '/home/<user>/.local/share/hermes')
   from hermes_cli.skills_hub import do_list
   from rich.console import Console
   do_list(console=Console(force_terminal=False, no_color=True, width=200))
   ```

   关键参数:`force_terminal=False, no_color=True, width=200` 让 rich table 输出可被 AI 解析(默认会输出 ANSI 色码跟 box-drawing,在受限的 shell 渲染下乱)。

   **CLI 调不通时的 fallback**:`hermes skills list` 走 desktop 进程(常报 `ModuleNotFoundError: hermes_cli` 那种 broken venv 问题),直接用 Python API 调正在跑的后台 daemon venv(在 `ps -ef | grep 'hermes dashboard'` 找 `klnyl...-hermes-agent-env/bin/python3.12`,那是当前活着的 venv)。

6. **`blue stow` 不会覆盖已存在的目标 entry**。当用户的 `~/.local/share/hermes/skills/<name>/`(或 `~/.agents/skills/<name>/`)已经是个真目录(通常被另一个 `mutable/` 包部署过),新包 `blue stow <pkg>` **不会**替换这个目录——结果是顶层 entry 存在,但内部文件链(`SKILL.md` 是个指向仓库源的 symlink)**没建上**,agent 实际跑的时候读不到这个 skill。**症状**:`ls ~/.local/share/hermes/skills/<name>/SKILL.md` 是真文件但内容为空,或干脆 entry 是空目录。**修法**(任选):
   - `blue stow --adopt <pkg>` —— 收养目标现状,把当前内容挪进包源(适合"想保留 ~ 下现状"场景)
   - `blue stow --delete <pkg> && blue stow <pkg>` —— 干净重来(先把 ~ 下的 entry 删掉,stow 再建)
   - 跨包冲突场景(两个 `mutable/` 包都往 `~/.agents/skills/<x>/` 写):先 `blue stow --delete` 那个不该拥有此 entry 的包,只让一个包拥有该 path

   验证 deploy 真的生效的方式见 §1.5 —— `do_list` 是 source of truth,`0 disabled` 是最低门槛。

## 2. 标准精简协议(7 步)

### Step 1: 拍板前必须交叉验证

**最容易翻车的一步**。先别动手,先把决策交叉验证清楚:

- `KEEP` 集合与磁盘上真实存在的 skill 取**交集**(哪些"想保留"磁盘上根本不存在 → 不操作,只记录)
- `existing - KEEP` 得到**真正的待删清单**(不要直接按 `skills_list` 减 `KEEP`,会有 ~25 个伪差)
- **同一类目打包问**(智能家居/ML/社交/...),别一个个问 → 问 4-5 轮拍板所有类别。
- 拍板后用 `KEEP_NAMES` Python 集合 + `dry-run` 输出确认无误再 `--apply`。

### Step 2: 全局加写权限

```bash
chmod -R u+w ~/.local/share/hermes/skills/
```

不加这一句,所有 bundled skill 目录会 `PermissionError`(脚本里要捕获 `os.access(..., os.W_OK)` 跳过,记录到 skipped 列表)。

### Step 3: 用 trash,不用 rm

**XDG trash 范式**(用户偏好 + 可恢复):

```python
import shutil, datetime, pathlib
trash_files = pathlib.Path.home() / ".local/share/Trash/files"
trash_info = pathlib.Path.home() / ".local/share/Trash/info"
ts = datetime.datetime.now().strftime("%Y%m%d%H%M%S")
dest = trash_files / f"{ts}-{src.name}"   # 时间戳前缀防同名
info = trash_info / f"{dest.name}.trashinfo"
info.write_text(
    f"[Trash Info]\nPath={src}\n"
    f"DeletionDate={datetime.datetime.now().isoformat()}\n"
)
shutil.move(str(src), str(dest))
```

**禁止**:`os.remove`、`shutil.rmtree`、`rm -rf`(用户明确反对)。

### Step 4: 补刀嵌套目录

bundled skill 目录结构是 `mlops/{evaluation,inference,models}/<name>/`,`glob("*/<name>")` 抓不到。要么:

- `Path.rglob("SKILL.md")` 拿真实 `name`(路径倒数第二段)
- 或者显式列嵌套白名单

### Step 5: 恢复路径

```bash
# 从 trash 还原某个 skill
mv ~/.local/share/Trash/files/<ts>-<name> \
   ~/.local/share/hermes/skills/<category>/
```

注意 `~/.local/share/hermes/` 下的 Trash(`/home/brokenshine/.local/share/hermes/Trash/`)跟 `~/.local/share/Trash/` 是**两个不同位置**——trash 脚本里要用 `<skills_root>.parent / "Trash/files"`,别用 `~/.local/share/Trash/`。清理时优先用 `<skills_root>.parent/Trash`(就在 skill 目录隔壁,语义最近);软链接(symlink)删除时也要写 `.trashinfo` 记录 `LinkTarget=...`,不然恢复时只看到空名。

### Step 6: 验证 + 报告

- 重新跑 `find ~/.local/share/hermes/skills/ -name SKILL.md | wc -l` 确认最终数
- 输出 `trash 移动 N 个 / 跳过 K 个 / 失败 M 个` 三栏 + 完整路径
- 列"保留清单中磁盘上不存在的"(N 个) — 让用户知道为什么这些没动

### Step 7: 提醒"重建可能恢复"

bundled skill 来自 Hermes 安装包,下次 `blue rebuild` / Hermes self-update / `skills_list` 触发 lazy load 时可能从 upstream 重新拉回。**持久精简要在源头改**(`source/nix/configuration/programs/hermes.nix` 装 `minimal` 而不是 `full`,或者删 `~/Projects/Agent/hermes-agent/skills/<name>/SKILL.md`)。如果用户没要求持久化,只做 trash 就够了。

## 3. 反模式(本会话犯过的错)

- ❌ **直接 `rm -rf` 删 skill 目录** — 用户明确反对(且 trash 还能恢复)
- ❌ **相信 `skills_list` 返回 97,实际动手时按 97 算** — 磁盘只有 73,脚本会卡在"找不到目录"或者 `--apply` 报 0
- ❌ **不做 dry-run 直接 `--apply`** — 决策反复纠错时(本会话 28→50→29→14),需要 dry-run 反复回放,直接 --apply 等于拿用户数据试错
- ❌ **`glob("*/<name>")` 漏 mlops 嵌套** — 要 rglob SKILL.md
- ❌ **第一次拍板就把最终数字给用户** — 28/50/29/14 反复变化,先给"决策选项 + 数量",让用户**自己选**,不要代选
- ❌ **没有 chmod 就 --apply** — 脚本静默 0/52,让人以为是逻辑错
- ❌ **直接 trash builtin skill 当作"已卸载"** — 必须用 `hermes skills opt-out --yes` 写 `.no-bundled-skills` marker,否则下次 `hermes update` 拉回。trash 只是删副本,不是卸载语义
- ❌ **`hermes skills uninstall <local-skill>`** — local 不接受 uninstall,会报 "is not a hub-installed skill";要走 trash
- ❌ **`hermes skills config` 试图 echo 走 stdin** — 报 "requires an interactive terminal",必须 PTY,AI 跑不了
- ❌ **删 cc-switch 软链接指向的真实目录** — 软链接 `~/.config/agents/skills/docx` 指向 `~/.config/cc-switch/skills/docx`,cc-switch 用 SQLite 状态管理;只 `os.unlink` 软链接,不要删 cc-switch 那边的源

## 4.5 hermes CLI 关键路径(2026-06-21 确认)

- **二进制**:`~/.nix-profile/bin/hermes`(nix profile 装的,PATH **默认不含** —— `which hermes` 找不到,要用绝对路径或 `~/.nix-profile/bin` 加进 PATH)
- **不是**:`~/.nix-profiles/bin/hermes`(注意 profiles **复数 vs profile 单数**)
- **CLI 关键子命令**:
  - `hermes skills list` — 完整 4 列表(Name/Category/Source/Trust/Status)
  - `hermes skills opt-out [--remove] [--yes]` — 写 `.no-bundled-skills` marker + (可选)删未修改 bundled
  - `hermes skills uninstall <name>` — **仅** hub-installed;local/bundled 拒绝
  - `hermes skills config` — 交互式 enable/disable,必须 PTY
  - `hermes skills list-modified` — 列出 user-modified bundled(影响 `--remove` 行为)
  - `hermes skills audit` — 重新扫描 hub-installed 检查更新
  - `hermes curator {run,pause,resume,status,pin,unpin}` — 后台维护 daemon;`~/.local/share/hermes/.curator_state` 看状态
- **bundle 区分**:`Source` 列 `builtin`=Hermes 自带,`local`=dotfile 源,`hub`=第三方注册表

## 4. 用户咨询模板(本会话用过的,复用)

```text
Q1: 内容创作(PPT / 视频 / 设计 / 音乐)占多少比重?
    1. 完全不做,PPT/视频/设计类全删
    2. 偶尔做 PPT / 分享稿,PPT类全保留,其他删
    3. 偶尔做 PPT 也偶尔做点视觉
    4. 经常做(含 demo 视频、设计稿、音乐),这类全部保留

Q2: 知识管理用什么工具?
    1. Obsidian   2. Notion   3. Airtable   4. 纯 Org-mode(全删)

Q3: 是否跑本地 LLM / AI 模型 / ComfyUI?
    1. 完全不用,全部删   2. 偶尔从 HF 下模型
    3. 经常跑(含本地 LLM / ComfyUI)   4. 只跑 ComfyUI 出图

Q4: AI agent CLI 委派用哪个?
    1. 都不用(保留 hermes-agent,其他删)  2. 只 Claude Code
    3. 只 Codex   4. 都用

Q5: find-skills / pack-guix / 浏览器自动化 / 社交 CLI 等小项(逐项)
```

**经验**:多选场景下,先**分类打包问**(5 大类),再用单选问小项;每题给具体数字预期(留多少删多少),用户拍板时更有依据。

## 5. 边界

- 本 skill **不缓存** KB 卡片全文,只缓存精简协议本身。
- 任何细节冲突 → 以 `~/Documents/Org/experiences/` 对应 KB 卡片为准(session_search 召回)。
- 新增协议不写本 skill,直接写 KB 卡片(人类主笔);本 skill 周期性从 KB 提取。
- 持久化精简的"源头修改"路径(`hermes.nix` / `~/Projects/Agent/hermes-agent/skills/` 删除)不在本 skill 范围 — 那是 `guix-configs-workflow` 改源 + `blue rebuild` 流程。

## 6. 配套脚本

- `references/curation-scripts.md` — 三个验证过的脚本(builtin 批量 trash / local 含 symlink / 标准验证)+ 5 大类用户咨询模板。改 `KEEP_NAMES` / `TO_DELETE` 即可复用。
