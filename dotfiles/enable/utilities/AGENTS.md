# 开发工具配置

通过 Guix Home 部署到 `~/.config/` 和 `~/.local/`。

## 结构

```
utilities/.config/
├── git/                 # Git
│   ├── config           # Git 配置
│   └── gitmessage       # Commit 消息模板
├── helix/               # Helix 编辑器
│   ├── config.toml
│   ├── languages.toml
│   └── themes/
│       └── transparent.toml
├── kanata/              # 键盘映射
│   └── kanata.kbd
├── pnpm/                # pnpm 包管理器
│   └── rc
└── winapps/             # Windows 应用集成
    ├── compose.yaml
    └── winapps.conf

utilities/.local/
├── bin/
│   └── opencode-update  # OpenCode 更新脚本
└── share/
    ├── fcitx5/rime/     # ★ Rime 输入法（子模块 → github.com/iDvel/rime-ice）
    └── gnupg/
        └── gpg-agent.conf
```

## 核心子系统

### Rime 输入法

- Git 子模块，实际代码在 `github.com/iDvel/rime-ice`
- 包含双拼方案（flypy、mspy、sogou 等）、词典、Lua 扩展
- **不要直接编辑子模块内容**，除非是 `custom_phrase.txt` 等用户自定义文件

### Helix 编辑器

- 使用 `transparent.toml` 透明主题
- `languages.toml` 定义语言服务器和格式化器

### Kanata 键盘映射

- `kanata.kbd` 定义键盘层映射，用于改键/宏

## 修改约束

- Rime 子模块修改需单独 commit 并 push 到上游
- Git commit 模板通过 `git config commit.template` 引用
- winapps 配置修改后需重建 VM
