# 无 tty 环境解锁 GPG 签名（preset-passphrase）

agent 的 shell 没有 tty：pinentry-qt 要 GUI、pinentry-curses 要 tty，都起不来 → `git commit`（全局 `commit.gpgsign=true`）以「gpg 签名超时」失败（index 不受影响）。解法：让用户在**自己的终端**（SSH / tmux / 本地皆可）跑一次解锁，把密码直接灌进 gpg-agent 缓存；之后 agent 侧签名命中缓存、无需任何交互，缓存 TTL 内连续多个 commit 只需解锁一次。

本机脚本：`~/unlock-gpg.sh`。核心流程：

```bash
export GNUPGHOME=$HOME/.local/share/gnupg     # 钉死真实密钥环，别用 ${GNUPGHOME:-...}
PRESET=$(dirname "$(dirname "$(readlink -f "$(command -v gpg)")")")/libexec/gpg-preset-passphrase
GRIP=$(gpg --with-keygrip --list-secret-keys '<uid>' | sed -n 's/.*Keygrip = //p' | head -1)
gpgconf --kill gpg-agent
gpg-agent --daemon --allow-preset-passphrase --default-cache-ttl 3600 --max-cache-ttl 14400
IFS= read -r -s PASS                           # 用户在自己终端输入，不回显
printf '%s' "$PASS" | "$PRESET" --preset "$GRIP"
unset PASS
printf 'probe' | timeout 20 gpg --local-user '<uid>' --clearsign -o /dev/null   # 唯一可信判据
```

- `gpg-preset-passphrase` 在 gnupg 的 `libexec/` 下，不在 PATH。

## 假成功陷阱（本机都实际踩过）

- **`--clearsign -o /dev/null </dev/null` 会假成功**：stdin 为空时 gpg 读到空输入直接返回 0，既不碰私钥也不调 pinentry——解锁脚本会永远报「成功」而缓存里什么都没有。必须喂真实数据（`printf 'probe' |`）。
- **`KEYINFO --list` 的缓存标志位不是判据**：preset 即使密码错误也会留下 `1` 标记，之后真正签名仍会去调 pinentry 卡住。唯一判据是「实际签名能在超时内完成」。
- **GNUPGHOME 被污染会静默失败**：脚本若继承外部 `${GNUPGHOME:-...}`，测试残留的临时值会让它在真实密钥环里找不到密钥而提前退出（表现为「没反应」）。钉死真实路径 + 显式校验目录存在。
- 一个密钥环可能有多个 keygrip（签名主密钥、加密子密钥），取签名那个（`--list-secret-keys` 的第一条）。
- 别把 `gpg-preset-passphrase` 的退出码当成功——密码错时它也可能返回 0。

## 相关事实

- 本机 GNUPGHOME = `~/.local/share/gnupg`（Guix home 管理），其中 `gpg-agent.conf` 是 store 只读软链——**改不了也不该改**。
- agent 启动时命令行 `--pinentry-program` 能压过配置里的 pinentry-qt（已验证），但 curses pinentry 仍需要 tty，headless 场景救不了——preset 才是正解。
- 解锁后想恢复 GUI pinentry：`gpgconf --kill gpg-agent`（agent 按配置重启）；agent 重启即清空缓存。
