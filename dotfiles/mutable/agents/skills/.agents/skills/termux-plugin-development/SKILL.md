---
name: termux-plugin-development
description: "改 termux-float 等 Termux 插件、重签上游官方 APK：构建、签名、会话共享。"
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [android, termux, gradle, signing, plugin]
    related_skills: [termux-configs-workflow, hermes-cron-ops]
---

# Termux 插件开发

Termux 插件（`com.termux.*`）是共享 Termux UID 的 Android app：manifest 声明 `android:sharedUserId="com.termux"`，安装时靠**同签名**拿到同一 Linux UID，从而能读写 Termux 的 `files/` 前缀、用主程序公开的 IPC（RUN_COMMAND / ACTION_SERVICE_EXECUTE）通信。本 skill 是这类仓库改代码 → 构建 → 签名 → 装机的完整工作方式。

本机相关仓库：`~/Projects/Android/termux-float-modern`（Termux:Float 的 fork，含 MD3 界面、zh-rCN、tmux 会话共享）；`~/Projects/Android/termux-emacs`（重签上游官方 APK 的独立流水线：主程序 + 全部官方插件，本地 `just all` 一条龙，CI 每周跟进上游新版本）。

## When to Use

- 改 Termux:Float / Termux:API / Termux:Tasker 类插件仓库
- 构建、签名、发布插件 APK 到手机（或发给用户）
- 插件要与 Termux 主程序共享会话、环境、数据

## 1. 签名：必须与手机上的 Termux 主程序同证书

- sharedUserId 要求所有同 UID 的包同一证书签名。不同签名 → `INSTALL_FAILED_SHARED_USER_INCOMPATIBLE`；绕过装上也不是同一 UID，读不到 Termux 数据、用不了 IPC。F-Droid / Play / GitHub 各渠道 Termux 签名互不兼容，插件同理。这决定了插件签名没有选择余地：主程序是什么签名，插件就是什么。
- 本机 Termux 是用 **GNU Emacs 公开构建密钥**重签的（为了让 `org.gnu.emacs` 与 Termux 共享 UID）。密钥与重签脚本的当前产地：`ShineBreaker/termux-emacs`（本地 `~/Projects/Android/termux-emacs` 的 `assets/emacs.keystore` 与 `scripts/resign-apk.sh`）。插件必须用同一把：证书 SHA-256 必须等于 `50b47e8f09b8781fccc998df3fc5c02de0dd9670a3d37e6cacba9f4e76319604`。
- 密钥是公开的：alias `emacs keystore`（含空格），storepass/keypass 都是 `emacs1`。本机副本 `~/Programs/Android/emacs.keystore`。
- 接法：app 模块的 build.gradle 从 `local.properties`（已 gitignore）读 `emacs.keystore.path`，有值就注册 signingConfig 并让 debug/release 都用它，无值回退上游 testkey（保持 fork 的通用性）。片段见 `references/build-toolchain.md`；`local.properties` 同时写 `sdk.dir`。
- **验证是交付的一部分**：`java -jar "$ANDROID_HOME/build-tools/<ver>/lib/apksigner.jar" verify --print-certs <apk>`，debug 与 release 的证书摘要都必须等于上面的指纹。

### 重签上游官方 APK（不构建、只换签名）

官方主程序与插件的预构建 APK 就在各自 GitHub release 上，直接重签即可装机，不必从源码构建（本机流水线与完整清单见 `references/upstream-apk-resign.md`）：

- 资产命名：插件 `<repo>-app_<tag>+github.debug.apk` + `checksums-sha256.txt`；主程序 `termux-app_<tag>+<flavor>-<buildtype>_<abi>.apk` + 按 flavor 分的 `_sha256sums`；termux-gui 例外（`app-release.apk`、无 checksums）。
- 上游资产都是 **debug 变体**，签名必须带 `-debuggable-apk-permitted`；再加 `--v4-signing-enabled false`，否则多出用不到的 `.idsig` sidecar。
- 官方插件全家：api / boot / styling / tasker / widget 皆重签；GUI 上游停更；Float 用本机 fork 构建；X11 的 release tag 固定为 `nightly`、无法按版本跳过，不入自动流水线。
- 判下载完整性用 zip 魔数（`head -c 2` 等于 `PK`）+ 官方 checksums，**不要设最小文件大小**——termux-boot 的 APK 只有约 740 KB。

## 2. 构建链（Guix 本机）

```bash
cd <plugin-repo>
guix shell openjdk@21:jdk -- bash -c 'export JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(which javac)")")")"; export PATH="$JAVA_HOME/bin:$PATH"; ./gradlew -I /tmp/tfm-build/mirror-init.gradle :app:assembleDebug :app:testDebugUnitTest --console=plain'
```

四条必须知道的机制（否则会在这几处各烧一轮）：

- **`openjdk@21` 这个包给的是 JRE，没有 javac**——要 JDK 必须写 `openjdk@21:jdk` 输出。Gradle 8.9 跑不了 Java 25（报 `Unsupported class file major version 69`，会被误读成构建脚本 bug）。
- **显式 `export JAVA_HOME` 指向该 JDK**：环境里若已存在一个指向空目录的 JAVA_HOME（本机有），Gradle 会找不到可用 JVM 而报 invalid directory。
- **dl.google.com 本机不可达**（直连与 7890 代理都 TLS 握手失败）。用 `-I` 注入 init script 把阿里云 google 镜像排在仓库列表前面，并在其中覆盖 `buildToolsVersion`（AGP 默认要的版本本机没装，报 `Failed to find Build Tools revision <v>`）。**不要改仓库的 build.gradle**——上游仓库要保持通用。init script 全文见 `references/build-toolchain.md`。
- **guix daemon 没跑时 `guix shell` 直接失败**（`/var/guix/daemon-socket/socket` 不存在，`herd status` 里也没有 guix-daemon）。store 里已有多份 `openjdk-21.0.2-jdk`，直接指过去、不用 daemon：`export JAVA_HOME=$(ls -d /gnu/store/*openjdk-21*-jdk | head -1)`，并 `export GRADLE_USER_HOME="$HOME/.local/share/gradle"`（wrapper 8.9 与依赖缓存都在那里；`~/.gradle` 是空的）。

依赖坐标来自 jitpack（termux-shared / terminal-view），mavenCentral 上没有，直连可用。

guix daemon 未运行时（`guix shell` 报无法连接 `/var/guix/daemon-socket/socket`）不必停工：store 里通常已留着现成的 openjdk-21 JDK，直接引用 + 显式 `GRADLE_USER_HOME=~/.local/share/gradle` 即可构建（wrapper 发行包与依赖缓存都在后者，已验证）。完整命令见 `references/build-toolchain.md` 的「daemon 不可用时的替代」。

## 3. 会话共享只能是中介（tmux），不是接管

- **普通 shell 会话无法在插件里显示**：pty 属于创建它的进程，fd 不能跨进程迁移；Termux 也不提供「列出/接管现存会话」的 IPC（TermuxService 无 AIDL 接口，跨 app 只有 RUN_COMMAND）。任何「把主程序已开的普通 shell 搬到别处」的需求都不成立——先把这个边界告诉用户，别先写代码。
- 可行路径：把会话放进 **tmux** 作为共享层，两边各自 `tmux new-session -A -s <name>`，同一会话的多个 client 内容实时镜像，即「双向可见」。前提是 Termux 内 `pkg install tmux`。
- 插件侧「在主程序中打开」= 发 `com.termux.RUN_COMMAND` intent 到 `com.termux.app.RunCommandService`；需要 `allow-external-apps=true`（可用 `TermuxAppSharedProperties.init(ctx).shouldAllowExternalApps()` 预检，不开就 Toast 提示而不是静默失败）。extras 细节、shellName 复用、切换会话时 `onSessionFinished` 误关服务的修法，见 `references/session-sharing.md`。

## 4. 发布节奏与验收

- **每个可交付功能一次 commit**，同时 bump `versionName` + `versionCode` 与 README 里的版本行；**不 push**，推送时机由用户掌控。
- **fork 的 Actions 不响应 push / release 事件**（GitHub 对 fork 默认禁用 workflow，除非去 Actions 页面启用）：发版用 `gh workflow run github_action_build.yml --ref master` 验证；`gh release create v<ver>` 之后用 `gh workflow run github_release_build.yml --ref master -f tag=v<ver>` 触发 release 构建（该 workflow 已带 tag input）。等待用 `gh run watch --exit-status`。
- **发 release 前核对三处**：工作区还有没有未提交的发版改动（用户说「只差 release」时往往有）；CI 侧 keystore（`gh secret list` / `gh variable list` 为空 = +emacs 变体被跳过，手机装不上）；release workflow 声明 `permissions: contents: write`（fork 的 GITHUB_TOKEN 默认只读，缺了上传 release 资产 403）。逐项清单见 `references/release-checklist.md`。
- push / 发 release / 变更仓库 secret 与 variable 都属需用户授权的动作，先确认再执行。
- commit 前跑 `assembleDebug`（发布路径再补 `assembleRelease`、`testDebugUnitTest`、`lintDebug`）。lint 只为本地链干净：用户不是上游维护者，不值得为发布建 baseline 或迎合上游。
- 真机步骤写进汇报时要带上前置条件：手机上已有其它签名的同名插件必须先卸载；tmux 类功能要 `pkg install tmux`。
- 交付物用 `hermes send --to qqbot:<chat_id> "... MEDIA:<apk 绝对路径>"` 直接发到用户 QQ（用法与日志判读见 hermes-cron-ops 的 `references/qqbot-delivery.md`）。

## 坑

- **固定 tag 的上游（termux-x11 的 `nightly`）**：按 tag 判重会永远跳过。用 GitHub API 资产对象的 `digest`（`sha256:...`）前 12 位做版本键，内容变化才重建。该 release 无 checksums 资产，digest 同时可作下载校验兜底。重签对象必须是 `universal-sharedUid-debug.apk`（另一个 `universal-debug` 不声明 sharedUserId）。
- **插件 APK 可能小于 1MB**（termux-boot 仅 ~740KB）：判下载完整性用 zip 魔数（`head -c 2` == `PK`），不要设大小下限。
- **apksigner 默认产 v4 签名**，会多出 `.idsig` 文件，侧载用不到：加 `--v4-signing-enabled false`。
- **官方 checksums 资产名有三种**：主程序 `<flavor>_sha256sums`（按 flavor 各一个）、插件 `checksums-sha256.txt`、个别 release 无（termux-gui 需跳过校验）。抓取脚本要遍历候选逐个查条目。
- **GPG 无 GUI 会话下签名**（SSH / agent 无 tty）：pinentry 起不来。用 `gpg-preset-passphrase`（在 `$GNUPGHOME` 所属 gnupg 的 `libexec/`，不在 PATH）灌密码，agent 需带 `--allow-preset-passphrase`。**校验只信「非交互签名能否在超时内完成」**——`KEYINFO` 第 5 字段即使密码错误也会置 1，是假缓存。
- **AGP 8.7.3 下布局里的 `android:onClick` 会让整个 `lintDebug` 崩溃**（AppCompat 的 `OnClickXmlDetector` 在 module analysis 阶段报 `called context.getMainProject()`）。改成代码里 `setOnClickListener`——这也是现代写法，顺带清掉 lint error。
- **Guix 下 build-tools 的 `apksigner` shell 包装脚本不可执行**（报缺文件），签名/校验一律 `java -jar <build-tools>/lib/apksigner.jar`。
- 构建会生成 `app/.project` 与 `app/.settings/`（Buildship），加进 `.gitignore` 免得污染 `git status`。
- **所有用户可见文案走 string 资源**（含 `contentDescription`），但要注意默认语言文件里有 `<plurals>` 时，翻译覆盖检查脚本的正则也要匹配 `<plurals name=`，否则新资源类型静默漏检。
- 悬浮窗类插件从 Service 弹 Dialog 必须自设窗口类型（`TYPE_APPLICATION_OVERLAY`，API<26 用 `TYPE_PHONE`）并显式设尺寸。
- **commit 要 GPG 签名**（全局 `commit.gpgsign=true`）：agent 的 shell 没有 tty，pinentry 起不来，commit 以「gpg 签名超时」失败（index 不受影响，重试即可）。解法：让用户在**自己的终端**跑一次解锁、把密码灌进 agent 缓存（`references/gpg-headless-unlock.md`；本机脚本 `~/unlock-gpg.sh`），60 分钟内连续多个 commit 只需解锁一次。**判断解锁是否生效的唯一判据是非 tty 环境下的实际签名能完成**——不要信 `KEYINFO` 的缓存标志位（密码错也会留标记）。`--no-gpg-sign` 只在用户明确同意时用。

## references

- `references/build-toolchain.md` — 完整构建命令、镜像/build-tools 的 init script 模板、签名注入的 gradle 片段、apksigner 校验
- `references/upstream-apk-resign.md` — 上游官方 APK 重签：官方 app 家族清单与资产命名、checksums 变体、apksigner 参数、批量脚本与 CI 设计
- `references/gpg-headless-unlock.md` — 无 tty 环境解锁 GPG 签名（preset-passphrase）及其假成功陷阱
- `references/session-sharing.md` — RUN_COMMAND 交接会话的 extras 与常量位置、tmux 共享层实现要点与顺序坑
- `references/release-checklist.md` — fork 发版逐项核对：开工摸底、CI 前置（keystore / permissions）、两条签名路径本地验证、发布链触发与验收
