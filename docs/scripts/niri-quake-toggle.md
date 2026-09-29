<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# niri-quake-toggle — quick-access 下拉面板呼出/收起

- 源码：`dotfiles/immutable/desktop/.local/bin/niri-quake-toggle`
- 部署：`~/.local/bin/niri-quake-toggle`（immutable，改后需 `blue home`）
- 调用方：niri 键位绑定 Mod+grave（`key-bindings.kdl`）

## 用法

```bash
niri-quake-toggle    # 呼出/收起 kitty quick-access-terminal 面板
```

## 依赖

`kitten`（kitty 遥控器）、`/proc/net/unix`（socket 发现）。

## 工作原理

呼出瞬间以会话身份对面板做一次 `load-config` 刷新主题：**darkman hook 切主题时对面板的刷新不可靠**——darkman 后代身份的 RC 写被 kitty 忽略，hidden 态重载还会延迟。面板未运行时无 socket，直接跳过，不阻塞主流程。

socket 发现：`awk` 扫 `/proc/net/unix` 找 `quick-access-` 后缀的 kitty 控制 socket；找到且 `kitten` 可用时 `kitten @ --to unix:$sock load-config`（静默容错），最后 `exec kitten quick-access-terminal "$@"`。

## 设计决策与不变量

- **`exec` 收尾**：脚本即薄壳，进程替换为面板本体，信号与退出码直透。
- load-config 失败不阻断呼出（`|| true`）。

## 变更记录

无破坏性改动（本次重构只压缩注释）。
