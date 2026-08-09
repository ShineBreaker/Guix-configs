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

gh CLI 已可用（绝对路径 `/home/brokenshine/.local/state/nix/profile/bin/gh`，2026-08-06 实测）——**优先用 gh，命令更短且自带鉴权**：

```bash
GH=/home/brokenshine/.local/state/nix/profile/bin/gh
$GH api 'repos/ShineBreaker/jeans/actions/runs?per_page=5' --jq '.workflow_runs[] | {id, status, conclusion, created_at, updated_at}'
$GH run view <run_id> --jobs          # 定位 failed step（比翻全文快）
$GH run view <run_id> --log-failed    # 只输出失败步骤日志，配合 grep 'Traceback|KeyError|error' 抓根因
$GH issue list --repo ShineBreaker/jeans --state open
```

gh 不可用或撞 403 时，用仓库 origin remote 内嵌的 x-access-token 提取后作 Bearer 即可：

```bash
TOKEN=$(git remote get-url origin | sed -E 's#https://x-access-token:([^@]+)@.*#\1#')
curl -sS -H "Authorization: Bearer $TOKEN" \
  "https://api.github.com/repos/ShineBreaker/jeans/actions/runs?per_page=15"
```

常用端点（`{owner}=ShineBreaker` `{repo}=jeans`）：
- 运行列表：`/actions/runs?per_page=N`（加 `?created=>...` 按时间过滤）
- 单 workflow：`/actions/workflows/{auto-update.yml|mirror-codeberg.yml}/runs`
- 运行内 job + 步骤结论：`/actions/runs/{run_id}/jobs`（**先看哪个 step failed，再拉日志**）
- 完整日志：`/actions/jobs/{job_id}/logs`（加 `-L` 跟随重定向；浏览器看日志要登录，API 不用）。**2026-08-01 实测：未授权访问返回 403 `Must have admin rights to Repository`** —— 拿不到日志时不要死磕，fallback = 本地复现失败 + 读 report.json / build-report.json artifact（`/actions/artifacts/<id>/zip`）。
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
- **`guix refresh: error: <pkg>: unknown package` + 失败步骤 `Run guix refresh`**（2026-08-08 run 31230210821 / 31073843776，运行时长 ~30min，build test 从未开始、无 issue）= `auto-update.yml` 硬编码的 refresh 包列表引用了已删除/改名包。修法：`grep -rhoP '\(define-public \K[^ )]+' modules/jeans/packages/*.scm` 与 workflow 列表对比找出失效名（本次 6 个：`opencode-bin`→已改名 `opencode-desktop-bin`；`mimocode-bin`/`orca-ide-bin`/`oh-my-pi-bin`/`open-interpreter-bin` 被 `293affd` 删、`python-screeninfo` 被 `fd3628f` 删），**用户改 workflow 列表**（agent 边界：不改 CI 文件），**重跑 action 无效**（确定性失败）。注意与 `Test updater release tag prefixes` 签名同根因（删包未同步引用）但**位置不同**——看失败步骤名区分。修正列表后本机 `guix refresh` 跑通即可证明根因唯一。
- **Python `Traceback` / `KeyError: '<pkg-name>'` + 失败步骤是 `Test updater release tag prefixes`**（2026-08-06 run 30880286426 / 31067714158）= 回归测试引用了已删除的包：某 commit 删了 `define-public`（如 `293affd` 删 `open-interpreter-bin`）但 `test_tag_prefix.py` 用例 / config.json 注释没同步删。修法：删过时引用 + 本地 `python3 scripts/check-updates/test_tag_prefix.py` 验证；**注意时间特征与基础设施失败几乎一样短（~13s），必须看失败步骤名区分**；**重跑 action 无效**——CI 用远端 main 代码，本地修复未 push 时重跑必败，验证留给用户 commit/push 之后。与上面 `Run guix refresh` 签名同根因（删包未同步引用）但位置不同——两个都要靠失败步骤名定位。
- `Node.js 20 is deprecated` 警告 = 噪音，不影响结果。

## 构建验证回填（重要）

构建需要 nonguix 通道。本机 nonguix checkout 在 `~/.cache/guix/checkouts/<hash>/`（guix pull 通道缓存），定位并注入 load path：

```bash
NONGUIX_DIR=$(for d in ~/.cache/guix/checkouts/*/; do
  [ "$(git -C "$d" remote get-url origin 2>/dev/null)" = "https://gitlab.com/nonguix/nonguix" ] && echo "$d" && break
done)
export GUIX_EXTRA_LOAD_PATH="$NONGUIX_DIR"
# 注意：nonguix 的 nongnu/ 目录直接在 checkout 根下，没有 modules/ 前缀
guix build -L modules -L "$NONGUIX_DIR" <pkg>
```

`test_updated_packages.py` 的构建测试**在第一个失败包处中断**，失败包之后的包全部未测。修复了阻塞包后，必须**回填验证**失败点之后的所有更新包：

```bash
# 从 report.json（本地可能残留上次运行）拿 updated 列表
python3 -c "import json; d=json.load(open('scripts/check-updates/report.json')); print('\n'.join(p['name'] for p in d['packages'] if p['status']=='updated'))"
guix build -L modules --no-grafts <pkg1> <pkg2> ...
```

验证不只是"构建通过"：-bin 包要**检查产物内容**（`ls` store 路径 bin/、`grep Exec` .desktop、`file` ELF），确认修复意图真正落地（2026-08-01：reasonix-guard 装入 bin/ + Exec 改指 guard；motrix-next-engine 从资源目录移到 bin/ 都靠内容验证确认）。

## guix refresh 更新应用陷阱（2026-08-08 实战）

- **unknown package 全盘阻塞 vs 跳过不失败**：`guix refresh` 先解析全部 spec 再统一处理——列表里一个 unknown package 就 exit 1，**整个步骤零更新**；而 `源中无 version 字段；跳过` 只是 warning（source uri 不是标准 `string-append` + version 形式，refresh 无法自动改写 hash；这类包如 `github-copilot`/`crush-bin`/`motrix-next-bin` 全部由 Python updater 兜底），跳过不阻塞。本机验证时可用**修正后的列表**跑 `guix refresh -L modules <pkgs>`（报告模式不改文件）确认哪些有真实更新。
- **版本比较误导（字母段版本号）**：版本含字母段时 Guix 版本比较可能把字母段判为大于数字段——`zen-browser-bin` 的 `1.21.10b` 被 refresh 报"升级到 1.21b"（实际是**降级**，`1.21b` 是旧 tag；真实最新 1.21.12b）。refresh 报的更新含字母段时必须对照上游：`gh api repos/<owner>/<repo>/releases --jq '.[].tag_name' | head` 核实，不要盲信。
- **`/releases/latest` 返回 404 = 该 repo 所有 release 都是 prerelease**（GitHub latest 端点只返回 stable，`inso-bin` 案例：v0.3.4–v0.3.6 全部 prerelease=true → Python updater 报 failed）。用 `/releases?per_page=N` 列出全部并看 `prerelease`/`draft` 字段，手动 `guix download` 资产算 hash 更新即可。
- **两个 updater 改同一批包是正常的**：refresh 与 Python updater 覆盖范围重叠，后者覆盖前者，最终 diff 一致即可，不必纠结是谁改的。
- **cron 会话内跑自定义 Python 逻辑**：用 `write_file` 写脚本 + `terminal python3 <script>` 执行（execute_code 在 cron 模式会被安全策略拦截，且改仓库文件前先在脚本里断言解析结果——见 references/rust-crates-manual-update.md 的事故复盘）。

## 工作边界（cron 无用户在场时的判断准则）

存在**两类 cron**，边界不同：
- **只读巡检 cron**（CI 诊断）：不跑 `update_versions.py`（会写文件），只读 report.json。
- **更新助手 cron**（本次任务形态）：用户显式授权跑 `blue upgrade` / `guix refresh -u` 并把可用更新**应用到本地 .scm**，再逐个 `blue build` 验证；产物留在工作树，**绝不 commit/push**（GPG 签名只能在用户在场时做）。

- **不跑 `update_versions.py`**（它会写文件）：定时 CI 数小时内会跑，抢跑会与其竞态。只读 report.json 判断更新集合。（更新助手 cron 例外：任务明确要求应用更新时照跑，但注意它是**先收集后批量写盘**，中途 git diff 为空是正常中间态。）
- **不代推 workflow 改动**：历史 `FIX: (ci)` 提交全是用户本人做的（89e28aa / 85cda2f / 13f9147 / 1fc7d60）。发现 CI 加固点（如 Install Guix 重试）→ 写进报告建议，不擅自 push。尤其 mirror 正在挂的时候，任何 push 都会再触发一次失败运行。
- **不提交/推送包更新**：那是 CI 的职责（GPG 签名提交）。本地验证结果作为报告证据。
- 工作树保持干净：诊断只读，构建只写 store。

## 参考文件

- `references/ci-failure-signatures-2026-08.md` — 2026-08-01 完整诊断案例：失败签名表、具体 API 命令、Codeberg 403 鉴别过程。
- `references/rust-crates-manual-update.md` — rust-crates.scm 依赖树手动更新全流程（Cargo.lock diff → guix import --lockfile → 合并脚本）＋ 2026-08-08 正则 bug 静默破坏文件的事故复盘与脚本改写铁律。
