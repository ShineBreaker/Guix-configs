# stow/ — GNU Stow 源目录

本目录管理**频繁变动且需要版本备份**的配置文件，与 `dotfiles/`（Guix Home stow，源只读）的部署模型互补：

| 维度         | `dotfiles/enable/`                                       | `stow/`                                                   |
| ------------ | -------------------------------------------------------- | --------------------------------------------------------- |
| 部署机制     | Guix Home `home-dotfiles-service-type`（layout `'stow`） | GNU Stow（`stow --no-folding --dir=stow --target=$HOME`） |
| 源-目标关系  | 软链接到 `/gnu/store` 只读副本                           | **单文件**软链接直接到 `stow/PKG/` 仓库源                 |
| 目标目录形态 | 软链接到 store 只读副本                                  | **真实目录**（`--no-folding`，运行时可写入）              |
| 改源后生效   | 必须 `blue home`                                         | **无需任何命令，直接生效**                                |
| 适合场景     | 稳定的配置文件（niri、fish 等）                          | 频繁手改、需要 git 备份追踪（如 emacs、hermes）           |
| 版本控制     | git 跟踪 + Guix store hash                               | git 跟踪（无中间层）                                      |

## 部署模型：no-folding + 三层忽略

> 核心约束：**目标目录必须保持为真实目录，stow 只对单个文件建软链接**。这避免应用运行时产物（`logs/`、`state.db`、`sessions/` 等）经整目录软链写进仓库源。

`.stow-local-ignore` 语法：**Perl 正则，逐行一条，匹配路径尾部**；`#` 起注释、空行允许（见 Stow 手册 "Ignore Lists"）。

## 目录结构

<!-- structor:begin -->

<!-- 此树形目录由 structor 自动生成，请勿手动编辑。 -->

```
stow/
├── appimage-run/
│   ├── .local/
│   │   └── bin/
│   │       ├── appimage-run_lib/
│   │       └── appimage-run
│   ├── .stow-local-ignore
│   └── README.md
├── emacs/
│   ├── .config/
│   │   ├── agents/
│   │   │   └── skills/
│   │   └── emacs/
│   │       ├── configs/
│   │       ├── core/
│   │       ├── diagnose/
│   │       ├── .gitignore
│   │       ├── CLAUDE.md
│   │       ├── LICENSE
│   │       ├── README.org
│   │       ├── early-init.el
│   │       └── init.el
│   ├── .local/
│   │   ├── .local/
│   │   └── bin/
│   │       ├── ag_lib/
│   │       ├── ag-ent
│   │       ├── agenote
│   │       ├── agenote_cli.py
│   │       └── agenote_mcp.py
│   └── .stow-local-ignore
├── hermes/
│   └── .local/
│       └── share/
│           └── hermes/
├── pi/
│   ├── .config/
│   │   └── pi/
│   │       ├── agents/
│   │       ├── extensions/
│   │       ├── npm/
│   │       ├── prompts/
│   │       ├── .gitignore
│   │       ├── APPEND_SYSTEM.md
│   │       ├── keybindings.json
│   │       ├── lsp.json
│   │       ├── mcp.json
│   │       ├── models.json
│   │       ├── plannotator.json
│   │       └── settings.json
│   ├── .local/
│   │   ├── bin/
│   │   │   ├── pi
│   │   │   ├── pi-acp
│   │   │   └── pi-update
│   │   └── share/
│   │       └── pi/
│   └── .stow-local-ignore
├── secrets/
│   ├── .keys/
│   │   └── age
│   ├── .local/
│   │   └── share/
│   │       └── secrets-decrypted/
│   └── .stow-overlay/
├── skills/
└── .stowrc
```

<!-- /structor -->

## 当前纳管的包

| 包       | 部署目标                                                                                                         | 包含文件                                                                                                                                                                                                         |
| -------- | ---------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `hermes` | `~/.local/share/hermes/`                                                                                         | SOUL.md、config.yaml、memories/MEMORY.md、memories/USER.md                                                                                                                                                       |
| `emacs`  | `~/.config/emacs/`                                                                                               | 子模块 `codeberg.org/BrokenShine/.emacs.d`（init.el、early-init.el、core/、configs/ 等）                                                                                                                         |
| `pi`     | `~/.config/pi/`、`~/.local/bin/{kb-agent,pi,pi-acp,pi-update}`、`~/.local/share/pi/`、`~/.config/agents/skills/` | pi-coding-agent 全部配置(settings/models/lsp/keybindings/plannotator、agents/_.md、prompts/_.md、extensions/{atelier,custom-shortcuts,default-timeout,global-context,agenote-hooks})、启动脚本与 scripts/ 辅助； |

## 工作流

### 修改已纳管的配置

直接编辑 `stow/hermes/.local/share/hermes/<file>`，保存即生效（hermes 进程会重新读取）。

```bash
$EDITOR stow/hermes/.local/share/hermes/SOUL.md
git add stow/ && git commit -S -m "..."
```

### 添加新文件到已纳管的包

```bash
# 1. 把文件复制到源目录
cp ~/.local/share/hermes/new-file stow/hermes/.local/share/hermes/new-file

# 2. 让 stow 建链（替换原文件为软链接）
blue stow --restow hermes

# 3. 验证软链接生效
ls -la ~/.local/share/hermes/new-file

# 4. git commit
git add stow/ && git commit -S -m "..."
```

### 添加新包

```bash
# 1. 创建包目录结构
mkdir -p stow/<new-pkg>/.config/<app>

# 2. 复制 ~ 下的现有文件到源
cp ~/.config/<app>/<file> stow/<new-pkg>/.config/<app>/<file>

# 3. 删 ~ 下的原文件（让 stow 建链）
mv ~/.config/<app>/<file> /tmp/backup-<file>

# 4. （按需）添加每包忽略清单：源里若含编译产物/.git/运行时目录，
#    写 stow/<new-pkg>/.stow-local-ignore（Perl 正则逐行，# 注释允许），
#    模板见 stow/emacs/.stow-local-ignore。纯配置文件包（如 hermes）可跳过。

# 5. 部署（--no-folding 自动生效，目标为真实目录）
blue stow <new-pkg>

# 6. 验证 + commit
ls -la ~/.config/<app>/<file>
git add stow/<new-pkg>/ && git commit -S -m "..."
```

### 批量操作所有包（stow-all）

枚举 `stow/` 下所有直接子目录为包，逐个执行（包不能嵌套；`.git`/`.agents` 等元目录自动跳过）。逐一执行、遇错即停。

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

- **不要**把 `stow/` 下的任何文件加入 `dotfiles/enable/`（会产生双重部署冲突）
- `home-dotfiles-service-type` 的 `directories` 默认为 `("../dotfiles/enable")`，不涉及 `stow/`
- `~/.local/share/hermes/` 下其他文件（logs/、state.db、sessions/ 等运行时产物）**不属于** `stow/hermes/` 范围，stow 不会动它们

## 备份与恢复

文件在 `stow/` 下由 git 跟踪，无需额外备份。误删后用 git 恢复：

```bash
git checkout HEAD -- stow/hermes/
blue stow --restow hermes
```
