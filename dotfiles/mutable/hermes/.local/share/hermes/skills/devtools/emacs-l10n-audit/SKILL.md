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

```bash
# 静态检查
emacs --batch -Q --script scripts/configctl.el check load test check-strict

# 二次扫描确认无残留
python3 -c "
import re
with open('emacs.org') as f:
    lines = f.readlines()
for i, line in enumerate(lines, 1):
    s = line.strip()
    if s.startswith('#') or s.startswith('#+'): continue
    for m in re.finditer(r'\"([A-Z][a-z]+( [a-z]+){2,})\"', line):
        print(f'L{i}: {m.group(0)}')
"
```

## 翻译数据文件

`data/*.el` 是外置翻译数据，通过 `setq` 赋值给 `custom:...` 变量：

| 文件 | 变量 | 用途 |
|------|------|------|
| `which-key-zh.el` | `custom:which-key-description-spec` | which-key 中文描述 |
| `help-zh.el` | `custom:help-introduction` | 帮助缓冲区介绍 |
| `context-menu-zh.el` | `custom:context-menu-label-translations` | 右键菜单翻译 |

这些文件通常已较完整，审计时对照 UI 实际显示补充缺失条目。

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
