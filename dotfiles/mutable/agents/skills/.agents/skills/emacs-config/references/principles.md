# 五大核心原则(doomemacs / spacemacs 提炼)

> doomemacs(1125 文件 / 62k 行)+ spacemacs(1318 文件 / 91k 行)逐文件剖析提炼。
> 每个原则都有真实源码佐证(doom 早期优化 / spacemacs layer 体系)。
> 所有"应该这样做"都给出文件路径+行号。

> 这些原则不是抽象口号,每个都能在 doom 或 spacemacs 的真实代码里找到佐证。

## 原则 1: **early-init.el 才是真正的主入口**

> "early-init.el was introduced in Emacs 27.1. It is loaded before init.el, before Emacs initializes its UI or package.el, and before site files are loaded. This is great place for startup optimizing, because only here can you _prevent_ things from loading, rather than turn them off after-the-fact." — doom early-init.el L14-22

`early-init.el` 是在 `init.el` 之前加载的,在这阶段:

- GC 阈值可以推迟到最大
- `file-name-handler-alist` 可以暂时清空
- `package-enable-at-startup` 可以关掉
- `load-prefer-newer` 可以关掉
- UI 元素可以预先关掉

**这是只此一次的优化窗口**,在 `init.el` 里做同样的事已经晚了一拍。

→ 详见 `references/A-startup-and-packages.md` §2

## 原则 2: **不要让 Emacs 在启动期"知道"任何不需要立即用的包**

范式: `use-package` 的 lazy-load(详细见 `references/A-startup-and-packages.md` §4):

| 触发关键字             | 何时加载                                                    |
| ---------------------- | ----------------------------------------------------------- |
| `:defer t`             | 第一次访问命令/变量时                                       |
| `:hook '<mode>-hook`   | 第一次进入该 mode 时                                        |
| `:mode "\\.ext\\'"`    | 第一次打开该扩展名文件时                                    |
| `:magic "\\=\\(#!\\)"` | 第一次打开文件首行匹配 regex 时                             |
| `:bind "C-c x"`        | 用户第一次按该键时                                          |
| `:commands <cmd>`      | 用户第一次 M-x 调用时                                       |
| `:init` vs `:config`   | `:init` 包加载时执行(就废了);`:config` 包加载后执行(才生效) |

**反模式**: 在 `:init` 块里写 `(magit-mode 1)` —— 这意味着包在 `init.el` 阶段就被强制加载,所有 lazy-load 都白做。

→ 详见 `references/A-startup-and-packages.md` §4

## 原则 3: **用"等待时机"代替"全部加载"**

doom 的范式创新:`doom-first-input-hook`、`doom-first-file-hook`、`doom-first-buffer-hook` 三个 hook —— 名字直白,意思是"等用户首次按键/首次打开文件/首次打开 buffer 时再启用"。

**典型用法**: which-key / vertico / company / modeline 都挂在 `doom-first-input` 上 —— 让 Emacs 启动到能编辑的最小状态,等到用户首次按键再启用所有"补全/提示"功能。

→ 详见 `references/A-startup-and-packages.md` §5

## 原则 4: **用 macro 把范式固化下来,让用户写起来像 DSL**

两个框架都做了这件事:

- doom: `package!`、`use-package!`、`map!`、`set-popup-rule!`、`add-load-path!`、`def-modeline-segment!`、`custom-set-faces!`、`set-company-backend!`、`after!`、`modulep!`、`defun!`、`defadvice!`、`cmd!`、`lambda!`、`str!`、`add-hook!`
- spacemacs: `spacemacs/declare-prefix`、`spacemacs/set-leader-keys`、`configuration-layer/declare-layer`

**意义**: 用户面对的是一个 DSL,而不是 200 个包的零散 API。配置文件的"形状"是稳定的,即使内部包换了。

**对自己的启发**: 当你的 init.el 超过 200 行时,开始考虑封装自己的宏 —— 把 `with-eval-after-load` + `setq` + `bind-key` 的组合包成 `setup-X!`,让配置长得像用 DSL。

→ 详见 `references/D-modules-and-architecture.md` §6

## 原则 5: **把"包"组织成"功能单元",而非按字母排序的清单**

```
❌ 错误组织 (按字母):
  packages.el ─┬─ agenda
               ├─ company
               ├─ counsel
               ├─ dap-mode
               ├─ direnv
               ├─ eglot
               ├─ evil
               ├─ ...

✅ 正确组织 (按功能单元):
  modules/
  ├─ ui/        ─┬─ completion/   ─── vertico
  │              ├─ workspaces/   ─── persp-mode
  │              ├─ modeline/     ─── doom-modeline
  │              └─ zen/          ─── writeroom
  ├─ editor/    ─┬─ evil/
  │              └─ snippets/
  ├─ tools/     ─┬─ magit/
  │              ├─ lsp/
  │              └─ tree-sitter/
  ├─ lang/      ─┬─ python/
  │              ├─ rust/
  │              └─ web/
  └─ term/      ─┬─ vterm/
                 └─ eshell/
```

doom 的 `modules/<category>/<module>/` 双层目录就是这一原则的工程化体现。

→ 详见 `references/D-modules-and-architecture.md` §4
