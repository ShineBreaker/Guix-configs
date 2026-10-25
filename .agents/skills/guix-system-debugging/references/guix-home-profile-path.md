# Guix Home profile PATH 漂移

**现象**：Guix Home 容器内 `git: command not found` / `guix: command not found`，但宿主正常

**根因**：`~/.guix-home/profile` 是 symlink 到 `/gnu/store/<hash>-profile`，每次 `guix home reconfigure` 生成新 hash。旧 store 目录残留，`$PATH` 仍指向旧 hash 时新 profile 的二进制不在旧路径。

**取证**：

```bash
ls -l ~/.guix-home/profile                  # 看 symlink 指向的 hash
ls /gnu/store/*-profile/bin/git 2>/dev/null | head  # 找存活 profile（~4 个并存常见）
/gnu/store/<alive>-profile/bin/git --version  # 绝对路径验证
echo $PATH | tr : '\n' | grep guix-home
```

**修复**：

```bash
# 临时
export PATH="/gnu/store/<alive>-profile/bin:$PATH"
# 或绝对路径
/GNU/STORE/<alive>-profile/bin/git -C ~/Documents/Org status --short
```

**策展实战**（2026-08-30）：`agenote health` 时 `git` 不在 `~/.guix-home/profile/bin`，实为 profile hash 已变（`3zz...` vs `3j6...`），用 `ls /gnu/store/*-profile/bin/git` 定位存活 profile 后 `export PATH` 解决。`agenote commit` 内部 `git` 依赖 `$PATH`，需先保证 PATH 正确。

**预防**：`blue home` 后重开 shell 或 `hash -r`；脚本中用 `command -v git || ls /gnu/store/*-profile/bin/git | head -1` 兜底
