# Org 配置文件

本目录包含 Guix System / Guix Home 的 org-babel 源文件。

## 结构

```
configs/
├── home-config.org      # Home 环境配置（tangle → tmp/home-config.scm）
└── system-config.org    # 系统配置（tangle → tmp/system-config.scm）
```

## Org Noweb 机制

- `#+NAME: ref` 命名代码块
- `<<ref>>` 在其他代码块中引用（**Org Mode 语法，非 Scheme 原生**）
- 由 `emacs --batch org-babel-tangle` 展开为完整 .scm 到 `tmp/`

## 管线流程

```
configs/*.org
    → maak 调用 emacs --batch org-babel-tangle
    → tmp/*.scm
    → guix time-machine --channels=source/channel.lock system/home reconfigure
```

## Agent 专区

每个 org 文件头部有 `Agent 指引` 区域，包含：

- 配置职责边界和修改规则
- dotfiles 管理规则
- 新增应用配置流程
- 决策规则（Home vs System、dotfile vs org）

**修改前必须先阅读对应 org 文件的 Agent 专区。**

## 修改约束

- 不要手动编辑 `tmp/` 中的文件（自动生成）
- 修改后先用 `MAAK_DRY_RUN=1 maak system/home` 验证
- 括号检查：`maak check-system` / `maak check-home`
