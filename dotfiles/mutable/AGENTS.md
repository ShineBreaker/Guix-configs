# dotfiles/mutable/ — GNU Stow 源目录

管理**频繁变动且需要版本备份**的配置，与 `dotfiles/immutable/`（Guix Home stow → store 只读副本，改源须 `blue home`）互补：GNU Stow 把**单文件**软链直接建到 `dotfiles/mutable/PKG/` 仓库源，**改源即生效**，无需任何命令。

| 维度         | `immutable/`                 | `mutable/`                                    |
| ------------ | ---------------------------- | --------------------------------------------- |
| 部署         | Guix Home → store 只读副本   | `blue stow` → 直链仓库源                      |
| 目标目录     | store 副本                   | **默认真实目录**（`--no-folding`，运行时可写） |
| 改源后生效   | 必须 `blue home`             | 直接生效                                      |
| 适合         | 稳定配置（niri、fish 等）    | 频繁手改、需 git 追踪（emacs、hermes 等）     |

## 部署模型

- **目标目录默认保持真实目录**，stow 只对单个文件建链——避免应用运行时产物（`logs/`、`state.db`、`sessions/`）经整目录软链写进仓库源。在 `<PKG>/` 放空标记 `.stow-folding` 可对该包 opt-in 整目录折叠
- **包身份**由 `<PKG>/.stow-package` 空标记显式声明，是 `blue stow-all` 的唯一枚举依据：带标记的是包，无标记目录视为分组（如 `agents/`、`tools/`）并下钻一层收集子包。`blue stow PKG` 显式指定时只查目录存在；整包子模块（`tools/appimage-run`）的标记提交在其子模块仓库内。标记文件本身经 `--ignore=\.stow-(folding|package)$` 保证不部署
- `.stow-local-ignore`：**Perl 正则逐行，匹配路径尾部**，`#` 注释允许；源里含编译产物/运行时目录的包用它排除，模板见 `emacs/.stow-local-ignore`

## 目录结构

<!-- structor:begin depth=2 -->

<!-- 此树形目录由 structor 自动生成，请勿手动编辑。 -->

```
mutable/
├── agenote/
│   ├── .config/
│   ├── .zcode/
│   ├── .stow-local-ignore
│   └── .stow-package
├── agents/
│   ├── dsh/
│   ├── hermes/
│   ├── omp/
│   ├── skills/
│   └── zcode/
├── emacs/
│   ├── .config/
│   ├── .local/
│   ├── .stow-local-ignore
│   └── .stow-package
├── lem/
│   ├── .config/
│   ├── .stow-local-ignore
│   └── .stow-package
└── tools/
    ├── appimage-run/
    └── secrets/
```

<!-- /structor -->

## 当前纳管的包

| 包                   | 部署目标                                                     | 说明                                                                                     |
| -------------------- | ------------------------------------------------------------ | ---------------------------------------------------------------------------------------- |
| `agents/hermes`      | `~/.local/share/hermes/` + `~/.local/bin/hermes*`            | SOUL.md、config.yaml、memories/skills/plugins、启动脚本与 .desktop                        |
| `agents/omp`         | `~/.config/omp` + `~/.config/agents/skills/`                 | omp 配置 + extensions/；2026-08 自 pi 迁移（`PI_CONFIG_DIR=.config/omp`）                 |
| `agents/skills`      | `~/.config/agents/skills/`                                   | 第三方锁 skills-lock.json（askill 引擎装）+ 自建 skill（git 跟踪）；恢复后跑 `askill install` |
| `agents/dsh`         | `~/.local/share/dsh/` + `~/.local/bin/dsh-web`               | DeepSeek Harness 配置层 + wrapper；程序本体经 `uv tool install deepseek-harness-runtime-bin`，`$DSH_HOME` 由 conf.d 与 wrapper 双注入 |
| `emacs`              | `~/.config/emacs/`                                           | literal-config 本体，单 profile 无 chemacs2；规范见包内 `AGENTS.md`                        |
| `lem`                | `~/.config/lem/`                                             | VSCode 风格配置（init.lisp + modules/），规范见包内 `AGENTS.md`                            |
| `agenote`            | `~/.config/agents/skills/` + `~/.config/omp/extensions/`     | 纯 submodule 容器（agenote-skills + pi-agenote）；CLI 本体由 `uv tool install` 独立装      |
| `agents/zcode`       | `~/.zcode/`                                                  | zcode 配置（cli/commands/hooks/agents/plugins）                                            |
| `tools/appimage-run` | `~/.local/bin/appimage-run`                                  | AppImage 运行器（**submodule**）                                                          |
| `tools/secrets`      | `~/.local/share/keys/`                                       | age 密钥对 + 加解密脚本，规范见包内 `AGENTS.md`；密文目录被 stow 排除                      |

## 工作流

改既有包内的文件：直接编辑源，保存即生效，git commit 备份。新文件进既有包：复制到源目录 → `blue stow --restow <pkg>` → `ls -la` 验证软链 → commit。

**添加新包**：

```bash
# 1. 目录结构 + 包身份标记（stow-all 枚举依据）
mkdir -p dotfiles/mutable/<new-pkg>/.config/<app>
touch dotfiles/mutable/<new-pkg>/.stow-package
# 2. 收编 ~ 下现有文件：复制进源，原文件移走（/tmp 备份）让 stow 建链
# 3. 需要时写 .stow-local-ignore（排除编译产物/运行时目录）
# 4. 部署 + 验证 + commit
blue stow <new-pkg>
ls -la ~/.config/<app>/<file>
git add dotfiles/mutable/<new-pkg>/ && git commit -S -m "..."
# 想整目录折叠：touch .stow-folding && blue stow --restow <new-pkg>
```

**批量操作**：`blue stow-all [--restow|--delete|--adopt]`——按 `.stow-package` 标记枚举所有包逐个执行、遇错即停。单包回退 `blue stow --delete <pkg>`（~ 下变回实际文件，源不变），恢复再 `blue stow <pkg>`。误删源文件：`git checkout HEAD -- <pkg>/` 后 `--restow`。

## 约束

- `.local/bin/` 新增可执行必须在 `dotfiles/immutable/terminal/.config/fish/completions/<name>.fish` 同步鱼壳补全（`complete -c <name>`）；`blue`/`denv` 例外
- **不要**把本目录文件加入 `dotfiles/immutable/`（双重部署冲突）；`~` 下运行时产物（logs/、state.db 等）不属于包范围，stow 不会动它们
