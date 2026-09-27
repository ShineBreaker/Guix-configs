# 新插件装入新 profile — 完整配方

适用：给 dsh 装一个**自带 agent preset / 独立 launcher** 的插件（TUI 类、终端类），
或任何需要与 web profile 隔离的插件。SKILL.md §4 是判据层，本文件是操作层。

## 0. 版本决策（先定要不要降级）

```bash
export PATH="$HOME/.local/state/nix/profiles/profile/bin:$PATH"
pnpm view <pkg> versions --json
pnpm view <pkg>@<ver> peerDependencies    # peer 锁的 @deepseek-ai/dsh-* 范围
~/.local/bin/dsh --version                 # 本体版本
```

- peer 范围含本体版本 → 直接装，不降级。
- 不含但插件确有该能力 → `allow-version ... --accept-risk` 授权，授权记录落
  `compatibility.json`（新机复现的一部分，必须进仓库源）。
- 真正要降级的判据（web 侧先例）：peer 锁的核心版本区间够不到本体（semver 预发布
  区间只匹配同 `0.1.x` 元组，永远升不上去），或启动即
  `pending (waiting for service: <已不存在服务>)`。逐版本 view peerDependencies，
  找最后一个能解析的版本。

## 1. 安装与源同步

```bash
~/.local/bin/dsh plugin --profile <name> allow-version <pkg>@<ver> --dsh-version <core> --accept-risk
~/.local/bin/dsh plugin --profile <name> add -w <pkg>@<ver>
```

产物六件套，全部进仓库源
`dotfiles/mutable/agents/dsh/.local/share/dsh/profiles/<name>/`：

| 文件 | 内容 | stow 形态 |
| --- | --- | --- |
| `package.json` | dependencies + `dsh.profile.bundles` | 软链 |
| `cordis.yml` | 空 entry 列表（编辑 patch，别动它） | 软链 |
| `cordis.patch.yml` | 用户 patch 层 | 软链 |
| `pnpm-workspace.yaml` | pnpm 配置 | 软链 |
| `pnpm-lock.yaml` | 锁文件 | 源副本 + 部署侧真实文件（stow ignore，pnpm 拒写软链） |
| `compatibility.json` | compat 授权记录（部署侧 600 权限） | 软链 |

```bash
cd <repo>/dotfiles/mutable/agents/dsh/.local/share/dsh/profiles
mkdir -p <name> && cd <name>
for f in package.json cordis.yml cordis.patch.yml pnpm-workspace.yaml \
         compatibility.json pnpm-lock.yaml; do
  cp -p ~/.local/share/dsh/profiles/<name>/$f . && chmod 644 "$f"
done
cd <repo> && blue stow --restow agents/dsh
cp ./pnpm-lock.yaml ~/.local/share/dsh/profiles/<name>/pnpm-lock.yaml  # stow ignore 了 lock
cd ~/.local/share/dsh/profiles/<name> && PATH="$HOME/.local/state/nix/profiles/profile/bin:$PATH" \
  pnpm install --frozen-lockfile    # 确认 lock 与 node_modules 一致
```

`blue stow` 包参数是 **`agents/dsh`**；lockfile 从源拷回部署侧（与 web profile
同模式），拷完 `cmp -s` 双向核对。

## 2. restow 撞车处置

pnpm 把部署侧配置写成实体文件、dsh 包装器自愈建**绝对**软链，两种都让 `--restow`
全量中止：

```
cannot stow ... over existing target ... since neither a link nor a directory
Ignoring an absolute symlink: <path> => <绝对路径>
existing target is not owned by stow: <path>
```

- 实体文件冲突：内容已在源里 → `trash-put` 部署侧文件再 restow（**不要**
  `--adopt`，那会把部署侧当基线反向覆盖源）。
- 绝对软链：`trash-put` 掉，restow 用相对路径重建。
- 逐条清到 stow 输出只剩 `[重建] agents/dsh -> ... (no-folding)`。
- **stow ignore 的文件（pnpm-lock.yaml）trash 后不会自动回来**：它是真实文件，
  清撞车时若把它一起 trash，restow 后部署侧缺失——从源 `cp` 回去再
  `pnpm install --frozen-lockfile` 核对。

## 2b. 收尾提交（git 侧）

- `git commit` 只接受 `-m`（gate 拒 `-F` 与 heredoc）；多段 body 用多个 `-m`
  按序拼：header / why 各一个，`Co-authored-by` trailer 一个。
- **提交前核对暂存清单恰好等于本任务文件表**：上个会话遗留的 staged 文件不会
  被 `git add -- <路径>` 排除，会静默混进提交。先
  `git restore --staged <遗留路径>`，再 `git diff --cached --name-only` 核对。
- **署名 = 当前 agent 名 + 实际模型**。仓库里的 commit 规范（SOUL.md 偏好、
  agent skill 规范、wrapper 头注释）可能残留**别的 agent** 的 attribution
  规定——那是配置源头写错了，先修配置，已写错的提交用
  `git reset --soft HEAD~N` + 按正确清单重提换 trailer（不用交互式 rebase，
  editor 路径过不了 gate）。
- 新 profile / 新入口必须同步仓库 `agents/dsh/AGENTS.md`：布局表加行 + 专节写
  安装命令、compat 门、版本线判据。文档写不进去（编辑门禁拦 AGENTS.md）时
  **重试一次**，仍被拦再如实上报，不要留「无文档的新入口」。

## 3. 验证三连

```bash
~/.local/bin/dsh --profile <name> --dump-config | grep -c '^- id:'          # 对基线
~/.local/bin/dsh --profile <name> --dump-config | grep -c '^- id: <bundle-id>$'
node <profile>/node_modules/<pkg>/bin/<bin>.js doctor                        # 自带 launcher 才有
```

**compatibility.json 删除测试**（判定它是否 boot 必需，做一次把基线钉住）：移走它
再 dump-config，条目数应下降；放回恢复。数字对不上 = bundle 被静默跳过。

## 4. alt-screen CLI 的 boot 冒烟

```bash
cd <profile> && timeout 30 bash -c \
  'setsid script -qfc "timeout 14 ~/.local/bin/dsh --profile <name> 2>/tmp/be.log" /tmp/p.log \
   >/dev/null 2>&1 </dev/null & sleep 18'
grep -c "setRawMode EIO" /tmp/be.log    # agent 伪终端固有噪声，不是失败
```

通过判据（任一）：

- `/tmp/be.log` 出现 `ESC[?25l`（隐藏光标）= 已进入 ink 渲染阶段；
- `~/.local/share/dsh/sessions/--<profile 路径转义>--/<uuid>/session.v4.jsonl.zstd`
  生成，`zstd -dc` 首行含 `"agentPreset":"<名>"`。

真机 TTY 下没有 EIO；agent 环境里它不代表失败。

## 5. 入口：双态 launcher → libexec 挂靠

1. 新建 `.local/libexec/<name>`（可执行）：

   ```bash
   : "${DSH_HOME:=${XDG_DATA_HOME:-$HOME/.local/share}/dsh}"; export DSH_HOME
   _bin="$DSH_HOME/profiles/<name>/node_modules/<pkg>/bin/<bin>.js"
   [[ -r $_bin ]] || { printf 'dsh <sub>: 找不到 %s\n' "$_bin" >&2; exit 127; }
   exec node "$_bin" "$@"
   ```

2. 在 `bin/dsh` 的 case 分发点加一行：
   `<sub>) exec "$_libexec_dir/<name>" "${@:2}" ;;`
3. 透传全部子命令；上游原生已有同名子命令时属**遮蔽**，注释写明原生行为只能经
   `$_cli_bin` 直调（无同名子命令则无此问题）。

## 6. preset 行的补丁限制

profile 层 `cordis.patch.yml` 的 `- id:` 目标若属于某个 preset 的组合行，preset 没
挂载前该 id 不存在 → 每次 boot 报 `patch: entry "<id>" not found`。改 preset 行
（如 Guix 无 `/bin/bash` 时的 `shellPath`）必须整块复制官方 preset + 换 id + 保留
改动；registry 按 `config.id` 去重，同 id 覆盖直接抛 `Duplicate agent preset`。
