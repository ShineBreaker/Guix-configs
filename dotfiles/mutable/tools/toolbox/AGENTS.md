# toolbox — 自研工具目录

浏览 / 运行本仓库自研 `.local/bin` 工具的统一入口：fzf 列表 + 详情预览，运行页展示帮助并支持 Tab 补全传参，GUI 侧由 `.desktop` 拉起专用 kitty 窗口。命令与界面细节见 [docs/scripts/toolbox.md](../../../../docs/scripts/toolbox.md)；本篇讲清单的收录标准与维护约定。

## 文件

| 文件                                        | 作用                                           |
| ------------------------------------------- | ---------------------------------------------- |
| `.local/bin/toolbox`                        | 主脚本（bash + yq + fzf）                      |
| `.local/share/toolbox/tools.yaml`           | 清单，单一数据源（mutable 直链，改源即时生效） |
| `.local/share/applications/toolbox.desktop` | GUI 入口：kitty `--class toolbox` 独立窗口     |

## 收录标准（用户拍板 2026-09-15）

只收**自己写了实质逻辑的原创工具**；纯透传 wrapper（hermes / pi / dsh 等把上游 CLI 摆进 PATH 的启动器）不收。登记是 opt-in 的。

清单字段：

- `name / brief / category` 必填；`category ∈ {agents, desktop, utilities, tools}`
- `usage` 用法示例行，运行页与 fzf 预览都会展示
- `args` 空格分隔的子命令与旗标词表，供运行页 Tab 补全（`complete -W`）
- `help_cmd` 白名单：仅当确认该旗标**只打印用法、不触发主逻辑**才填（反例：`niri-app-switcher --help` 会直接启动切换器；`pi --help` 挂起）
- `source` 仓库内相对路径

子命令化工具（`dsh update` / `pi-update` / `hermes desktop` 这类增强逻辑并入主命令的）条目挂**主命令名**下，`usage` 写子命令形态，`args` 含子命令旗标。

## 维护

- 新增原创工具：`tools.yaml` 加一条 → `toolbox check` 对账。check 只对账清单自身健康性；「仓库未登记脚本」是信息级提示（wrapper 预期不登记）。
- `toolbox check` 同时是 `.local/bin` 入口准入规则的执法者，一包一入口、`*-acp` 豁免、`tools.yaml` 登记对账三条都在里面，规则见 `dotfiles/mutable/AGENTS.md`「`.local/bin` 入口准入规则」。
- 脚本经 `readlink -f $0` 自定位仓库，依赖 mutable 直链部署——**勿改为 immutable**（home 单文件 store 会让自定位失效）。部署 `blue stow tools/toolbox`，改源即时生效，无需重建。
