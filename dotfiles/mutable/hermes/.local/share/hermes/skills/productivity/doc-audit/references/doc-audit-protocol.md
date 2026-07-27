# 全库文档校对协议(2026-07-27 实战沉淀)

> 适用场景：用户要求"遍历所有文档检查是否反映最新状态"或"简化 AGENTS.md"时,按本节协议系统性地完成校对。

## 1. 校对三问(每个文档必答)

1. **文档里的路径/包/文件实际存在吗?** 用 `search_files` 验证每个声称存在的路径。
   - `source/AGENTS.md` 的 files/ 下列出 `nftables.conf` / `zed.json` → 实际不存在 → 删
   - `docs/loopctl.md` 列出 `pi.json` adapter → 实际只有 `omp.json` → 改
   - `dotfiles/mutable/AGENTS.md` 列出 `pi` 包 → 实际不存在 → 删
2. **文档之间矛盾吗?** 同一实体在不同文档中的描述必须一致。
   - `docs/iso-build.md` §2.6 D1 说 KDE Plasma + sddm,但 §1.2 产物列表说 XFCE + lightdm → 以实际代码为准统一
   - `docs/iso-build.md` §2.6 D5 说 "sddm auto-login" → 实际是 lightdm → 改
   - `docs/iso-build.md` §2.6 D6 说 "显式加 kmscon" → 实际是删 kmscon → 改
3. **文档有冗余/可指针化吗?** 重复其他文档已有内容的段落,替换为指针。

## 2. AGENTS.md 简化原则(用户偏好 2026-07-27)

> **核心规则**: AGENTS.md 是给 AI 助手的路由表,不是代码副本。任何可以从其他文件、指令、源码直接获取的内容,一律指针化。

**简化手段优先级**:

| 手段 | 示例 | 何时用 |
| ---- | ---- | ------ |
| **指针替代代码块** | 把 `(service home-dotfiles-service-type ...)` 完整 scheme 块替换为 "详见 `dotfiles/AGENTS.md`" | 代码块是某配置的完整声明,而该配置已有专属文档 |
| **指针替代重复描述** | 把 Emacs 启动路径的详细描述替换为 "详见 `dotfiles/mutable/emacs/.config/emacs/AGENTS.md`" | 同一内容在多个 AGENTS.md 中重复出现 |
| **删除死引用** | 删掉不存在的 `pi` 包、`nftables.conf` 文件、`pi.json` adapter | 引用的实体已不存在 |
| **精简语言** | "所有 `dotfiles/immutable/<app>/` 子目录统一通过 Guix Home 的 `home-dotfiles-service-type`(`layout 'stow`)" → 一句话概括 | 段落是另一文档的口头摘要 |

**硬约束**:
- **不删 structor 标记对** —— `<!-- structor:begin -->...<!-- /structor -->` 是自动维护的,保留
- **不删路由表** —— 任务路由表是 AGENTS.md 的核心价值,保留
- **不删硬约束** —— `<critical>` 块里的路由硬约束,保留
- **删整段冗余代码** —— scheme 代码块如果只是重复 `source/config.org` 里的声明,删

## 3. 80 列硬换行清理(用户偏好 2026-07-27)

> **规则**: Markdown 源文件**不**强制 80 列断行。GUI 渲染器里无视觉收益,反而让 `patch` 模糊匹配更难、源文件难编辑。段落内自然换行即可。

**操作**:
- 用 `search_files` 找 `^.{80,}$` 匹配的行
- 把硬断行合并回自然段落(注意保留表格、代码块等结构化内容的格式)
- 表格行、列表项、标题不在此列

## 4. 校对产出清单

完成全库校对后,报告应包含:

1. **事实错误修正列表** —— 每个修正注明:文件、行号、错误内容、修正依据(实际代码/文件存在性验证)
2. **冗余清理列表** —— 每个清理注明:文件、删了什么、替换为什么指针
3. **一致性修正列表** —— 每个修正注明:哪些文档矛盾、以谁为准、统一后的表述

## 5. 本次(2026-07-27)实战修正记录

### 5.1 事实错误修正

| 文件 | 行号 | 错误 | 修正 | 依据 |
| ---- | ---- | ---- | ---- | ---- |
| `source/AGENTS.md` | 90-96 | files/ 下列出 `nftables.conf`、`zed.json` | 删除 | `search_files` 验证不存在 |
| `dotfiles/mutable/AGENTS.md` | 92-96 | 列出 `pi` 包 | 删除 | `dotfiles/mutable/` 下无 `pi/` 目录 |
| `docs/loopctl.md` | 82 | 列出 `pi.json` adapter | 删除 | `adapters/` 目录下只有 `omp.json` |
| `docs/loopctl.md` | 484 | 示例用 `--adapter pi` | 改为 `--adapter omp` | 同上 |
| `docs/loopctl.md` | 517 | 示例用 `adapter show pi` | 改为 `adapter show omp` | 同上 |
| `docs/iso-build.md` | 138 | D1 决策说 KDE Plasma + sddm | 改为 XFCE Desktop + lightdm | 实际 `source/config.org` 的 `live-installation-os` 跑的是 XFCE |
| `docs/iso-build.md` | 142 | D5 说 "sddm auto-login" | 改为 "lightdm auto-login" | 同上 |
| `docs/iso-build.md` | 143 | D6 说 "显式加 kmscon" | 改为 "显式删 kmscon" | §3.7 明确说删 kmscon + console-font |
| `dotfiles/disable/waybar-suite/AGENTS.md` | 14 | structor 树中目录名写 `desktop-suite/` | 改为 `waybar-suite/` | 实际目录名 |

### 5.2 冗余清理

| 文件 | 清理内容 | 替换为 |
| ---- | -------- | ------ |
| 根 `AGENTS.md` | 删除 dotfiles 部署模型的完整 scheme 代码块 | 指针 "详见 `dotfiles/AGENTS.md`" |
| 根 `AGENTS.md` | 删除 Emacs 启动路径的详细描述 | 指针 "详见 `dotfiles/mutable/emacs/.config/emacs/AGENTS.md`" |
| `dotfiles/AGENTS.md` | 删除部署机制的 scheme 代码块 | 保留纯文本描述 |
| `dotfiles/AGENTS.md` | 删除重复的 "核心子系统" 段落 | 各子目录指引表已覆盖 |

### 5.3 一致性修正

| 矛盾文档 | 矛盾点 | 以谁为准 | 统一后 |
| -------- | ------ | -------- | ------ |
| `docs/iso-build.md` §2.6 vs §1.2 | 桌面环境 | §1.2 产物列表(XFCE) | 全部统一为 XFCE + lightdm |
| `docs/iso-build.md` §2.6 D6 vs §3.7 | kmscon 操作 | §3.7(删 kmscon) | D6 改为 "删 kmscon" |
| `docs/loopctl.md` vs 实际 adapters 目录 | pi.json | 实际目录(无 pi.json) | 删 pi 相关引用 |
