# GNU Stow 二级 dotfile 部署策略

> 实现位置：仓库顶层 `stow/` 目录 + `blueprint.scm` 的 `stow-command`。补充说明 Guix Home stow（`home-dotfiles-service-type` layout `'stow`）覆盖不到的场景：**频繁变动 + 需要版本追踪** 的配置文件。

## 核心思想：双轨部署

Guix-configs 仓库原有 dotfiles 部署模型：

```
dotfiles/enable/<app>/  →  /gnu/store/<hash>-home-dotfiles-.../  (只读副本)  →  $HOME 软链接
                          └─ Guix rebuild 时重建 ─┘
```

痛点：**改源 ≠ 生效**，每次都要 `blue home`（甚至 `blue rebuild` 走 store hash）。对"频繁手改"的配置（hermes 的 SOUL.md / MEMORY.md、agent prompt、scratch configs 等）来说太重。

解决方案：引入 GNU Stow 作为**第二轨**，直接建软链接到仓库源：

```
stow/<pkg>/.local/share/hermes/X.md  →  $HOME/.local/share/hermes/X.md  (软链接)
                                       └─ 改源即生效，无任何中间层 ─┘
```

## 何时用哪一轨

| 场景 | 用哪一轨 |
|------|----------|
| 稳定配置（emacs、niri、fish） | Guix stow（`dotfiles/enable/`） |
| 频繁手改、需要 git 备份追踪（agent context、prompt、SOUL.md） | GNU Stow（`stow/`） |
| 需要 Guix 包系统注入路径（`$$bin/foo$$`） | `source/files/`（`home-files-service-type`） |
| 纯运行时产物（db、cache、logs） | **不入库**，靠 `%data-dirs` bind-mount 保活 |

判断标准：**改完之后多久生效可以接受**？可接受重启一次的就 Guix stow；要保存立刻生效的就 GNU Stow。

## 目录结构约定

```
stow/
├── hermes/                              # 包名 = stow 命令的 PKG 参数
│   └── .local/share/hermes/             # 路径前缀直接映射到 $HOME
│       ├── SOUL.md
│       ├── config.yaml
│       └── memories/
│           ├── MEMORY.md
│           └── USER.md
└── <other-pkg>/                         # 每个包一个子目录
```

**关键约束**：
- **不要**把 `stow/` 下的任何文件加到 `dotfiles/enable/` —— 双轨部署会产生软链接到软链接的冲突
- `home-dotfiles-service-type` 默认 `directories '("../dotfiles/enable")`，**不**递归到 `stow/`
- 包目录内**不要**有空目录 —— 空目录 stow 会建奇怪的链，且 git 会污染

## 首次建链（adopt 模式）

**不能用 `rm` 直接删 `~` 下的原文件** —— Hermes 硬保护 (`BLOCKED recursive delete of home directory`)。必须用 `mv` 移到临时目录，让 stow 建链后再清理临时目录。

```bash
# 0. 备份到 /tmp/hermes-backup-<timestamp>/
BACKUP=/tmp/hermes-backup-$(date +%Y%m%d-%H%M%S)
mkdir -p "$BACKUP"
cp -p ~/.local/share/hermes/SOUL.md "$BACKUP/SOUL.md"
# ... 其他文件
md5sum ~/.local/share/hermes/X "$BACKUP/X"  # 验证

# 1. 复制到源目录（保留权限，先建副本不删原文件）
mkdir -p stow/hermes/.local/share/hermes/memories
cp -p ~/.local/share/hermes/SOUL.md stow/hermes/.local/share/hermes/SOUL.md
cp -p ~/.local/share/hermes/memories/MEMORY.md stow/hermes/.local/share/hermes/memories/MEMORY.md

# 2. 验证源 vs 备份 md5 一致
md5sum stow/hermes/... "$BACKUP/..."

# 3. mv（不是 rm！）原文件到临时目录
TMP=/tmp/hermes-mv-backup
mkdir -p "$TMP"
mv ~/.local/share/hermes/SOUL.md "$TMP/SOUL.md"
# ...

# 4. 让 stow 建链
stow --dir=stow --target="$HOME" hermes

# 5. 验证软链接 + md5 三方一致（源/软链接/备份）
ls -la ~/.local/share/hermes/SOUL.md   # 应是 lrwxrwxrwx
md5sum ~/.local/share/hermes/SOUL.md stow/hermes/.../SOUL.md "$BACKUP/SOUL.md"

# 6. 清理临时目录
rm -rf "$TMP"
```

### `--adopt` 模式的坑

直接 `stow --adopt --dir=stow --target=$HOME hermes` 会失败 —— 当**源目录是空的**时 stow 没东西可链，`--adopt` 不会触发"把 ~ 下文件移到源"的动作；建链前源目录**必须先有文件**。本 skill 推荐的"cp → mv → stow"三步法是更可靠的等价流程。

## blue stow 命令包装

实现位置：`blueprint.scm` 的 `stow-command`。接口：

| 命令 | 行为 |
|------|------|
| `blue stow PKG` | 从源部署（建软链接） |
| `blue stow --adopt PKG` | 首次使用：把 ~ 下文件移到源，再建链 |
| `blue stow --restow PKG` | 强制重建（先删链再重建） |
| `blue stow --delete PKG` | 撤销链（~ 下变回实际文件） |
| `blue stow PKG1 PKG2` | 同时部署多个包 |

底层调用 `stow --dir=stow --target=$HOME [--adopt|--restow|--delete] PKG`，默认从 `%repo-root` 取 `stow-dir`。

## 实时生效验证

软链接建好后，**改源即生效**。验证：

```bash
echo "TEST-LIVE-$(date +%s)" >> stow/hermes/.local/share/hermes/SOUL.md
tail -1 ~/.local/share/hermes/SOUL.md  # 应立即看到测试行
# 回滚
cp "$BACKUP/SOUL.md" stow/hermes/.local/share/hermes/SOUL.md
```

## 与 blue structor 的集成

`stow/AGENTS.md` 加 `<!-- structor:begin -->...<!-- /structor -->` 标记对，`blue structor` 自动维护目录树段。但**注意 depth**：`stow/hermes/.local/share/hermes/memories/` 已经 5 层深，默认 depth=4 会截断在 `hermes/`。

```bash
ORG_STRUCTOR_DEPTH=6 ORG_STRUCTOR_TARGET=stow/AGENTS.md blue structor
```

若仓库根 AGENTS.md 也想列 stow 包，**手写**（不靠 structor —— structor 只扫到第 4 层）。

## git commit 规范

按仓库 gitmessage 规范分两个 serial commit：

1. `FEATURE: (blue) added \`stow\` command for direct symlink deployment.` —— `blueprint.scm` + 根 `AGENTS.md`
2. `FEATURE: (stow) added \`<pkg>\` package for ... backing.` —— `stow/AGENTS.md` + `stow/<pkg>/` 源文件 + `blue structor` 自动连锁更新的其他 AGENTS.md

混在一起 commit 信息会模糊；分两个让 git log 可读。

## 反模式

- ❌ **直接 `rm ~/.local/share/hermes/X`** —— Hermes 硬保护拦截；即便绕过，丢失风险太大
- ❌ **让 `stow/` 与 `dotfiles/enable/` 部署同一文件** —— 双链冲突，激活时哪个生效不确定
- ❌ **stow 软链接到 `~/.local/share/hermes/logs/` 等运行时目录** —— stow 会试图建软链接到目录下的每个文件，污染严重
- ❌ **在 `stow/<pkg>/` 里建空目录占位** —— stow 会建奇怪链，git 跟踪空目录无意义
- ❌ **跑 `blue rebuild` 期望 stow 生效** —— stow 与 Guix 无关，rebuild 不会重建 stow 链

## 现有纳管的包

| 包 | 部署目标 | 文件数 |
|----|----------|--------|
| `hermes` | `~/.local/share/hermes/` | 4 (SOUL.md / config.yaml / memories/{MEMORY,USER}.md) |

## 故障排查

| 症状 | 排查 |
|------|------|
| `blue stow hermes` 报 "stow 包不存在" | 确认 `stow/hermes/` 目录存在；当前 cwd 应是仓库根 |
| 软链接建了但内容没更新 | `md5sum` 源 vs 软链接，确认是同一文件；确认没残留旧进程持有旧 fd |
| `--delete` 后 ~ 下文件消失 | 检查源目录文件还在；`blue stow hermes` 重建链 |
| `stow` 报 "could not stow" 冲突 | `~` 下目标位置有实际文件（不是链）；先 mv 走或 `blue stow --adopt` |