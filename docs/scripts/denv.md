<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# denv — 项目环境管理器（direnv + Guix + 语言脚手架 + LLM 骨架）

- 源码：`dotfiles/immutable/terminal/.config/fish/functions/denv.fish`
- 部署：`~/.config/fish/functions/denv.fish`（immutable，改后需 `blue home`）
- 调用方：交互 shell 手动调用；`denv` 无参时默认走 `load`

## 用法

```text
denv                 # 无参 = load：有 .denv 回放之，否则默认 guix
denv init   [FLAGS]  # 初始化目录结构 + direnv 环境（建目录、.gitignore、git init、再走 load）
denv load   [FLAGS]  # 仅创建 direnv 相关文件
denv remove [--all] [-f]   # 删除 denv 管理的文件；--all 连 AGENTS.md/.agents 一起
denv status          # 状态总览（配置、envrc、manifest、provider 检查、direnv）
denv doctor [--fix]  # 诊断；--fix 修断裂软链/缺 .gitkeep
denv help | -h | --help
```

init/load 的 FLAGS：`-l/--lang <langs>`（逗号分隔或多次出现，支持 `-l=x`/`--lang=x`）、`-L/--LLM`（LLM 脚手架）、`--full`（配合 -L 用完整 AGENTS.md 模板）、`--no-guix`、`-f/--force`（覆盖 .envrc 不询问）、`-h/--help`。

语言 canonical：`python node rust java c cpp csharp`；别名 `py js ts rs jvm gradle maven cc c++ cs c# dotnet`。

## 依赖

`direnv`（写 .envrc 后自动 `direnv allow`；缺失时提示手动执行）、`git`（init 时建仓库）、`guix`（写 manifest.scm，仅数据写入不调用 guix）、各语言 provider 的可选工具（`uv`、`npm`、`cargo`、`dotnet`——缺失时手写最小模板兜底）。

## 工作原理

provider 插件架构：每个 provider 是 7 个约定函数 `__denv_provider_<name>_{init,envrc,files,dirs,gitignore,guix_packages,check}`，通过 `functions -q` 存在性检测 + 动态调用分发。providers 由 flags 组装：`guix`（除非 `--no-guix`）+ 各语言 + `llm`。

- `init`：建基础目录（`src/`、`doc/` + provider dirs）→ 幂等拼装 `.gitignore`（已存在则只追加缺失行）→ `git init` → 转 `load`。
- `load`：`.envrc` 存在且无 `--force` 时先询问 → provider `init` 建语言文件 → guix 活跃时渲染 `manifest.scm` → 写 `.envrc`（`# --- denv managed ---` 包裹）→ 写 `.denv` 声明式记录 → `direnv allow`。
- `.denv` 是无参回放的依据：`langs=`、`llm=`、`guix=`、`full=`。`status`/`doctor` 也据此标记活跃 provider（`*`）。
- `remove`：汇集所有 provider `files` + `.denv` + csharp 动态产物（`*.csproj`、`Program.cs`）+ `.venv` + LLM 软链（`CLAUDE.md`、`./.claude/skills`）；`--all` 追加 `AGENTS.md`、`.agents/skills`。确认后逐个 `rm`，顺道清空 `.claude`/`.agents` 目录，最后 `direnv deny`。
- `doctor`：`.envrc` 缺失、活跃 provider 文件缺失、断裂软链、空 `.agents/skills` 缺 `.gitkeep`、`.envrc` 含 `use guix` 但无 manifest；`--fix` 修软链和 `.gitkeep`。

## 设计决策与不变量

- **manifest.scm 只合并不覆盖**：已有 `manifest.scm` 时抽取 `"pkg"` 条目并入去重列表，不丢手写包。
- **全局标记传递**：`--force`/`--full` 经 `__denv_force`/`__denv_llm_full` 全局变量传给下游，`__denv_parse_and_run` 收尾清理；`__denv_write_config` 依赖调用方先设 `__denv_cfg_*`。
- **`--full` 必须配合 `-L`**，否则报错。c/cpp 同选共享 `CMakeLists.txt`，先建者赢。
- **手写 while 而非 argparse**：需要兼容 `-l a,b` 逗号展开与 `-l=x`/`--lang=x` 等号形态，fish `argparse` 表达不了。
- **flag 开头无子命令按 `load` 处理**：`denv -l python` ≡ `denv load -l python`。
- 有显式参数时不合并历史 `.denv`（避免配置意外膨胀）；无参才回放。
- LLM 软链契约：`CLAUDE.md → AGENTS.md`、`.claude/skills → ../.agents/skills`；已是正确软链则跳过，指向他处/普通文件则警告不覆盖。

## 变更记录

- 2026-09-29：注释压缩与文档外移（行为不变）；`.gitignore` 拼装去掉无实义的逐行拷贝循环。

## 故障排查

- `denv load` 卡住：`.envrc` 已存在且未加 `-f`，正在等 `[y/N]` 输入。
- `status` 显示 provider 全量检查：说明无 `.denv`，属正常兜底展示。
