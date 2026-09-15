# Guix-configs — 仓库导引

以 Guix 为核心的个人系统配置仓库：由单一 `source/config.org` 同时声明 `operating-system` 与 `home-environment`，经 `blue` 工具构建（`config.org` → tangle → `tmp/config.scm` → 单次 reconfigure 同时应用系统与 Home）。`CLAUDE.md` 是本文件的软链接。

<!-- structor:begin depth=1 -->

<!-- 此树形目录由 structor 自动生成，请勿手动编辑。 -->

```
Guix-configs///
├── .agents/
├── docs/
├── dotfiles/
├── screenshots/
├── source/
├── tools/
├── .gitattributes
├── .gitignore
├── .gitmodules
├── CLAUDE.md
├── LICENSE
├── README.org
└── blueprint.scm
```

<!-- /structor -->

## 任务路由

| 任务                          | 入口                                                                                                                  |
| ----------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| System / Home 配置            | `source/AGENTS.md`（配置逻辑与技术知识集中在此）                                                                      |
| 应用 dotfiles                 | `dotfiles/AGENTS.md` 为索引；immutable 各子目录大多有 AGENTS.md，mutable 包见 `dotfiles/mutable/AGENTS.md`            |
| Emacs                         | `dotfiles/mutable/emacs/.config/emacs/AGENTS.md`（必读）；新包须同步 `config.org` 的 `emacs-services` manifest        |
| Agent 配置（anchors/context） | 共享体系见 `dotfiles/immutable/agents/AGENTS.md`；各 agent 包在 `dotfiles/mutable/agents/`（omp/pi/dsh 等）           |
| 静态模板 / 频道 / 全局变量    | `source/files/`、`source/channel.scm`、`source/information.scm`（见 `source/AGENTS.md`）                              |
| 新机装机（官方 ISO）          | `tools/bootstrap.sh` 准备 blue 环境，随后人工执行 `blue init`；流程见 `README.org`（自建 ISO 见 `docs/iso-build.md`） |

## 硬约束

<critical>
1. **就近原则**：更近目录的 `AGENTS.md` 优先生效；文档若与仓库实际结构冲突，以源码为准。
2. **只改源码**：禁止直接修改 `~/.config/`、`~/.local/` 等已部署位置，一律修改仓库中的配置源文件。
3. **immutable 部署**（`dotfiles/immutable/`）：构建时复制进 `/gnu/store` 只读副本再软链到 `$HOME`。**改源后不会自动生效**，必须运行 `blue home` 重建；验证可用 `md5sum` 对比源码与部署文件。
4. **mutable 部署**（`dotfiles/mutable/`：`agents/`、`emacs`、`lem`、`tools/` 下的各包）：GNU Stow 直链仓库源码，改源即时生效，无需运行 `blue home`。
5. **权限限制**：禁止 agent 自行执行 `blue rebuild` 或 `guix system reconfigure`（需要 sudo 权限）；调试仅允许运行 `blue home`，确认无误后提醒用户手动 rebuild 固化。切勿绕过 `blue` 直接调用 `guix`（确保频道锁定）。
6. **文件操作禁区**：禁止手动编辑 `tmp/` 下的任何生成物和 `source/channel.lock`（由 `blue update` 自动生成）；禁止直接编辑子模块内容；禁止将 mutable 文件放入 immutable 目录（避免双重部署冲突）。
7. 命令清单以 `blue list` 为准，单命令详情见 `blue help <命令>`。
</critical>

## 验证（修改 `source/config.org` 后必做）

```bash
blue --dry-run rebuild   # tangle + 括号检查 + 构建验证，不写入系统（对全部 %run 子进程生效）
blue check               # 最快：逐块括号平衡检查，定位到具体块名
```

## Scheme 代码规范（R6RS 中括号）

方括号与圆括号语法等价，但**仅用于「否则会出现两个连续左括号」的语法位置**（参考 [R6RS 附录 C](https://r6rs.org/final/html/r6rs-app/r6rs-app-Z-H-5.html#node_chap_C)）：

- `cond` / `case` / `guard` 子句
- `let` 体系与 `do` 的变量绑定
- `case-lambda` / `syntax-rules` / `syntax-case` 子句
- Guile 扩展：`match` / `match-lambda` 子句
- 示例：`(cond [(eof-object? c) #f] [else ...])`、`(let ([x 1]) ...)`
- **注意**：普通函数调用、lambda 参数表、quote 数据等位置一律使用圆括号。

## 结构图维护

`<!-- structor -->` 标记对之间的目录树由 `blue structor` 自动生成，请勿手动编辑。新增或移动文件后运行 `blue structor` 刷新（`ORG_STRUCTOR_DRY=1` 预览，`depth=N` 控制深度），文件可见性遵循 `.gitignore`。
