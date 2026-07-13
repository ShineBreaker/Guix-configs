# Secrets — 加密入仓配置管理

> 把个人凭证、API token、SSH 私钥等敏感信息**加密后**随仓库版本控制分发,
> 明文只在本机临时出现,任何 push 出去的字节都是 `.age` 密文。

## 1. 设计原则

### 1.1 三层信任边界

| 层   | 路径                                                                               | 进 git? | 出现在 `~`?    | 权限 |
| ---- | ---------------------------------------------------------------------------------- | ------- | -------------- | ---- |
| 密文 | `dotfiles/mutable/secrets/.local/share/secrets-encrypted/<name>.age`               | ✓       | ✗（Stow 排除） | 644  |
| 公钥 | `dotfiles/mutable/secrets/.local/share/keys/age.pub`                               | ✓       | ✓              | 644  |
| 私钥 | `dotfiles/mutable/secrets/.local/share/keys/age`(软链到 `~/.local/share/keys/age`) | ✗       | ✓              | 600  |
| 明文 | `~/.local/share/secrets-decrypted/<name>`                                          | ✗       | ✓              | 600  |

整个仓库 push 到 origin 的字节里,**没有**任何明文,也没有解密所需的私钥。

### 1.2 为什么选 age 而不是 sops/gpg/pass

- **age**:单一二进制([`age-encryption.org`](https://age-encryption.org/)),无配置,无密钥服务器,无 GPG 信任网
  X25519 + ChaCha20-Poly1305,加密速度远超 GPG
- **sops**:YAML/JSON 友好的键级加密,但本仓库的密文形态多样(纯文本/二进制/JSON),用整文件加密更直接
- **pass**:GPG 生态,UI 美观但依赖 GPG,Guix 包里 age 更轻量

### 1.3 部署边界

`secrets` 是 `dotfiles/mutable/` 下的 GNU Stow 包，不加入 Guix Home
`dotfile-services.packages`。Stow 部署公钥和私钥，但 `.stow-local-ignore` 明确排除
`secrets-encrypted/`，所以密文只留在仓库源和必要的 Guix store 闭包中。

## 2. 文件布局

```
Guix-configs/
├── dotfiles/mutable/secrets/
│   ├── .local/share/keys/
│   │   ├── .gitignore                    # 精确忽略私钥 age
│   │   ├── age                           # X25519 私钥,mode 600,不进 git
│   │   └── age.pub                       # 公钥,进 git
│   ├── .local/share/secrets-encrypted/
│   │   └── <name>.age                    # 密文,进 git但不经 Stow 部署
│   ├── .local/share/secrets-decrypted/   # 运行时明文,不进 git
│   └── .stow-local-ignore
├── tools/
│   └── secrets                           # 加密/解密/编辑 CLI
└── docs/
    └── secrets.md                        # 本文件(给人类)
```

`~/.local/share/secrets-decrypted/` 是运行时解密落地,**不进 git**,应用自
己从那里读。

## 3. 快速开始

### 3.1 全新部署

首次 `init` 时:

```bash
cd ~/Projects/Config/Guix-configs
./tools/secrets init                # 生成密钥对到 dotfiles/mutable/secrets/.local/share/keys/age
blue stow secrets                   # 建软链 ~/.local/share/keys/age
./tools/secrets list                # 验证一切就绪
```

`init` 会:

1. 调用 `age-keygen` 生成 X25519 密钥对
2. 写私钥到 `dotfiles/mutable/secrets/.local/share/keys/age`,权限 600
3. 从私钥首行注释提取公钥,写到 `dotfiles/mutable/secrets/.local/share/keys/age.pub`,权限 644
4. 提示下一步:`blue stow secrets`

### 3.2 添加新密文

```bash
echo 'token = "..."' > /tmp/example.toml
./tools/secrets encrypt example < /tmp/example.toml
./tools/secrets decrypt example --stdout      # 回圆验证
trash /tmp/example.toml

git add dotfiles/mutable/secrets/.local/share/secrets-encrypted/example.age
git commit -S -m "UPDATE: (secrets) added example.age"
git push
```

> 演练预览(不落盘):`./tools/secrets --dry-run encrypt example < /tmp/x.toml`
> 只打印 `[dry-run] ...` 计划,不写 `.age`。

### 3.3 修改已有密文

```bash
$EDITOR your-favorite
./tools/secrets edit example       # 解密 → 编辑 → 重加密
```

或一步走完:`./tools/secrets edit example` 内部完成解密、`$EDITOR`、回写。

### 3.4 应用加载

```bash
# 方式 1:脚本直接 source
source <(./tools/secrets decrypt dotenv --stdout)

# 方式 2:文件加载
./tools/secrets decrypt dotenv      # 落 ~/.local/share/secrets-decrypted/dotenv
source ~/.local/share/secrets-decrypted/dotenv
```

`show` 子命令是 `decrypt --stdout` 的别名,等价于打印到 stdout。

## 4. 子命令与选项

运行 `tools/secrets`（无参数）即可查看完整命令清单、环境变量和全局选项。

## 5. 密钥轮换

密钥丢失或泄漏后**必须**立即轮换。核心原则:**旧私钥必须保留到 re-encrypt
完成之后**才能销毁——否则无法解密旧密文,密文永久丢失。

```bash
# 1. 备份旧私钥(重加密期间需要它解密旧密文,不能先删)
cp dotfiles/mutable/secrets/.local/share/keys/age /tmp/age.old
chmod 600 /tmp/age.old

# 2. trash 旧私钥,生成新密钥对(init 检测到旧 age 会拒绝,必须先 trash)
trash dotfiles/mutable/secrets/.local/share/keys/age
./tools/secrets init                    # 生成新 age + 覆盖 age.pub
blue stow --restow secrets              # 重建 ~/.local/share/keys/age 软链指向新私钥

# 3. 用旧私钥解密所有旧密文 + 新公钥重加密
./tools/secrets re-encrypt --with /tmp/age.old

# 4. 演练预览(可选):再跑一次 dry-run 确认无残留旧密文需要处理
./tools/secrets --dry-run re-encrypt --with /tmp/age.old

# 5. 验证 + 提交
./tools/secrets list
git add dotfiles/mutable/secrets/.local/share/keys/age.pub dotfiles/mutable/secrets/.local/share/secrets-encrypted/*.age
git commit -S -m "ROTATE: (secrets) regenerated keypair + re-encrypted all .age"
git push

# 6. 销毁旧私钥(重加密已完成,旧私钥不再需要)
trash /tmp/age.old
```

轮换后旧私钥无法解密新写入的密文(新公钥加密),但**旧私钥仍能解密 push
历史里的旧 `.age`**——所以轮换的真正目的是让"泄漏的旧私钥"无法读"未来
新增的密文",并配合 `git filter-repo` 清理历史才能彻底止血。

## 6. 跨机部署

新机拉取仓库后只需要:

```bash
cd ~/Projects/Config/Guix-configs
blue stow secrets                   # 建 ~/.local/share/keys/age 软链
./tools/secrets list                # 验证公钥已就位
./tools/secrets decrypt example     # 应能解密回明文
```

私钥需要**手动迁移**:

```bash
# 旧机
scp dotfiles/mutable/secrets/.local/share/keys/age user@newhost:~/.local/share/keys/age
chmod 600 ~/.local/share/keys/age

# 新机
./tools/secrets list                # 应看到私钥已就位
```

或者用物理介质 / `gpg --symmetric` 中转,具体看威胁模型。

## 7. 安全注意事项

1. **密文 git 历史是可恢复的**。即使现在 push 出去的全是 `.age`,曾经
   commit 过明文的话,旧 commit 仍在历史里。需要的话用
   `git filter-repo --invert-paths --path <泄漏文件>` 重写历史。
2. **`tools/secrets edit` 的临时文件**(已解决)。`cmd_edit` 现在用 `mktemp -d`
   建隔离目录,明文放目录内,`trap 'rm -rf "$tmpdir"' RETURN INT TERM` 整体
   清理;emacs 的 backup `~` / autosave `#` 副产物也落在隔离目录内,随退出
   一起删除。不再需要 `cd /tmp` 的 workaround。如需额外保险,可在 tmpfs 上
   操作。
3. **`.age` 文件名是公开信息**。不要把凭证类型放进文件名(如
   `aws-secret-key.age`),保持中性命名(`aws-prod.age`、`accounts.age`)。
4. **明文落地的生命周期**。`~/.local/share/secrets-decrypted/` 下的文件
   不会自动清理,过期凭证记得 `trash`。

## 8. 故障排查

| 症状                                     | 原因                                      | 解决                                                       |
| ---------------------------------------- | ----------------------------------------- | ---------------------------------------------------------- |
| `tools/secrets decrypt` 报找不到私钥     | stow 没部署或软链失效                     | `cd Guix-configs && blue stow --restow secrets`            |
| `list` 报 `DECREPT_DIR: 未绑定的变量`    | 脚本 typo 触发 `set -euo pipefail`        | 修脚本;`bash -n` 不查变量绑定,必须真跑                     |
| `age: error: no identity`                | 私钥权限被改了                            | `chmod 600 dotfiles/mutable/secrets/.local/share/keys/age` |
| `init` 后 `.age.pub` 是空的              | 私钥不是用本脚本 init 生成                | trash 旧私钥重跑 init,或手动 `awk` 提取                    |
| `~/.local/share/secrets-encrypted/` 出现 | `.stow-local-ignore` 未排除密文目录       | 修复 ignore 后 `blue stow --restow secrets`                |
| `re-encrypt` 报 `failed to decrypt`      | `--with` 指定的私钥不是加密这些密文的那个 | 确认备份的旧私钥正确(轮换前先 `cp` 备份)                   |

## 9. 与同类方案的对比

| 维度       | 本方案 (age + stow)         | sops + git               | pass + gpg                  |
| ---------- | --------------------------- | ------------------------ | --------------------------- |
| 包大小     | 1 个二进制                  | sops + gnupg             | pass + gpg + tree + gettext |
| 配置复杂度 | 一个 shell 脚本             | .sops.yaml + 密钥映射    | gpg-agent 配置              |
| 加密粒度   | 整文件                      | YAML/JSON 键级           | 整文件                      |
| 跨机分发   | git pull + 私钥迁移         | git pull + 密钥服务/文件 | git pull + gpg key 同步     |
| 适合场景   | 任意格式凭证                | 结构化配置(主要是 YAML)  | 密码管理器                  |
| 已集成工具 | `tools/secrets`(本仓库自带) | sops CLI                 | pass CLI / 各种 UI          |

如果将来需要键级加密(比如 terraform state 里只加密特定字段),再考虑迁移到
sops。当前体量下 age 足够。

## 10. 参考

- [age 官方文档](https://age-encryption.org/)
- [`tools/secrets` 源码](../tools/secrets)
- [`dotfiles/mutable/secrets/AGENTS.md`](../dotfiles/mutable/secrets/AGENTS.md) — 维护范式
- [`keys/.gitignore`](../dotfiles/mutable/secrets/.local/share/keys/.gitignore) — 私钥排除规则
