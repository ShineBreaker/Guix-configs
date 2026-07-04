# Git-Fetch CI Sandbox 修复全记录 — 2026-06-25

本文件记录 jeans channel 的 git-fetch CI 沙箱问题从诊断到最终修复的完整历程，
供将来遇到同类问题时参考。

## 时间线

| Commit | 策略 | 结果 | 原因 |
|--------|------|------|------|
| `1fc7d60` | `GIT_CONFIG_NOSYSTEM: "1"` in workflow env | ❌ | Env 不穿透 guix-daemon 构建沙箱 |
| `13f9147` | `rm -f /etc/gitconfig` before daemon start | ❌ | AppArmor 对路径的拦截与文件存在无关 |
| `3727139` | git-fetch → url-fetch for affected packages | ✅ 部分 | 暴露了两个预存 bug（见下） |
| `ce55df6` | Fix pre-existing bugs (license phase + patch) | ✅ 部分 | osu-lazer-bin 通过；emacs-ghostel patch 修复但仍有 NotDir |
| `2a50680` | tar xf instead of copy-recursively for url-fetch origins | ✅ | 全部通过本地验证 |

## 关键发现

### 1. guix-daemon 不传递 GIT_CONFIG_NOSYSTEM

`guix-daemon` 的 `impureEnvVars` 白名单包含 `http_proxy`、`https_proxy`、
`NIX_*` 等，但**不包含** `GIT_CONFIG_NOSYSTEM`。代码在
`nix/libstore/globals.hh` 中编译时固定，无法通过 daemon 配置或 systemd
override 在运行时追加。附带的后果是其他 git 相关环境变量（如
`GIT_CONFIG_SYSTEM`、`GIT_CONFIG_COUNT` 等）同样无法传入沙箱。

### 2. AppArmor 对路径的拦截与文件存在无关

即使 `rm -f /etc/gitconfig` 从 host 文件系统删除了该文件，GitHub Actions
runner 的 AppArmor 配置仍会拦截沙箱进程对该路径的 `stat()` 调用并返回 EACCES。
Git 对 `/etc/gitconfig` 的 EACCES 响应是 fatal error（不是 graceful skip），
因此任何 git-fetch checkout 都无法在 CI 沙箱中完成。

### 3. url-fetch origin 在 build phase 中是 tarball，不是目录

这是本次修复链中最隐蔽的陷阱。GitHub archive tarball 经 `guix download` 下载后，
Guix 将其（及任何 patches 应用的 repack 版本）作为**单个压缩文件**存入 store。
`#$origin` gexp 展开为该文件的路径，**不是**目录。

因此 `copy-recursively` 会把整个 tarball 文件复制到目标位置，
而不是提取内容。后续工具（zig、make 等）找不到预期的目录结构。

**正确替代方案：**
```scheme
(let ((dest-dir (string-append deps "/ghostty")))
  (mkdir-p dest-dir)
  (invoke "tar" "xf" #$%ghostel-ghostty-source
          "-C" dest-dir "--strip-components=1"))
```

### 4. auto-update 脚本保留 method 字段

`update_versions.py` 的 `apply_pending_updates()` 只通过正则替换 `version`
和 `base32` 字段，**不会**修改 `method`。因此将包从 `git-fetch` 转为 `url-fetch`
后，后续的自动更新会通过 url-fetch 路径处理（`construct_download_url_from_uri`
→ `get_base32_from_guix_download`），不会意外回退到 git-fetch。

### 5. 修复 CI 阻塞 bug 会暴露下游 bug

git-fetch 的 checkout 是构建流程的第一个阶段。当一个包因 git-fetch 失败时，
所有后续阶段（patch、build、install）的 bug 都被掩盖——构建在到达它们之前
就已中止。

**诊断警告：** 当 git-fetch 修复后 CI 仍报告"同一包失败"，**切勿假设是同一原因**。
必须获取 `build-report.json` artifact（API path:
`/repos/{owner}/{repo}/actions/artifacts/{id}/zip`）并检查 `output` 字段
的 error lines。

### 6. CI artifact 下载方法

GitHub Actions 的 logs API (`/actions/jobs/{id}/logs`) 返回 302 重定向到 Azure
blob storage。Azure 需要 Microsoft 认证（Bearer token），不能用 GitHub PAT 直接
访问。替代方案：下载 workflow artifact（`/actions/artifacts/{id}/zip`），
需要进行一次 302 重定向（不要传 Authorization header 到重定向目标）然后
unzip 读取 JSON 内容。

Uses: `urllib.request` with custom `HTTPRedirectHandler` that strips auth headers。

## 不可重试的方案

以下两种修复方法**已被证明无效**，将来复现此问题时不应浪费时间重新尝试：

1. **`GIT_CONFIG_NOSYSTEM: "1"` 环境变量** — `guix-daemon` 不将其传入构建沙箱。
   保留在 workflow 中仅作为将来 Guix 上游修复后的预备。

2. **`rm -f /etc/gitconfig` 或 `chmod`** — AppArmor 对路径的拦截独立于文件存在性
   和权限。即使文件被删除，沙箱进程对该路径的 `stat()` 仍返回 EACCES。
