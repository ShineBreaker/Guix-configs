---
name: flatpak-update-repair
description: "Use when flatpak update, install, or repair fails."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [flatpak, ostree, update, repair, debugging, desktop]
---

# Flatpak 更新失败与仓库修复

## When to Use（触发条件）
- `flatpak update/install` 报 `No such metadata object <hash>.commit/.dirtree`、`Couldn't find file object`、`对象缺失`
- `flatpak repair` 卡在 `正在修剪对象`（prune）报错退出
- 更新反复失败，但应用本身能打开（启动失败走 flatpak-app-debugging）

## 诊断流程

1. **复现并看它到底有没有下载**（只读）
   ```bash
   timeout 120 flatpak update --user -v <ref> 2>&1 | tail -20
   ```
   若日志里只有 `summary.idx` 加载、没有任何对象下载请求就直接报错 → 本地 tracking ref 已提前指向新提交，本次 update 短路跳过下载、死在 checkout。这是最常见的形态，先入为主按中断残留查，不要先换镜像源。

2. **查中断残留**（`repo/state/*.commitpartial`）
   ```bash
   ls ~/.local/share/flatpak/repo/state/
   ```
   报错 hash 对应的 `.commitpartial` 是上次中断留下的半截标记。用 `trash-put` 清掉（rm 会被 hook 拦截，且 trash 可恢复），再重试 update。state 目录下有几十个同类文件是常态，说明这台机器历史上频繁中断更新。

3. **证伪镜像再动手**（只读对照）
   ```bash
   ostree --repo=/tmp/orepo-t1 init --mode=bare-user-only
   ostree --repo=/tmp/orepo-t1 remote add --no-gpg-verify t <remote-url>
   ostree --repo=/tmp/orepo-t1 pull --commit-metadata-only t:<ref>
   ```
   空仓能拉到即证明网络与镜像源无辜，回头专心修本地仓库。

4. **全仓扫描坏引用**（只读，164 个引用约需几分钟）
   ```bash
   ostree --repo=~/.local/share/flatpak/repo refs > /tmp/refs.txt
   while read -r r; do ostree --repo=~/.local/share/flatpak/repo ls "$r" >/dev/null 2>&1 || echo "BROKEN: $r"; done < /tmp/refs.txt
   ```
   区分两种命名空间：`deploy/*` 是已部署（含孤儿部署），`flathub:*` 只是跟踪记录。坏的 deploy 不超过个位数是常态。

5. **repair 先 dry-run 评估**
   ```bash
   flatpak repair --user --dry-run 2>&1 | tail -20
   ```
   看 `对象缺失` 的数量级和 `正在删除引用` 的名单。EOL 旧分支（24.08 系）和 Locale 翻译包是重灾区，被删的多是修不好的孤儿引用。

6. **收尾（三件套，按序）**
   - 孤儿部署（`flatpak list` 里没有、但 deploy ref 和部署目录还在，如旧版 Locale）：`flatpak uninstall --user <ref>`；若报未安装，记下来走 ostree refs 手工清，不要强删部署目录。
   - 部署中损坏（如已安装应用缺子树对象，update 因已是最新而不会重拉）：`flatpak uninstall` 后重装，`~/.var/app/<id>` 下的用户数据默认保留（只有 `--delete-data` 会清），重装后一般只需重新登录。
   - 最后 `flatpak repair --user && flatpak update --user` 跑通，prune 不报错即闭环。

## Pitfalls
- `flatpak repair` 不补对象、只删修不好的引用——指望它自动下回缺失对象会落空，部署中的损坏必须走卸载重装。
- deploy ref 已指向新提交、而实际部署仍是旧提交，就是半截更新的铁证，update 必然短路失败，不要反复重试同一命令。
- repair 删掉已安装应用的 Locale 跟踪引用是正常行为，下次 update 会重新拉取，无需手动补装。
- 不要用 curl 直取 `objects/…/*.file` 来判定镜像缺对象——官方源对本地已存在的对照对象同样 404，该探针法无效。
- 大体积 Locale（如 KDE 400MB+ 级别）更新时保证网络不中断，否则回到步骤 2。
