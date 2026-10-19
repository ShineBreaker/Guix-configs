---
name: termux-configs-workflow
description: 维护 termux-configs（手机 Termux 配置仓库）：just 指令、UniEmacs 接入。
version: 0.1.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [termux, dotfiles, just, uniemacs]
    related_skills: [guix-configs-workflow]
---

# termux-configs 仓库维护（手机端 Termux 配置）

## When to Use（何时用）

- 在 `~/Projects/Config/termux-configs` 里改配置、加/改 `just` 一键指令、动 `setup.sh` / `dot`
- 手机（真机 Termux）侧 Emacs 配置接入（UniEmacs）与部署排障

仓库自身的 `AGENTS.md` 在仓库内工作时自动注入（结构、文档同步表、检查清单、commit 规范），是本仓库的权威指引。本技能只补它没有的：跨仓库上下文、指令设计偏好、验证配方与坑。

## 相关仓库生态

| 仓库 | 关系 |
|------|------|
| termux-configs（本仓库） | 手机端 Termux 配置；stow 包 + setup.sh + dot 命令 + justfile |
| UniEmacs | Emacs 配置（桌面 + 手机共用）；手机侧 clone 到 Termux `~/.config/emacs`；桌面上它是 Guix-configs 的子模块 |
| Guix-configs | 桌面配置仓库，有自己的 `guix-configs-workflow` skill |
| termux-emacs | 为 Emacs 重签 Termux 系 APK 的独立仓库（`ShineBreaker/termux-emacs`：主程序 + 全部官方插件，CI 自动跟进上游）；UniEmacs 原重签流水线已剥离至此 |

用户说「仓库里改了文案」时不指定哪个仓库时：先对候选仓库各跑 `git status --short` / 看最近 commit，别默认是本仓库。

## justfile 约定（新增/修改指令时）

- **薄入口原则**：`justfile` 只做转发——`setup`/`install`/`export` → `setup.sh`，`status` → `dot status`，`install-emacs` → clone 后调 UniEmacs 自带的 `just emacs`。任何逻辑都不在本文件重新实现（单一真相源）。
- **配方注释第一行即 `just --list` 菜单文本**：一句话、中文、清晰易懂。
- **移动端体验优先（用户明确要求）**：名字短而自明（`install-emacs` 而非缩写）、指令总数少而全、`just` 裸跑必须直接出菜单（`default: @just --list`）、不要复杂参数。
- **依赖清单类内容一律不复制**：Termux 包列表等指向上游入口（UniEmacs `just termux-deps`），上游迭代自动跟进。
- **just 的工作目录 = justfile 所在目录**（从仓库任意子目录调用，recipe 都以仓库根为 cwd）——配方里写相对路径（`bash setup.sh`、`for pkg in */`）是安全的。
- 新增指令后按 AGENTS.md 同步表更新 `README.md` 指令表、`docs/keybindings.md`、`cheat.fish`。

## UniEmacs 手机侧接入（跨仓库事实）

- **部署两处、缺一不可**：仓库本体 clone 到 Termux 的 `~/.config/emacs`（TUI emacs 直接读它，无需其他步骤）；Android 原生 Emacs 另需把入口两文件（`early-init.el`、`init.el`）副本放到 `/data/data/org.gnu.emacs/files/.emacs.d/`。`just install-emacs` 只负责 Termux 侧（clone + 依赖），入口副本属应用侧。
- **依赖走上游一键**：`just emacs`（= termux-deps → font → icons → packages）；`termux-deps` 在 Termux 上装 `curl unzip fontconfig emacs git sqlite ripgrep`，桌面自动跳过。首次插件预构建耗时数分钟。
- **`install-emacs` 行为**：`~/.config/emacs` 已存在且是 git 仓库 → 跳过 clone、直接补依赖（可重复运行）；已存在但非 git 仓库 → 报错退出，不覆盖用户配置。
- **Termux 系 APK 必须是重签版**（与 Emacs 同签名，sharedUserId 机制）：主程序与插件都从 `ShineBreaker/termux-emacs` 的 Releases 拿（原 UniEmacs 重签流水线已剥离到该仓库），否则 Termux 子进程互通不可用。
- **UniEmacs 迭代极快**（文案、依赖清单、部署路径都可能变）：一切细节以它自己的 `docs/mobile/README.md` 为准，本仓库不做镜像。

## 变更验证配方（桌面可全跑）

```bash
cd ~/Projects/Config/termux-configs
bash -n setup.sh
fish -n fish/.config/fish/conf.d/*.fish fish/.config/fish/config.fish fish/.config/fish/functions/cheat.fish
just --list && just                       # 语法 + 裸跑菜单
fish -c 'source fish/.config/fish/functions/cheat.fish; cheat' | head -40   # cheat 实际输出
```

### 脚本类配方的隔离冒烟（restow / install-emacs 等，绝不碰真实家目录）

假仓库 + 假 HOME + 真实 just 执行：

```bash
S=$(mktemp -d)
mkdir -p "$S/repo/bin/.local/bin" "$S/repo/fish/.config/fish" "$S/repo/docs" "$S/home"
echo x > "$S/repo/fish/.config/fish/config.fish"
cp justfile "$S/repo/" && cd "$S/repo"
HOME="$S/home" just restow        # 验证链接建立 + docs 被跳过 + 可重复执行

# install-emacs 分支：空目录应报错退出
mkdir -p "$S/home2/.config/emacs" && HOME="$S/home2" just install-emacs
# 已存在 git 仓库：git init + 假 justfile（emacs: @echo OK）验证调用链走到 just emacs
```

## 坑

- **stow 折叠**：链接后 `ls -l ~/.local/bin/dot` 显示普通文件并不代表链接坏了——中间目录被折叠成目录级 symlink 后 `ls` 会穿透显示最终文件。验证要逐层 `ls -ld` 或 `readlink`，别据此误判重链失败。
- **`set -euo pipefail` 脚本里不用 `[ cond ] && continue`** 这类裸短路：条件为假时整条 AND 列表返回非零会触发退出；写成 `if [ cond ]; then ... fi`。
- **setup.sh 里加工具依赖沿用 `ensure_xxx` 模式**：`if pkg install -y X; then ...; else print_warning`（安装失败只警告不中断）——工具只是便捷入口，不应阻断主安装流程。
- 修改 `justfile` 后在仓库子目录跑一次裸 `just`：`default` 配方的菜单输出是最容易坏且最早被用户看到的地方。
- 交付涉及真机（Termux/Android）的改动时，桌面验证完成仍要标注「待真机验证」——重签 APK、pkg 安装、触屏路径桌面不可达。
