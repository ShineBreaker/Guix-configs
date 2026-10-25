# 修改 `source/config.org` 的安全协议与坑位

> 适用场景：用户说"改 dotfiles"且改的是 system 层（操作系统配置），需要直接编辑 `source/config.org` 的某个 `#\+NAME:` 块。
> 与 §3（多行编辑安全）和 §4（Guix service 排查）互补——本份专门讲**改 system 层 service 定义的完整流程与三类坑**。

## 工作流（4 步，必走）

```
① 在仓库根 cd ~/Projects/Config/Guix-configs
② 用 patch 工具精确改 source/config.org（见 §3 安全提示）
③ blue check            # 括号平衡检查，秒级
④ GUIX_DRY_RUN=1 blue rebuild  # 完整构建，不写入系统
```

如果 DRY_RUN 报错，**不要 commit**——回到 ② 改源码，回到 ③ 重跑。直到 DRY_RUN 通过，才能让用户跑 `blue rebuild`（AI 禁跑，sudo 卡死）。

## 坑位 1：`patch` 工具 fuzzy match 偷偷换括号数

### 现象

`patch` 用 fuzzy 匹配（9 策略之一），当 `old_string` 和 `new_string` 在某种字符（特别是 `)`）上的视觉差异被误判为"近似匹配"时，可能把原文 5 个 `)` 替换成 6 个，**只多出 1 个**而 `blue check` 立刻报"open=905 close=906"。

### 实测 transcript（2026-06-22 自动热点修复）

```diff
- (respawn? #f)))))        ← 原文 5 个 )
+ (respawn? #f))))))       ← patch new_string 6 个 )（手抖写错）
```

`blue check` 报：

```
[ERROR] 多余 1 个右括号 (open=905 close=906)
```

### 防护

**改 Org/Scheme 前先 `cat -A` 精确数括号**（特别是末尾的 `))))))` 链）：

```bash
cd ~/Projects/Config/Guix-configs && sed -n '600,620p' source/config.org | cat -A
# 注意每行末尾的 $ 前有多少个 )
```

或者用 python 精确数：

```bash
cd ~/Projects/Config/Guix-configs && python3 -c "
with open('source/config.org') as f: lines = f.readlines()
line = lines[606]  # 1-indexed
print(repr(line))
print('open =', line.count('('))
print('close =', line.count(')'))
"
```

`old_string` 和 `new_string` 在同一行末尾的 `)` 数必须**字节级一致**。

### 撤回

```bash
git checkout source/config.org
# 然后重新 patch，这次精确数
```

## 坑位 2：凭空捏造 Guix service 字段名

### 现象

改 `network-manager-configuration` / `nftables-configuration` 等 Guix service 时，按"想当然"写字段名（典型：`regulatory-domain` / `wifi-scan-rand-mac-address` / `packages`），`GUIX_DRY_RUN=1 blue rebuild` 报：

```
extraneous field initializers (regulatory-domain wifi-scan-rand-mac-address packages)
```

### 实测发现（2026-06-22）

Guix commit `ecd4ab5994c4cfd02414f0b2e86125fdc25fd877` 的 `network-manager-configuration` **只有 7 个字段**：

```scheme
(define-record-type* <network-manager-configuration>
  network-manager-configuration make-network-manager-configuration
  network-manager-configuration?
  (network-manager ...)                    ; package，默认 network-manager
  (shepherd-requirement ...)
  (dns ...)
  (vpn-plugins ...)
  (iwd? ...)                               ; deprecated
  (extra-configuration-files ...)         ; 注入 /etc/NetworkManager/conf.d/
  (dnsmasq-configuration-files ...))       ; 注入 /etc/NetworkManager/dnsmasq.d/
```

**没有** `regulatory-domain` / `wifi-scan-rand-mac-address` / `packages` 字段。改 regulatory 得走 `simple-service` + `iw reg set CN` 一次性服务；改 wifi 行为得走 `extra-configuration-files` 注入 `NetworkManager.conf`。

### 防护：动笔前先查 upstream 字段定义

```bash
# 1) 查 Guix 频道 commit（先 guix describe 看版本）
guix describe --format=channels

# 2) 拉对应 commit 的 networking.scm 全文
curl -fsSL "https://git.savannah.gnu.org/cgit/guix.git/plain/gnu/services/networking.scm?id=$(guix time-machine --channels=source/channel.lock -- describe --format=channels 2>&1 | grep -oP 'commit \"\K[^\"]+')" > /tmp/nm-scm.scm

# 3) 搜字段定义
grep -n -A 2 "define-record-type\* <network-manager-configuration>" /tmp/nm-scm.scm
```

或更简单：

```bash
curl -fsSL "https://git.savannah.gnu.org/cgit/guix.git/plain/gnu/services/networking.scm?id=ecd4ab5994c4cfd02414f0b2e86125fdc25fd877" | grep -n "define.*network-manager-configuration"
```

`http(s)` 拉源码是 read-only、不会污染仓库。

## 坑位 3：`simple-service` 在 `(append ...)` 链中位置错位

### 现象

在 `source/config.org` 的某个服务块（如 `networking-services`）里加 `simple-service`，DRY_RUN 报：

```
Wrong type argument in position 1 (expecting empty list):
  #<<service> type: #<service-type iw-reg-cn ...>>
```

意思是 `append` 第一个参数**不是 list 而是单个 service 对象**。

### 根因

块结构通常是：

```scheme
#+NAME: networking-services
#+begin_src scheme
(list (service ...)
      (service ...)
      (simple-service ...))    ← 全部在 (list ...) 里
#+end_src
```

`<<networking-services>>` 在 main 块的 `(services (append <<networking-services>> <<other-blocks>> ...))` 链路里被 `append` 处理。如果 `simple-service` 错放在 `(list ...)` 外，会被当成 list 第一个元素传给外层 `append`。

### 防护

每次新增 service / simple-service，**先确认它的父表达式是 `(list ...)` 还是 `(append ...)`**，再决定缩进和括号。简单判断：

- 块开头那行是 `(list ...)` → 所有成员都直接放在这个 list 里，末尾不要额外加 `)`
- 块开头那行是 `(append ...)` → 这个块本身已经是 list-of-list，成员是子块
- 自己写的 `simple-service` 跟着现有 `(simple-service 'foo shepherd-root-service-type ...)` 的缩进和括号风格

DRY_RUN 报 `Wrong type` / `expecting empty list` 时，第一反应是看新加的那行**是不是漏了或多包了一层 `)`**。

## 字段引用小抄（直接给 Guix 模块 → 变量映射）

| 想用                            | 来自哪个模块                | 是否已 use-modules                   | 备注                             |
| ------------------------------- | --------------------------- | ------------------------------------ | -------------------------------- |
| `network-manager-service-type`  | `(gnu services)`            | ✅                                   | re-exported                      |
| `network-manager-configuration` | `(gnu services networking)` | ✅                                   | 7 字段，见坑位 2                 |
| `dnsmasq-service-type`          | `(gnu services dns)`        | ✅                                   | re-exported by `(gnu services)`  |
| `dnsmasq`（package）            | `(gnu packages dns)`        | ❌ use-package-modules               | 不在 packages 模块列表里需手动加 |
| `iw`（package）                 | `(gnu packages linux)`      | ✅ `linux`                           | 直接可用                         |
| `nftables-service-type`         | `(gnu services)`            | ✅                                   |                                  |
| `tailscale-service-type`        | rosenthal 频道              | ✅ rosenthal services networking     |                                  |
| `wpa-supplicant`（package）     | `(gnu packages networking)` | ✅ `networking`（在 rosenthal 频道） |                                  |

判断某变量是否在当前 use-modules 里：

```bash
# 在仓库根跑 blue check 前，临时 export GUIX_PACKAGE_PATH 不行（那是别的用法）。
# 直接：
guix time-machine --channels=source/channel.lock -- environment --ad-hoc \
  iw -- iw --version
```

如果 `iw --version` 报 package 不存在，说明 `use-package-modules` 没引入 `(gnu packages linux)`，需要加 `linux` 模块。

## 验证命令速查

```bash
# 1. 括号平衡（最快）
cd ~/Projects/Config/Guix-configs && blue check

# 2. 完整 dry-run（构建但不写入系统，分钟级）
cd ~/Projects/Config/Guix-configs && GUIX_DRY_RUN=1 blue rebuild

# 3. 看具体 Guix 错误栈（DRY_RUN 报错时）
cd ~/Projects/Config/Guix-configs && GUIX_DRY_RUN=1 blue rebuild 2>&1 | head -80

# 4. 撤回（单个文件，安全）
git checkout source/config.org

# 5. 看自己改了什么
git diff source/config.org

# 6. 块的语义检查（必须 dry-run 通过）
ORG_BLOCK=networking-services blue block-show 2>&1 | tail -1 | xargs cat
```

## 反模式

- ❌ **不查字段就改 Guix service** → DRY_RUN 100% 报 extraneous field initializers
- ❌ **`patch` 改 `(respawn? #f)))))` 这种多 `)` 链时手抖加一个** → blue check 报"多 1 个 )"，但 git diff 里两行看着一样（坑位 1）
- ❌ **AI 跑 `blue rebuild`** → sudo 卡死 CLI（不变量 #3）
- ❌ **改完直接让用户 rebuild，不先 DRY_RUN** → 用户跑 `blue rebuild` 时可能编译几分钟后发现一个括号错，前功尽弃
- ❌ **`blue block-replace` 改 config.org** → 当前 Guix 时间机器 + emacs-minimal 组合下报 `Symbol's value as variable is void: replaced`，跑不通（见 `references/hermes-gateway-shepherd-service.md` §4）
