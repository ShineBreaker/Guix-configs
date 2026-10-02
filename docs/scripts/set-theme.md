<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# set-theme.sh — darkman 模板渲染器（`$$VAR$$` → 模式变量组）

`dotfiles/immutable/noctalia-suite/.config/darkman/script/set-theme.sh` · immutable → `~/.config/darkman/script/set-theme.sh`（改后须 `blue home`） · `~/.local/libexec/theme-common.sh`（由 darkman mode.d hook 触发）

按 `script_dir/config.json` 中选定模式的变量组，把模板树里所有 `$$KEY$$` 占位符渲染后写入 `~/.config/` 下的对应相对路径。

## 用法

```bash
set-theme.sh <light|dark>
```

参数不是 1 个或不是 `light`/`dark` → usage + `exit 1`；`jq` 缺失 → `Error: jq is required but not found in PATH.` + `exit 1`。

## 输入输出

| 角色         | 位置                                                                              |
| ------------ | --------------------------------------------------------------------------------- |
| 变量组       | `$script_dir/config.json` 的 `.dark` / `.light`（`.colors` 子表会展平进顶层后删除） |
| 模板树       | `~/.config/darkman/config/` 下的所有文件与符号链接（`find -type f -o -type l`）      |
| 输出         | `~/.config/<rel>`                                                                  |

- 固定注入两个变量：`mode`（当前模式）与 `home`（`$HOME`），模板可直接写 `$$mode$$` / `$$home$$`。
- 输出**先 `rm -f` 再写**（目标可能是 store 软链或只读副本），随后 `chmod --reference="$src"` 保权限。
- 模板树目录不存在 → `Error: template directory not found: …` + `exit 1`。

## 设计决策与不变量

- **越界写防护**：渲染目标 `dst` 先经 `realpath -m` 解析，再校验解析结果必须落在 `$HOME` 之内，否则 `Error: destination escapes $HOME, aborting: …` + `exit 1`。模板文件名可携带 `..` 或经符号链接越界，这一步是必须的。
- **未定义占位符 fail-fast**：渲染前用 `grep -oE '\$\$[A-Za-z0-9_-]+\$\$'` 扫出模板里的全部占位符，逐一比对变量组，出现未声明的立即报错 `exit 1`——宁可留空文件，不留半渲染态。
- **先删后写**：目标可能是 store 软链或只读副本，`rm -f` 后重建才写得进去。
- **sed 脚本双重转义**：key 转 regex 元字符（`[][(){}.^$*+?|\\-`），value 转 `|&\`——`|` 是自定义分隔符，必须转义。整份脚本由 `mktemp` 生成并用 `trap … EXIT` 清理。
- 配置与模板目录缺失也 fail-fast，不静默跳过。

## 故障排查

- `Error: no variables resolved for mode "X"` → `config.json` 缺该模式键，或该模式的变量组为空。
- `Error: undefined placeholder "…"` → 模板用了未声明的变量，补 `config.json` 的键或改模板。