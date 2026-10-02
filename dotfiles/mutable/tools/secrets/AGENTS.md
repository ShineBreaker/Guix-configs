# dotfiles/mutable/tools/secrets — Age 密钥与机密数据管理

用 [age](https://age-encryption.org/) 管理加密的敏感配置：明文 → age 加密 → `.age` 密文入库 Git，运行时由 `secrets` 命令解密到 `$XDG_RUNTIME_DIR/secrets-decrypted/`（tmpfs，重启即消）供应用读取。设计原则、密钥轮换与故障排查见 [docs/secrets.md](../../../../docs/secrets.md)；本篇讲本包的硬约束与维护范式。

## 目录结构

<!-- structor:begin depth=4 -->

<!-- 此树形目录由 structor 自动生成，请勿手动编辑。 -->

```
secrets/
├── .local/
│   ├── bin/
│   │   └── secrets
│   └── share/
│       ├── bash-completion/
│       │   └── completions/
│       ├── keys/
│       │   ├── .gitignore
│       │   └── age.pub
│       └── secrets-encrypted/
│           ├── mihomo-subscriptions.age
│           ├── twitter-x.age
│           └── wifi-trust.age
├── .stow-local-ignore
└── .stow-package
```

<!-- /structor -->

## 安全硬约束

<critical>
1. **私钥绝对禁止入库**：私钥只放 `.local/share/keys/age`（Stow 软链到 `~/.local/share/keys/age`，权限 600）。同目录的 `.gitignore` 精确忽略 `age`，严禁放宽或删除该规则。
2. **公钥必须入库**：`age.pub` 随 Git 版本同步，是密文可解的前提。
3. **明文绝不入库**：密文统一放 `.local/share/secrets-encrypted/`；明文只写 `$XDG_RUNTIME_DIR/secrets-decrypted/`（tmpfs），`edit`/`set` 的中间态走 `mktemp -d`（优先 tmpfs，退 `/dev/shm`）。严禁明文落盘到任何 `.config/` 源码目录。
4. **条目名即路径**：脚本用 `^[A-Za-z0-9._-]+$` 校验条目名，这是防路径穿越的唯一闸门，不可放宽。
5. **禁止双重纳管**：本包已由 Mutable Stow 纳管，切勿加入 Guix Home 的 `dotfile-services`。
6. **隐私防泄露**：禁止在文档或对话中打印或外发敏感凭据明文及其内部结构。
</critical>

## 常用操作与维护范式

```bash
# 交互入口：无参数弹出 fzf 菜单（选条目 → 选动作）
secrets

# 新增加密密文：输入明文 → age 加密 → 校验回解 → 将 .age 密文加入暂存区
secrets encrypt example < /tmp/example.toml
secrets decrypt example --stdout
git add dotfiles/mutable/tools/secrets/.local/share/secrets-encrypted/example.age

# 安全编辑已有密文（解密到内存临时目录，编辑后自动重加密）
secrets edit example

# KEY="value" 型条目的单字段操作（无需开编辑器）
secrets set mihomo-subscriptions MIHOMO_SUB_ONE "https://..."
secrets get mihomo-subscriptions MIHOMO_SUB_ONE
eval "$(secrets env mihomo-subscriptions)"   # 不落盘加载为环境变量

# 复制到剪贴板（45s 后自动清空）/ 管理操作
secrets clip example
secrets rename old new   # 重命名
secrets remove example   # 删除（git 可恢复）
secrets clean            # 清空 tmpfs 明文缓存（含旧路径残留）

# 查看当前密文、私钥与明文状态
secrets list

# 预演加密（不落盘）；加密与剪贴板类写操作都认这个全局开关
secrets --dry-run encrypt example < /tmp/example.toml
```

**明文权限窗口**：脚本先 `mktemp`（600）再 `mv`，不走「建文件 → chmod」，避免中间态可读。改这条时别简化回去。

## 部署边界与形态

| 资产路径                               | 是否提交 Git            | Stow 是否部署到 `$HOME`                 |
| -------------------------------------- | ----------------------- | --------------------------------------- |
| `.local/share/keys/age`（私钥）        | 否（`.gitignore` 拦截） | 是（软链，权限 600）                    |
| `.local/share/keys/age.pub`（公钥）    | 是                      | 是                                      |
| `.local/share/secrets-encrypted/*.age` | 是                      | **否**（`.stow-local-ignore` 排除）     |
| `$XDG_RUNTIME_DIR/secrets-decrypted/*` | 否                      | 运行时动态生成（tmpfs），不属于仓库文件 |
| `.local/bin/secrets`（命令实体）       | 是                      | 是（`~/.local/bin/secrets`）            |

> **校验铁律**：`~/.local/share/secrets-encrypted/` 不应在用户主目录存在；若出现说明 `.stow-local-ignore` 规则异常。

## 跨机迁移

新机上执行 `blue stow tools/secrets` 建立私钥软链与 `secrets` 命令（公钥已随仓库到位）；私钥须经安全通道（物理介质或加密传输）手动拷入并确保权限 `0600`。密钥轮换的完整顺序见 [docs/secrets.md §5](../../../../docs/secrets.md)——顺序有依赖（先备份旧私钥再 trash，否则旧密文解不开）。
