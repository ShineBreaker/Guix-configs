# dotfiles/secrets — Age 加密入仓

本目录存放用 [age](https://age-encryption.org/) 加密后的密文与公开身份。私钥
**绝不**入库。所有密文都是「明文 → age → `.age` → git」单向管道,运行时由
`tools/secrets` 解密到 `$XDG_DATA_HOME/secrets-decrypted/`(默认
`~/.local/share/secrets-decrypted/`)供应用加载。

> 给人类读者的完整介绍见 `docs/secrets.md`。

## 目录结构

<!-- structor:begin -->

<!-- 此树形目录由 structor 自动生成，请勿手动编辑。 -->

```
secrets/
├── .local/
│   └── share/
│       ├── keys/
│       │   ├── .gitignore
│       │   ├── age
│       │   └── age.pub
│       └── secrets-decrypted/
├── .stow-overlay/
└── .stow-local-ignore
```

<!-- /structor -->

## 硬约束

1. **私钥绝不进 git**。私钥只能位于 `dotfiles/mutable/secrets/.keys/age`(由 GNU Stow 软链
   到 `~/.keys/age`)。`dotfiles/mutable/secrets/.keys/` 在根 `.gitignore` 命中 `.keys/` 通配
   规则被排除,**不要**修改这条规则。
2. **公钥必须入库**。`dotfiles/secrets/.keys/age.pub` 走 `!.keys/*.pub` 放行规
   则进入 git,这是跨机部署密文的唯一信任锚。如果公钥丢失或泄漏,**必须立即
   重新生成密钥对**(所有现存 `.age` 用旧公钥加密,旧私钥泄漏等于明文泄漏)。
3. **明文绝不进 git、不进 dotfile-services**。
   - `dotfile-services.packages` 不要加 `secrets`(`source/config.org` 已确认
     未加),否则 `.age` 会被 Guix Home 复制到 `/gnu/store/` 并软链到
     `~/.config/secrets/`,破坏隔离。
   - 解密出的明文只能落在 `~/.local/share/secrets-decrypted/`,不进任何
     `.config/<app>/` 目录。
4. **不要把 `dotfiles/secrets/` 加进 `dotfile-services.packages`**。当前
   `packages` 列表(`agents desktop system terminal utilities`)是源码中已声明
   的白名单,新增任何条目都会导致对应目录被部署到 `~`。
5. **不要在文档中打印公钥/私钥指纹以外的任何敏感信息**。例如不要写
   "accounts.json.age 包含哪些字段" —— 这等于给攻击者一份密文目录的字段图。

## 维护范式

### 添加新密文

```bash
# 1. 准备明文(可以是任意文本/JSON/凭证)
echo 'my-token = "..."' > /tmp/example.toml

# 2. 加密 → 写入 dotfiles/secrets/example.age
tools/secrets encrypt example < /tmp/example.toml
trash /tmp/example.toml

# 3. 验证解密回圆
tools/secrets decrypt example --stdout

# 4. 提交(只 add 密文,不要 add 解密产物)
git add dotfiles/secrets/example.age
git commit -S -m "UPDATE: (secrets) added example.age"
```

### 修改已有密文

```bash
tools/secrets edit example     # 自动解密 → $EDITOR → 重新加密
```

`edit` 子命令内部用 `mktemp`(权限 600)做中转,只在原地重建 `.age` 期间存在
临时文件,不在 dotfiles/secrets/ 留下任何明文痕迹。

### 验证流程

```bash
# 列密文/私钥/明文状态
tools/secrets list

# 列所有 recipients(目前只有一个 age.pub)
tools/secrets recipients

# 确认私钥路径与软链都正确
ls -la dotfiles/mutable/secrets/.keys/age ~/.keys/age
stat -c '%a' dotfiles/mutable/secrets/.keys/age     # 应为 600
# 预演加密(不落盘):打印 [dry-run] 计划,不写 .age
./tools/secrets --dry-run encrypt example < /tmp/example.toml
```

## 常见踩坑

1. **「`tools/secrets list` 报 `DECREPT_DIR: 未绑定的变量`」** —— 这是脚本里
   拼写 typo 触发的 `set -euo pipefail` 失败。`DECREPT_DIR` 应为 `DECRYPT_DIR`。
   修复后用 `bash -n tools/secrets` + 真跑每个子命令验证(只查语法不查变量绑
   定,必须真跑)。
2. **「`init` 之后 `dotfiles/secrets/.keys/age.pub` 是空的」** —— 脚本靠
   `awk '/^# public key:/ {print $NF}' dotfiles/mutable/secrets/.keys/age > ...` 从私钥头
   注释行提取公钥,如果私钥不是用本脚本的 `init` 生成(如手动 `age-keygen` 复
   制过来),注释行格式可能不同。**不要**手动修改脚本绕过,正确做法是重新跑
   `tools/secrets init`(覆盖前先 trash 现有私钥)。
3. **「git add 时 .pub 没进暂存区」** —— 可能是误以为文件未被 ignore 但其实
   已被某个未显示的 `.gitignore` 命中。诊断:
   `git check-ignore -v dotfiles/secrets/.keys/age.pub`(应静默返回 = 未 ignore)。
4. **`edit` 子命令的 $EDITOR 临时文件**(已解决) —— `cmd_edit` 现在用
   `mktemp -d` 建隔离目录,明文放目录内,`trap 'rm -rf "$tmpdir"' RETURN INT TERM`整体清理;emacs 的 backup`~`/ autosave`#` 副产物也落在隔离目录内,随退出
一起删除。**实现坑**:`set -u`下 trap 引用 local 变量(此处`$tmpdir`)须用
   `${tmpdir:-}` 守卫,否则未赋值就触发未绑定变量错误。
5. **`re-encrypt` 轮换时旧私钥丢失** —— 密钥轮换前必须先 `cp dotfiles/mutable/secrets/.keys/age
/tmp/age.old` 备份旧私钥,确认 `re-encrypt --with /tmp/age.old` 成功后再
   `trash /tmp/age.old`。`trash` 旧私钥后 `init` 生成新密钥对,期间旧密文只能
   用备份的旧私钥解密;若先销毁旧私钥,旧 `.age` 永久丢失。

## 与 dotfile-services 的边界

| 维度       | `dotfiles/secrets/`            | `dotfiles/immutable/<app>/`            |
| ---------- | ------------------------------ | -------------------------------------- |
| 部署机制   | **不部署**(仅 stow 软链 + git) | Guix Home `home-dotfiles-service-type` |
| 进 `~`     | 公钥 + 密文从不直接进 `~`      | 软链到 `/gnu/store/<hash>`             |
| 改源后生效 | `git pull` 即可                | 必须 `blue home`                       |

**铁律**:`dotfiles/secrets/` 任何文件都不应出现在 `~/.config/secrets/` 下。
如果出现,说明 dotfile-services 误把它加入了 `packages`,立即检查
`source/config.org` 的 `dotfile-services` 块并修正。

## 跨机部署

新机拉取仓库后:

```bash
cd Guix-configs
blue stow secrets                  # 建私钥软链 ~/.keys/age
# 公钥会随 git pull 自动到位
# 之后所有 tools/secrets decrypt 都能在本机运行
```

私钥需要**手动迁移**:从旧机的 `dotfiles/mutable/secrets/.keys/age` 用安全信道(物理介质 /
加密隧道)复制到新机,权限保持 600。
