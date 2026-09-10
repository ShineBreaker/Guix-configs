# dotfiles/mutable/tools/secrets — Age 加密与 Stow 部署

用 [age](https://age-encryption.org/) 加密的密文与公开身份。所有密文都是「明文 → age → `.age` → git」单向管道，运行时由 `tools/secrets` 解密到 `$XDG_DATA_HOME/secrets-decrypted/` 供应用加载。给人类的完整介绍见 `docs/secrets.md`。

## 目录结构

<!-- structor:begin depth=4 -->

<!-- 此树形目录由 structor 自动生成，请勿手动编辑。 -->

```
secrets/
├── .local/
│   └── share/
│       ├── keys/
│       │   ├── .gitignore
│       │   └── age.pub
│       └── secrets-encrypted/
│           ├── wifi-hotspot.age
│           └── wifi-trust.age
├── .stow-local-ignore
└── .stow-package
```

<!-- /structor -->

## 硬约束

1. **私钥绝不进 git**。私钥只能位于 `.local/share/keys/age`（Stow 软链到 `~/.local/share/keys/age`）；同目录 `.gitignore` 只忽略精确文件名 `age`，**不要放宽或删除**。
2. **公钥必须入库**（`.local/share/keys/age.pub`）；只有私钥丢失/泄漏才需轮换密钥并重加密现存 `.age`。
3. **明文绝不进 git**：密文写 `.local/share/secrets-encrypted/`（`.stow-local-ignore` 排除，不部署）；解密明文只落 `~/.local/share/secrets-decrypted/`，不进任何 `.config/<app>/`。
4. **不要**把本目录加入 Guix Home dotfile-services（双重部署冲突）。
5. **不要**在文档中打印敏感明文的字段结构（等于给攻击者密文目录图）。

## 维护范式

```bash
# 新增密文：明文 → 加密 → 验证回圆 → 只 add 密文
tools/secrets encrypt example < /tmp/example.toml
tools/secrets decrypt example --stdout
git add dotfiles/mutable/tools/secrets/.local/share/secrets-encrypted/example.age

tools/secrets edit example     # 修改：解密 → $EDITOR → 重加密（mktemp 600 中转，不留明文）
tools/secrets list             # 密文/私钥/明文状态
tools/secrets --dry-run encrypt example < /tmp/example.toml   # 预演不落盘
```

## 常见踩坑

1. **`init` 后 `age.pub` 为空**：脚本从私钥头注释行 `# public key:` 提取公钥；手动 `age-keygen` 生成的私钥注释格式可能不同。**不要**改脚本绕过，重新 `tools/secrets init`（覆盖前先 trash 旧私钥）。
2. **`.pub` 进不了暂存区**：`git check-ignore -v <路径>` 诊断（静默 = 未 ignore）。
3. **`re-encrypt` 轮换前必须备份旧私钥**：`cp .../keys/age /tmp/age.old`，确认 `re-encrypt --with /tmp/age.old` 成功后再删；先销毁旧私钥则旧 `.age` 永久丢失。

## 部署边界

| 内容 | Git | Stow 到 `$HOME` |
| ---- | --- | --------------- |
| `keys/age` 私钥 | 否 | 是，权限 600 |
| `keys/age.pub` 公钥 | 是 | 是 |
| `secrets-encrypted/*.age` | 是 | 否（stow ignore） |
| `secrets-decrypted/*` 明文 | 否 | 运行时文件，不应来自仓库 |

**铁律**：`~/.local/share/secrets-encrypted/` 不应存在；若出现说明 Stow ignore 失效。

## 跨机部署

新机 `blue stow secrets` 建私钥软链后解密即可用（公钥随 git 到位）；私钥须从旧机经安全信道（物理介质/加密隧道）手动迁移，权限 600。
