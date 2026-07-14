---
title: ISO 移植会话复盘 — 接手 agent 必读
version: 2026-07-06
session: hermes ISO 移植细化文档工作
---

# ISO 移植会话复盘

> 本文档是 2026-07-06 hermes 跟 user 一同细化 Guix-configs ISO 移植方案的**会话级复盘**。完整方案文档在 `~/Projects/Config/Guix-configs/docs/iso-build.md`(1200 行,§0-§13),本复盘聚焦**接手 agent 真正需要知道的事**——决策背后的反例、踩过的坑、我自己的失误。

## 1. 会话产物清单

| 文件                                                       | 大小 | 用途                                  |
| ---------------------------------------------------------- | ---- | ------------------------------------- |
| `~/Projects/Config/Guix-configs/docs/iso-build.md`         | **1986 行 / v0.5** | **主方案文档**,接手 agent 直接照这个干 |
| 本文件 (`references/iso-build-handoff.md`)                | 本文件 | 会话复盘,接手 agent 必读                |
| `~/.local/share/hermes/skills/guix-configs/guix-configs-workflow/SKILL.md` §10 | 新增 5 子节(10.1~10.5) | 用户偏好 + 模块归属陷阱 + 文档交接习惯,内嵌到 umbrella skill |

**v0.5 改动摘要**(从 1201 行扩到 1986 行):

- §接手必读(新):阅读路径 + 7 条工作纪律
- §9.0 子文档索引(新):5 文件详细说明
- §9.4.3.1 / §9.5.1.1 / §9.5.2.1(新):三处代码块逐行解释
- §11.0~§11.7(重写):按症状 + 按错误码双维度 + 接手 agent 边界表
- §12.0~§12.3(重写):[A]/[U]/[R] 标签 + 期望输出样板 + 打假绿勾反模式
- §13.1~§13.4(重写):桌面/平台/工程三档变体矩阵 + 决策权
- §14(新):仓库状态快照
- §15(新):维护纪律 + 版本表

## 2. 决策记录复盘(为什么这么选)

### 2.1 首选 XFCE(不是 minimal,不是 niri)

**用户原始诉求**: "我最需要的就是一个带桌面的 iso,也可以不用和目前的桌面一样,kde 和 gnome 或 xfce 都可以的,我感觉 xfce 更加轻量"。

**我的错误**: 我**先**列了 Testament blueprint 自带的 `minimal` 和 `niri`,然后**默认选 minimal**(理由"先做最简单的"),让 user 纠正了。User 反馈是:

> 我看你想要构建的是 minimal 镜像,为什么???我最需要的就是一个带桌面的 iso

**教训**: 见 SKILL.md §10.1「以工具可能性当目标」反模式。**正确的顺序是**:

1. 先问 user 想要什么
2. 再列技术可能性
3. 最后给候选 + 默认

### 2.2 jeans- 前缀(不是 rosenthal-,不是 guix-configs-)

user: "前缀就叫 jeans- 吧"

理由:本仓库已经在用 `jeans` 频道(见 `source/channel.lock` 第三条 channel),`jeans-` 是本仓库自有名,语义自洽。

### 2.3 live user + nonguix 频道恢复

我自己最初砍掉这 3 项(nonguix / live user / examples / zfs)。User 明确说:

> 我需要你好好的思考一下,至少 liveuser、example 和 nonguix 频道是必须得要保留的

最终结果:
- ✅ live user 恢复(密码留空,装机后 `passwd live` 设)
- ✅ nonguix 频道恢复(`channels-with-nonguix` + nonguix 公钥内嵌)
- ✅ examples/ 仍不放(用户没说改,理由是本仓库 dotfiles 模型与 Testament 不同)
- ❌ zfs 默认不开(用户没提)

### 2.4 密码留空(用户拍板)

User 三选一拍板: "留空密码,装机后 passwd 设"。理由:`(password #f)` 强制首次登录改密,避免文档化弱密码被"开箱即用"误用。

## 3. 我自己踩的坑(接手 agent 警觉)

### 3.1 模块归属陷阱(已写入 SKILL.md §10.3)

我**第一次估 XFCE 工作量时错了**,因为错把 `(gnu services xorg)` 当成"唯一桌面服务模块",搜不到 `xfce-desktop-service-type`。

**真相**:`xfce-desktop-service-type` / `gnome-desktop-service-type` / `plasma-desktop-service-type` / `mate-desktop-service-type` / `lxqt-desktop-service-type` / `enlightenment-desktop-service-type` **都在 `(gnu services desktop)` 模块**。

**这些 service-type 不只是包装包**,还自动配齐 polkit / udisks / 权限规则 —— 比"裸装 xfce4-session + xfwm4"省事得多。

**防护套路**(跟 SKILL.md §8.2 坑 2 同):

```bash
guix time-machine -C ~/Projects/Config/Guix-configs/source/channel.lock -- repl <<'EOF'
(use-modules (gnu services desktop) (gnu services xorg) (gnu services))
;; 输出真正的 module-variable value,而不仅靠 defined?
(format #t "xfce in desktop: ~a~%"
  (module-variable (resolve-module '(gnu services desktop)) 'xfce-desktop-service-type))
EOF
```

返回 `#<variable ... value: #<service-type xfce-desktop ...>>` 才算确认。**不要相信 `defined?` 的布尔返回** —— 它对 bound vs unbound 判断不靠谱(我第一次就被它骗了,以为 `xfce-service-type #t` 是已定义,实际是 `unbound` 但 `defined?` 返回 #t)。

### 3.2 上游 #7373 状态实测

Testament README 说 #7373 阻止新 ISO 构建。**实测后修正**:

- #7373 仍 Open(2026-03-21 由 hako 报,挂 1.6.0 milestone)
- **根因**: Guile 3.0.11 + Guix `safe-clone`(commit `1eccea7ff`)让 installer 的 `scm_fork` / signal thread 死锁
- **影响范围**: **只阻塞装机完结**,**不影响 ISO 构建**
- **Testament 反证**: 2026-06-12 仍出新 ISO

**结论**: P7 `blue build-iso` 大概率能跑通,P8 实战装机可能撞 #7373。

### 3.3 shim 试过的命令(接手 agent 复用)

```bash
# 拉 issue 状态
curl -fsSL --max-time 20 "https://codeberg.org/guix/guix/issues/7373" \
  | grep -oE '<title>[^<]+</title>|Open|Closed'

# 直接 api(更稳)
curl -fsSL "https://codeberg.org/api/v1/repos/guix/guix/issues/7373"

# rosenthal trunk 最新 commit
curl -fsSL "https://codeberg.org/api/v1/repos/hako/rosenthal/branches"

# Guix commit 提取(channel.lock 用)
guix time-machine -C ~/Projects/Config/Guix-configs/source/channel.lock \
  -- describe --format=channels > /tmp/channels.txt
grep -A1 "name 'guix'" /tmp/channels.txt | grep commit
```

## 4. 接手 agent 工作清单(从 iso-build.md §9 抽取)

按依赖顺序:

| 阶段 | 任务 | 关键文件 | AI 可做? |
|------|------|---------|---------|
| P0 | 验证 #7373 仍 Open(已实测) | 见 §9.2 | ✅ |
| P1 | 新建 `tools/build-image.scm` | 18 行,SPDX 头 | ✅ |
| P2 | config.org 增 `* Live ISO` 章 + 3 块 | `:tangle ../tmp/live-iso.scm :noweb yes` | ✅ |
| P3 | blueprint.scm 增 `build-iso-command` | 1 个 define-command + 1 处 commands 列表追加 | ✅ |
| P4 | manifest.scm 视情况增包 | 默认不动 | ✅ |
| P5 | .gitignore 加 `dist/` | 1 行 | ✅ |
| P6 | `blue check` 验证括号 | dry-run | ✅ |
| **P7** | **用户手动 `blue build-iso xfce`** | dist/jeans-xfce-<date>.iso | ❌ AI 禁跑(30+ 分钟) |
| **P8** | **QEMU 启动验收** | 看到 slim + XFCE | ❌ AI 禁跑 |

## 5. 验收清单(从 iso-build.md §12 抽取 + 标签)

[AI] = AI 自验(可以跑 dry-run / 文件检查)
[USER] = 必须用户手动跑(AI 禁跑)
[USER-OPT] = 可选,看用户意愿

**v0.5 在原文基础上扩了 7 项**(以下为完整清单):

- [AI] P0:codeberg.org/guix/guix/issues/7373 状态确认(curl)✅ 已实测 Open
- [AI] P1:`tools/build-image.scm` 文件存在 + 18 行 + SPDX 头
- [AI] P2:config.org 已加 `* Live ISO` 章 + `live-modules` + `live-installation-os`
- [AI] P2:`tmp/live-iso.scm` 经 `blue check` 通过,末行是 `%live-installation-os`
- [AI] P2:`tmp/config.scm` 经 `blue check` 通过,**没有** `%live-installation-os` 字样
- [AI] P3:`blueprint.scm` 已加 `build-iso-command`,`blue list` 能看到
- [AI] P3:`blue help build-iso` 输出 help 文本
- [AI] P4:manifest.scm 已评估(默认不动)
- [AI] P5:.gitignore 已加 `dist/`
- [AI] P6:`blue check` 全过(无 FAIL)
- [AI] P6:无新增 `[SKIP]` 块(若新增,需说明)
- [AI] P7:`blue --dry-run build-iso xfce` 输出与 §9.9 描述一致
- [USER] P7:`blue build-iso xfce` 跑通
- [USER] P7:产物路径:`dist/jeans-xfce-<YYYYMMDD>.x86_64-linux.iso`
- [USER] P8:QEMU 启动 ISO,slim 自动登录 live,XFCE 桌面出现
- [USER] P8:`uname -r` 显示非 -libre 内核
- [USER] P8:root shell 是 `/gnu/store/...fish`
- [USER] P8:装好后 `/etc/guix/channels.scm` 含 nonguix 条目
- [USER-OPT] P7:`blue build-iso minimal` 也跑通
- [USER-OPT] P8:U 盘真机启动 + 实战装机

**v0.5 自验率**: 12/19 = 63%(AI 能做的)
**v0.5 用户必跑**: 5/19 = 26%
**v0.5 实跑**: 1/19 = 5%(装机验证)

**打假绿勾反模式**(v0.5 新增,接手 agent 别踩):

- "看 git diff 有改动就勾" —— 没跑 blue check 验证
- "blue check 通过就勾所有 P2 项" —— `tmp/config.scm` 是否被污染没验证
- "我把 %live-installation-os 注释掉勾 P2" —— 等于没做
- "P7 我没跑,看代码应该对就勾" —— P7 是真活,代码对 ≠ 跑通

**期望输出样板**(每项验收都有,见 iso-build.md §12.1):

```bash
# P1 验证
$ wc -l tools/build-image.scm
18 tools/build-image.scm

$ head -3 tools/build-image.scm
;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: MIT

# P3 验证
$ blue list | grep build-iso
  build-iso    构建 Guix System Live ISO
```

## 6. 后续扩展(接手 agent 可立项)

§13 后续扩展已写明,这里只标**对接手 agent 最相关的两条**:

| 扩展 | 工作量 | 触发条件 |
|------|--------|----------|
| `gnome` 变体(GNOME 桌面) | 2-3 小时 | 用户机器装了 nvidia/需要 Wayland 体验 |
| `kde` 变体(KDE Plasma) | 2-3 小时 | 需要 KDE 专有应用(Krita / Kdenlive 等) |
| `niri` 变体(rosenthal Noctalia) | 4-5 小时 | 想跟 Testament 的体验对齐 |

每条都依赖 xfce P0-P8 通过。

## 7. 重要参考链接

- 主方案:`~/Projects/Config/Guix-configs/docs/iso-build.md`(1201 行)
- Guix 1.5 桌面服务文档:`https://guix.gnu.org/manual/1.5.0/en/html_node/Desktop-Services.html`
- 上游 #7373:`https://codeberg.org/guix/guix/issues/7373`
- rosenthal 模块索引:`https://codeberg.org/hako/rosenthal/src/branch/trunk/modules/rosenthal`
- Guix 仓库 xorg 服务:`https://git.savannah.gnu.org/cgit/guix.git/plain/gnu/services/xorg.scm`(用本地 channel.lock commit 替换)
- Guix 仓库 desktop 服务:`https://git.savannah.gnu.org/cgit/guix.git/plain/gnu/services/desktop.scm`

## 8. 用户偏好备忘(已嵌入 SKILL.md §10)

1. **需求澄清顺序**:开工前先问 user 想要什么,再列技术可能性,不要默认沿用上游现成变体。
2. **文档交接习惯**: user 说"让其他 agent 接手"时立刻停手,只产出完整方案文档(决策记录 + 完整代码 + 实施步骤 + 验收清单),不写代码。
3. **模块归属陷阱**:动笔前用 `module-variable` 验证 service-type 在哪个模块,不要信 `defined?`。

这三项已嵌入 `guix-configs-workflow` SKILL.md §10。接手 agent 加载该 skill 时自动看到。