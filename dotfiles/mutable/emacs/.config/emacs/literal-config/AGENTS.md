# AGENTS.md — literal-config 工作规范(自包含)

> **本文件是仓库内所有 AI agent 的唯一工作规范**。
> 自包含:任何 agent 拿到本文件即可独立工作,**不得**再依赖已退役的 `docs/` 目录、`PLAN.md`、根 `CONTEXT.md`。
>
> 适用对象:literal-config 仓库及其全部子文件;工作范围从「阅读与扩展」到「迁移收尾」与「验收」。

---

## 1. 仓库是什么

| 项       | 值                                                                                   |
| -------- | ------------------------------------------------------------------------------------ |
| 路径     | `~/Projects/Config/Guix-configs/dotfiles/mutable/emacs/.config/emacs/literal-config` |
| 用途     | 个人 Emacs 配置(literate),chemacs2 选 `literal` profile 后加载                       |
| 技术栈   | GNU Emacs 31+、org-mode / org-babel、Guix 包管理、`use-package`、noweb               |
| 启动路径 | chemacs2 → `init.el` →(按需 tangle `emacs.org` → `main.el`)→ `load main.el`          |

### 1.1 文件清单与处理规则

| 文件            | 处理                                        | 谁来维护                                  |
| --------------- | ------------------------------------------- | ----------------------------------------- |
| `emacs.org`     | **唯一真理源**,git 跟踪                     | 人类 + agent 编辑                         |
| `init.el`       | 固定手写 bootstrap,git 跟踪,chemacs2 入口   | 人类手维护,agent **禁止**改动 tangle 签名 |
| `early-init.el` | 固定手写启动期优化,git 跟踪                 | 人类手维护                                |
| `main.el`       | **tangle 产物**,`/.gitignore` 忽略,禁止手改 | 由 `init.el` 按需重建                     |
| `scripts/`      | 辅助 Python/Bash 脚本,git 跟踪              | 见 §7                                     |

### 1.2 启动契约(init.el 不可改)

```elisp
(let* ((org-file  (expand-file-name "emacs.org" user-emacs-directory))
       (main-file (expand-file-name "main.el"  user-emacs-directory)))
  (when (or (not (file-exists-p main-file))
            (file-newer-than-file-p org-file main-file))
    (require 'org) (require 'ob-tangle)
    (let ((gc-cons-threshold most-positive-fixnum))
      (org-babel-tangle-file org-file main-file "emacs-lisp")))
  (load main-file nil t))
```

约束:

- `init.el` 不由 `emacs.org` tangle 生成(否则机制自杀)
- tangle 第二参数始终是 `main-file` 字面量,**不得**改成 `nil` 或 `"lisp/..."`
- `main.el` 由 `init.el` 触发重建,不依赖人工手跑命令

### 1.3 仓库根 `#+PROPERTY`(emacs.org 第 4 行)

```org
#+PROPERTY: header-args:emacs-lisp :tangle main.el :lexical yes :mkdirp yes :noweb tangle
```

约束:

- `:noweb tangle` — 仅在 tangle 时展开 `<<ref>>`;load 时 main.el 已是纯 elisp
- **不**加 `:comments link`(P10;noweb 碎块会让 main.el 注释爆炸)
- 默认仍 `:tangle main.el`;块级 **禁止** `:tangle lisp/...`

## 2. 设计原则(P1–P10)

### P1 — 主题优先 + org link 交叉引用

逻辑模块的 prose 按主题落在对应 `*` 域;跨域关系用 `[[*…]]` 链接,不靠重复叙述 require 表。

### P2 — 单产物 main.el

单一真理源不蕴含多文件 tangle。无「单模块热重载 / 独立分发」刚需时,不保留 `lisp/*.el` 作为架构出口。

### P3 — 文档顺序即加载契约

去掉 sibling 间 `provide`/`require`;第三方包 require 与 `use-package` 保留,正常路径不依赖 feature 名表达逻辑模块边界。
emacs.org 内已无消费者的「假 feature」; 仅可保留文件末尾 `(provide 'main)`。

### P4 — noweb 增强结构与可读性

主动用 noweb 把大段配置拆成可命名、可组装的片段(按功能/主题分组后在组装块中 `<<…>>`),并抽取真正跨处复用的样板;目标是 org 内逻辑清晰、main.el 仍是一份连贯脚本,**而不是**为多文件出口服务。

### P5 — noweb 粒度与命名(结构组装为主)

- 大逻辑模块 / 大内联块按功能小节拆 `:noweb-ref`,底部一个组装块决定写入 `main.el` 的顺序
- 小模块(≤~150 行)可整段一个 src 块
- ref 名**只用英文**,推荐 `module/section`(如 `dashboard/banner`、`keys/editing`、`helpers/call-process`)
- 每个逻辑模块(或大主题)**一个**入口组装块,避免多父块重复展开
- **不用** noweb 模拟 require

### P8 — 跨逻辑模块真重复用 noweb 去重

单产物下用 noweb 共享片段(如 `helpers/call-process`)保留**一份**定义;组装顺序上 helpers **必须**先于使用方(服从 P3)。
**不**把共享片段伪装成可 require 的基座 feature。

### P10 — tangle 注释默认关闭

全局 header `:noweb tangle`,**不**默认 `:comments link`; main.el 保持可加载脚本形态。
可追溯性靠 emacs.org 内 org link 与大纲。

---

## 3. 启动顺序与模块依赖速查

> emacs.org 顶部必须保留此表;新架构下「加载顺序」= 文档顺序 = 域顺序。

| 顺序 | 顶层域           | 内联逻辑模块                                                              | 关键跨域依赖点                                                                                                                                                                    |
| ---- | ---------------- | ------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1    | 启动与基础设施   | bootstrap、frame、键位辅助、包管理、基础行为                              | `defconst` 路径常量与 `defun` frame hook 实现;后者被 color-scheme / dashboard / completion 直接调用                                                                               |
| 2    | 界面与外观       | git、color-scheme、tab-line、modeline、help、context-menu、which-key-data | color-scheme 调用 `literal/add-frame-hook`;`literal/register-buffer-refresh!` 在此域导出供 dashboard 调用                                                                         |
| 3    | 编辑与文本       | (无外置模块)                                                              | 本域内联 `literal/{copy,cut,rename,comment}-dwim` 等;`delete-selection-mode` 覆盖选区粘贴;`with-eval-after-load 'which-key` 注册中文描述                                          |
| 4    | 编程与开发       | (无新增模块)                                                              | 共享顺序 2 已加载的 git / color-scheme / tab-line / modeline / help                                                                                                               |
| 5    | 项目与导航       | (无外置模块)                                                              | projectile-known-projects 与 terminal 子模块内联                                                                                                                                  |
| 6    | Org 与知识库     | org-knowledge、agenote                                                    | 依赖 bootstrap 提供的 `literal:org-directory` / `literal:org-inbox-file` / `literal:agenote-directory` 等 `defconst`;导出 `literal/knowledge-collect-org-files` 供 dashboard 调用 |
| 7    | 键位与补全       | completion                                                                | vertico / corfu / which-key 本体走 `use-package`,框架内联在 completion 模块;直接调用 `literal/add-frame-hook` 注册 per-frame childframe 适配                                      |
| 8    | 系统工具与实验性 | dashboard                                                                 | 直接调用 knowledge / help / color-scheme / frame 的函数;延后到此域末尾以保证依赖先就绪                                                                                            |

**依赖图**(简化):

```
bootstrap → frame → (git, color-scheme, tab-line, modeline, help, context-menu, which-key-data)
          → knowledge / agenote(需 bootstrap 路径常量;call-process helpers 已先定义)
          → completion(需 frame hooks)
          → dashboard(需 frame + knowledge + help + color-scheme 等已定义)
```

---

## 4. 命名与硬约束(实施前自检)

### 4.1 明确禁止(违反即架构破坏)

| 禁止                                                     | 原因                                          |
| -------------------------------------------------------- | --------------------------------------------- |
| `:tangle lisp/anything.el` 或多文件 tangle               | 单产物架构只要 `main.el`                      |
| 把 `init.el` 的 `org-babel-tangle-file` 第二参改成 `nil` | 那是多文件出口写法;本路线保持指向 `main-file` |
| 全局 `:comments link`                                    | P10;noweb 碎块会让 main.el 注释爆炸           |
| 修改 `~/.config/` 部署副本                               | 仓库规则:改源即可(mutable stow)               |
| `(add-to-list 'load-path … "lisp")` 任何形态             | lisp/ 不存在即该行无效且误导                  |
| `(require 'literal-…)` / `(provide 'literal-…)` 任何形态 | P3;只保留 `(provide 'main)`                   |
| 手改 `main.el`                                           | `.gitignore` 已忽略;tangle 是唯一生成路径     |

### 4.2 必须遵守(P1–P10 摘要)

1. **P1** 按域(`*` headline)放 prose 与代码;跨引用用 `[[*章节]]`
2. **P2** 唯一产物 `main.el`
3. **P4–P5** noweb 做结构组装;ref 名**仅英文** `module/section`;每逻辑模块一个组装入口
4. **P8** 跨模块真重复 → noweb 共享,一份定义
5. **验收** tangle → batch load → verify-config(改完断言)→ 静态检查
6. **P10** PROPERTY 加 `:noweb tangle`,**不加** `:comments link`

### 4.3 不改的文件(除非清单点名)

| 文件               | 处理                                                                         |
| ------------------ | ---------------------------------------------------------------------------- |
| `init.el`          | **默认不改**。继续 `(org-babel-tangle-file org-file main-file "emacs-lisp")` |
| `early-init.el`    | **不改**(非 tangle 真理源)                                                   |
| `main.el`          | **禁止手改**;只通过 tangle 生成(已在 `.gitignore`)                           |
| `var/*` 运行时状态 | 不碰(除更新 `var/verify-config.el` 断言)                                     |

### 4.4 命名约定

- noweb ref:`module/section`,**仅英文**
  - 例:`bootstrap/paths`、`frame/hooks`、`keys/editing`、`helpers/call-process`、`dashboard/banner`
- 共享 helpers 用 `helpers/...` 前缀
- 函数/变量公开命名用 `literal/xxx`(slash 命名空间);**不**用 `literal-xxx`(dash 已被 sibling require 时代占用,P3 退役)
- Lisp-2 共存:`literal/add-frame-hook` 既是函数(由 frame 模块 `defun`)又是早期 color-scheme/dashboard 头部声明的占位变量;新代码不引入新同名 defun+defvar,旧的可保留作防御

---

## 5. noweb 规则(详细)

### 5.1 片段块(不单独写入 main.el)

```org
#+begin_src emacs-lisp :noweb-ref dashboard/banner :tangle no
;; 该段代码只通过组装块展开
#+end_src
```

**强制**:

- 子块 `:tangle no` + `:noweb-ref name`
- 块外不得被直接写入 main.el
- 防漏:若组装块未 `<<name>>`,该片段被静默丢弃(无语法错误,但行为缺失)

### 5.2 组装块(写入 main.el 的入口,每逻辑模块一个)

```org
#+begin_src emacs-lisp
<<dashboard/vars>>
<<dashboard/banner>>
<<dashboard/sections>>
<<dashboard/hooks>>
#+end_src
```

**强制**:

- 每个逻辑模块(大主题)**一个**入口组装块
- `<<...>>` 顺序 = main.el 中代码顺序
- helpers 组装块**必须**出现在所有使用方之前(建议放在启动域、bootstrap 代码之后或 knowledge 之前)

### 5.3 org link

- 纯文字 `见 *某章节*` → `见 [[*某章节]]`
- 标题必须与真实 `*` / `**` headline **完全一致**,否则链接失效
- emacs.org 顶部「启动顺序与模块依赖速查」表内也用 `[[*域 headline]]` 链接

### 5.4 命名清单(可扩展)

| ref 名                                             | 来源         | 使用方                                |
| -------------------------------------------------- | ------------ | ------------------------------------- |
| `bootstrap/paths`                                  | bootstrap    | 全部                                  |
| `frame/hooks`                                      | frame        | color-scheme / completion / dashboard |
| `helpers/call-process`                             | helpers      | knowledge / agenote(共享,见 §6.3)     |
| `keys/editing` / `keys/navigation`                 | 编辑与文本域 | 全局                                  |
| `knowledge/...`                                    | Org 与知识库 | dashboard                             |
| `dashboard/vars` / `banner` / `sections` / `hooks` | dashboard    | 内部                                  |

---

## 6. 特殊处理清单(弱模型易漏)

### 6.1 删除 load-path

`emacs.org` 启动域中:

```elisp
(add-to-list 'load-path
             (expand-file-name "lisp" user-emacs-directory))
```

**整段删除**(含相关分隔注释)。目录删除后该代码有害/误导。

### 6.2 假 feature provide(emacs.org 内联已有)

**必须删除**(无真实 require 消费者,或仅历史残留):

- `(provide 'literal-keys)`(键位辅助函数块)
- `(provide 'literal-which-key)`
- `(provide 'literal-terminal)`
- `(provide 'literal-project)`

可保留文件末尾:

```elisp
(provide 'main)
```

### 6.3 `helpers/call-process` 去重(P8)

**已知问题**:历史上 `literal/knowledge--call-process` 与 `literal/agenote--call-process` 逻辑相同(双横线私有)。

**去重方法**:

1. 在启动域或 Org 域**之前**定义 **一份** noweb 片段:
   - ref 名:`helpers/call-process`
   - 函数名建议统一为:`literal/call-process`(若 bootstrap 已有同名则复用,**不要**定义两份)
2. knowledge / agenote 内所有调用改为该公开名
3. 删除两份 `--call-process` 私有拷贝

**先做探测**:

```bash
rg -n "call-process|defun literal/call-process" emacs.org
```

若有 `literal/call-process` 已存在,只改 call site,勿重复 `defun`。

### 6.4 开篇「启动顺序与模块依赖速查」

整表重写:

- **旧**:加载顺序 × require 的 lisp 文件 × 跨域 require
- **新**:域顺序 × 内含逻辑模块(org 子树名)× **文档顺序依赖**(谁必须写在谁前面)

删除硬 require 叙事;改为「按文档顺序加载」。

### 6.5 静态审计脚本(规则)

> 当前实现位于 `scripts/` 或根;新架构下扫描对象**仅** `emacs.org`(抽出 src)和/或 tangle 后的 `main.el`。

五类检查项:

1. **同名 defun/defvar/defcustom 重复定义**(同名 ≥ 2)— 同名出现 ≥ 2 次即报
2. **`literal/set-key` 悬空绑定** — 注册命令无对应 defun 实现
3. **defvar/defun 声明但全文零引用的疑似死代码** — 零引用 ≠ 死代码(注入点 defvar 后续 setq、命令被键绑定等都算「引用」);逐条人工判定
4. **命名不一致**:
   - 4a. defvar/defun 同名注入点(Lisp-2 共存)— 应已在本规范 §4.4 标注
   - 4b. `literal/xxx`(slash 命名空间,helper/命令)与 `literal-xxx`(dash,模块名)混用 — 新架构下 `literal-xxx` 只应出现在字面量字符串引用(注释/PROVIDE 等),不应有 require/provide/load 形式
5. **tangle 目标一致性**:
   - 5a. 顶层 `#+PROPERTY` 默认 `:tangle main.el`
   - 5b. 块级 `:tangle` 覆写(非默认 main.el 的需核对)— `:tangle no` 或 `:tangle *.el` 均需逐条人工判定
   - 5c. `#+begin_src` 与 `#+end_src` 配对(应相等)

**禁止**:`LISP_DIR=""` 之外重新引入对 `lisp/` 的扫描依赖。

---

## 7. 脚本与命令

仓库根 `scripts/` 下:

| 脚本                    | 用途                                                            | 调用                                        |
| ----------------------- | --------------------------------------------------------------- | ------------------------------------------- |
| `rebuild_org.sh`        | 从 git 历史重放重建 emacs.org                                   | `bash scripts/rebuild_org.sh`               |
| `migrate_inlines.py`    | 把内联配置迁入 emacs.org 域                                     | `python3 scripts/migrate_inlines.py ...`    |
| `reorder_modules.py`    | 按 §3 顺序重排模块                                              | `python3 scripts/reorder_modules.py ...`    |
| `strip_literal_refs.py` | 批量清理 `require/provide 'literal-...` 与 `load-path ... lisp` | `python3 scripts/strip_literal_refs.py ...` |
| `merge_newhead.sh`      | 合并新章节头部(辅助编辑器)                                      | `bash scripts/merge_newhead.sh`             |

**常用命令清单**:

```bash
# 启动
emacs --batch --script var/verify-config.el          # 验收
emacs --batch -L . --eval '(load "main.el" nil t)'   # batch 加载
emacs --batch -l org -l ob-tangle --eval \
  '(org-babel-tangle-file "emacs.org" "main.el" "emacs-lisp")'  # 强制 tangle

# 静态检查
rg -n "require 'literal-|provide 'literal-|lisp/literal-" emacs.org main.el
rg -n ":tangle +lisp/" emacs.org
rg -n "add-to-list 'load-path" emacs.org main.el
test ! -e lisp && echo OK

# git
git status --short
```

---

## 8. 实施前自检(agent 开干前勾选)

- [ ] 已读本文件 §2 设计原则 P1–P10
- [ ] 确认不会改 `init.el` tangle 签名(§1.2)
- [ ] 确认不会使用 `:tangle lisp/`(§4.1)
- [ ] 确认 `lisp/` 不存在(§6.1 删除 load-path)
- [ ] 确认会更新 `var/verify-config.el` 断言(§7 命令)
- [ ] 确认 helpers 去重与文档顺序(§6.3)
- [ ] 已通读 `emacs.org` 顶部「启动顺序与模块依赖速查」(§3)
- [ ] 已计划验收全跑:tangle → batch load → verify-config → 静态检查(§7)

---

## 附录 A — noweb 示例(可直接模仿)

### A.1 小模块整段(frame)

```org
** Frame 生命周期与 daemon
daemon/client 下 per-frame 初始化入口。依赖:无。被 color-scheme / completion / dashboard 等在文档后方调用。

#+begin_src emacs-lisp
(defun literal/add-frame-hook (function)
  ...)
(defun literal/remove-frame-hook (function)
  ...)
;; 注意:不要 (provide 'literal-frame)
#+end_src
```

### A.2 大模块组装(dashboard 示意)

```org
** Dashboard

#+begin_src emacs-lisp :noweb-ref dashboard/vars :tangle no
(defvar literal/dashboard--todo-cache nil)
#+end_src

#+begin_src emacs-lisp :noweb-ref dashboard/banner :tangle no
(defvar literal/dashboard-ascii-banner ...)
#+end_src

#+begin_src emacs-lisp :noweb-ref dashboard/open :tangle no
(defun literal/dashboard-open-for-client-frame ()
  ...)
#+end_src

#+begin_src emacs-lisp
;; dashboard 组装(写入 main.el 的唯一入口)
<<dashboard/vars>>
<<dashboard/banner>>
<<dashboard/open>>
#+end_src
```

### A.3 共享 helper

```org
** 共享进程辅助
#+begin_src emacs-lisp :noweb-ref helpers/call-process :tangle no
(defun literal/call-process (command &rest args)
  "..."
  ...)
#+end_src

#+begin_src emacs-lisp
<<helpers/call-process>>
#+end_src
```

knowledge 组装块中 **不要**再 defun 同名函数;只调用 `literal/call-process`。
