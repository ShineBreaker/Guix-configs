# stow/ — GNU Stow 源目录

本目录管理**频繁变动且需要版本备份**的配置文件，与 `dotfiles/`（Guix Home stow，源只读）的部署模型互补：

| 维度 | `dotfiles/enable/` | `stow/` |
|------|--------------------|---------|
| 部署机制 | Guix Home `home-dotfiles-service-type`（layout `'stow`） | GNU Stow（直接 `stow --dir=stow --target=$HOME`） |
| 源-目标关系 | 软链接到 `/gnu/store` 只读副本 | 软链接直接到 `stow/PKG/` 仓库源 |
| 改源后生效 | 必须 `blue home` | **无需任何命令，直接生效** |
| 适合场景 | 稳定的配置文件（emacs、niri、fish 等） | 频繁手改、需要 git 备份追踪 |
| 版本控制 | git 跟踪 + Guix store hash | git 跟踪（无中间层） |

## 目录结构

<!-- structor:begin -->

<!-- 此树形目录由 structor 自动生成，请勿手动编辑。 -->

```
stow/
└── hermes/
    └── .local/
        └── share/
            └── hermes/
                ├── memories/
                │   ├── MEMORY.md
                │   └── USER.md
                ├── SOUL.md
                └── config.yaml
```

<!-- /structor -->

## 当前纳管的包

| 包 | 部署目标 | 包含文件 |
|----|----------|----------|
| `hermes` | `~/.local/share/hermes/` | SOUL.md、config.yaml、memories/MEMORY.md、memories/USER.md |

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

# 4. 部署
blue stow <new-pkg>

# 5. 验证 + commit
ls -la ~/.config/<app>/<file>
git add stow/<new-pkg>/ && git commit -S -m "..."
```

### 临时撤销 stow 部署（软链接回退为实际文件）

```bash
blue stow --delete hermes   # ~ 下变回实际文件；源目录不变
# 恢复：
blue stow hermes
```

### 重建软链接（文件被改过位置后）

```bash
blue stow --restow hermes
```

## 与 Guix stow 的边界

- **不要**把 `stow/` 下的任何文件加入 `dotfiles/enable/`（会产生双重部署冲突）
- `home-dotfiles-service-type` 的 `directories` 默认为 `("../dotfiles/enable")`，不涉及 `stow/`
- `~/.local/share/hermes/` 下其他文件（logs/、state.db、sessions/ 等运行时产物）**不属于** `stow/hermes/` 范围，stow 不会动它们

## 备份与恢复

`blue stow` 操作前无需额外备份——文件就在仓库 `stow/` 下，git 跟踪本身就是备份。但若执行 `--adopt` 把 ~ 下文件移动到源，git status 会立刻显示变化；如果误删，恢复方式：

```bash
git checkout HEAD -- stow/hermes/
blue stow --restow hermes
```