# fork 发版检查清单（agent 视角）

仓库侧流程文档是 `RELEASING.md`；本文件补 agent 实际操作时的核对点与命令。

## 0. 开工摸底（用户说「只差发 release」时先核对）

- `git status --short`：未提交改动往往**就是这次发版的内容**（版本 bump、CI 改造、文档），不要假设只差一个 tag。
- `git branch -vv` + `git rev-list --left-right --count origin/master...master`：本地与远端差距；`git tag` / `git ls-remote --tags origin` 看已有 tag。
- `gh run list -R <repo> -L 5` 与 `gh api repos/<repo>/actions/workflows --jq '.workflows[] | {path,state}'`：Actions 有没有真实跑过、workflow 是否 active。

## 1. CI 硬性前置（缺了 release 会残或 403）

- `gh secret list` / `gh variable list`：emacs keystore 必须配 `EMACS_KEYSTORE_BASE64`（secret）或 `EMACS_KEYSTORE_URL`（variable）之一，否则 CI 跳过 +emacs 变体（workflow 打 warning），重签名版 Termux 装不上。keystore 是公开密钥，`ShineBreaker/emacs-mobile` 的 `assets/emacs.keystore`（public 仓库）可直接作为 URL 源。**配置仓库 secret/variable 前先与用户确认。**
- release workflow 必须声明 `permissions: contents: write`：fork 的 GITHUB_TOKEN 默认只读（`gh api repos/<repo>/actions/permissions/workflow` 查默认值），否则 `gh release upload` / `gh release delete` 一律 403。workflow 里显式声明即可，不需要动仓库全局设置。

## 2. 本地验证（commit 前）

- 完整链：`assembleRelease` + `testDebugUnitTest` + `lintDebug`（命令见 build-toolchain.md；daemon 不在时走它的 store 直引替代节）。
- 两条签名路径都过一遍（对应 CI 的两个变体），用 apksigner 验指纹：
  - emacs 路径（local.properties 指向 keystore）：`50b47e8f09b8781fccc998df3fc5c02de0dd9670a3d37e6cacba9f4e76319604`
  - testkey 路径（模拟 CI 先 `rm -f local.properties` 的 +github 变体）：把 local.properties 挪走重建再挪回——**本 harness 冻结 `rm`，用 `mv` 到 /tmp**。指纹 `b6da01480eefd5fbf2cd3771b8d1021ec791304bdd6c4bf41d3faabad48ee5e1`（= 仓库内置 `app/testkey_untrusted.jks`）。

## 3. 发布链与触发

- push master → `github_action_build.yml` 构建两个变体（Artifacts 区），等于发版前验证。
- 建 tag 并发布 release → `github_release_build.yml`（`on: release: published`）构建并 attach 两个 APK + `checksums-sha256.txt`；失败会自动删掉该 release 和 tag，可放心重试。
- 验收：`gh release download` 拉产物核对 checksums，指纹复验。
- push、发布 release、配置仓库 secret/variable 都属需用户授权的动作——先确认再做（本机另有全局 `commit.gpgsign=true`，提交会弹 pinentry，见 SKILL.md 坑列表）。
