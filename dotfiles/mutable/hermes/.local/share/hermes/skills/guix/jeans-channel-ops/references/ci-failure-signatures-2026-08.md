# CI 失败签名表与诊断案例（2026-08-01 实战）

## 失败签名速查表

| 签名 | 阶段 | 根因 | 处理 |
|------|------|------|------|
| 运行 <30s + exit code 8 + `ERROR 502: Bad Gateway` 于 `ftpmirror.gnu.org/gnu/guix/` | Install Guix（第 6 步） | GNU 镜像瞬时故障（wget exit 8 = 服务器错误响应），`set -euo pipefail` 中止 | 瞬时故障，重试即可；长期加固 = 给 Install Guix 步骤套重试循环（用户拍板才推） |
| 运行 30-40min + failed step = "Build test updated packages" | 构建测试 | 某更新包构建失败（阻塞点） | 修包或回退更新；**测试在首个失败包中断，之后的包未测** → 修复后回填验证 |
| exit 128 + `remote: Bye` + `The requested URL returned error: 403` | mirror push 到 codeberg | FORGEJO_TOKEN 过期/吊销，或 Codeberg 封 runner IP | 查 Codeberg API 最后 commit 定位断点；token 无法本地验证，报告用户 |
| `No files were found: report.json`（artifact 警告） | 任意 | job 死在 updater 之前（如 Install Guix），不是 updater 问题 | 往上找 failed step |
| `Node.js 20 is deprecated... forced to run on Node.js 24` | 全程 | GitHub 平台行为，噪音 | 忽略 |
| "GitHub Issue 已存在，跳过创建" | 构建测试 | 同一阻塞包已建过 issue（issue 标题含 commit hash） | 说明失败模式重复，查 issue 历史 |

## 诊断用命令（2026-08-01 验证可用）

```bash
# token 提取（remote 内嵌，勿打印）
TOKEN=$(git remote get-url origin | sed -E 's#https://x-access-token:([^@]+)@.*#\1#')

# 运行列表 + 时间过滤（判断"今天有没有跑"必须用这个，网页列表可能漏）
curl -sS -H "Authorization: Bearer $TOKEN" \
  "https://api.github.com/repos/ShineBreaker/jeans/actions/runs?per_page=15"
curl -sS -H "Authorization: Bearer $TOKEN" \
  "https://api.github.com/repos/ShineBreaker/jeans/actions/runs?created=%3E2026-07-31T23:00:00Z"

# 单 workflow 历史（auto-update 与 mirror 运行号是两套编号）
curl -sS -H "Authorization: Bearer $TOKEN" \
  "https://api.github.com/repos/ShineBreaker/jeans/actions/workflows/auto-update.yml/runs?per_page=15"
curl -sS -H "Authorization: Bearer $TOKEN" \
  "https://api.github.com/repos/ShineBreaker/jeans/actions/workflows/mirror-codeberg.yml/runs?per_page=15"

# job 步骤结论（先定位 failed step）
curl -sS -H "Authorization: Bearer $TOKEN" \
  "https://api.github.com/repos/ShineBreaker/jeans/actions/runs/{run_id}/jobs"

# 完整日志（-L 必须，会 302 到下载地址）
curl -sS -L -H "Authorization: Bearer $TOKEN" \
  "https://api.github.com/repos/ShineBreaker/jeans/actions/jobs/{job_id}/logs" -o /tmp/job.log
# 噪音过滤：grep -vE "Node 20|DEP0040|punycode"
```

## Codeberg 403 鉴别法（token 失效 vs IP 封禁）

```bash
# 1) Codeberg 可达性 + 最后镜像 commit
curl -sS "https://codeberg.org/api/v1/repos/BrokenShine/jeans/commits?limit=3"
# 最后 commit 停在某天 = 从那一天起 mirror 断的（403 是首次失败）

# 2) 判断倾向
#    - 之前 14+ 次 mirror 全成功、同 runner 区域（northcentralus）、同 token → 倾向 token 过期/吊销
#    - `remote: Bye` 后连接被断 + 403 → 也可能是 WAF/IP 封禁
# 最终验证只能由用户：GitHub Settings → Secrets 检查 FORGEJO_TOKEN（Codeberg token 可设过期时间）
# 或手动 workflow_dispatch 重跑 mirror 一次
```

## 2026-08-01 案例要点

- auto-update 连续 4 次失败：`#87/#88`（7/28、7/30 定时）构建测试卡 emacs-ghostel；`#89/#90`（7/30 手动）Install Guix 撞 ftpmirror 502。
- emacs-ghostel 阻塞点由用户提交 `2e5e658` 修复（0.46→0.48.0 + zig 0.16 补丁），本地复验构建通过。
- e72bb6d（7/30 手动跑的更新集，report.json 时间戳 18:40 本地）含 11 个更新包；`#88` 只测到 reasonix-desktop-bin / github-copilot 就中断，**其余 9 包本次回填全部构建通过**。
- 今天的定时运行"没触发"是误报：历史触发在 05:12–05:29 UTC（cron 02:00 + 排队延迟），当时才 03:11 UTC。
- mirror 首次失败（80f322b，08-01 00:19 +0800），此前 14 次全成功；Codeberg 最后镜像 commit = 3242c07（7/30）。
- 边界遵守：未跑 update_versions.py（定时 CI 2 小时内接手）、未推 workflow 加固（用户自己做 FIX:(ci)）、工作树保持干净。
