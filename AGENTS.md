# Guix-configs — 仓库导引

以 Guix 为核心的个人系统配置仓库：单一 `source/config.org` 同时声明 `operating-system` 与 `home-environment`，经 `blue` 构建（`config.org` → tangle → `tmp/config.scm` → 单次 reconfigure 同时应用系统与 Home）。`CLAUDE.md` 是本文件软链。

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

| 任务                            | 入口                                                                                                              |
| ------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| System / Home 配置              | `source/AGENTS.md`（config.org 正文已化简为结构标签，技术知识集中在该文件）                                       |
| 应用 dotfiles                   | `dotfiles/immutable/<app>/`（各子目录有 AGENTS.md）；`dotfiles/mutable/`（Stow 直链，见其 AGENTS.md）             |
| Emacs                           | `dotfiles/mutable/emacs/.config/emacs/AGENTS.md`（必读）；新包须同步 `config.org` 的 `emacs-services` 块 manifest |
| Agent 配置（omp/Crush/anchors） | `dotfiles/immutable/agents/AGENTS.md`；omp 扩展在 `dotfiles/mutable/agents/omp/`                                  |
| 静态模板 / 频道 / 全局变量      | `source/files/`、`source/channel.scm`、`source/information.scm`（见 `source/AGENTS.md`）                          |
| 新机装机（官方 ISO）            | `tools/bootstrap.sh` → `blue init`；流程见 `README.org`（自建 ISO 见 `docs/iso-build.md`）                        |

## 硬约束

<critical>
1. 更近目录的 `AGENTS.md` 优先；文档与仓库实际结构冲突时以源码为准
2. **禁止直接修改 `~/.config/`、`~/.local/` 等已部署位置**，一律改源
3. **immutable 部署**（`dotfiles/immutable/`）：构建时复制进 `/gnu/store` 只读副本再软链到 `$HOME`，**改源 ≠ 生效**，必须 `blue home` 重建；验证用 `md5sum` 对比源与部署位
4. **mutable 部署**（`dotfiles/mutable/`：emacs、lem、hermes、omp、secrets 等）：GNU Stow 直链仓库源，改源即生效，无需 `blue home`
5. **禁止** agent 自行运行 `blue rebuild` / `guix system reconfigure`（需 sudo）；只许 `blue home` 调试，确认正常后提醒用户手动 rebuild 固化。不要绕过 `blue` 直接调 guix（频道不会被锁）
6. **禁止**手动编辑 `tmp/` 下任何产物、`source/channel.lock`（`blue update` 重生成）；不要直接编辑子模块内容；不要把 mutable 文件加进 immutable（双重部署冲突）
7. 相关命令以 `blue help` 为准
</critical>

## 验证（改 `source/config.org` 后必做）

```bash
blue --dry-run rebuild   # tangle + 括号检查 + 构建验证，不写入系统（对全部 %run 子进程生效）
blue check               # 最快：逐块括号平衡检查，定位到块名
```

## Scheme 代码规范（R6RS 中括号）

方括号与圆括号语法等价，但**只用于「否则会出现两个连续左括号」的句法位置**（[R6RS 附录 C](https://r6rs.org/final/html/r6rs-app/r6rs-app-Z-H-5.html#node_chap_C)）：`cond`/`case`/`guard` 子句、`let` 系与 `do` 的绑定、`case-lambda`/`syntax-rules`/`syntax-case` 子句；仓库延伸：Guile `match`/`match-lambda` 子句。如 `(cond [(eof-object? c) #f] [else ...])`、`(let ([x 1]) ...)`。函数调用、lambda 参数表、quote 数据不用。

## 结构图维护

`<!-- structor -->` 标记对之间的目录树由 `blue structor` 自动生成：不要手改；新增/移动文件后跑 `blue structor` 刷新（`ORG_STRUCTOR_DRY=1` 预览，`depth=N` 控制深度）。可见性遵循 `.gitignore`。
