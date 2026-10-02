<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# 加密入仓配置管理 — age 密文随仓库分发

把个人凭证、API token、SSH 私钥等敏感信息**加密后**随仓库版本控制分发，明文只在本机的 tmpfs 里短暂出现，任何 push 出去的字节都是 `.age` 密文。本文档讲 `secrets` 命令怎么用与它的安全边界。

## 前置

选 age 而非 sops / gpg / pass：age 是单一二进制、无配置、无密钥服务器、无 GPG 信任网，X25519 + ChaCha20-Poly1305 对任意格式的凭证直接整文件加密；本仓库的密文形态多样（纯文本 / 二进制 / JSON），键级加密反而不直接。未来若确有键级加密需求再考虑迁移 sops。

四层资产的边界：

| 层 | 路径 | 进 git | 出现在 `~` | 权限 |
| --- | --- | --- | --- | --- |
| 密文 | `dotfiles/mutable/tools/secrets/.local/share/secrets-encrypted/<name>.age` | ✓ | ✗（Stow 排除） | 644 |
| 公钥 | `dotfiles/mutable/tools/secrets/.local/share/keys/age.pub` | ✓ | ✓ | 644 |
| 私钥 | `dotfiles/mutable/tools/secrets/.local/share/keys/age`（软链到 `~/.local/share/keys/age`） | ✗ | ✓ | 600 |
| 明文 | `$XDG_RUNTIME_DIR/secrets-decrypted/<name>`（tmpfs，重启即消） | ✗ | ✗ | 600 |

整个仓库 push 到 origin 的字节里，**没有**任何明文，也没有解密所需的私钥。

部署边界：`secrets` 是 `dotfiles/mutable/` 下的 GNU Stow 包，**不**加入 Guix Home 的 `dotfile-services.packages`。Stow 只部署公钥、私钥与 `.local/bin/secrets` 命令本体，`.stow-local-ignore` 明确排除 `secrets-encrypted/`，所以密文只留在仓库源里。运行时解密落地在 `$XDG_RUNTIME_DIR/secrets-decrypted/`（通常 `/run/user/$UID/`），tmpfs 内存文件系统，不进 git、重启即消，应用自己从那里读，`secrets clean` 可手动清空。同目录的 `keys/.gitignore` 精确忽略私钥 `age`。

## 操作

### 1. 全新部署

首次 `init` 时（`init` 检测到已有私钥会拒绝覆盖，必须先 trash）：

```bash
cd <仓库根目录>  # Guix-configs 位置任意，脚本经软链自定位
secrets init                          # 生成密钥对到 .local/share/keys/（age + age.pub）
blue stow tools/secrets               # 建软链 ~/.local/share/keys/age + ~/.local/bin/secrets
secrets list                          # 验证一切就绪
```

`init` 会先确认 `keys/age` 确实在 git 的忽略范围内（失配则拒绝生成，防私钥入库），再调 `age-keygen` 生成 X25519 密钥对、私钥落盘 600、从私钥首行注释提取公钥写 `age.pub`（644），最后提示下一步。`secrets` 需要 PATH 里有 `age`（Guix 环境里装 `age` 包即可）。

### 2. 添加新密文

```bash
echo 'token = "..."' > /tmp/example.toml
secrets encrypt example < /tmp/example.toml
secrets decrypt example --stdout      # 回圆验证
trash /tmp/example.toml

git add dotfiles/mutable/tools/secrets/.local/share/secrets-encrypted/example.age
git commit -S -m "feat(secrets): add example.age"
git push
```

`secrets add <name>` 可直接开编辑器新建（等于 `edit` 的空模板起手）；演练预览用 `secrets --dry-run encrypt example < /tmp/x.toml`，只打印 `[dry-run] ...` 计划、不写 `.age`。

### 3. 修改已有密文

```bash
$EDITOR your-favorite
secrets edit example       # 解密（内存临时目录）→ 编辑 → 重加密
```

`KEY="value"` 型条目也可不开编辑器单字段改：`secrets set example KEY "value"`，取值 `secrets get example KEY`，导出环境变量 `eval "$(secrets env example)"`。

### 4. 应用加载

```bash
# 方式 1：eval 输出 export 行（不落盘）
eval "$(secrets env dotenv)"

# 方式 2：文件加载（tmpfs）
secrets decrypt dotenv      # 落 $XDG_RUNTIME_DIR/secrets-decrypted/dotenv
source "$XDG_RUNTIME_DIR/secrets-decrypted/dotenv"
```

`show` 是 `decrypt --stdout` 的别名，等价于打印到 stdout。

### 5. 子命令速览

运行 `secrets`（无参数）弹出 fzf 交互菜单；`secrets --help` 看完整清单。除常规 encrypt/decrypt/edit 外，另有 `clip`（剪贴板 + 到时自清，默认 45 秒）、`get`/`set`/`env`（字段级操作）、`rename`/`remove`/`clean`（条目与缓存管理）、`recipients`（列出公钥）、`re-encrypt`（轮换，见下）。

### 6. 跨机部署

新机拉取仓库后只需要：

```bash
cd <仓库根目录>  # Guix-configs 位置任意，脚本经软链自定位
blue stow tools/secrets             # 建 ~/.local/share/keys/age 软链 + secrets 命令
secrets list                        # 验证公钥已就位
secrets decrypt example             # 应能解密回明文
```

私钥需要**手动迁移**：

```bash
# 旧机
scp dotfiles/mutable/tools/secrets/.local/share/keys/age user@newhost:~/.local/share/keys/age

# 新机
chmod 600 ~/.local/share/keys/age
secrets list                        # 应看到私钥已就位
```

也可以用物理介质或 `gpg --symmetric` 中转，具体看威胁模型。

## 关键约束

**密钥轮换**：密钥丢失或泄漏后必须立即轮换。核心原则是**旧私钥必须保留到 re-encrypt 完成之后**才能销毁——否则无法解密旧密文，密文永久丢失。

```bash
# 1. 备份旧私钥（重加密期间需要它解密旧密文，不能先删）
cp dotfiles/mutable/tools/secrets/.local/share/keys/age /tmp/age.old
chmod 600 /tmp/age.old

# 2. trash 旧私钥，生成新密钥对（init 检测到旧 age 会拒绝，必须先 trash）
trash dotfiles/mutable/tools/secrets/.local/share/keys/age
secrets init                        # 生成新 age + 覆盖 age.pub
blue stow tools/secrets --restow    # 重建 ~/.local/share/keys/age 软链指向新私钥

# 3. 用旧私钥解密所有旧密文 + 新公钥重加密
secrets re-encrypt --with /tmp/age.old

# 4. 演练预览（可选）：再跑一次 dry-run 确认无残留旧密文需要处理
secrets --dry-run re-encrypt --with /tmp/age.old

# 5. 验证 + 提交
secrets list
git add dotfiles/mutable/tools/secrets/.local/share/keys/age.pub dotfiles/mutable/tools/secrets/.local/share/secrets-encrypted/*.age
git commit -S -m "ROTATE: (secrets) regenerated keypair + re-encrypted all .age"
git push

# 6. 销毁旧私钥（重加密已完成，旧私钥不再需要）
trash /tmp/age.old
```

`re-encrypt` 的不变量是解密失败即中止整条命令（`set -o pipefail`），避免部分轮换后新旧密文混杂。轮换的真正目的是让「泄漏的旧私钥」无法读「未来新增的密文」——旧私钥仍能解密 push 历史里的旧 `.age`，要彻底止血还需配合 `git filter-repo` 清理历史。

**其他安全注意事项**：

1. **密文 git 历史是可恢复的**。即使现在 push 出去的全是 `.age`，曾经 commit 过明文的话旧 commit 仍在历史里；需要的话用 `git filter-repo --invert-paths --path <泄漏文件>` 重写历史。
2. **`secrets edit` 的临时文件**在 `$XDG_RUNTIME_DIR`（tmpfs，缺则退 `/dev/shm`）下 `mktemp -d` 建隔离目录，明文与 emacs 的 backup `~` / autosave `#` 副产物都落在目录内，`trap ... RETURN INT TERM` 随命令退出整体删除，全程不碰持久盘。
3. **`.age` 文件名是公开信息**。不要把凭证类型放进文件名（如 `aws-secret-key.age`），保持中性命名（`aws-prod.age`、`accounts.age`）。
4. **明文落地的生命周期**。`decrypt` 先 `mktemp`（600）再 `mv` 到目标，没有权限窗口；条目名限 `[A-Za-z0-9._-]` 防路径穿越。

## 排障

| 症状 | 原因 | 处理 |
| --- | --- | --- |
| `secrets decrypt` 报找不到私钥 | stow 没部署或软链失效 | `cd <仓库根目录> && blue stow tools/secrets --restow` |
| `secrets` 命令未找到 | stow 未部署 `.local/bin/secrets` | `blue stow tools/secrets` |
| `age: error: no identity` | 私钥权限被改了 | `chmod 600 dotfiles/mutable/tools/secrets/.local/share/keys/age` |
| `init` 拒绝生成密钥 | `keys/age` 不在 git 忽略范围内 | 先在 `.gitignore` 加规则，或确认 `keys/.gitignore` 未被删改 |
| `init` 报「已存在」 | 旧私钥还在 | 按轮换流程先 `trash` 旧私钥 |
| `init` 后 `.age.pub` 是空的 | 私钥不是用本脚本 init 生成 | trash 旧私钥重跑 init，或手动从私钥首行注释 `awk` 提取 |
| `~/.local/share/secrets-encrypted/` 出现 | `.stow-local-ignore` 未排除密文目录 | 修复 ignore 后 `blue stow tools/secrets --restow` |
| `re-encrypt` 报 `failed to decrypt` | `--with` 指定的私钥不是加密这些密文的那个 | 确认备份的旧私钥正确（轮换前先 `cp` 备份） |
| `list` 报 `DECREPT_DIR: 未绑定的变量` | 脚本 typo 触发 `set -euo pipefail` | 修脚本；`bash -n` 不查变量绑定，必须真跑 |

## 相关

- [age 官方文档](https://age-encryption.org/)
- [`secrets` 源码](../dotfiles/mutable/tools/secrets/.local/bin/secrets)——子命令与安全不变量的唯一真源
- [`dotfiles/mutable/tools/secrets/AGENTS.md`](../dotfiles/mutable/tools/secrets/AGENTS.md)——维护范式
- [`keys/.gitignore`](../dotfiles/mutable/tools/secrets/.local/share/keys/.gitignore)——私钥排除规则