<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# sarasa-ttf-extract — 从 Sarasa TTC 提取 Gothic SC 单文件 TTF

`tools/sarasa-ttf-extract.py` · 不部署（手动运行） · 维护者执行 · 依赖 fontTools

## 用法

```
guix shell python-fonttools -- python3 tools/sarasa-ttf-extract.py
```

脚本从 `/run/current-system/profile/share/fonts/truetype/Sarasa-*.ttc` 提取全部 `Sarasa Gothic SC` 子字体，写入 `~/.local/share/fonts/SarasaGothicSC-*.ttf`，末尾执行 `fc-cache -f ~/.local/share/fonts`。升级 `font-sarasa-gothic` 后重跑一次；重复执行安全（幂等覆盖）。

## 实现与约束

### 为什么需要单 TTF

Chromium 150（Electron 43.8.4）对 generic family（sans-serif、serif、monospace）的 fontconfig 匹配结果拒绝采用 TTC 文件：命中 TTC 时不报错，静默 fallback 到后续 sans 候选。`source/config.org` 的 `font-services` 块把 sans-serif 与 serif 的首选设为 Sarasa Gothic SC，而 Guix 的 `font-sarasa-gothic` 只发布 TTC（10 个文件，每文件 48 个子字体），Electron 150 应用的界面拉丁字母因此渲染成等宽的 Iosevka Nerd Font，中文正常。同机 Chromium 156 与 `fc-match` 不受影响；点名家族（`font-family: "Sarasa Gothic SC"`）、alias 指向单 TTF、lang=zh 的中文逐字回退路径同样不受影响，问题只在 generic 路径的首选匹配。

### 提取范围与命名

TTC 内家族名以 `Sarasa Gothic SC` 开头的子字体全部提取，共 10 个文件。Light、SemiBold、XLight 系列把字重写进家族名（如 `Sarasa Gothic SC SemiBold`），italic 信息在 subfamily（`Italic`）。文件名取「家族后缀 + subfamily」并去空格：`SarasaGothicSC-Regular.ttf`、`SarasaGothicSC-SemiBold.ttf`、`SarasaGothicSC-LightItalic.ttf`。单文件 42 至 46 MiB（`glyf` 表约 41.6 MiB，numGlyphs 48694 是 TTC 共享字形池展开后的全量，cmap 覆盖 46231 个码位），十件合计约 440 MiB。

### 为什么不动 fontconfig 配置

fontconfig 对同家族的多文件候选按目录扫描顺序排序，`~/.local/share/fonts` 在 `font-services` 的 dir 列表中先于系统 profile，提取出的 TTF 稳定胜出。实测 generic 与点名查询、lang=en 与 lang=zh-cn、regular 到 semibold 的全部字重都返回单 TTF，因此 `config.org` 的字体偏好（sans-serif 与 serif 首选 Sarasa Gothic SC，monospace 首选 Maple Mono NF CN）无需改动。

Sarasa Mono SC 不提取：monospace 首选 Maple Mono NF CN 已是单 TTF，Chromium 150 的 monospace generic 路径不经过 TTC；Sarasa Mono SC 保留 TTC 形态，继续作不禁用 TTC 的应用的兜底。

### 维护边界

`~/.local/share/fonts` 是手管字体区，Guix Home 既不清理也不部署它，提取物因此不入 git，源变体由本脚本再生产。Guix 升级 `font-sarasa-gothic` 后 TTC 内容更新，须重跑本脚本，否则应用继续匹配旧的单 TTF。

## 验证

生效判据（`fc-match` 输出首列应为文件列）：

```
fc-match sans-serif                # SarasaGothicSC-Regular.ttf
fc-match sans-serif:lang=zh-cn     # SarasaGothicSC-Regular.ttf
fc-match serif                     # SarasaGothicSC-Regular.ttf
fc-match monospace                 # MapleMono-NF-CN-Regular.ttf（不变）
```

另以 Qoder（qoder-cn 0.5.6，Electron 43.8.4）实跑截图核对：界面拉丁字母为比例字形，中文渲染正常。

## 排障

`fc-match "Sarasa Gothic SC"` 仍返回 `.ttc` 时按序检查：提取物是否在 `~/.local/share/fonts/`；`fc-cache -f ~/.local/share/fonts` 是否执行过；`fc-list SarasaGothicSC-Regular.ttf` 是否注册成功。目录顺序由 `config.org` 的 `font-services` 块决定，若该块调整 dir 顺序使系统 profile 先于 `~/.local/share/fonts`，同家族排序可能翻回 TTC。
