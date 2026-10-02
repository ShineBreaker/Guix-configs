<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# denv — 项目环境管理器（direnv + Guix + 语言脚手架 + LLM 骨架）

`dotfiles/immutable/terminal/.config/fish/functions/denv.fish` · immutable → `~/.config/fish/functions/denv.fish`（改后须 `blue home`） · 交互 shell 手动调用，补全 `completions/denv.fish` 独立维护

源码 1575 行、9 个 provider、6 个子命令，是子系统而非小函数，故自成一篇。

## 用法

```text
denv                 # 无参 = load：有 .denv 回放之，否则默认 guix
denv init   [FLAGS]  # 初始化目录结构 + direnv 环境（建目录、.gitignore、git init，再走 load）
denv load   [FLAGS]  # 仅创建 direnv 相关文件
denv remove [--all] [-f]   # 删除 denv 管理的文件；--all 连 AGENTS.md 与 .agents 一起
denv status          # 状态总览（配置、envrc、manifest、provider 检查、direnv）
denv doctor [--fix]  # 诊断；--fix 修断裂软链与缺 .gitkeep
denv help | -h | --help
```

init/load 的 FLAGS：`-l/--lang <langs>`（逗号分隔或多次出现，支持 `-l=x` / `--lang=x`）、`-L/--LLM`（LLM 脚手架）、`--full`（配合 `-L` 用完整 AGENTS.md 模板）、`--no-guix`、`-f/--force`（覆盖 `.envrc` 不询问）、`-h/--help`。

语言 canonical：`python node rust java c cpp csharp`；别名 `py js ts rs jvm gradle maven cc c++ cs c# dotnet`（`cpp` 同时是 canonical 与别名，指向自身）。

依赖：`direnv`（写 `.envrc` 后自动 `direnv allow`，缺失时提示手动执行）、`git`（init 时建仓库）、`guix`（只往 `manifest.scm` 写数据，不调用）、各语言的可选工具（`uv`、`npm`、`cargo`、`dotnet`——缺失时写最小模板兜底）。

## 工作原理

provider 插件架构：每个 provider 是 7 个约定函数 `__denv_provider_<name>_{init,envrc,files,dirs,gitignore,guix_packages,check}`，靠 `functions -q` 做存在性检测 + 动态调用分发，缺哪个就跳过哪个。provider 集合由 flags 组装：`guix`（除非 `--no-guix`）+ 各语言 + `llm`。

- `init`：建基础目录（`src/`、`docs/` + provider dirs）→ 幂等拼装 `.gitignore`（已存在则只追加缺失行）→ `git init` → 转 `load`。
- `load`：`.envrc` 存在且无 `--force` 时先询问 → provider `init` 建语言文件 → guix 活跃时渲染 `manifest.scm` → 写 `.envrc`（`# --- denv managed ---` 包裹）→ 写 `.denv` 声明式记录 → `direnv allow`。
- `remove`：汇集所有 provider 的 `files` + `.denv` + csharp 动态产物（`*.csproj`、`Program.cs`）+ `.venv` + LLM 软链（`CLAUDE.md`、`.claude/skills`），`--all` 再追加 `AGENTS.md` 与 `.agents/skills`。确认后逐个删，末尾清空 `.claude` / `.agents` 目录并 `direnv deny`。
- `doctor`：`.envrc` 缺失、活跃 provider 文件缺失、断裂软链、空 `.agents/skills` 缺 `.gitkeep`、`.envrc` 含 `use guix` 但无 manifest；`--fix` 修软链与 `.gitkeep`。

## 设计决策与不变量

- **无参 = `load`，`.denv` 是无参回放的唯一依据**：记录 `langs=`、`llm=`、`guix=`、`full=`，`status` / `doctor` 也据此标记活跃 provider。**有显式参数时不合并历史 `.denv`**（避免配置意外膨胀），只有无参才回放。
- **flag 开头无子命令按 `load` 处理**：`denv -l python` ≡ `denv load -l python`。
- **手写 while 解析而非 fish `argparse`**：要兼容 `-l a,b` 的逗号展开与 `-l=x` / `--lang=x` 的等号形态，`argparse` 表达不了。
- **`manifest.scm` 只合并不覆盖**：已存在时抽出其中的 `"pkg"` 条目并入去重列表再重写，不丢手写包。
- **`--full` 必须配合 `-L`**，否则报错退出。c 与 cpp 同选时共享 `CMakeLists.txt`，**先建者赢**（后到的 provider 检测到文件已存在就跳过）。
- **LLM 软链契约**：`CLAUDE.md → AGENTS.md` 与 `.claude/skills → ../.agents/skills`。已是正确软链则跳过；已是软链但指向他处、或存在同名普通文件，则警告并跳过，不覆盖用户文件。
- **全局标记传递**：`--force` / `--full` 经 `__denv_force` / `__denv_llm_full` 全局变量传给下游，由 `__denv_parse_and_run` 收尾清理。
- **`llm` provider 的 `files` 刻意留空**：`remove` 只删 LLM 软链，`AGENTS.md` 等内容文件只有 `--all` 才删。

## 故障排查

- `denv load` 卡住不动：`.envrc` 已存在且未加 `-f`，正在等 `[y/N]` 输入。
- `status` 走全量 provider 检查：说明没有 `.denv`，属正常兜底展示。
- 某语言文件没生成：先确认语言已归一到 canonical（`denv` 会把未知语言直接报错列出可用值），再看该 provider 的 `check` 输出。