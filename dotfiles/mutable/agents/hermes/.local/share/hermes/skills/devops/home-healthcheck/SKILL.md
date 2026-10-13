---
name: home-healthcheck
description: "诊断家目录失控感并交付只读体检工具。触发：家目录乱/超出控制/清 agent 尸骸/盘点长胖目录。"
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [home-hygiene, disk-audit, visibility, read-only, cleanup-triage]
---

# Home Healthcheck

诊断「我的电脑超出我控制了」这类诉求，并交付一个**只读**体检工具让它保持可见。

核心立场：**报告，而非治理**。工具只回答「有多少、在哪、谁在长」，不判定「该不该删」——哪些该留只有用户知道（Steam 沙箱数据、某个还在用的 agent 家目录）。越权判定的脚本会在用户不在场时做出看起来很对的误判。

## When to Use

- 用户说「家目录一团糟」「超出我的控制」「很久没敢看某些目录」
- 要清理：试过一次的软件/agent 残留、精简掉但没清的东西、临时资料
- 用户抱怨配置仓库越来越复杂、脚本越来越多、看不懂的地方变多
- 想定期知道「什么在长胖」而不想每次手动翻

## 触发后第一件事：先测量，再提方案

**在看到真实数字之前不要给方向。** 这类诉求几乎从不是空间危机，而是可见性危机——凭感觉开出的「清理方案」通常清掉 20G 而用户照样觉得失控，还附带误删风险。

先跑这些（可并行，具体命令见 `references/probes.md`）：

```bash
# HOME 顶层规模（并行 du，避免单点超时拖垮整份报告）
{ for d in "$HOME"/*/ "$HOME"/.[!.]*/; do [ -d "$d" ] && printf '%s\0' "$d"; done; } \
  | xargs -0 -P 4 -I{} bash -c 'timeout 180 du -sh "$@" 2>/dev/null' _ {}

# 磁盘真实余量
df -h /home /gnu

# 每个仓库的同步债（未提交 = 未提交，未推送 = 无备份）
find ~/Projects -maxdepth 3 -name .git -type d | sed 's|/.git$||' | while read r; do
  cd "$r" || continue
  printf '%-46s dirty=%-4s unpushed=%s\n' "${r/#$HOME\//~/}" \
    "$(git status --porcelain | wc -l)" "$(git rev-list --count @{u}..HEAD 2>/dev/null || echo NOUP)"
done
```

`~/.cache` 是高频漏项——它不匹配 `~/.*` 的常规扫描口径，却能到几十 G。顶层散落文件也单列一段。

## 三层分类法（决定什么能动）

| 层 | 判据 | 处置 |
|---|---|---|
| ① agent 尸骸 / 迁移残留 | 每个 CLI 试一次就永久落户的家目录；内部最新 mtime 很久以前 | 零决策成本，清（走 trash-put） |
| ② 会自己长胖的 | Wine 前缀、flatpak repo、包管理器缓存、容器镜像、游戏沙箱 | **不自行判定**，报给用户 |
| ③ 在工作的 | 用户明确在用的 agent、配置源、Guix store | 不动 |

判「① 是否真的死了」要两条证据齐上：**内部最新 mtime** + **是否被 dotfiles 仓库引用**。只凭名字像尸骸就清是这类任务最贵的错误——`~/.rustup` 曾被当成迁移残留，实际某个项目锁定了它的 nightly toolchain，系统版 cargo 会直接编译失败。

清理前逐个确认，用 clarify 摆选项，不要批量猜。

## 排序：数据风险 > 空间风险

未推送的本地 commit 等于没有备份，磁盘一坏全没；而空间 56% 占用通常不急。**先报同步债，再报可回收空间。**

可回收空间按「安全性」排序给：

1. 包管理器缓存（`~/.cache/{uv,npm,pnpm,pip,cargo,guix,nix,rattler}`）——清了只损失重下时间，且会立刻长回来。单列一节：**它的价值不是省空间，是让增长可见**。
2. Trash（逐项确认，最大项单独问）
3. flatpak repo 中超出已装 app 的差额（历史版本）
4. rustup `tmp/` + `downloads/`（toolchains 不动）

## 交付物：只读体检脚本

放进配置仓库的 `immutable/utilities/.local/bin/`（与既有脚本同层），五段输出：磁盘 / HOME 顶层 top15 / 会长胖目录 / 仓库同步债 / 可回收空间与缓存。

同一次改动内必须完成的登记（缺一项 `blue check` 或 `toolbox check` 会红）：

- `tools/toolbox/.local/share/toolbox/tools.yaml` 加一条
- `terminal/.config/fish/completions/<name>.fish`（无参工具 `complete -c <name> -f`）
- `docs/scripts/misc-scripts.md` 加一节 + `docs/scripts/README.md` 索引行

**immutable 包新建文件后，`toolbox check` 会报「清单条目在部署位找不到」**——预期行为，要 `blue home` 重建才进 `~/.local/bin`。先原地 `bash <源文件路径>` 跑通再提交，别等部署。

写脚本时每个 `du` 套 `timeout`：单个超大目录超时只该让那一行空着，不该让整份报告中断。

## 用户偏好（本类任务恒定）

- **不要主动提「我把每条改动讲给你听」。** 用户自己看过那些 commit，逐条 walkthrough 是重复劳动。推送/同步债状态给「数量 + 每条一行标题」的一句话概览就够；要细节先问。
- **不要为了「更完善」新建体系。** 「再多一套管理机制」正是失控感的成因。加一条只读命令 + 一条边界规则，不开新工具、不建新目录。
- **配置仓库「看不懂」的解法不是提前拆文件。** 它在工作，拆它有真实风险。等用户真被某段卡过，只给那一段补一句「为什么」。
- 给用户拍过板的方向不再游说；已定的事执行即可。

## Pitfalls

- **本环境 `rm` 被冻结，且命令文本里出现 `rm` 字样也会被 hook 误拦。** 删除一律 `trash-put`；写循环时连 `rm -f` 这样的清理片段都可能让整条命令在执行前被拒。需要临时文件就先写后 `trash-put`，或 `mv` 到 `/tmp` 留可恢复副本。
- **`du -sh ~/.*` 一类 glob 会漏东西**，`~/.cache` 之外还有顶层散落文件——两个都单独列一段。
- **「清理过」不等于清掉了。** Trash 里躺着的东西用户以为没了——报 Trash 体积与项数，别默认它是空的。
- **别把 `guix gc` 当成大头。** 先看代数（见 `references/probes.md`）；代数少时 store 基本是活跃内容，回收不了多少。
- **提交时只 add 自己改的文件。** 工作区常有并行会话的未提交改动，一并提交会把别人的活计混进你的 commit。
- **宣称「远程可推」前先在无头条件下验证凭据。** 前台通过可能是吃着 GUI 解锁的凭据；口径见 `references/probes.md`。

## References

- `references/probes.md` — 各层探测的具体命令：并行 du、mtime+引用双重判活、仓库同步债、git remote 内嵌 token 扫描、无头凭据验证、guix 代数。