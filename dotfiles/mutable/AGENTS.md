# dotfiles/mutable/ — GNU Stow 源目录

本目录管理**频繁变动且需要版本备份**的配置文件，与 `dotfiles/immutable/`（Guix Home stow，源只读）的部署模型互补：

| 维度         | `dotfiles/immutable/`                                    | `dotfiles/mutable/`                                                     |
| ------------ | -------------------------------------------------------- | ----------------------------------------------------------------------- |
| 部署机制     | Guix Home `home-dotfiles-service-type`（layout `'stow`） | GNU Stow（`blue stow` → `stow --dir=dotfiles/mutable --target=$HOME`）  |
| 源-目标关系  | 软链接到 `/gnu/store` 只读副本                           | **单文件**软链接直接到 `dotfiles/mutable/PKG/` 仓库源                   |
| 目标目录形态 | 软链接到 store 只读副本                                  | **默认真实目录**（`--no-folding`，运行时可写入）；可按包 opt-in folding |
| 改源后生效   | 必须 `blue home`                                         | **无需任何命令，直接生效**                                              |
| 适合场景     | 稳定的配置文件（niri、fish 等）                          | 频繁手改、需要 git 备份追踪（如 emacs、hermes）                         |
| 版本控制     | git 跟踪 + Guix store hash                               | git 跟踪（无中间层）                                                    |

## 部署模型：默认 no-folding，可按包 opt-in folding

> 核心约束：**目标目录默认保持为真实目录，stow 只对单个文件建软链接**。这避免应用运行时产物（`logs/`、`state.db`、`sessions/` 等）经整目录软链写进仓库源。

> **folding 控制**：在 `dotfiles/mutable/<PKG>/` 下放一个 `.stow-folding` 标记文件（空文件即可），即对该包启用 tree folding（目标目录本身折叠成单条指向源的软链）。无标记的包走默认 `--no-folding`。`blueprint.scm` 每次调用 stow 时都带 `--ignore=\.stow-folding$`，确保标记文件本身不会被部署到 `$HOME`。

`.stow-local-ignore` 语法：**Perl 正则，逐行一条，匹配路径尾部**；`#` 起注释、空行允许（见 Stow 手册 "Ignore Lists"）。

## 目录结构

<!-- structor:begin depth=4 -->

<!-- 此树形目录由 structor 自动生成，请勿手动编辑。 -->

```
mutable/
├── agenote/
│   ├── .config/
│   │   └── agents/
│   │       └── skills/
│   ├── .local/
│   │   └── bin/
│   │       ├── ag_lib/
│   │       ├── ag-ent
│   │       ├── agenote
│   │       ├── agenote_cli.py
│   │       ├── agenote_mcp.py
│   │       └── orgfmt
│   ├── .stow-folding
│   └── .stow-local-ignore
├── appimage-run/
├── emacs/
│   ├── .config/
│   │   ├── agents/
│   │   │   └── skills/
│   │   └── emacs/
│   │       ├── data/
│   │       ├── docs/
│   │       ├── scripts/
│   │       ├── test/
│   │       ├── .gitignore
│   │       ├── early-init.el
│   │       ├── emacs.org
│   │       └── init.el
│   ├── .local/
│   │   └── share/
│   │       └── applications/
│   └── .stow-local-ignore
├── hermes/
│   ├── .local/
│   │   ├── bin/
│   │   │   ├── hermes
│   │   │   ├── hermes-desktop
│   │   │   ├── hermes-desktop-manifest.scm
│   │   │   ├── hermes-update
│   │   │   └── hermes-version
│   │   └── share/
│   │       ├── applications/
│   │       └── hermes/
│   ├── .stow-folding
│   └── .stow-local-ignore
├── secrets/
│   ├── .local/
│   │   └── share/
│   │       ├── keys/
│   │       └── secrets-encrypted/
│   └── .stow-local-ignore
└── skills/
    ├── .config/
    │   └── agents/
    │       └── skills/
    └── .stow-folding
```

<!-- /structor -->

## 当前纳管的包

| 包       | 部署目标                                                                                                         | 包含文件                                                                                                                                                                                                         |
| -------- | ---------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `hermes` | `~/.local/share/hermes/`                                                                                         | SOUL.md、config.yaml、memories/MEMORY.md、memories/USER.md                                                                                                                                                       |
| `emacs`  | `~/.config/emacs/`                                                                                               | 子模块 `codeberg.org/BrokenShine/.emacs.d`（init.el、early-init.el、core/、configs/ 等）                                                                                                                         |
| `pi` | `~/.config/pi/`、`~/.local/share/pi/scripts/` | oh-my-pi (omp) 配置：`config.yml`、`models.yml`、`mcp.json`、`global-context.json`、`APPEND_SYSTEM.md`、`extensions/{pi-gate,agenote-hooks,global-context}`（自写扩展，agent 本体由 omp 官方安装脚本部署）；`share/pi/scripts/` 辅助脚本； |

## 工作流

### 修改已纳管的配置

直接编辑 `dotfiles/mutable/hermes/.local/share/hermes/<file>`，保存即生效（hermes 进程会重新读取）。

```bash
$EDITOR dotfiles/mutable/hermes/.local/share/hermes/SOUL.md
git add dotfiles/mutable/ && git commit -S -m "..."
```

### 添加新文件到已纳管的包

```bash
# 1. 把文件复制到源目录
cp ~/.local/share/hermes/new-file dotfiles/mutable/hermes/.local/share/hermes/new-file

# 2. 让 stow 建链（替换原文件为软链接）
blue stow --restow hermes

# 3. 验证软链接生效
ls -la ~/.local/share/hermes/new-file

# 4. git commit
git add dotfiles/mutable/ && git commit -S -m "..."
```

### 添加新包

```bash
# 1. 创建包目录结构
mkdir -p dotfiles/mutable/<new-pkg>/.config/<app>

# 2. 复制 ~ 下的现有文件到源
cp ~/.config/<app>/<file> dotfiles/mutable/<new-pkg>/.config/<app>/<file>

# 3. 删 ~ 下的原文件（让 stow 建链）
mv ~/.config/<app>/<file> /tmp/backup-<file>

# 4. （按需）添加每包忽略清单：源里若含编译产物/.git/运行时目录，
#    写 dotfiles/mutable/<new-pkg>/.stow-local-ignore（Perl 正则逐行，# 注释允许），
#    模板见 dotfiles/mutable/emacs/.stow-local-ignore。纯配置文件包（如 hermes）可跳过。

# 5. 部署（默认 --no-folding，目标为真实目录）
blue stow <new-pkg>
#    若想让该包改用整目录折叠（目标目录本身变成指向源的软链）：
#    touch dotfiles/mutable/<new-pkg>/.stow-folding && blue stow --restow <new-pkg>

# 6. 验证 + commit
ls -la ~/.config/<app>/<file>
git add dotfiles/mutable/<new-pkg>/ && git commit -S -m "..."
```

### 批量操作所有包（stow-all）

枚举 `dotfiles/mutable/` 下所有直接子目录为包，逐个执行（包不能嵌套；`.git`/`.agents` 等元目录自动跳过）。逐一执行、遇错即停。

```bash
blue stow-all              # 部署所有包
blue stow-all --restow     # 重建所有软链接（最常用，改完源结构后跑）
blue stow-all --delete     # 撤销所有软链接（~ 下变回实际文件）
blue stow-all --adopt      # 把 ~ 下已有文件收养进各包源
```

### 临时撤销 stow 部署（软链接回退为实际文件）

```bash
blue stow --delete hermes   # ~ 下变回实际文件；源目录不变
# 恢复：
blue stow hermes
# 或一次恢复所有：
blue stow-all
```

### 重建软链接（文件被改过位置后）

```bash
blue stow --restow hermes
# 或全部重建：
blue stow-all --restow
```

## 与 Guix stow 的边界

- **不要**把 `dotfiles/mutable/` 下的任何文件加入 `dotfiles/immutable/`（会产生双重部署冲突）
- `home-dotfiles-service-type` 的 `directories` 默认为 `("../dotfiles/immutable")`，不涉及 `dotfiles/mutable/`
- `~/.local/share/hermes/` 下其他文件（logs/、state.db、sessions/ 等运行时产物）**不属于** `dotfiles/mutable/hermes/` 范围，stow 不会动它们

## 备份与恢复

文件在 `dotfiles/mutable/` 下由 git 跟踪，无需额外备份。误删后用 git 恢复：

```bash
git checkout HEAD -- dotfiles/mutable/hermes/
blue stow --restow hermes
```
