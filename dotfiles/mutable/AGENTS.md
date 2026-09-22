# dotfiles/mutable/ — GNU Stow 可变配置包

本目录用于管理**高频变动且需要 Git 版本备份**的应用配置。与 `immutable/`（Guix Home 构建 store 只读副本）互补，GNU Stow 将文件**直接软链接到仓库源目录**，实现**修改源码即时生效**，无需执行部署命令。

| 维度             | `immutable/`（不可变）              | `mutable/`（可变）                       |
| ---------------- | ----------------------------------- | ---------------------------------------- |
| **部署方式**     | Guix Home 复制进 store 只读副本     | `blue stow` 直接软链到仓库源             |
| **目标目录形态** | 指向 store 的只读链接               | 真实目录（`--no-folding` 单文件软链）    |
| **生效机制**     | 必须运行 `blue home` 重建           | 保存源码立即生效                         |
| **适用场景**     | 稳定系统与桌面组件（Niri、Fish 等） | 高频调试与动态应用（Emacs、DSH 等）      |

## 部署模型与机制

1. **单文件链接（`--no-folding`）**：
   - Stow 默认保持 `$HOME` 侧的各层级目录为真实目录，仅对具体配置文件建立软链。
   - 这能防止应用运行期生成的日志、数据库和缓存（如 `logs/`、`state.db`、`sessions/`）意外写入 Git 仓库。
   - 若某软件包确需整目录链接，可在其目录下放置 `.stow-folding` 空文件进行 opt-in。
2. **包发现与身份标记（`.stow-package`）**：
   - 包含 `.stow-package` 文件的目录被 `blue stow-all` 识别为独立包。
   - 无该标记的目录（如 `agents/`、`tools/`）视为分组目录，Stow 会自动下钻扫描其子目录中的包。
3. **忽略规则（`.stow-local-ignore`）**：
   - 逐行写入 Perl 正则表达式（匹配路径结尾，支持 `#` 注释），用于排除包内的运行时产物、构建缓存或临时文件。

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
│   ├── extensions/
│   ├── hermes/
│   ├── omp/
│   ├── pi/
│   ├── skills/
│   └── zcode/
├── emacs/
│   ├── .config/
│   ├── .local/
│   ├── .stow-local-ignore
│   └── .stow-package
└── tools/
    ├── appimage-run/
    ├── blue/
    ├── secrets/
    └── toolbox/
```

<!-- /structor -->

## 纳管软件包列表

| 软件包               | 部署目标                                                                       | 说明与手册                                                                                                       |
| -------------------- | ------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------- |
| `emacs`              | `~/.config/emacs/`                                                             | 单一 `emacs.org` 驱动的 Emacs 配置，详见 [emacs/.../AGENTS.md](emacs/.config/emacs/AGENTS.md)                    |
| `agents/dsh`         | `~/.local/share/dsh/` + `~/.local/bin/dsh` + 图标/desktop 项                   | DeepSeek Harness 配置层与 CLI（update/web 为 Guix 增强子命令），详见 [dsh/AGENTS.md](agents/dsh/AGENTS.md)       |
| `agents/hermes`      | `~/.local/share/hermes/` + `~/.local/bin/hermes` + `hermes-acp`                | Hermes Agent 提示词、配置、插件与启动项（update/desktop 增强子命令由主入口分发）                                 |
| `agents/omp`         | `~/.config/omp/`                                                               | OMP Agent 配置与扩展                                                                                             |
| `agents/pi`          | `~/.config/pi/` + `~/.local/bin/pi*` + `~/.local/share/pi/`                    | Pi 编码 Agent 的 wrapper 与配置（pnpm 自管理），详见 [pi/AGENTS.md](agents/pi/AGENTS.md)                         |
| `agents/skills`      | `~/.config/agents/skills/` + `~/.local/bin/askill`                             | 第三方技能锁（`skills-lock.json`）、自建技能与 `askill` 管理器                                                   |
| `agents/zcode`       | `~/.zcode/`                                                                    | ZCode 配置与子智能体规则，详见 [zcode/.../AGENTS.md](agents/zcode/.zcode/AGENTS.md)                              |
| `agenote`            | `~/.config/agents/skills/` + `~/.config/omp/extensions/` + `~/.zcode/plugins/` | 知识库技能与各端 Hook/插件（内含子模块）                                                                         |
| `tools/secrets`      | `~/.local/share/keys/` + `~/.local/bin/secrets`                                | Age 密钥对与 `secrets` 命令（加密/解密/编辑/fzf 菜单/剪贴板），详见 [secrets/AGENTS.md](tools/secrets/AGENTS.md) |
| `tools/appimage-run` | `~/.local/bin/appimage-run`                                                    | AppImage 运行器（子模块）                                                                                        |
| `tools/blue`         | `~/.local/bin/blue`（增强脚本在包内 `.local/libexec/`）                        | blue 启动 wrapper（借系统 guile 直跑，绕过字节码错配；上游修复后删包），update 防呆/gc 清理分发至包内 `.local/libexec/`（docs/emergency-blue.md §8-9）     |
| `tools/toolbox`      | `~/.local/bin/toolbox` + `~/.local/share/toolbox/`                             | 自研工具统一入口（fzf 清单），详见 [toolbox/AGENTS.md](tools/toolbox/AGENTS.md)                                  |

> `agents/extensions/` 无 `.stow-package` 标记，不单独部署：它是 omp/pi 共享自建扩展的源码存放点，两侧 `extensions/<name>/` 经软链引用（见 [pi/AGENTS.md](agents/pi/AGENTS.md)）。

## .local/bin 入口准入规则

mutable 包的 `~/.local/bin` 入口遵循**一包一入口**（2026-09 已将 blue/hermes/dsh/pi 四族
从 21 个入口收敛到 15 个，规则成文防回潮），由 `toolbox check` 执法：

1. **一包一入口**：每个 stow 包默认只在 `.local/bin/` 放一个入口文件；其余实现放包内
   `.local/libexec/`，由主入口 case 分发子命令（范本：
   [agents/hermes](agents/hermes/.local/bin/hermes) 与 [tools/blue](tools/blue/.local/bin/blue) 的 wrapper）。
2. **先论证挂靠**：新增入口前必须先论证无法作为现有工具的子命令挂靠；直接新建独立入口视为违规。
3. **禁止新增 `*-update` 入口文件**：更新逻辑一律实现为 `tool update` 子命令。
4. **`*-acp` 协议入口豁免**：外部 ACP host（Zed 等）按命令名寻址 agent，无法子命令化，允许
   作为包内第二入口；头注释须说明约束来源（范本：[hermes-acp](agents/hermes/.local/bin/hermes-acp)）。
   `toolbox check` 对其自动豁免。
5. **拦截即遮蔽须写明**：主入口分发与上游 CLI 已有同名子命令撞名时（如 `hermes update`），
   分发处头注释必须写明「拦截即覆写」及原生行为的直调触达路径（范本：hermes wrapper 头注释）。
6. **例外声明**：确无法子命令化的入口（如上游子命令语义撞车、不可遮蔽）在包根
   `.bin-entries-allow` 声明，每行「入口名 # 理由」，理由不可省略（范本：agents/pi 的 `pi-update`）。
7. **登记对账**：原创工具新入口须同步登记 tools.yaml（`toolbox check` 对账）；子命令化工具
   条目挂主命令名下，usage 写子命令形态。
8. **执法**：`toolbox check` 的一包一入口检测为阻断级——包内入口计入数 > 1 或豁免缺理由即
   非零退出（`*-acp` 自动豁免不计入；immutable 包不在检测范围）。

## 工作流与操作指南

### 1. 修改与新增文件

- **修改已有文件**：直接编辑仓库源文件，保存即时生效，Git 提交留痕。
- **向已有包添加新文件**：将文件放入源目录对应路径 → 运行 `blue stow --restow <pkg>` 建立新软链 → 检查软链是否就绪并提交。

### 2. 添加全新软件包

```bash
# 1. 创建目录结构与包身份标记
mkdir -p dotfiles/mutable/<pkg-name>/.config/<app>
touch dotfiles/mutable/<pkg-name>/.stow-package

# 2. 迁移文件：将 ~/.config/<app> 下的配置移入源目录
# 3. 按需编写 .stow-local-ignore（排除日志/缓存）
# 4. 部署并验证
blue stow <pkg-name>
ls -la ~/.config/<app>/
git add dotfiles/mutable/<pkg-name>/ && git commit -S -m "feat(dotfiles): add mutable package <pkg-name>"
```

### 3. 批量维护与恢复

- **全量重链接**：`blue stow-all --restow` 扫描所有包并刷新软链。
- **单包卸载**：`blue stow --delete <pkg-name>`（移除 `$HOME` 侧软链，仓库源文件保持不变）。
- **误删恢复**：若误删源文件，先 `git checkout HEAD -- <pkg>/` 检出，再执行 `blue stow --restow <pkg>`。

## 约束与规范

1. **防重部署**：禁止将 `mutable/` 纳管的文件同时加入 `dotfiles/immutable/`，避免软链冲突。
2. **Tab 补全同步**：若在 `.local/bin/` 新增了可执行命令，需同步在 `dotfiles/immutable/terminal/.config/fish/completions/<name>.fish` 添加补全。
