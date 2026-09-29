<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# git-resign — 重签名 base..HEAD 全部提交

- 源码：`dotfiles/immutable/terminal/.config/fish/functions/git-resign.fish`
- 部署：`~/.config/fish/functions/git-resign.fish`（immutable，改后需 `blue home`）
- 调用方：手动调用；补全 `completions/git-resign.fish`

## 用法

```bash
git-resign <base-ref>   # 等价于 git rebase --exec 'git commit --amend --no-edit -S' <base-ref>
git-resign HEAD~3       # 重签最近 3 个提交
git-resign 43d43e4~1    # 重签 43d43e4 起（含）之后的所有提交
```

参数个数 != 1 时打印用法并 `return 1`。rebase 成功后打印 `git log --format='%h %G? %s'` 核验提示（`%G?` 显示 `G` 即签名有效），退出码透传 rebase 结果。

## 依赖

`git`（须在仓库内；GPG/SSH 签名须已配置）。

## 设计决策与不变量

- 本质是交互式 rebase 的 `--exec` 逐提交 `commit --amend -S`，冲突时由 git 自身处理。
- 函数名含连字符，completion 注册名同为 `git-resign`。

## 变更记录

- 2026-09-29：注释压缩、`fish_indent` 规范化（行为不变）。
