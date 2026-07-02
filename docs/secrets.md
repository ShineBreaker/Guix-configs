# Secrets — 加密入仓配置管理

> 把个人凭证、API token、SSH 私钥等敏感信息**加密后**随仓库版本控制分发,
> 明文只在本机临时出现,任何 push 出去的字节都是 `.age` 密文。

## 1. 设计原则

### 1.1 三层信任边界

| 层     | 路径                                          | 进 git? | 出现在 `~`? | 权限 |
| ------ | --------------------------------------------- | ------- | ----------- | ---- |
| 密文   | `dotfiles/secrets/<name>.age`                 | ✓       | ✗           | 644  |
| 公钥   | `dotfiles/secrets/.keys/age.pub`              | ✓       | ✗           | 644  |
| 私钥   | `stow/secrets/.keys/age`(软链到 `~/.keys/age`) | ✗       | ✓           | 600  |
| 明文   | `~/.local/share/secrets-decrypted/<name>`     | ✗       | ✓           | 600  |

整个仓库 push 到 origin 的字节里,**没有**任何明文,也没有解密所需的私钥。

### 1.2 为什么选 age 而不是 sops/gpg/pass

- **age**:单一二进制([`age-encryption.org`](https://age-encryption.org/)),无
  配置,无密钥服务器,无 GPG 信任网,X25519 + ChaCha20-Poly1305,加密速度远
  超 GPG
- **sops**:YAML/JSON 友好的键级加密,但本仓库的密文形态多样(纯文本/二
  进制/JSON),用整文件加密更直接
- **pass**:GPG 生态,UI 美观但依赖 GPG,Guix 包里 age 更轻量

### 1.3 为什么不用 dotfile-services 部署

`source/config.org` 的 `dotfile-services.packages` 是白名单,只列出
`agents desktop system terminal utilities`。**没有** `secrets`。

这是有意为之 —— `home-dotfiles-service-type` 会把白名单目录复制到
`/gnu/store/` 然后软链到 `~/.config/<app>/`。如果把 `dotfiles/secrets/` 加
进 packages,`~/.config/secrets/` 会出现 `.age` 密文副本,本机出现两份解密
目标 → 隔离失效。

## 2. 文件布局

```
Guix-configs/
├── dotfiles/
│   └── secrets/                          # 密文 + 公钥(进 git)
│       ├── .keys/
│       │   └── age.pub                   # X25519 公钥
│       ├── <name>.age                    # 加密产物(N 个)
│       └── AGENTS.md                     # 维护范式(给 AI)
├── stow/
│   └── secrets/                          # 私钥(不进 git,stow 软链)
│       └── .keys/
│           └── age                       # X25519 私钥,mode 600
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
./tools/secrets init                # 生成密钥对到 stow/secrets/.keys/age
blue stow secrets                   # 建软链 ~/.keys/age
./tools/secrets list                # 验证一切就绪
```

`init` 会:

1. 调用 `age-keygen` 生成 X25519 密钥对
2. 写私钥到 `stow/secrets/.keys/age`,权限 600
3. 从私钥首行注释提取公钥,写到 `dotfiles/secrets/.keys/age.pub`,权限 644
4. 提示下一步:`blue stow secrets`

### 3.2 添加新密文

```bash
echo 'token = "..."' > /tmp/example.toml
./tools/secrets encrypt example < /tmp/example.toml
./tools/secrets decrypt example --stdout      # 回圆验证
trash /tmp/example.toml

git add dotfiles/secrets/example.age
git commit -S -m "UPDATE: (secrets) added example.age"
git push
```

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

## 4. 子命令清单

| 命令                  | 用途                                            |
| --------------------- | ----------------------------------------------- |
| `init`                | 生成密钥对(已存在则报错)                       |
| `list` / `ls`         | 列密文 + 私钥/公钥状态 + 已解密明文            |
| `recipients`          | 列出所有 recipients 公钥(目前只有一个)         |
| `encrypt <name>`      | 从 stdin 读明文 → `dotfiles/secrets/<name>.age` |
| `decrypt <name>`      | 解密到 `~/.local/share/secrets-decrypted/<name>`|
| `decrypt --stdout`    | 解密打印到 stdout(管道用)                      |
| `show <name>`         | 同 `decrypt --stdout`                           |
| `edit <name>`         | 解密 → `$EDITOR` → 重加密                      |

环境变量:

- `SECRETS_PRIVATE_KEY`: 自定义私钥路径(默认 `~/.keys/age`)
- `SECRETS_PUBLIC_KEY`: 自定义公钥路径(默认 `dotfiles/secrets/.keys/age.pub`)
- `EDITOR`: `edit` 子命令用的编辑器(默认 `nano`)

## 5. 密钥轮换

密钥丢失或泄漏后**必须**立即轮换。流程:

```bash
# 1. 备份旧私钥(应急)
cp stow/secrets/.keys/age /tmp/age.old
chmod 600 /tmp/age.old

# 2. trash 旧密钥
trash stow/secrets/.keys/age

# 3. 生成新密钥
./tools/secrets init                 # 会提示已存在 → trash 后再跑

# 4. 重新加密所有 .age(用新公钥)
for name in $(./tools/secrets list 2>/dev/null | grep -oP '\.age' | sed 's/\.age//'); do
    ./tools/secrets decrypt "$name" --stdout | ./tools/secrets encrypt "$name"
done

# 5. 验证 + 提交
./tools/secrets list
git add dotfiles/secrets/.keys/age.pub
git add dotfiles/secrets/*.age
git commit -S -m "ROTATE: (secrets) regenerated keypair."
git push
```

旧私钥仍能解密 `.age`,但新写入的密文用新公钥加密,泄漏的旧私钥无法解密
新内容。

## 6. 跨机部署

新机拉取仓库后只需要:

```bash
cd ~/Projects/Config/Guix-configs
blue stow secrets                   # 建 ~/.keys/age 软链
./tools/secrets list                # 验证公钥已就位
./tools/secrets decrypt example     # 应能解密回明文
```

私钥需要**手动迁移**:

```bash
# 旧机
scp stow/secrets/.keys/age user@newhost:~/.keys/age
chmod 600 ~/.keys/age

# 新机
./tools/secrets list                # 应看到私钥已就位
```

或者用物理介质 / `gpg --symmetric` 中转,具体看威胁模型。

## 7. 安全注意事项

1. **密文 git 历史是可恢复的**。即使现在 push 出去的全是 `.age`,曾经
   commit 过明文的话,旧 commit 仍在历史里。需要的话用
   `git filter-repo --invert-paths --path <泄漏文件>` 重写历史。
2. **`tools/secrets edit` 的临时文件**。`mktemp` 权限 600,在脚本进程退出
   时清理。如果 `EDITOR=emacs`,emacs 的 `backup~` 和 autosave `#` 副产物
   会落到当前目录,可能产生明文痕迹。建议 `edit` 前 `cd /tmp`。
3. **`.age` 文件名是公开信息**。不要把凭证类型放进文件名(如
   `aws-secret-key.age`),保持中性命名(`aws-prod.age`、`accounts.age`)。
4. **明文落地的生命周期**。`~/.local/share/secrets-decrypted/` 下的文件
   不会自动清理,过期凭证记得 `trash`。

## 8. 故障排查

| 症状                                  | 原因                                | 解决                                                  |
| ------------------------------------- | ----------------------------------- | ----------------------------------------------------- |
| `tools/secrets decrypt` 报找不到私钥  | stow 没部署或软链失效               | `cd Guix-configs && blue stow --restow secrets`      |
| `list` 报 `DECREPT_DIR: 未绑定的变量` | 脚本 typo 触发 `set -euo pipefail`  | 修脚本;`bash -n` 不查变量绑定,必须真跑               |
| `age: error: no identity`             | 私钥权限被改了                      | `chmod 600 stow/secrets/.keys/age`                    |
| `init` 后 `.age.pub` 是空的           | 私钥不是用本脚本 init 生成          | trash 旧私钥重跑 init,或手动 `awk` 提取               |
| `~/.config/secrets/` 出现了文件       | dotfile-services 误把 secrets 加入  | 检查 `source/config.org` 的 dotfile-services 块       |

## 9. 与同类方案的对比

| 维度                | 本方案 (age + stow)        | sops + git                | pass + gpg               |
| ------------------- | -------------------------- | ------------------------- | ------------------------ |
| 包大小              | 1 个二进制                 | sops + gnupg              | pass + gpg + tree + gettext |
| 配置复杂度          | 一个 shell 脚本            | .sops.yaml + 密钥映射     | gpg-agent 配置           |
| 加密粒度            | 整文件                     | YAML/JSON 键级            | 整文件                   |
| 跨机分发            | git pull + 私钥迁移        | git pull + 密钥服务/文件  | git pull + gpg key 同步  |
| 适合场景            | 任意格式凭证               | 结构化配置(主要是 YAML)  | 密码管理器               |
| 已集成工具          | `tools/secrets`(本仓库自带) | sops CLI                  | pass CLI / 各种 UI       |

如果将来需要键级加密(比如 terraform state 里只加密特定字段),再考虑迁移到
sops。当前体量下 age 足够。

## 10. 参考

- [age 官方文档](https://age-encryption.org/)
- [`tools/secrets` 源码](../tools/secrets)
- [`dotfiles/secrets/AGENTS.md`](../dotfiles/secrets/AGENTS.md) — 维护范式(给 AI)
- [.gitignore 第 15-19 行](../.gitignore) — 密钥排除规则