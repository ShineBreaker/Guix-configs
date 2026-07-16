---
name: jeans-channel-workflow
description: Maintain the personal Guix channel at ~/Projects/Config/jeans (Just Enough AI-geNerated Slops). Use when the user asks to "fix the CI build failure issue", "升级 X 包", "add a package", "check upstream updates", "跑 blue upgrade", "修复 auto-update 流水线的 issue #N", or any other task inside the jeans Guix channel — including the recurring auto-fix cron (blue upgrade → blue gen-docs drift sweep → docs sync commit). Covers the dual build-system (cargo-build-system + url-fetch bin packages), the weekly Auto Update Packages GitHub Actions workflow, the bot-driven commit pipeline, and the `jeans-issue-fixer` cron entrypoint that auto-fixes build failures when CI surfaces an issue.
category: guix-packaging
---

# jeans Channel Workflow

jeans (`~/Projects/Config/jeans`, `main` branch, mirror at codeberg) is a personal [Guix channel](https://guix.gnu.org/manual/en/html_node/Channels.html) that packages bleeding-edge and proprietary software for Guix. It depends on `nonguix` for some imports (`.guix-channel`).

**Repository layout reality (as of 2026-07-11):** the repo root contains only `.guix-channel` (the channel manifest declaring `(name jeans) (directory "modules") (dependencies … nonguix)`) — there is **no** `source/` directory or `source/channel.lock` file. `AGENTS.md` (auto-injected project context) sometimes references `source/channel.lock` as if it existed; treat that as a doc drift — the authoritative layout is `blueprint.scm` + `.guix-channel` + `-L modules`. Auto-fix scripts should never create a `source/` directory to match AGENTS.md; if it ever becomes real, it would be a conscious layout change, not a missing-file stub.

This skill covers routine maintenance of that repo. Project conventions (commit message prefixes, file layout, linting, etc.) live in `AGENTS.md` and are auto-injected as project context — do not duplicate them here. This skill captures **workflow patterns and known failure modes** that AGENTS.md does not.

## 1. The auto-update pipeline (most common failure source)

`.github/workflows/auto-update.yml` runs weekly (Tue/Thu/Sat 02:00 UTC):

```
checkout → update_versions.py → detect changes →
  (if changes) install guix + git clone nonguix → test_updated_packages.py →
  gpg sign + commit + push to github → mirror to codeberg
```

- `scripts/check-updates/update_versions.py` queries GitHub API, bumps `version` + recomputes `base32` for url-fetch packages, or `git clone --depth=1` to compute nar-base32 for git-fetch packages. Updates are written in-memory first, then flushed to disk in `apply_pending_updates()`.
- `scripts/check-updates/test_updated_packages.py` reads `report.json`, runs `guix build -L modules <pkg>` for every entry with `status=updated`, creates a GitHub issue titled `❌ Updated package build failures — <sha1[:8]>` on any failure, exits 1 to block the commit step.

### 1.1 Known CI failure mode: sandbox git-fetch can never finish (issue #20 / #21)

**Status (2026-06-25):** 经三轮尝试后确认有效修复。

- commit `1fc7d60`（`GIT_CONFIG_NOSYSTEM`）：❌ env 不穿透 daemon 沙箱
- commit `13f9147`（`rm -f /etc/gitconfig` 在 daemon 前）：❌ AppArmor 仍拦截
- commit `3727139`（**git-fetch → url-fetch**）：✅ 本次确认有效，彻底绕过 git 对 /etc/gitconfig 的依赖

**根因链条（最终确认）：**

1. GitHub Actions `ubuntu-latest` 的 AppArmor 在构建沙箱内拦截对 `/etc/gitconfig` 的任何访问（即使文件不存在也返回 EACCES）
2. `guix-daemon` 创建构建沙箱时只传递白名单环境变量（`http_proxy`、`NIX_*` 等），`GIT_CONFIG_NOSYSTEM` 不在其中
3. Guix 上游的 `guix/build/git.scm` 未在 git-fetch 构建器内设置该变量（NixOS #63774 同类修复未移植）
4. 因此 git-fetch 包的 checkout 阶段必然失败：`git init` → EACCES → exit 128

如果遇到匹配此模式的症状，**先查 `git log --oneline .github/workflows/auto-update.yml` 看是否有更新的修复，再继续诊断。**

Symptoms in the build log:

```
building /gnu/store/<h>-<pkg>-<ver>-checkout.drv...
warning: unable to access '/etc/gitconfig': Permission denied
fatal: unknown error occurred while reading the configuration files
git-fetch: '.../git-minimal-2.52.0/bin/git init --initial-branch=main' failed with exit code 128
Trying content-addressed mirror at bordeaux.guix.gnu.org... 404 Not Found
SWH: revision "v<X>" originating from https://github.com/<org>/<repo> could not be found
```

Root cause: guix sandbox cannot read `/etc/gitconfig`, so `git init` fails. The `GIT_CONFIG_NOSYSTEM` env var set on the CI workflow step does **not propagate** into the sandbox because `guix-daemon` only passes a whitelist of environment variables (`http_proxy`, `NIX_*`, etc.) to build environments. After `git init` fails, guix falls back to:

1. bordeaux/ci.guix.gnu.org nar mirror — nar not yet published → 404
2. Software Heritage — `v<tag>` revisions often not indexed for newly-tagged releases → 404

The result: **every** git-fetch package whose version was bumped in the same run fails to build, including **transitive dependents** that pull in the broken git-fetch package via `native-inputs`. Example: `osu-lazer-bin` was reported as failed in issue #20 because its `native-inputs` includes `opentabletdriver-udev-rules` (which is itself git-fetch).

**Diagnostic checklist when this issue recurs:**

1. `curl -s https://api.github.com/repos/<org>/<repo>/tags` — verify the tag still exists upstream. If yes, it's not an upstream regression.
2. `curl -sL -o /dev/null -w "%{http_code}\n" https://archive.softwareheritage.org/api/1/revision/origin/https://github.com/<org>/<repo>/tag/v<X>/` — check SWH. 404 here is normal for fresh tags; SWH re-indexing takes hours to days.
3. Confirm the failure pattern is "git init failed" not "checkout failed" — the former is CI sandbox; the latter is real upstream change.

**Known mitigations（按有效性从高到低）：**

1. ✅ **将受影响的 git-fetch 包转为 url-fetch**（主修复，commit `3727139`）：
   改为 `https://github.com/<org>/<repo>/archive/refs/tags/v<ver>.tar.gz`。
   使用 `guix download <url>` 计算 base32。注意 GitHub archive tarball 目录
   结构为 `<repo>-<ver>`（无 `v` 前缀），但文件相对路径与 git clone 一致。
   转换后 `update_versions.py` 能正常通过 url-fetch 路径更新版本和 hash。
   辅助 origin（固定 commit 的私有 source 定义）也可转为 url-fetch：
   `https://github.com/<org>/<repo>/archive/<full-commit-hash>.tar.gz`。

2. ❌ `rm -f /etc/gitconfig` 在 daemon 启动前（commit `13f9147`，已证明无效）：
   AppArmor 对路径的拦截不仅限于已存在的文件——即使文件已被删除，沙箱内
   对该路径的访问仍被 AppArmor 拒绝。**不要再次尝试此方法。**

3. ❌ `GIT_CONFIG_NOSYSTEM: "1"` 在 workflow step env（commit `1fc7d60`，已证明无效）：
   `guix-daemon` 只将白名单环境变量传入构建沙箱，`GIT_CONFIG_NOSYSTEM` 不在其中。
   保留在 workflow 中仅作为将来 Guix 上游修复后的预备，当前无实际效果。

### 1.2 Issue-handling protocol

When asked to "fix the new issue" in jeans:

1. `curl -s https://api.github.com/repos/ShineBreaker/jeans/issues?state=open` — list open issues. CI-bot auto-issues follow the `❌ Updated package build failures — <8hex>` title pattern; manually-created issues look different.
2. For each failure, identify whether the failing package itself changed, or whether it was pulled in transitively. Cross-reference `(native-inputs (list ...))` and `(inputs (list ...))` of every failing package.
3. **Do not trust `report.json` / `build-report.json` on disk alone** — they may be stale or from a previous run. Always re-read the issue body for the canonical failure log.
4. CI bot issues are blocked-commit notifications; the commit they refer to (`Base commit: <sha>` in the body) has typically already landed if the step ordering failed open. Verify with `git log --oneline <sha>`.

### 1.3 Masked failures（git-fetch 修复后暴露的预存 bug）

**教训（2026-06-25）：** git-fetch 的沙箱错误发生在 checkout 阶段（构建的最早期）。
一个 git-fetch 包失败时，后续阶段（unpack、patch、build、install）的 bug 被**完全掩盖**，
因为在到达这些阶段之前构建就已中止。

当 git-fetch → url-fetch 转换消除了 checkout 错误后，原先被掩盖的错误会**立即暴露**。
对每个"修复后仍然失败"的包，必须**重新读取完整的 build log**（而非依赖 issue title 或
过去的经验），因为失败原因已经变了。

**本会话碰到的两个实例：**

| 包              | 掩盖前（git-fetch 时代）        | 暴露后（url-fetch 时代）                                         |
| --------------- | ------------------------------- | ---------------------------------------------------------------- |
| `osu-lazer-bin` | checkout: git init EACCES → 128 | `install-license-files`: match-error（AppImage 无 license 文件） |
| `emacs-ghostel` | checkout: git init EACCES → 128 | `patch`: `Hunk #1 FAILED`（upstream 变更导致补丁不兼容）         |

**诊断范式：** 当 CI 报"同一个包仍然失败"时，**不要假设是同一个原因**。
必须获取 `build-report.json` artifact（API: `/actions/artifacts/<id>/zip`），
逐包检查 `output` 字段的**最后 30 行**。checkout 失败的特征是 `git-fetch: ... git init`
和 `EACCES`；其他错误则是新问题。

### 1.4 copy-build-system 的 install-license-files 陷阱

`copy-build-system` 继承自 `gnu-build-system` 的 `install-license-files` 阶段，
该阶段用 `%license-file-regexp` 搜索 license 文件。AppImage 等二进制包通常没有
标准的 license 文件，导致 `match-error: no matching pattern`。

**修复：** 在 `#:phases` 中加 `(delete 'install-license-files)`。

```scheme
#:phases
#~(modify-phases %standard-phases
    (delete 'install-license-files)   ;; AppImage 包无标准 license 文件
    ...)
```

此问题在 git-fetch 沙箱修复前被掩盖——checkout 失败比 license 阶段更早触发。

### 1.5 版本升级时 patch 兼容性

`emacs-ghostel` 的 `%ghostel-patches` 中有一项 `ghostel.el.patch` 仅修改 docstring
示例（`/bin/bash` → `bash`），功能性修复已在 `substitute*` 阶段单独完成。
当 upstream 0.38.0 变更了该行上下文后，patch 无法应用。

**通用规则：** 每当 auto-update 脚本升级了某包的版本，其**所有 patch**
都可能因 upstream 变更而失效。诊断时优先检查 build log 中的 `Hunk #N FAILED`。
若 patch 只是 cosmetic（docstring 修正、注释调整），直接移除比重新生成更稳妥。

### 1.6 url-fetch origin 在 build phase 中是 tarball，不是目录

**关键陷阱（本会话发现）：** 当辅助 origin（private source 定义，如
`%ghostel-ghostty-source`）从 `git-fetch` 转为 `url-fetch` 后，其 `#$origin` gexp
展开为**文件路径（tarball）**，而非目录。Guix 对 url-fetch（即使带 patches 的）
会在 store 中存储 repack 后的 `.tar.xz` 压缩包。

如果 build phase 中对这类 origin 使用 `copy-recursively`，会将 tarball 文件直接
复制到目标位置，而非解压提取——导致后续工具（如 zig、make）找不到预期的文件。

**错误症状：**

```
error: unable to load package manifest '...deps/ghostty/build.zig.zon': NotDir
```

**正确做法：** 用 `mkdir-p` + `tar xf --strip-components=1` 替代 `copy-recursively`：

```scheme
;; ❌ 错误：url-fetch origin = tarball 文件，copy-recursively 只复制文件
(copy-recursively #$%ghostel-ghostty-source
                  (string-append deps "/ghostty")
                  #:log (%make-void-port "w"))

;; ✅ 正确：先创建目录，再解压 tarball（--strip-components=1 剥离顶层目录）
(let ((ghostty-dir (string-append deps "/ghostty")))
  (mkdir-p ghostty-dir)
  (invoke "tar" "xf" #$%ghostel-ghostty-source
          "-C" ghostty-dir "--strip-components=1"))
```

**适用范围：** 所有在 build phase 中通过 `#$origin` 引用辅助源的场景。
主包 source 不受此影响——`gnu-build-system` 的 `unpack` 阶段自动处理提取。

**检测方法：** 区别 `git-fetch` 和 `url-fetch` 的 store 输出类型：

- `git-fetch` → 目录（checkout） → `copy-recursively` 正确
- `url-fetch` → 文件（tarball） → 必须 `tar xf` 解压

- `update_versions.py` 的 `apply_pending_updates()` 只修改 `version` 和
  `base32`,**不会**改动 `method` 字段。因此将 `method git-fetch` 改为
  `method url-fetch` 后,auto-update 脚本会保留 url-fetch 并正确走 url-fetch
  更新路径(`construct_download_url_from_uri` + `get_base32_from_guix_download`)。

### 1.8 `blue upgrade` 撞 GitHub API rate limit(本次 2026-07-16 实测)

未配 `GITHUB_TOKEN` 时,cron 跑 `blue upgrade` 经常会全 0 检出,看起来"啥也没干"。

**根因(直接读源码确认):**

- `scripts/check-updates/update_versions.py:286` `get_latest_github_release` 在 `requests.get(...)` 后调用 `response.raise_for_status()`,把 HTTP 4xx/5xx 转化为 `requests.exceptions.HTTPError`
- 同文件 `is_retryable_http_error`(~line 120)**只**判 5xx(`500 <= status <= 599`),403 **不重试**
- 撞到 403 时:走 `except HTTPError` 分支,`is_retryable_http_error(e)=False` → 直接 `raise` → 被外层 `except requests.exceptions.RequestException` 捕获 → 返回 None
- 结果:41 个包的 release/tags/commits endpoint **全部** 撞 60/h 未鉴权上限 → 全部返回 None → `0 更新、0 保持、0 跳过`

**诊断 prompt 关键字:**

```
⚠️  无法获取GitHub release: 403 Client Error: rate limit exceeded for url:
https://api.github.com/repos/<owner>/<repo>/releases?per_page=30
```

如果 `blue upgrade` 输出里 100% 包都带这个,而且报告是 `已更新: 0 / 保持最新: 0 / 已跳过: <少量非 GitHub 包>`,**别去查 update_versions.py 逻辑**,是 rate limit。

**修复方向(任选,不强制实施):**

1. **`GITHUB_TOKEN` 注入**:`export GITHUB_TOKEN=$(gh auth token 2>/dev/null)` 给 cron 加上,5000/h 上限即可彻底脱困。`update_versions.py:301` 已经支持 `Authorization: token <...>` header,无需改脚本。
2. **Retry-After 处理**:把 `is_retryable_http_error` 扩展到 403 且 `Retry-After` header 存在的情形,按 header 等待后重试。
3. **fail-fast 早退**:无 token 时第一个 403 就 `sys.exit("no GITHUB_TOKEN; aborting to avoid burning quota")`,别跑完 41 个空请求。

**不要做:**

- ❌ 自己改 cron 直接给所有 `update_versions.py` 调用挂代理——治标不治本
- ❌ 把这个错误当成"正常无更新"假装成功——这会延迟下游 issue 报警

### 1.9 `blue gen-docs` drift detection(本次 2026-07-16 实测)

加包后忘了跑 `blue gen-docs`,`docs/packages.md` 会跟模块顺序漂移:
- 同一包可能同时出现在"AI agents 段"和"utilities 段"(gen-docs 按 `scripts/gen-docs.scm` 的 `%package-modules` 顺序扫描,如果新包**加了同名到 `tools.scm`,但实际定义在 `agent.scm`**,docs 就会基于 `define-public` 位置去归类)
- 表现: `git status -s` 长期有 `M docs/packages.md` 一行差(±1 行)未提交

**cron 自动修复会话必备一步:**

```bash
# 1. blue upgrade 后,跑一次 gen-docs 看有无漂移
blue gen-docs
git status --short   # 期望:clean

# 2. 若有漂移(典型 1 行 ±,新包从 utilities 段搬到 AI agents 段)
#    审视 diff:确保只是位置漂移,不是内容漂移
git diff docs/packages.md | head -30
# 应该只看到 ±1 行同名包位置迁移

# 3. commit(必须带前缀 DOC:)
git add docs/packages.md
git commit -m "DOC: (docs/packages.md) regen via 'blue gen-docs' to include <新包名>"
# 不 push,留给用户
```

**反模式:**

- ❌ 跳过 `blue gen-docs` 认为不影响构建——这是"自动修复 cron"的本职工作之一,不是 nice-to-have
- ❌ 手写 patch 修 docs 漂移——`blue gen-docs` 是 deterministic 的,直接重生成更稳
- ❌ `M doc` 长期留在 working tree——会让后续 CI bot 推 commit 时撞非空 working tree

## 2. Adding/upgrading a package

Standard flow lives in `AGENTS.md` (see `blue build`, `blue upgrade`, `blue import-crate`). Two recurring pitfalls:

- **`rust-crates.scm` is auto-managed.** Never edit by hand. `guix import crate -f ./Cargo.lock` rewrites it whole. Manual edits cause `cargo build --offline` failures later.
- **`-bin` suffix packages use one of three templates** depending on artifact shape (AppImage / archive / bare ELF). Pattern details + the "bare ELF still links libgcc_s via dlopen'd .node addon" trap are in AGENTS.md "预编译二进制包" — re-read that section before touching a -bin package.

## 2.1 Wrapping an existing Guix package to add resources (langpack / theme / extension)

A distinct pattern from §2: you're not packaging a new upstream; you're **(inherit <existing-package>)** + replacing source/build with `trivial-build-system` + `copy-recursively` + `union-build` to merge external resources (langpack .deb, theme archive, extension zip) into the existing package's store layout.

Why a separate pattern: many GUI apps (LibreOffice / Firefox / Chromium / Thunderbird) hard-code resource paths in their bootstrap files (`fundamentalrc`, `omni.ja`, `chrome.manifest`) using `${ORIGIN}/..` or argv[0]-relative paths. **Profile-derivation's `union-build` cannot reach inside `<existing-pkg>/lib/<app>/` from a sibling package** — the only way to add resources is to wrap the existing package itself.

Full recipe (background, .deb internals, package template, verification, upgrade checklist) lives in `references/langpack-resource-merge-pattern.md`. Do **not** attempt the "add langpack as a separate `propagated-input`" approach — confirmed empirically that LibreOffice 25.x doesn't see resources added via `XDG_DATA_DIRS` for paths inside `lib/<app>/`.

## 3. Lint + verification

`guix lint -L modules <pkg>` is mandatory after any package modification per AGENTS.md. The repo's auto-update CI does NOT run lint — it only runs `guix build`. So lint regressions sneak in via auto-updates; spot-check lint on any package that appears in `report.json` with status `updated` before merging.

### 3.1 `guix lint` checker names — Guix 9e068cc baseline

The single combined `inputs` checker from older Guix was **split into 4** in 9e068cc. When debugging lint invocation failures, run `guix lint -l` once on the host to confirm the current name set; this list drifts between Guix commits. As of Guix `9e068cc03bfacbbcd199f3618fcf360df3f368e0`:

- `wrapper-inputs` — flags packages using `wrap-program` but missing `bash-minimal` in `inputs`. **Common in -bin packages** that do `wrap-program ... LD_LIBRARY_PATH prefix ...` after patchelf. (This was rolled into the old `inputs` checker; treat "wrapper-inputs" as the authoritative name now.)
- `input-labels` — label must match the package's actual `name` field. Use quasiquote alist `("foo:lib" ,foo "lib")`, not `(list foo `(,foo "lib"))` (the modern form generates bare `"foo"` label and trips lint). AGENTS.md has the full table.
- `inputs-should-be-minimal` — suggests `coreutils` → `coreutils-minimal`, etc. Usually **a false positive** for -bin packages that need full GNU coreutils at install time (cp / install / find). Don't blindly apply.
- `inputs-should-be-native` — only relevant for `native-inputs`. Less common.
- `description` — first-sentence-validity + **"description should end with a period"** (sentence-terminator check). Trailing `(revert guix patch)` and similar parentheticals without a final period trip this; fix is to append a final English sentence ending in `.`.
- `formatting` — line-length and formatting hygiene. Long `(substitute* "..." "..."  "..."` patterns with embedded `\n` legitimately exceed 89 chars; treat as unfixable noise.
- `source-unstable-tarball` / `source-file-name` — flags `archive/refs/tags/v<X>.tar.gz` from GitHub. Often a false positive for jeans since the CI auto-update script depends on the GitHub archive tarball URL format. Don't mask with `file-name` override without checking §1.1 first.
- `patch-file-names` / `patch-headers` — flags `Foo.patch` style. Cosmetic only.

**Cron rule of thumb:** when picking packages to lint-sweep during auto-fix, pick 1 representative from each category that lint complains about; the **wrapper-inputs** class is the highest-impact silent failure (introduced by any auto-update that adds `wrap-program` but forgets `bash-minimal`).

### 3.2 Text-level paren delta is a false signal, not a real mismatch

If you `git diff` or byte-count `(` vs `)` on a `.scm` file and get a non-zero delta, **do not panic**. The delta almost always comes from `(`, `)` characters inside string literals — URLs (`https://...`), `(revert guix patch)`, `substitute*` regex patterns (`\\(`), or `local-file` paths. Verify the real signal via:

1. `(use-modules (jeans))` in a fresh `guix repl -L modules /dev/stdin` — should print your sentinel string.
2. `guix build -L modules -e '(@ (jeans packages <file>) <pkg>)' --no-grafts` — must resolve to a derivation without throwing.
3. `guix lint -n -L modules <pkg>` — for the specific class of warning you changed.

All three green = real verification. The byte-delta alone is meaningless.

### 3.3 Common lint-fix recipes (proven recipes)

Full transcripts (input/output, the exact patch hunks, and re-check commands) live in `references/lint-recipes.md`. Canonical classes:

- **Wrap-program + missing bash-minimal** → add one line to `inputs` after `at-spi2-core` (alphabetical insert), `("bash-minimal" ,bash-minimal)`. Re-run `guix lint -c wrapper-inputs -L modules <pkg>` to confirm.
- **Description trailing-period** → two valid fixes: add `.` at end of last quoted string in `(description "...")`; or append `.<sentence>.` after a trailing parenthetical.
- **coreutils → coreutils-minimal** → DON'T apply for binary wrappers; verify with `man <pkg>` what install-time tools are needed before subsituting.

### 3.4 Auto-fix session template

When cron auto-fix runs lint sweep, follow this exact 5-step flow:

```bash
# 1. Pull + status
git -C ~/Projects/Config/jeans pull --ff-only

# 2. Module load smoke
guix repl -L modules /dev/stdin <<< '(use-modules (jeans)) (display "OK\n")'

# 3. Lint 3-5 representative packages per category
guix lint -n -L modules <representative-1> <representative-2> ...

# 4. Apply minimal patches via `patch` tool with surrounding context
#    - keep alphabetical input order
#    - match §3.3 recipes

# 5. Re-run lint targeted at patched packages only
guix lint -n -L modules <pkg>  # each one you touched
```

Critical: **do not auto-push or auto-commit** GPG-signed fixes for jeans. The cron only generates patches; user owns the GPG signature + push. This matches the existing §4.1 commit-message guidance.

### 3.5 cron 自动修复可做 / 不可做边界(2026-07-16 实测)

| 可以做 ✅ | 不可以做 ❌ | 边界依据 |
| --- | --- | --- |
| `git pull`(无冲突时) | `git push` 到任何 remote | 不变量 + AGENTS.md "禁止 commit 中 push 到 remote" |
| 跑 `blue upgrade` 读日志 | 改 `update_versions.py` 让它能改 hash | cron 是"汇报 + 修 drift",不是"修工具" |
| 跑 `blue gen-docs` 重生成 docs | 手编辑 docs/packages.md | `gen-docs` 是 deterministic,手写易引 §1.9 的反向漂移 |
| `git commit`(单文件 serial) | 任何批量 `git checkout HEAD -- .` | §AGENTS.md 不变量 |
| 修 docs 漂移并 commit | 修包定义本身(`modules/jeans/packages/*.scm`) | 包定义修改属于 issue-fixer cron 范畴(§1.7),不是基础修复 cron |
| 探查 `report.json` / `build-report.json` 状态 | 删文件 / `rm -rf` | §4 Don'ts |
| 跑 lint、出报告、列 diff | `guix system reconfigure` / `guix home reconfigure` | 通用 AI-禁忌(sudo 卡 CLI) |

**衡量边界的方法:** 看 diff 落在哪一类文件:

- `docs/**/*.md` → AI 可改、必须 commit
- `modules/jeans/packages/<file>.scm`(或 `rust-crates.scm` *之外* 的定义) → **不要碰**,留给 issue-fixer cron 或手动
- `rust-crates.scm` → 绝对不碰(§4 Don'ts)
- `scripts/check-updates/*` → 改脚本不算 cron 任务,但**别在 cron 里顺手优化**(出去单独会话)
- `blueprint.scm` / `.github/workflows/*` → 改 runner 配置属"仓库元配置"变更,需用户拍板

**Cron 报告三段式模板:**

```
1. ✅ / ⚠️ / ❌ 每一步结果(blue pull / upgrade / gen-docs / commit)
2. 唯一的 commit hash + diff stat
3. 值得 follow-up 的根因(若有,如 §1.8 的 rate limit 撞墙)
```

报告**就这三段**,不堆原理、不解释背景,让用户一眼看完决定下一步。

Full session transcript (commands, output, ad-hoc verification script run + cleanup) is in `references/lint-recipes.md`.

## 4. Don'ts

- **Never** modify `rust-crates.scm` by hand.
- **Never** delete files via `rm`/`rm -rf`/`shutil.rmtree` — user preference is XDG trash (`~/.local/share/Trash/`). The CI cleanup paths in scripts/check-updates use `shutil.rmtree(...)` for tmpdirs — that's fine because tmpdirs are not user files.
- **Never** `git push --force` to `main`. The Codeberg mirror step uses `git push --force codeberg ...` internally; that is the workflow bot's job, not yours.
- **Never** read or commit `.env` / credentials. jeans has no secrets in the working tree; `WORKFLOW_GPG_PRIVATE_KEY`, `FORGEJO_TOKEN`, `GITHUB_TOKEN` all live in GitHub secrets/vars and never enter the repo.

## 4.1 Commit message format (project-specific, supplements AGENTS.md)

AGENTS.md names the prefixes (`FIX:` / `ADD:` / `UPDATE:` / `FEATURE:` / `MIGRATE:`) but does not lock the body shape. jeans in practice uses a five-section Chinese body with two-space indentation, scoped like `FIX: (<file-class>) <一句话> (closes #N)`. Section names observed in commit `1fc7d60` and earlier: `问题：` / `根因：` / `修复：` / `验证：` / `附注：`. Sections are flexible — drop any that don't apply, but keep the five-name vocabulary for grep-ability. Reference: `git log --format='%B' -3`.

Body must be passed via HerEDOC (`cat > /tmp/msg <<'EOF' ... EOF` then `git commit -F /tmp/msg`), not as `git commit -m "..."` arg — multi-line `-m` strings break on shell escaping of Chinese punctuation.

Author attribution: do **not** add a "Generated with Crush" trailer; jeans is not a Crush-managed repo. The existing commit authors are `ShineBreaker` (local) and `jeans workflow bot` (CI). `git config user.{name,email}` is already set on this host — do not override.

## 5. Quick command reference

The current task runner is **BLUE** (defined in `blueprint.scm`), not `maak`. Older sessions and stale skill text may still say `maak <cmd>` — that command **does not exist** in this repo. If the user/agent types `maak`, the working-tree state will not match what the actual CLI does. `blue` is a hard drop-in: `blue build <pkg>` ≡ `guix build --load-path=./modules <pkg>`, etc. Always use `blue` for repo-local actions; fall through to `guix ... -L modules` only when bypassing the runner.

```bash
# Single-package build
blue build <pkg>            # = guix build --load-path=./modules <pkg>

# Multi-package
blue build pkg-a pkg-b

# Check upstream versions
blue upgrade                # runs scripts/check-updates/update_versions.py

# Regenerate docs/packages.md from current modules
blue gen-docs               # uses scripts/gen-docs.scm via guix repl

# Import a Rust crate
blue import-crate <name>[@version]   # edits rust-crates.scm in place

# Direct guix (no blue)
guix build -L modules <pkg>
guix shell -L modules <pkg> -- <cmd>
guix lint -L modules <pkg>
guix graph <pkg>
```

## 5. Adding a new package file — don't forget `%public-modules`

When you create a new modules/jeans/packages/<file>.scm, you may also need to
register it in `modules/jeans.scm` so that `(jeans)` re-exports it:

```scheme
(define %public-modules
  '(...
    (jeans packages <file>)
    ...))
```

**Symptom of omission:** `(jeans)` users can't see the new packages. `guix lint
-L modules modules/jeans/packages/<file>.scm` prints `未知软件包`, even though
`guix repl -L modules` can resolve the symbols correctly — lint runs each file
in isolation, so its result is misleading when the only problem is missing
re-export. The real test is the REPL:

```bash
guix repl -L modules -e '(use-modules (jeans packages <file>))
(format #t "~a~%" (module-variable (resolve-module (quote (jeans packages <file>)))
         (quote <symbol>)))'
```

If that exits 0 and prints a variable, the package is loadable and the
re-export is the only missing piece. **After fixing the re-export, regenerate
`docs/packages.md` with `blue gen-docs` and include it in the same commit.**

### 5.1 `guix lint` "未知软件包" （实为 re-export 缺失的间接表现）

`guix lint -c <module-file>` 在沙箱内逐文件求值。若 `%public-modules` 漏了
该文件，lint 会报 `未知软件包`，但：

- `guix repl -L modules` 加载 `(jeans)` 后可直接 `(module-variable
(resolve-module '(jeans packages <file>)) '<pkg>)` —— 能 resolve 说明定义
  本身正确，只是顶层 re-export 链断了。
- 核实顺序：先 `rg <pkg-name> modules/jeans/packages/<file>.scm` 确认
  `define-public` 存在，再查 `modules/jeans.scm` 的 `%public-modules` 里有
  没有该模块条目。

**不要**为了"修 lint"去动 package 定义本身；应该补 `%public-modules`。

### 5.2 `search-path %load-path` 的相对路径 warning

`modules/jeans/patches/emacs-ghostel-*.patch` 等文件通过
`(search-path %load-path "jeans/patches/<name>")` 引用时，`guix repl -L
modules` 会输出：

```
正在将"modules/jeans/patches/..."解析为相对于当前目录
```

这是 `search-path` 在 REPL 非标准 cwd 下的已知 carry-over warning；不影响
解析结果。`guix lint -L modules` 在同一上下文中也会转发这 6 条。属于
upstream posix 路径检查行为，**不是包定义错误**，可以在审阅时忽略。

## 6. Where to look when stuck

| Symptom                                                                   | First read                                                                                                                                                                                                                               |
| ------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Build fails in CI but passes locally                                      | `references/auto-update-ci-failures.md` + §1.1 本文件。注意：`1fc7d60` 和 `13f9147` 的 workflow 级修复**均已证明无效**（前者 env 不穿透沙箱，后者 AppArmor 拦截路径）。唯一可靠修复为 `3727139`：将受影响的 git-fetch 包转为 url-fetch。 |
| `cargo build --offline` fails after upgrade                               | `rust-crates.scm` likely stale; re-run `blue import-crate`                                                                                                                                   |
| `guix lint` complains about synopsis/description                          | AGENTS.md "Guix 打包参考" → "测试与验证"                                                                                                                                                                                                 |
| AppImage binary segfaults at runtime                                      | AGENTS.md "裸 ELF 的陷阱" — check for dlopen'd native addons needing `(,gcc "lib")`                                                                                                                                                      |
| 改 `jeans-issue-fixer` cron job 的 prompt                                 | §1.7（先验 action + 分支决策 + retry guard 设计） + `references/cron-issue-fixer-prompt-template.md`（完整 prompt 模板 + 调试路径 + 各分支决策表）                                                                                       |
| CI 显示 "包仍然失败" 但之前修过 git-fetch                                 | §1.3：**检查 build-report.json artifact**，失败原因可能已改变（patch 不兼容 / license 阶段等）                                                                                                                                           |
| `install-license-files` match-error（copy-build-system）                  | §1.4：AppImage/二进制包需 `(delete 'install-license-files)`                                                                                                                                                                              |
| `Hunk #N FAILED` in patch application                                     | §1.5：版本升级后 patch 与 upstream 不兼容；cosmetic patch 直接移除                                                                                                                                                                       |
| `NotDir` or `unable to load package manifest` in zig/build phase          | §1.6：url-fetch origin 是 tarball 文件，不能用 copy-recursively；改用 tar xf                                                                                                                                                             |
| 添加 langpack / 翻译资源 / 主题资源到现有 Guix 包（如 LibreOffice zh-CN） | `references/langpack-resource-merge-pattern.md` —— fundamentalrc 写死相对 argv[0] 路径，profile union 不进 `lib/<app>/`，必须 `inherit + copy-recursively + union-build`                                                                 |
| 新建包文件后 `guix lint` 报 `未知软件包`                                  | §5 / §5.1：先确定 `define-public` 存在，然后检查 `%public-modules` 是否注册了该模块；lint 在文件级沙箱里报的"未知"往往是 re-export 链断了，不是包本身有错。                                                                              |
| `search-path %load-path` 在 REPL/lint 里频刷"解析为相对于当前目录"        | §5.2：已知 carry-over warning；不影响解析结果，审阅时忽略。                                                                                                                                                                                                                                                                                                                                                                              |
| `wrapper-inputs` lint:`wrap-program` 但 inputs 缺 `bash-minimal`           | §3.1 / `references/lint-recipes.md` §Recipe 1:quasiquote alist 字母位插一行。                                                                                                                                                                                                                                                                                                                                                            |
| lint `description` 末尾应有点号(trailing parenthetical 触发的)           | §3.3 / `references/lint-recipes.md` §Recipe 2:补 `.` 或追加一句 English sentence 收尾。                                                                                                                                                                                                                                                                                                                                                    |
| byte-level paren delta ≠ 真实 s-exp 不平衡                                    | §3.2 / `references/lint-recipes.md` §Recipe 5:URL/字符串/正则里 `(`,`)` 多算;以 `guix repl -L modules` + `(use-modules (jeans))` + `guix build -L modules -e ...` + `guix lint` 三件套为准。                                                                                                                                                                                                                                                                                                                   |
| `blue upgrade` 全 0/41 检出,100% 包都报 `403 rate limit exceeded`           | §1.8:无 `GITHUB_TOKEN` 时撞 60/h 上限。修法:`export GITHUB_TOKEN=$(gh auth token)` 给 cron;或 `is_retryable_http_error` 扩到 403+`Retry-After`;或无 token 时 fail-fast。不要反复"诊断逻辑 bug"。                                                                                                                                                                                                                                                                                                         |
| `M docs/packages.md` 长期漂移(典型 ±1 行,新包同名段重复出现)             | §1.9:`blue gen-docs` 是 deterministic,直接重生成 + 审视 diff + commit,不要手改。                                                                                                                                                                                                                                                                                                                                                          |
| cron 自动修复会话里"不知道能做什么/不能做什么"                            | §3.5:docs 可改 + commit + 单文件;包定义/`rust-crates.scm`/workflow 文件全部不碰;`git push` 永远留给用户。                                                                                                                                                                                                                                                                                                                                  |
| 系统调起 skill 时拽错了(例如把 `guix-configs-workflow` 拽到 jeans 任务里) | 优先读 jeans 工作目录里的 `AGENTS.md`(本仓库用的任务是 `blue` 不是 `blue home`)。本 skill 是 jeans 的专属 class 级 skill;`guix-configs-workflow` 专治 `~/Projects/Config/Guix-configs` 仓库,跟 jeans 不互通。                                                                                                                                                                                                                            |
| AGENTS.md 描述里有 `source/channel.lock`，但仓库只有 `.guix-channel`          | `references/lint-recipes.md` §Recipe 4：blueprint 走 `.guix-channel` + `-L modules`；不要为对齐文档建假的 `source/`。                                                                                                                                                                                                                                                                                                                       |
| `modules/jeans.scm` 补完 re-export 后要同步的事                           | `blue gen-docs` 重新生成 `docs/packages.md`，并在同一 commit 中提交。                                                                                                                                                                                                                                                                                                                                                                      |
