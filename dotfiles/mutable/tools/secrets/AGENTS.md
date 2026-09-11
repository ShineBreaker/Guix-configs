# dotfiles/mutable/tools/secrets — Age 密钥与机密数据管理

本目录使用 [age](https://age-encryption.org/) 工具管理加密的敏感配置。密文遵循「明文 → age 加密 → `.age` 密文入库 Git」的单向管理流程，运行时由 `tools/secrets` 脚本解密到 `$XDG_DATA_HOME/secrets-decrypted/` 供各应用读取。详细机制参见 `docs/secrets.md`。

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

## 安全硬约束

1. **私钥绝对禁止入库**：私钥仅存放在 `.local/share/keys/age`（通过 Stow 软链到 `~/.local/share/keys/age`，权限 600）。同目录的 `.gitignore` 精确忽略 `age`，严禁放宽或删除该规则。
2. **公钥必须入库**：公钥存放在 `.local/share/keys/age.pub`，随 Git 版本同步。
3. **明文绝不入库**：加密文件统一放置在 `.local/share/secrets-encrypted/`；解密后的明文只写入 `~/.local/share/secrets-decrypted/`，严禁直接落盘到任何 `.config/` 源码目录。
4. **禁止双重纳管**：本目录已通过 Mutable Stow 管理，切勿将其加入 Guix Home 的 `dotfile-services`。
5. **隐私防泄露**：禁止在文档或对话中打印或外发敏感凭据明文及其内部结构。

## 常用操作与维护范式

```bash
# 新增加密密文：输入明文 → age 加密 → 校验回解 → 将 .age 密文加入暂存区
tools/secrets encrypt example < /tmp/example.toml
tools/secrets decrypt example --stdout
git add dotfiles/mutable/tools/secrets/.local/share/secrets-encrypted/example.age

# 安全编辑已有密文（通过 600 权限临时文件解密编辑并自动重加密）
tools/secrets edit example

# 查看当前密文、私钥与明文状态
tools/secrets list

# 预演加密（不落盘）
tools/secrets --dry-run encrypt example < /tmp/example.toml
```

## 部署边界与形态

| 资产路径 | 是否提交 Git | Stow 是否部署到 `$HOME` |
| --- | --- | --- |
| `.local/share/keys/age`（私钥） | 否（`.gitignore` 拦截） | 是（软链，权限 600） |
| `.local/share/keys/age.pub`（公钥） | 是 | 是 |
| `.local/share/secrets-encrypted/*.age` | 是 | 否（`.stow-local-ignore` 排除） |
| `~/.local/share/secrets-decrypted/*` | 否 | 运行时动态生成，不属于仓库文件 |

> **校验铁律**：`~/.local/share/secrets-encrypted/` 不应在用户主目录存在；若出现说明 Stow ignore 规则异常。

## 跨机迁移

在新机器上执行 `blue stow secrets` 建立私钥软链（公钥已随仓库到位）；私钥文件需通过安全通道（如物理介质或加密传输）手动拷贝到目标机器，并确保权限为 `0600`。
