---
name: emacs-l10n-audit
description: 审计与汉化 Emacs 配置。触发：用户要求汉化/检查残留英文/audit i18n。
---

# emacs-l10n-audit — Emacs 配置全面汉化审计

> 以用户当前使用的所有包为准，遍历查询插件中的所有文本，系统性地完成汉化工作。

## 核心原则

**只汉化用户可见的 UI 文本，不碰技术标识符。** Org 关键字、键位、命令名、模式名、正则、Org 属性名等保持原样——翻译它们会破坏功能或违背社区惯例。

## 工作流

### 1. 扫描全包清单

```bash
# 提取所有 use-package 声明
grep -n '^\s*(use-package\s' emacs.org
```

对每个包，定位其 `use-package` 块内的 `:custom`、`:config`、`:init`、`:mode`、`:hook`、`:bind` 等 section。

### 2. 提取用户可见字符串

用 `search_files` 定位以下模式（过滤注释行 `# ` / `#+`）：

| 模式 | 含义 |
|------|------|
| `message "..."` | 回显区/日志提示 |
| `user-error "..."` | 用户错误提示 |
| `help-echo "..."` | 工具提示 |
| `format "..."` | 含英文的格式字符串 |
| `mode-line-format` | mode-line 模板 |
| `defcustom :documentation "..."` | 自定义变量文档 |
| `defvar "..."` | 变量 docstring |
| `which-key` 描述 | 键位中文描述 |

### 2a. 扫描 which-key 缺口（关键步骤）

which-key 汉化有两层来源，**必须分别审计**：

**第一层：`custom/bind` 声明的键位** — 走 `emacs.org` 里的 `custom/bind` / `custom/bind-local`，描述自动注册。审计时提取所有 `custom/bind` 调用的 `(key, description)` 对，与 `which-key-zh.el` 全局 section 的展开结果交叉比对。

**第二层：第三方/内置 keymap 的原生绑定** — Org-mode、markdown-mode 等自带的 `C-c C-n`、`C-c C-*` 等**不走 `custom/bind`**，显示原始命令名。必须手动在 `which-key-zh.el` 的 major-mode section 中覆盖。Magit、yasnippet 等插件注入到其他 mode keymap 的绑定（如 org-mode 下的 `M-g` → magit-file-dispatch）也属此类。

**系统扫描方法（推荐，比手动截图更可靠）**：

1. 从运行中的 Emacs dump keymap（`scripts/dump-keymaps.el`）：

```bash
cd ~/.config/emacs
emacs --batch -Q \
  --eval '(progn (setq user-emacs-directory default-directory) \
                 (load (expand-file-name "init.el")))' \
  -l ~/.local/share/hermes/skills/devtools/emacs-l10n-audit/scripts/dump-keymaps.el \
  > /tmp/keymap-dump.txt
```

2. 用 `references/compare-keymap-dump.py` 自动比对 dump 与 `which-key-zh.el`：

```bash
python3 ~/.local/share/hermes/skills/devtools/emacs-l10n-audit/references/compare-keymap-dump.py /tmp/keymap-dump.txt
```

3. 逐 mode 审查输出中的 `missing` 列表，决定哪些需要翻译。

**注意事项**：
- batch 模式下 lazy-load 的包（markdown-mode、rust-mode 等）可能未被 require，导致 keymap 变量不存在（dump 返回 `NOT_FOUND`）。需要手动 `(require 'markdown)` 或在运行的 GUI Emacs 中用 `describe-mode` + `C-h m` 检查。
- 重点排查 `outline-*`、`org-*` 前缀的命令名——它们是 Org 自带 keymap 的典型未覆盖项。
- dump 脚本会过滤 `menu-bar`、`mouse`、`<remap>` 和数字前缀，只保留 which-key 实际会显示的条目。

### 3. 分类决策树

```
英文字符串
├─ 是技术标识符？
│   ├─ 键位序列 (C-x C-f, M-g n)         → 不翻译
│   ├─ 命令/模式/函数名 (find-file, org-mode) → 不翻译
│   ├─ 正则/路径/变量名                   → 不翻译
│   ├─ Org 关键字 (TODO, DONE, SCHEDULED)  → 不翻译
│   ├─ Org 属性名 (:PROPERTIES:, :ID:)     → 不翻译
│   ├─ 缓冲区名 (*Messages*, *dashboard*)   → 不翻译
│   └─ custom: 路径 / nerd icon / org- 前缀 → 不翻译
├─ 是 UI 状态/错误/提示？
│   ├─ VC 状态 (clean/edited/unsaved)      → 翻译
│   ├─ 诊断格式 (E:%d W:%d)                → 翻译
│   ├─ Dashboard 错误/提示                 → 翻译
│   ├─ 用户错误 (user-error)               → 翻译
│   ├─ 工具提示 (help-echo)                → 翻译
│   └─ 混合格式 ("Emacs %s · 启动 %s")     → 翻译
└─ 是 docstring？
    ├─ 面向开发者的 defvar/const 文档      → 不翻译
    └─ 面向用户的 :documentation            → 可选翻译
```

### 4. 批量汉化

用 `patch` 工具逐条替换。优先处理高频用户可见文本：

- **Mode-line VC 状态**：clean→已同步, edited→已编辑, unsaved→未保存, added→已添加, removed→已删除, missing→缺失, conflict→冲突, merge→合并, update→更新, ignored→已忽略, untracked→未跟踪
- **诊断格式**：`E:%d W:%d` → `错:%d 警:%d`
- **Dashboard 错误**：agenote process failed→agenote 进程失败, agenote executable not found→未找到 agenote 可执⾏文件
- **调试消息**：knowledge refresh failed→知识库刷新失败, cache warmup failed→缓存预热失败
- **功能提示**：feature not found→未找到 feature

### 5. 验收

**⚠️ configctl 脚本必须从 emacs 配置根目录运行，不能 cd 到 data/ 下**——否则 `--script scripts/configctl.el` 路径会解析到 `data/scripts/` 导致 `load-file` 找不到文件。

```bash
# ✅ 正确：从配置根目录运行
cd ~/.config/emacs
emacs --batch -Q --script scripts/configctl.el check load test check-strict

# ❌ 错误：从 data/ 目录运行（configctl 路径解析失败）
cd ~/.config/emacs/data
emacs --batch -Q --script ../scripts/configctl.el check  # 路径断裂
```

二次扫描确认无残留：

```python
import re
with open('emacs.org') as f:
    lines = f.readlines()
for i, line in enumerate(lines, 1):
    s = line.strip()
    if s.startswith('#') or s.startswith('#+'): continue
    for m in re.finditer(r'\"([A-Z][a-z]+( [a-z]+){2,})\"', line):
        print(f'L{i}: {m.group(0)}')
```

#### which-key 缺口验证

用 Emacs batch 模式加载数据文件，自动比对 `custom/bind` 声明与数据文件覆盖情况：

```bash
# 1. 提取所有 custom/bind 的 (key . description) 对
# 2. 解析 which-key-zh.el 的嵌套树为完整键路径 (如 "C-c g s")
# 3. 交叉比对找出缺失项
# 详见 references/which-key-gap-scan.py
```

### 6. ⚠️ 编辑 `.el` 文件时的 patch 转义陷阱

使用 `patch` 工具编辑含 `\\`（反斜杠转义）的 `.el` 数据文件时，`old_string` / `new_string` 中的 `\\` 会被**双重转义**为 `\\\\`。例如 `("\\"` 在 patch 后可能变成 `("\\\\"`，导致字符串语义从「一个反斜杠」变成「两个反斜杠」。

**防范**：patch 后用 `read_file` 读取修改区域确认，或用 `emacs --batch -Q --eval '(check-parens)'` 验证语法。

## 翻译数据文件

`data/*.el` 是外置翻译数据，通过 `setq` 赋值给 `custom:...` 变量：

| 文件 | 变量 | 用途 |
|------|------|------|
| `which-key-zh.el` | `custom:which-key-description-spec` | which-key 中文描述 |
| `help-zh.el` | `custom:help-introduction` | 帮助缓冲区介绍 |
| `context-menu-zh.el` | `custom:context-menu-label-translations` | 右键菜单翻译 |

这些文件通常已较完整，审计时对照 UI 实际显示补充缺失条目。

#### which-key 数据文件结构

```elisp
;; 全局描述（C-x / C-c / M-g 等前缀）
(setq custom:which-key-description-spec
      '(("C-x" "文件/缓冲区/窗口/标签"
         ;; 子前缀用 ("key" "组名" (...))，叶子用 ("key" . "描述")
         ("C-c" "命令" ...)
         ("C-x C-f" . "打开文件"))
        ...))

;; major-mode 局部描述
(setq custom:which-key-major-mode-description-spec
      '((org-mode
         ;; C-c 前缀下的 Org 原生绑定（C-c C-n 等，不走 custom/bind）
         ("C-c" "Org"
          ("C-n" . "下一个标题")  ;; ← outline-next-visible-heading
          ...)
         ;; 非 C-c 的顶层键必须放在 C-c 子树外层
         ("<down>" . "时间/优先级下移")
         ("M-g" . "Magit 文件分发"))
        (markdown-mode ...)
        ...))
```

数据文件在 `with-eval-after-load 'which-key` 时由 `custom/which-key-apply-descriptions` 自动展开并通过 `which-key-add-key-based-replacements` / `which-key-add-major-mode-key-based-replacements` 注册。

#### ⚠️ 结构陷阱：裸键不能放在前缀子树内

`("down" . "减少优先级")` 如果写在 `("C-c" "Org" ...)` 子树内部，会被展开成 `C-c down` 而非裸 `<down>`。裸方向键、`M-g` 等非前缀键**必须**放在 `(org-mode ...)` 下的 C-c 子树之外：

```elisp
(org-mode
 ("C-c" "Org" ...)      ;; ← C-c 子树在这里结束
 ("<down>" . "...")     ;; ← 正确：org-mode 的顶层裸键
 ("M-g" . "..."))       ;; ← 正确：Magit 注入的顶层键
```

## 反模式

- ❌ **翻译 Org 关键字** — `TODO` / `DONE` / `SCHEDULED` 是 Org 语法，翻译后 Org 无法识别
- ❌ **翻译键位描述** — `C-x C-f` 等是固定表示法
- ❌ **翻译命令/模式名** — `find-file` / `org-mode` 是符号名，用户已熟悉
- ❌ **翻译正则/路径** — 技术实现细节
- ❌ **翻译 docstring** — 面向开发者，保持英文是社区惯例
- ❌ **翻译 capture 模板中的 Org 结构** — `:PROPERTIES:` / `:CREATED:` 是 Org 文件格式要求

## 与本 skill 配合

- `emacs-config` — 配置与重构的最佳范式（加载后参考其架构契约）
- `guix-configs-workflow` — Guix-configs 仓库工作流（部署验证流程）
- `agenote-base` — 任务结束后记录经验卡片

## 参考文件

- `references/vc-state-translations.md` — mode-line VC 状态 / 诊断格式 / Dashboard 错误翻译映射表
- `references/which-key-gap-scan.py` — 扫描 **`custom/bind` 声明**与 `which-key-zh.el` 数据文件之间缺口的脚本（第一层：自定义键位）
- `references/compare-keymap-dump.py` — 比对 **keymap dump** 与 `which-key-zh.el`，找出第三方 keymap 原生绑定的未翻译条目（第二层：内置/第三方 keymap）
- `scripts/dump-keymaps.el` — 从运行中的 Emacs dump 各 major-mode keymap 的全部绑定
