---
name: jeans-channel-ops
description: 巡检与修复 jeans Guix channel（~/Projects/Config/jeans，github.com/ShineBreaker/jeans）—— CI 状态诊断、GitHub Actions 日志拉取、构建验证回填、更新工作流边界。触发：jeans 定时自动修复 cron / 用户问 "jeans CI 为什么失败" / "auto-update 运行挂了" / "检查 jeans 通道健康"。
---

# jeans-channel-ops — jeans Guix channel 巡检与 CI 修复

> jeans 通道的运维协议。与 `guix-configs-workflow`（Guix-configs 家目录仓库）是**两个不同仓库**：本 skill 只管 `~/Projects/Config/jeans`（打包通道）。两者共用 BLUE 任务运行器，但 AGENTS.md、CI 管线、部署模型完全不同，不要混用协议。

## 仓库硬约束（来自 AGENTS.md，操作前必读）

1. **任何操作前先 `git pull`**（CI 的提交可能未拉取到本地）。
2. 构建/更新用 BLUE：`blue build <pkg>` / `blue upgrade` / `blue gen-docs`；等价 `guix build -L modules <pkg>`。
3. 自动更新架构：**guix refresh 主力 + Python 脚本兜底**（`scripts/check-updates/update_versions.py`），两层在 CI 同一 job 串行，合并后统一构建测试。`rust-crates.scm` 禁止手改，只走 `blue import-crate`。
4. CI `auto-update.yml` 每周二/四/六跑；构建失败**阻止提交**并创建 GitHub Issue。
5. 提交前缀：`ADD:` / `FIX:` / `UPDATE:` / `FEATURE:` / `MIGRATE:`。

## CI 调度事实（防误判的关键）

- cron 是 `"0 2 * * 2,4,6"`（UTC），但**实际触发时间在 05:12–05:29 UTC**（GitHub 排队延迟 3+ 小时，历史稳定）。
- **在 06:00 UTC 之前看到"今天的运行没出现"绝不能下结论"调度坏了"** —— 先查历史触发时间再判断。2026-08-01 就因此差点误判。
- 运行号按 workflow 分开计数（auto-update 的 #90 和 mirror 的 #95 是两套编号），查错列表时会困惑。

## GitHub API 访问范式（绕开 403 rate limit）

未认证 API 会撞 rate limit（403）。**仓库 origin remote 内嵌 x-access-token**，提取后作 Bearer 即可：

```bash
TOKEN=$(git remote get-url origin | sed -E 's#https://x-access-token:([^@]+)@.*#\1#')
curl -sS -H "Authorization: Bearer $TOKEN" \
  "https://api.github.com/repos/ShineBreaker/jeans/actions/runs?per_page=15"
```

常用端点（`{owner}=ShineBreaker` `{repo}=jeans`）：
- 运行列表：`/actions/runs?per_page=N`（加 `?created=>...` 按时间过滤）
- 单 workflow：`/actions/workflows/{auto-update.yml|mirror-codeberg.yml}/runs`
- 运行内 job + 步骤结论：`/actions/runs/{run_id}/jobs`（**先看哪个 step failed，再拉日志**）
- 完整日志：`/actions/jobs/{job_id}/logs`（加 `-L` 跟随重定向；浏览器看日志要登录，API 不用）
- 网页版 `/actions` 与 `/issues` 可做只读总览（无 API 限流问题），但渲染不稳（"Sorry, something went wrong"），以 API 为准。

## CI 失败诊断 4 步（2026-08-01 实战验证）

```
① 运行列表 → 找到失败 run 的 run_id
② /jobs → 定位 failed step（先看步骤级，别直接翻全文日志）
③ /jobs/{id}/logs → grep 真实错误行（过滤 Node 20 deprecation / DEP0040 / punycode 噪音）
④ 对照失败签名表（见 references/ci-failure-signatures-2026-08.md）
```

已知失败签名：
- **exit code 8 + `ERROR 502: Bad Gateway`（ftpmirror.gnu.org）** = Install Guix 步骤撞上 GNU 镜像瞬时故障，wget exit 8 是"服务器错误响应"。修法：重试（临时）+ 给 Install Guix 步骤套重试循环（加固建议，用户拍板才推）。
- **exit 128 + `remote: Bye` + 403（codeberg push）** = Codeberg 拒绝：FORGEJO_TOKEN 过期/吊销 或 封 runner IP。鉴别：查 Codeberg API `https://codeberg.org/api/v1/repos/BrokenShine/jeans/commits` 看最后镜像 commit —— 停在旧 commit 就是从那一次开始断的。token 是 GitHub secret，本地无法验证，只能报告用户。
- **`No files were found: report.json` + 运行时长 <30s** = 死在 Install Guix 之前（Python updater 根本没跑），不是 updater 的锅。
- `Node.js 20 is deprecated` 警告 = 噪音，不影响结果。

## 构建验证回填（重要）

`test_updated_packages.py` 的构建测试**在第一个失败包处中断**，失败包之后的包全部未测。修复了阻塞包后，必须**回填验证**失败点之后的所有更新包：

```bash
# 从 report.json（本地可能残留上次运行）拿 updated 列表
python3 -c "import json; d=json.load(open('scripts/check-updates/report.json')); print('\n'.join(p['name'] for p in d['packages'] if p['status']=='updated'))"
guix build -L modules --no-grafts <pkg1> <pkg2> ...
```

验证不只是"构建通过"：-bin 包要**检查产物内容**（`ls` store 路径 bin/、`grep Exec` .desktop、`file` ELF），确认修复意图真正落地（2026-08-01：reasonix-guard 装入 bin/ + Exec 改指 guard；motrix-next-engine 从资源目录移到 bin/ 都靠内容验证确认）。

## 工作边界（cron 无用户在场时的判断准则）

- **不跑 `update_versions.py`**（它会写文件）：定时 CI 数小时内会跑，抢跑会与其竞态。只读 report.json 判断更新集合。
- **不代推 workflow 改动**：历史 `FIX: (ci)` 提交全是用户本人做的（89e28aa / 85cda2f / 13f9147 / 1fc7d60）。发现 CI 加固点（如 Install Guix 重试）→ 写进报告建议，不擅自 push。尤其 mirror 正在挂的时候，任何 push 都会再触发一次失败运行。
- **不提交/推送包更新**：那是 CI 的职责（GPG 签名提交）。本地验证结果作为报告证据。
- 工作树保持干净：诊断只读，构建只写 store。

## 参考文件

- `references/ci-failure-signatures-2026-08.md` — 2026-08-01 完整诊断案例：失败签名表、具体 API 命令、Codeberg 403 鉴别过程。
