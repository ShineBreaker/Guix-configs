# 上游官方 APK 重签（不构建，直接换签名）

官方主程序与插件的预构建 APK 就在各自 GitHub release 上，用 Emacs 公开密钥换签名即可装机，不必从源码构建。本机流水线在 `~/Projects/Android/termux-emacs`：`just all`（全部目标抓取 + 重签，产物在 `dist/`）、`just only <repo,...>`、`just status`；`scripts/build-apks.sh --publish` 发布为本仓库 release。

## 官方 app 家族与处理策略

| 应用 | 上游仓库 | 处理 |
| --- | --- | --- |
| Termux 主程序 | `termux/termux-app` | 重签（只认预览版 prerelease，`apt-android-7` + `universal`） |
| Termux:API | `termux/termux-api` | 重签 |
| Termux:Boot | `termux/termux-boot` | 重签（APK 仅约 740 KB） |
| Termux:Styling | `termux/termux-styling` | 重签 |
| Termux:Tasker | `termux/termux-tasker` | 重签 |
| Termux:Widget | `termux/termux-widget` | 重签 |
| Termux:GUI | `termux/termux-gui` | 上游停更；资产名 `app-release.apk`、无 checksums |
| Termux:Float | `termux/termux-float` | 不用上游——本机 fork（termux-float-modern）自构建自签名 |
| Termux:X11 | `termux/termux-x11` | release tag 固定为 `nightly`、无法按版本跳过 → 不自动化；手动重签 `termux-x11-universal-sharedUid-debug.apk` |
| Termux:AM | `termux/TermuxAm` | 已废弃（Android 10+ 失效） |

资产命名：插件 `<repo>-app_<tag>+github.debug.apk`；主程序 `termux-app_<tag>+<flavor>-<buildtype>_<abi>.apk`（buildtype 目前只有 `github-debug`，注意主程序用连字符、插件用点号）。这些都是 debug 变体。

## checksums 校验

三种资产名形态，抓取脚本要遍历候选、逐个下载并在文件里查 APK 资产名对应的行（主程序有多个 `_sha256sums`，按 flavor 各一个）：

- `..._sha256sums`（主程序）
- `sha256sums`（早期资产）
- `checksums-sha256.txt`（插件）

个别 release 没有 checksums（termux-gui）→ 警告跳过，不阻塞。

## apksigner 参数（与 Emacs 官方 SIGN_EMACS_V2 对齐）

```bash
java -jar "$ANDROID_HOME/build-tools/<ver>/lib/apksigner.jar" sign \
  --v2-signing-enabled --v4-signing-enabled false \
  --ks assets/emacs.keystore -debuggable-apk-permitted \
  --ks-pass pass:emacs1 --out out.apk in.apk
```

- `-debuggable-apk-permitted`：上游资产都是 debug 构建（manifest 带 `android:debuggable`），不带此参数签名直接失败。
- `--v4-signing-enabled false`：v4 只为 adb 增量安装服务，开着会多产出一个 `.idsig` sidecar（侧载用不到，发布时还得清）。
- 重签已签名 APK 直接可用——apksigner 自动替换旧签名，无需先删 `META-INF`。
- 校验：`verify --print-certs` 的摘要必须等于 `50b47e8f09b8781fccc998df3fc5c02de0dd9670a3d37e6cacba9f4e76319604`；插件 minSdk 24+，v2 足够（apksigner 按 minSdk 自动决定 v1）。

## 抓取下载要点

- **不要用文件大小下限判完整性**：Termux:Boot 的 APK 只有约 740 KB，设 1 MB 阈值会误杀合法文件。用 zip 魔数 `[[ $(head -c 2 f.apk) == PK ]]`，再加官方 checksums 比对（有则必校）。
- curl 加 `--retry 5 --retry-all-errors --retry-delay 2`：GitHub 对象存储偶发 TLS 握手中断，重试可恢复。
- 幂等：本地已有且 sha256 与官方一致就跳过下载。

## 批量与 CI

- 目标表驱动（`<repo>|<资产正则>|<额外参数>`），每目标：探测上游 tag →（已发布则跳过，连下载都省）→ 下载校验 → 重签 → 发布。
- release tag 用 `<repo>-<上游 tag>`（如 `termux-api-v0.53.0`），一仓库容纳多产品互不冲突。
- workflow：`schedule` 周检 + `workflow_dispatch`（可 `--only` 限定、可 force 重建）；`permissions: contents: write`；无需任何 Secrets（密钥本身是公开的）。
