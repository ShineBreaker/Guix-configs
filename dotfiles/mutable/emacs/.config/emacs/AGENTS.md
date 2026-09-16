# AGENTS.md — Emacs 配置规范与工作手册

本文件是本目录下 AI Agent 的唯一操作规范。`emacs.org` 仅维护配置逻辑、功能语义与设计取舍，无需在其中重复 Agent 工作流或验收规则。

本配置通过 GNU Stow 逐文件软链到 `~/.config/emacs/`，**修改仓库源码即时更新部署源**，切勿直接编辑 `~/.config/emacs/` 中的部署文件。

---

## 1. 架构契约与文件角色

| 文件 / 脚本         | 角色定位                 | 维护规则                                                     |
| ------------------- | ------------------------ | ------------------------------------------------------------ |
| `emacs.org`         | 唯一配置真理源           | 日常功能配置一律在此修改                                     |
| `init.el`           | 固定 Bootstrap 引导      | 保持 Tangle 逻辑与单产物模型稳定，不轻易改动                 |
| `early-init.el`     | 启动前优化配置           | 仅放置必须早于 `main.el` 执行的底层设置（如 GC、Frame 参数） |
| `main.el`           | Tangle 产物（gitignore） | **禁止手动编辑**，由 `emacs.org` 编译生成                    |
| `data/*.el`         | 静态翻译与数据           | 仅允许字面量 `setq` 与注释                                   |
| `scripts/configctl` | 代码块操纵工具           | 面向 Agent 的代码段提取、拼合与定位工具                      |

### 启动调用链

```
emacs → init.el → (按需 tangle emacs.org) → main.el → (load main.el)
```

### 核心硬约束

- **单一生成产物**：仅生成唯一的 `main.el`，严禁 `:tangle lisp/...`；禁止引入 `lisp/` 目录到 `load-path`，禁止使用 `(require 'custom-...)` 或 `(provide 'custom-...)`。
- **文件尾声明**：`main.el` 尾部仅保留 `(provide 'main)`。
- **包清单同步**：引入新的 Emacs 插件包时，必须同步更新根仓库 `source/config.org` 中的 `emacs-services` manifest。

---

## 2. 导航与配置域加载顺序

修改前无需阅读全文，优先使用 `configctl` 快速检索定位（如 `scripts/configctl map` / `show dashboard` / `locate dashboard`）：

| 工具命令           | 主要用途                                                 |
| ------------------ | -------------------------------------------------------- |
| `map`              | 列出所有 `CUSTOM_ID`、行号、代码量与 noweb ref 引用      |
| `show <ID>`        | 提取指定功能子树全文（支持唯一模糊匹配）                 |
| `locate <ID\|REF>` | 定位块行号区间或 noweb ref 的组装位置                    |
| `tangle`           | 拼合生成 `emacs.org → main.el`                           |
| `check`            | 执行静态轻量规则检查（域顺序、noweb 依赖图、括号平衡等） |

### 8 大配置域加载顺序

`emacs.org` 的文档编排顺序即为求值顺序，8 个配置域固定如下：

| 序号 | 配置域 / ID       | 主要职责                                                   | 前置依赖                  |
| ---- | ----------------- | ---------------------------------------------------------- | ------------------------- |
| 1    | `startup`         | 路径、外部进程、Frame 行为、键位基础原语                   | 无                        |
| 2    | `appearance`      | 帮助系统、Modeline、Tab-line、Git 状态、主题与字体         | `startup` 的 Frame 原语   |
| 3    | `editing`         | 通用编辑增强、DWIM 变换、内置终端                          | `git-display`             |
| 4    | `programming`     | Tree-sitter、Eglot (LSP)、Flymake、代码格式化与各语言 Mode | `bootstrap`、`appearance` |
| 5    | `projects`        | Project.el、目录树与项目导航                               | `terminal`、`git-display` |
| 6    | `org-knowledge`   | Org Mode、Roam 笔记、Agenote 知识库                        | `bootstrap`               |
| 7    | `keys-completion` | 顶层前缀声明、跨域基础键、内置补全栈 (Vertico/Consult)     | 交互命令与 Frame 体系     |
| 8    | `system-tools`    | Daemon 预热、Dashboard 欢迎屏、版本兼容兜底                | 前述全部模块              |

### 键位归属原则（功能内聚）

- **功能相关按键跟随其实现所在的域**，不再集中塞入全局按键块。
- `custom/bind` 内部通过 `custom--pending-wk-descs` 暂存 Which-key 描述，延迟到 Which-key 就绪后统一刷新。
- 仅有 14 个顶层前缀声明（`custom/declare-binding-group`）、跨域基础键（`C-x` / `M-s` / `C-c w` 等）以及全局 IDE 直达键保留在 `keys-completion` 域。

---

## 3. 标准开发流程

1. **定位与提取**：运行 `scripts/configctl map` 查询目标 ID，使用 `show <ID>` 提取对应子树，使用 `locate <ID>` 查看代码行号。
2. **就地修改**：编辑对应功能子树；除非修改了跨域导出的公共 API，否则不影响其他域。
3. **同步包清单**：若引入了新包，在 `source/config.org` 的 `emacs-services` 块中登记。
4. **编译与验证**：执行 `scripts/configctl tangle` 并在隔离环境验证无 Lisp Error。

---

## 4. 编码规范与设计公约

### Noweb 规则

- 绝大多数代码块按文档顺序直接 tangle 进 `main.el`。
- Noweb 仅用于两类特殊场景：
  1. **版本兼容 Shim（前向引用）**：定义在 `compatibility` 域尾部，由靠前的使用点通过列 0（顶格）的 `<<emacs31/...>>` 展开。
  2. **`#+name` 纯文本数据块**（如 Capture 模板）：声明 `:tangle no` 并紧跟引用者。

### 精简与防御边界

- **消除冗余 Wrapper**：只用一次的辅助函数直接内联；禁止仅用于原样转发的包装函数。
- **守卫边界（`fboundp` / `boundp`）**：仅用于**延迟加载的第三方包**与**跨构建变量**。同一 `main.el` 产物内部的函数互调不加守卫（加载顺序已保障可用）。
- **进程与异步安全**：存活检查（`frame-live-p` / `buffer-live-p`）仅在异步回调（Timer、D-Bus、Process Sentinel）中保留；遍历 `frame-list` / `window-list` 时无需逐层检查。
- **异常捕获**：`condition-case` 仅包裹文件 I/O、外部子进程或 D-Bus 调用；对于返回 nil 的查询型 API（如 `project-current`、`treesit-ready-p`）不加包裹。

---

## 5. 性能硬约束

1. **优先级**：Client 首次打开与交互延迟 > Daemon 长时间运行稳定性与内存 > Daemon 启动时间。
2. **热路径禁令**：禁止在 Mode-line、Tab-line、Redisplay、Post-command 等高频回调中执行文件 I/O、同步子进程或重复 `require`。
3. **缓存与失效**：昂贵计算结果使用 Buffer-local 或 Frame-local 缓存，并在 Save、Revert、Major-mode 切换时精准失效。
4. **异步 I/O**：UI 交互绝不同步等待外部 CLI，统一使用 `make-process` 异步刷新与展示。

---

## 6. 新增包与部署流程

当需要引入新的 Emacs 包时，执行以下标准流程：

1. **`emacs.org` 中声明**：使用 `use-package` 配合 `:commands` / `:hook` / `:mode` 配置懒加载，按键使用 `custom/bind`。
2. **同步 Manifest**：在根仓库 `source/config.org` 的 `emacs-services` 块（`specifications->manifest`）添加对应包名（先用 `guix package -A '^emacs-<name>$'` 确认包存在）。
3. **构建验证**：运行 `blue -n home`（dry-run）校验配置有效性。
4. **应用部署**：运行 `blue home` 更新 profile。
5. **重启 Daemon**：运行 `herd restart emacs-daemon`（Daemon 启动时自动按需重新 tangle 并加载最新配置）。

---

## 7. 验收标准与测试方法

### 7.1 轻量静态检查

```bash
scripts/configctl check     # 校验域顺序、Noweb 图、括号平衡与重复定义
git diff --check
```

### 7.2 加载验证（隔离环境）

Tangle 生成最新 `main.el` 后，在隔离环境执行 batch-load 验证是否有 Lisp Error：

```bash
scripts/configctl tangle
emacs --batch -q -l main.el
```

> **注意**：用 `-q` 而非 `-Q`——`-Q` 跳过 `site-start`，Guix profile 的 `guix-emacs.el` autoloads（如 `telega-prefix-map`）不会注册，`custom/bind` 会报 void-variable 假阳性。`load` 遇到 Error 会直接中断后续配置执行。必须确认 batch-load 零 Error，且 `custom:binding-spec` 数量符合预期。

### 7.3 按键有效性核对

- 功能键必须写为 `<f12>` 格式（而非 `"F12"`，避免被 `key-parse` 拆散）。
- 终端兼容性：`C-S-*`、`C-<tab>` 在部分终端下会退化，高频操作建议提供 `C-c` 前缀的备用键。

### 7.4 Tmux TTY 真机验收

针对 Daemon、按键或包改动，通过 Tmux 连接运行中的 Daemon 进行端到端实测：

```bash
tmux new-session -d -s emacsprobe -x 180 -y 45
tmux send-keys -t emacsprobe 'emacsclient -t' Enter
sleep 3
tmux capture-pane -t emacsprobe -p | tail
tmux kill-session -t emacsprobe
```

### 7.5 包清单双向一致性核对

- Manifest 中的每个 `emacs-*` 包在 `emacs.org` 均有实际引用（避免无用包）。
- `emacs.org` 中引用的每个第三方包在 Manifest 中均有登记（避免依赖缺失）。
