# dotfiles/mutable/ — GNU Stow 可变配置包

本目录管理**高频变动且需要 Git 版本备份**的应用配置。`immutable/` 走 Guix Home（构建 store 只读副本再软链 `$HOME`，改源后须 `blue home` 重建）；`mutable/` 由 GNU Stow **逐文件直链仓库源**，改源即时生效。

| 维度               | `immutable/`（不可变）              | `mutable/`（可变）                      |
| ------------------ | ----------------------------------- | --------------------------------------- |
| **部署方式**       | Guix Home 复制进 store 只读副本     | `blue stow` 直接软链仓库源              |
| **`$HOME` 侧形态** | 指向 store 的只读链接               | 真实目录 + 单文件软链（`--no-folding`） |
| **生效机制**       | 必须运行 `blue home` 重建           | 保存源码立即生效                        |
| **适用场景**       | 稳定系统与桌面组件（Niri、Fish 等） | 高频调试与动态应用（Emacs、DSH 等）     |

## 部署模型与机制

1. **`--no-folding`（默认形态）**：`$HOME` 侧各层级目录保持真实目录，只对具体配置文件建软链。这能防止应用运行期生成的日志、数据库与缓存（`logs/`、`state.db`、`sessions/`）意外写入 Git 仓库。
2. **`.stow-package`（包身份标记）**：含该文件的目录被 `blue stow-all` 识别为独立包。无标记的目录（`agents/`、`tools/`）视为分组目录，Stow 自动下钻扫描其子目录中的包。
3. **`.stow-local-ignore`（忽略规则）**：逐行写 Perl 正则（匹配路径结尾，支持 `#` 注释），用于排除包内运行时产物、构建缓存与临时文件。
4. **`.stow-folding`（目录折叠，按包 opt-in）**：有标记 → 目标目录整条变成指向源的软链；无标记 → 保持真实目录逐文件放链。**一个 `$HOME` 目录只能被一个包折叠**：两个包都想折叠同一目录时先部署者赢得该目录，后到者只能下探逐文件放链，形态静默退化为 no-folding。因此加标记前先确认目标目录没有被别的包占窝。

   `agents/hermes` 曾带该标记，但它的运行时产物（`logs/`、`state.db`、`sessions/`）只适合 no-folding，该标记已移除，防污染靠 `.stow-local-ignore` 那串规则。

## 目录结构

<!-- structor:begin depth=2 -->

<!-- 此树形目录由 structor 自动生成，请勿手动编辑。 -->

```
mutable/
├── agenote/
│   ├── .config/
│   ├── .local/
│   ├── .zcode/
│   ├── .stow-local-ignore
│   ├── .stow-package
│   ├── agenote.lock
│   └── sync-agenote.sh
├── agents/
│   ├── dsh/
│   ├── extensions/
│   ├── hermes/
│   ├── minimax-code/
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
    ├── secrets/
    └── toolbox/
```

<!-- /structor -->

## 纳管软件包列表

| 软件包                | 部署目标                                                                                                             | 说明与手册                                                                                                                                                                                                                |
| --------------------- | -------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `emacs`               | `~/.config/emacs/`                                                                                                   | 单一 `emacs.org` 驱动的 Emacs 配置，详见 [emacs/.../AGENTS.md](emacs/.config/emacs/AGENTS.md)                                                                                                                             |
| `agents/dsh`          | `~/.local/share/dsh/`（配置/状态）+ `~/.local/share/agents/dsh/`（CLI 安装树）+ `~/.local/bin/dsh` + 图标/desktop 项 | DeepSeek Harness 配置层与 CLI（update/web/tui 为 Guix 增强子命令），详见 [dsh/AGENTS.md](agents/dsh/AGENTS.md)；入口手册 [dsh.md](../../docs/scripts/dsh.md)                                                              |
| `agents/hermes`       | `~/.local/share/hermes/` + `~/.local/bin/hermes` + `hermes-acp`                                                      | Hermes Agent 提示词、配置、插件与启动项（update/desktop 增强子命令由主入口分发）；入口手册 [hermes.md](../../docs/scripts/hermes.md)                                                                                      |
| `agents/minimax-code` | `~/.local/share/agents/minimax-code/`（安装树）+ `~/.local/bin/mcode`                                                | MiniMax Code CLI（npm 包 `@minimax-ai/code`；`mcode tools` 分发上游第二 bin `mcode-tools`），详见 [minimax-code/AGENTS.md](agents/minimax-code/AGENTS.md)；入口手册 [minimax-code.md](../../docs/scripts/minimax-code.md) |
| `agents/omp`          | `~/.config/omp/`                                                                                                     | OMP Agent 配置与扩展                                                                                                                                                                                                      |
| `agents/pi`           | `~/.config/pi/` + `~/.local/bin/pi*` + `~/.local/share/agents/pi/`（安装树）+ `~/.local/share/pi/`（sessions 数据）  | Pi 编码 Agent 的 wrapper 与配置（pnpm 自管理），详见 [pi/AGENTS.md](agents/pi/AGENTS.md)；入口手册 [pi.md](../../docs/scripts/pi.md)                                                                                      |
| `agents/skills`       | `~/.config/agents/skills/` + `~/.local/bin/askill`                                                                   | 第三方技能锁（`skills-lock.json`）、自建技能与 `askill` 管理器（手册 [askill.md](../../docs/scripts/askill.md)）                                                                                                          |
| `agents/zcode`        | `~/.zcode/`                                                                                                          | ZCode 配置与子智能体规则，详见 [zcode/.../AGENTS.md](agents/zcode/.zcode/AGENTS.md)                                                                                                                                       |
| `agenote`             | `~/.config/agents/skills/` + `~/.config/omp/extensions/` + `~/.zcode/plugins/`                                       | 知识库技能与各端 Hook/插件（内含子模块）                                                                                                                                                                                  |
| `tools/secrets`       | `~/.local/share/keys/` + `~/.local/bin/secrets`                                                                      | Age 密钥对与 `secrets` 命令（加密/解密/编辑/fzf 菜单/剪贴板），详见 [secrets/AGENTS.md](tools/secrets/AGENTS.md)；机制见 [secrets.md](../../docs/secrets.md)                                                              |
| `tools/appimage-run`  | `~/.local/bin/appimage-run`                                                                                          | AppImage 运行器（子模块）                                                                                                                                                                                                 |
| `tools/toolbox`       | `~/.local/bin/toolbox` + `~/.local/share/toolbox/`                                                                   | 自研工具统一入口（fzf 清单），详见 [toolbox/AGENTS.md](tools/toolbox/AGENTS.md)；手册 [toolbox.md](../../docs/scripts/toolbox.md)                                                                                         |

> `agents/extensions/` 无 `.stow-package` 标记，不单独部署：它是 omp/pi 共享自建扩展的源码存放点，两侧 `extensions/<name>/` 经软链引用（见 [pi/AGENTS.md](agents/pi/AGENTS.md)）。

## Agent 运行时安装根（`~/.local/share/agents/`）

pnpm 安装的 agent（CLI 本体）统一把**安装树**——pnpm 项目（`package.json` + `pnpm-lock.yaml` + `node_modules`）——放在 `~/.local/share/agents/<pkg>/`（`AGENTS_ROOT` 环境变量可覆盖），与 pnpm 全局 store（`~/.local/share/pnpm`）同层。**配置与运行时状态不搬家**：各 agent 的 home（`~/.local/share/dsh`、`~/.local/share/pi`）与 `~/.config/<pkg>/` 原地不动。

两条决策依据：**整目录迁移而非只搬 `node_modules`**（pnpm 要求两者同目录，且 `.modules.yaml` 的 `virtualStoreDir` 是相对路径、`storeDir` 指向全局内容寻址 store，整目录 `mv` 后无需重装）；**不并进 `pnpm add -g`**（会把所有 agent 揉进同一依赖图，hoisted 平铺劫持全局解析的事故在 dsh 有前科，还丢掉每 agent 的 git 锁文件、更新粒度变粗）。

### 新增 pnpm 系 agent 的完整配方

范本：`agents/dsh`（回源最全：wrapper 双目录自愈 + update 参数化 sync）、`agents/pi`（最小形态：安装/数据目录拆分）。下文 `<pkg>` 为通配。

**0. 先判断走不走这条路**

| agent 形态                             | 去处                                             |
| -------------------------------------- | ------------------------------------------------ |
| npm 包、要版本锁定进 git               | 本配方                                           |
| Guix 频道已有                          | `source/config.org` 的 home-packages，不走本配方 |
| 非 node 生态（git checkout + venv 等） | 不走本配方，agent home 自持（如 hermes）         |

**1. 建包与安装清单**

```bash
PKG=<pkg>
mkdir -p dotfiles/mutable/agents/$PKG/.local/share/agents/$PKG
touch dotfiles/mutable/agents/$PKG/.stow-package
cp dotfiles/mutable/agents/pi/.stow-local-ignore dotfiles/mutable/agents/$PKG/
```

在 `.local/share/agents/$PKG/package.json` 写死首个目标版本（精确值不用 `^`）。同目录按需配 `pnpm-workspace.yaml`（stow 软链，两个高频坑必读）：`minimumReleaseAge: 0`——pnpm 12 默认 24h 供应链冷却，**发布不满一天的新版本会被静默排除出解析**；`allowBuilds: {<pkg>: true}`——依赖原生模块（better-sqlite3 等）时不批 build scripts 会装得上但跑不了，pnpm 安装输出的 `Ignored build scripts:` 名单照抄进即可（范本见 dsh 与 minimax-code）。**lockfile 不手写**，首装后由回源机制生成进仓库。

**2. 入口 wrapper**（一包一入口；更新逻辑先做 `<pkg> --install`，复杂化再学 dsh 分发到 libexec；上游有多个 bin 时学 minimax-code 在主入口 case 分发，不占第二个 `~/.local/bin` 文件）

```bash
#!/usr/bin/env bash
# <pkg> — <一句话用途>。安装树在 $AGENTS_ROOT/<pkg>，首跑自动 pnpm install，
# manifest 与 lockfile 回源。文档：docs/scripts/<pkg>.md
set -euo pipefail

: "${AGENTS_ROOT:=${XDG_DATA_HOME:-$HOME/.local/share}/agents}"
export AGENTS_ROOT
_proj="$AGENTS_ROOT/<pkg>"

install_cli() { (cd "$_proj" && pnpm install); }

# 断链自愈 + 回源：package.json / pnpm-workspace.yaml 被 pnpm 原子写（临时
# 文件 + rename）换成实体文件后，内容归源并重建 stow 软链；lockfile 只回拷
# 内容且仓库副本缺失时新建（pnpm 拒写软链 lockfile，仓库副本经
# .stow-local-ignore 剪枝防误链）。源目录从 $0 的 stow 软链反推，不从部署侧
# 链接推导——pnpm 覆写后链接随时不在。cmp 有差才动。
sync_to_source() {
  local src f
  src="$(dirname "$(dirname "$(readlink -f "$0")")")/share/agents/<pkg>"
  [[ -d "$src" ]] || return 0
  for f in package.json pnpm-workspace.yaml pnpm-lock.yaml; do
    [[ -f "$_proj/$f" ]] || continue
    if [[ -f "$src/$f" ]] && cmp -s "$_proj/$f" "$src/$f"; then continue; fi
    cp "$_proj/$f" "$src/$f"
    printf '<pkg>: %s 已同步回仓库源\n' "$f" >&2
  done
  for f in package.json pnpm-workspace.yaml; do
    [[ -f "$src/$f" && ! -L "$_proj/$f" ]] || continue
    ln -sfn "$src/$f" "$_proj/$f"
    printf '<pkg>: %s 软链已重建\n' "$f" >&2
  done
}

[[ "${1:-}" == "--install" ]] && { install_cli && sync_to_source; exit 0; }

if [[ ! -x "$_proj/node_modules/.bin/<bin>" ]]; then
  command -v pnpm >/dev/null || { echo "pnpm is not installed." >&2; exit 1; }
  install_cli && sync_to_source
fi

# 尾部统一回源：CLI 运行期若自举改写 manifest/lockfile（插件安装、自更新），
# 下次调用即归源；cmp 短路，无漂移时零开销
set +e
"$_proj/node_modules/.bin/<bin>" "$@"
rc=$?
set -e
sync_to_source
exit "$rc"
```

三条不变量（dsh/pi/minimax-code 踩坑换来的）：部署路径只从 `AGENTS_ROOT` 推导、仓库源路径从 `$0`（stow 软链）`readlink -f` 反推，都不依赖部署侧软链存活（pnpm 原子写会随时把它覆写成实体文件）；`package.json`/`pnpm-workspace.yaml` 回源 = 拷内容 + 重建软链，`pnpm-lock.yaml` 只回拷内容、仓库副本缺失时新建并加进 `.stow-local-ignore`（否则 stow 链出去，pnpm 立刻拒写）；回源要**每次调用/每次更新都做**（cmp 有差才动），只挂 update 脚本会漏掉手动安装路径——dsh 曾因此仓库 lockfile 落后一个 minor。

**3. 部署与首装**

```bash
blue stow agents/<pkg>
<pkg> --install                # 无人值守首装（交互环境首跑任意子命令也会触发）
blue stow --restow agents/<pkg>    # 确认幂等、无绝对软链/实体文件冲突
```

**4. 登记（同一次改动内）**

- `docs/scripts/<pkg>.md` 手册 + `docs/scripts/README.md` 登记一行
- 本文件「纳管软件包列表」加一行（部署目标写全：安装树 + 配置 + 入口）
- 新增 `~/.local/bin` 命令要配 fish 补全 `dotfiles/immutable/terminal/.config/fish/completions/<pkg>.fish`

**5. 验证**

```bash
<pkg> --version                       # 版本正确 = node_modules 完好
find ~/.local/share/agents/<pkg> -xtype l    # 无断链
git status --short                    # package.json / lockfile 已回源，只含预期文件
```

## `.local/bin` 入口准入规则

mutable 包的 `~/.local/bin` 入口遵循**一包一入口**（2026-09 已将 hermes/dsh/pi 族从多入口收敛到每包一个，规则成文防回潮），由 `toolbox check` 阻断级执法。

1. **一包一入口**：每个 stow 包默认只在 `.local/bin/` 放一个入口文件，其余实现放包内 `.local/libexec/`，由主入口 case 分发子命令（范本：[agents/hermes](agents/hermes/.local/bin/hermes) 的 wrapper）。
2. **先论证挂靠**：新增入口前必须先论证无法作为现有工具的子命令挂靠；直接新建独立入口视为违规。
3. **禁止新增 `*-update` 入口文件**：更新逻辑一律实现为 `tool update` 子命令。
4. **`*-acp` 协议入口豁免**：外部 ACP host（Zed 等）按命令名寻址 agent，无法子命令化，允许作为包内第二入口；头注释须说明约束来源（范本：[hermes-acp](agents/hermes/.local/bin/hermes-acp)），`toolbox check` 对其自动豁免。
5. **拦截即遮蔽须写明**：主入口分发与上游 CLI 已有同名子命令撞名时（如 `hermes update`），分发处头注释必须写明「拦截即覆写」及原生行为的直调触达路径（范本：hermes wrapper 头注释）。
6. **例外声明**：确无法子命令化的入口（如上游子命令语义撞车、不可遮蔽）在包根 `.bin-entries-allow` 声明，每行「入口名 # 理由」，理由不可省略（范本：agents/pi 的 `pi-update`）。
7. **登记对账**：原创工具新入口须同步登记 `tools.yaml`（`toolbox check` 对账）；子命令化工具条目挂主命令名下，usage 写子命令形态。
8. **执法**：`toolbox check` 的一包一入口检测为阻断级——包内入口计入数 > 1 或豁免缺理由即非零退出（`*-acp` 自动豁免不计入；immutable 包不在检测范围）。

## stow 常用操作

```bash
blue stow <pkg>                # 部署：建软链
blue stow --restow <pkg>       # 重建软链（新增文件到已有包后必跑）
blue stow --delete <pkg>       # 撤销 $HOME 侧软链，仓库源文件保留
blue stow-all --restow         # 扫描所有包并刷新软链
```

- **修改已有文件**：直接编辑仓库源文件，保存即时生效，Git 提交留痕。
- **向已有包添加新文件**：放入源目录对应路径 → `blue stow --restow <pkg>` → 确认软链就绪再提交。
- **误删源文件恢复**：`git checkout HEAD -- <pkg>/` 检出后 `blue stow --restow <pkg>`。
- **新增包骨架**：`mkdir -p dotfiles/mutable/<pkg>/.config/<app>` + `touch dotfiles/mutable/<pkg>/.stow-package` → 把 `~/.config/<app>` 下的配置移入源目录 → 按需写 `.stow-local-ignore` 排除日志/缓存 → `blue stow <pkg>` → 提交。pnpm 系 agent 的安装清单另放 `.local/share/agents/<pkg>/`，见「Agent 运行时安装根」。
