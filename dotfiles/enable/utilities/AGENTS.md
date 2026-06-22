# 开发工具配置

通过 Guix Home 部署到 `~/.config/` 与 `~/.local/`。涵盖编辑器、键盘改键、包管理器、Windows 应用桥接、Rime 输入法、GnuPG 等。

> **修改入口**：所有 `utilities/.config/<app>/` 下的文件改完都必须跑 `blue home`（不需 `blue rebuild`），然后 grep `~/.config/<app>/` 确认软链接到 store 副本。**禁止**直接编辑 `~/.config/<app>/` 已部署位置（store 副本只读，下次 `blue home` 会被覆盖）。

## 目录结构

<!-- structor:begin -->

<!-- 此树形目录由 structor 自动生成，请勿手动编辑。 -->

```
utilities/
├── .config/
│   ├── fcitx5/
│   │   ├── conf/
│   │   │   ├── classicui.conf
│   │   │   ├── keyboard.conf
│   │   │   ├── notifications.conf
│   │   │   ├── rime.conf
│   │   │   └── waylandim.conf
│   │   ├── config
│   │   └── profile
│   ├── git/
│   │   ├── config
│   │   └── gitmessage
│   ├── helix/
│   │   ├── themes/
│   │   │   └── transparent.toml
│   │   ├── config.toml
│   │   └── languages.toml
│   ├── kanata/
│   │   └── kanata.kbd
│   ├── pnpm/
│   │   └── rc
│   └── winapps/
│       ├── compose.yaml
│       └── winapps.conf
├── .local/
│   ├── bin/
│   │   ├── keepassxc-credential-setup
│   │   ├── nixgpu-update
│   │   ├── opencode-update
│   │   └── xdg-bwrap
│   └── share/
│       ├── fcitx5/
│       │   └── rime/
│       │       ├── cn_dicts/
│       │       │   ├── 41448.dict.yaml
│       │       │   ├── 8105.dict.yaml
│       │       │   ├── base.dict.yaml
│       │       │   ├── ext.dict.yaml
│       │       │   ├── others.dict.yaml
│       │       │   └── tencent.dict.yaml
│       │       ├── en_dicts/
│       │       │   ├── cn_en.txt
│       │       │   ├── cn_en_abc.txt
│       │       │   ├── cn_en_double_pinyin.txt
│       │       │   ├── cn_en_flypy.txt
│       │       │   ├── cn_en_jiajia.txt
│       │       │   ├── cn_en_mspy.txt
│       │       │   ├── cn_en_sogou.txt
│       │       │   ├── cn_en_ziguang.txt
│       │       │   ├── en.dict.yaml
│       │       │   └── en_ext.dict.yaml
│       │       ├── lua/
│       │       │   ├── cold_word_drop/
│       │       │   ├── autocap_filter.lua
│       │       │   ├── calc_translator.lua
│       │       │   ├── cn_en_spacer.lua
│       │       │   ├── convert_ar_num_to_zh.lua
│       │       │   ├── corrector.lua
│       │       │   ├── date_translator.lua
│       │       │   ├── debuger.lua
│       │       │   ├── en_spacer.lua
│       │       │   ├── force_gc.lua
│       │       │   ├── is_in_user_dict.lua
│       │       │   ├── long_word_filter.lua
│       │       │   ├── lunar.db
│       │       │   ├── lunar.lua
│       │       │   ├── number_translator.lua
│       │       │   ├── pin_cand_filter.lua
│       │       │   ├── reduce_english_filter.lua
│       │       │   ├── search.lua
│       │       │   ├── select_character.lua
│       │       │   ├── t9_preedit.lua
│       │       │   ├── unicode.lua
│       │       │   ├── uuid.lua
│       │       │   └── v_filter.lua
│       │       ├── opencc/
│       │       │   ├── emoji.json
│       │       │   ├── emoji.txt
│       │       │   └── others.txt
│       │       ├── others/
│       │       │   ├── Hamster/
│       │       │   ├── asserts/
│       │       │   ├── docs/
│       │       │   ├── fcitx4/
│       │       │   ├── iRime/
│       │       │   ├── pages/
│       │       │   ├── recipes/
│       │       │   ├── script/
│       │       │   ├── 双拼补丁示例/
│       │       │   ├── cn_en.txt
│       │       │   └── emoji-map.txt
│       │       ├── .gitignore
│       │       ├── LICENSE
│       │       ├── README.md
│       │       ├── custom_phrase.txt
│       │       ├── default.yaml
│       │       ├── double_pinyin.schema.yaml
│       │       ├── double_pinyin_abc.schema.yaml
│       │       ├── double_pinyin_flypy.schema.yaml
│       │       ├── double_pinyin_jiajia.schema.yaml
│       │       ├── double_pinyin_mspy.schema.yaml
│       │       ├── double_pinyin_sogou.schema.yaml
│       │       ├── double_pinyin_ziguang.schema.yaml
│       │       ├── go.work
│       │       ├── melt_eng.dict.yaml
│       │       ├── melt_eng.schema.yaml
│       │       ├── radical_pinyin.dict.yaml
│       │       ├── radical_pinyin.schema.yaml
│       │       ├── recipe.yaml
│       │       ├── rime_ice.dict.yaml
│       │       ├── rime_ice.schema.yaml
│       │       ├── squirrel.yaml
│       │       ├── symbols_caps_v.yaml
│       │       ├── symbols_v.yaml
│       │       ├── t9.schema.yaml
│       │       └── weasel.yaml
│       └── gnupg/
│           └── gpg-agent.conf
└── .nix-channels
```

<!-- /structor -->

## 核心子系统

> **实现位置**：fcitx5 用户配置 — `utilities/.config/fcitx5/` 由 `dotfile-services`（`home-dotfiles-service-type`）stow 到 `~/.config/fcitx5/`；运行期生成的 `cached_layouts` 与 `crash.log` 在 `dotfile-services` 的 `excluded` 列表里跳过。

### fcitx5 输入法框架

- 路径：`utilities/.config/fcitx5/`（7 个文件：顶层 `config` + `profile`，子目录 `conf/` 5 个 .conf）
- 与 `.local/share/fcitx5/rime/`（Rime 子模块）配套使用，**不要混**——`.config/fcitx5/` 是 fcitx5 行为，`.local/share/fcitx5/rime/` 是 Rime 引擎资产
- `classicui.conf` 关键字段 `ForceWaylandDPI` 在 XWayland 应用上避免候选词被缩成 1.0x（参见修改约束）
- 修改后跑 `blue home` 即可生效，**不**需要 `blue rebuild`

### Rime 输入法

- 路径：`utilities/.local/share/fcitx5/rime/`
- Git 子模块（`github.com/iDvel/rime-ice`）
- 包含双拼方案（flypy、mspy、sogou 等）、词典、Lua 扩展
- **不要直接编辑子模块内容**，除非是 `custom_phrase.txt` 等用户自定义文件
- 子模块更新：进入子模块目录，按上游流程 `git pull` 后在主仓 commit

### Helix 编辑器

- `languages.toml` 定义语言服务器和格式化器
- `themes/transparent.toml` 提供透明背景主题

### Kanata 键盘映射

- `kanata.kbd` 定义键盘层映射，用于改键/宏

### Nix 备份分支（独立使用）

- 仓库根的 `source/nix/` 与本目录的 `.nix-channels` 共同构成一份独立的 Nix home-manager 配置
- 与 Guix 配置并存但**不互通**：走 `blue nix` / `blue nix-init` / `blue nix-update`
- 主要作用是给特定工具（Nix 生态）做隔离验证

## 修改约束

- 改 `utilities/.config/<app>/` 后跑 `blue home` 即可生效（不需 `blue rebuild`）；重启对应服务验证
- Rime 子模块修改需在子模块内单独 commit 并 push 到上游
- Git commit 模板通过 `~/.config/git/gitmessage`（已通过 `git config commit.template` 引用）
- winapps 配置修改后需重建 VM
