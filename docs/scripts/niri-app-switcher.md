<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# niri-app-switcher — niri 统一窗口切换器（rofi -dmenu）

- 源码：`dotfiles/immutable/desktop/.local/bin/niri-app-switcher`
- 部署：`~/.local/bin/niri-app-switcher`（immutable，改后需 `blue home`）
- 调用方：niri 键位绑定（`dotfiles/immutable/desktop/.config/niri/settings/key-bindings.kdl`）

## 用法

```bash
niri-app-switcher    # 呼出 rofi 菜单，选中后聚焦该应用最近聚焦的窗口
```

环境变量（默认即正常使用路径，测试时可改指别处）：

- `NIRI_APP_SWITCHER_CONFIG` — 归组配置（默认 `~/.config/niri/app-switcher.json`）
- `NIRI_APP_SWITCHER_HISTORY` — 使用历史（默认 `~/.cache/niri-app-switcher-history.json`）
- `NIRI_APP_SWITCHER_ROFI_CONFIG` — rofi 主题（默认 `~/.config/rofi/config.rasi`）

## 依赖

`niri msg --json windows`、`jq`、`rofi -dmenu`。

## 工作原理

窗口按「规范应用名」归组：`app_id` 命中配置里某个应用的 `match_app_ids` → 用该配置键名；否则取 `app_id` 末段小写（`org.mozilla.firefox` → `firefox`）。菜单按历史上次使用时间倒序、`rofi -matching prefix -no-custom` 严格前缀匹配；选中后聚焦该应用**最近聚焦**的窗口并把名字写入历史。

流程：读配置与历史（缺失/损坏/空一律回落 `{}`）→ 归组定义（`match_app_ids` 缺省或空数组回退为 `[key]`；同一 `app_id` 被多 key 认领 → stderr 告警不中止）→ `niri msg --json windows` 按 `exclude_titles` 过滤 → 归组 → 历史排序菜单 → rofi 选择 → `niri msg action focus-window --id` + `update_history`。

`--help` **不是纯帮助路径**——会正常启动切换器，`tools.yaml` 的 `help_cmd` 不得为它登记 flag。

## 设计决策与不变量

- **`focus_timestamp` 是 `{secs, nanos}` 对象**：jq 直接 `max_by(.focus_timestamp)` 会先比 nanos 字段序而非数值，须拆成 `[.secs, .nanos]` 数组比较。
- **历史原子更新**：`mktemp` + `mv -f`；旧版历史把时间戳存成字符串，排序时用 `tonumber?` 兼容。
- **rofi 非零退出即取消**：`rofi ... || exit 0`，Esc 正常退出不算错误。
- 历史文件与父目录每次运行确保存在（`mkdir -p` + `printf '{}'`）。

## 故障排查

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| 菜单空的 | 全部窗口被 `exclude_titles` 过滤 / 无窗口 | 属预期，静默退出 |
| 某应用名字不对 | `app_id` 与 `match_app_ids` 不匹配 | 在 `app-switcher.json` 补 match_app_ids（看 `niri msg windows` 的实际 app_id） |
| stderr 报 collision | 同一 app_id 被多 key 认领 | 只告警不中止；整理配置消除冲突 |

## 变更记录

无破坏性改动（本次重构只压缩注释）。
