---
name: monorepo-release
description: "修本机 monorepo 上游 bug 并发布新版本（补丁、变更日志、打 tag 与验证）。触发：上游项目出 bug 要修并出包 / 走发版流程 / 更新版本号与校验——任一出现即调用。"
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [release, monorepo, versioning, changelog, tag, workflow]
---

# 上游 Monorepo 修 Bug 并发版

在本机 monorepo 里根治一个上游 bug、补回归测试、更新版本与 CHANGELOG、打 tag 推送、验证 CI/Release workflow，最后在真实产物上实测。

适用：用户说「直接改源码然后发版」「发个新版」；CLI/工具行为 bug 要根治而非规避；需要 bump 版本 + 打 tag + 推送 + 验证 workflow。

## When to Use

- 用户要求修上游 bug 后发版（「直接改源码然后发版」一类指令）
- 部署位（Guix profile / 宿主插件）行为有 bug，需要回到源码仓根治
- 已完成修复，需要走完 bump → CHANGELOG → commit → tag → push → workflow 验证全链路

## 硬规则

1. **先搜本机再下「源码不在本机」的结论**。`ls ~/Projects/<厂商>/` + `find <root> -name '<模块>.py' -not -path '*/node_modules/*'` 之后才允许说上游不在本机。常见位置是 `~/Projects/Agent/<名>/packages/<pkg>/src/` 与 `~/Projects/Config/<名>/`；只找到 Guix store / uv cache 副本不代表没有源码仓。
2. **部署版本与源码版本是两件事**。`<cmd> --version` 读到的是 profile 里的安装版；源码仓 `pyproject.toml` 的 version 可能已经领先。改的是源码仓，发布后另外验证部署位（见流程第 9 步）。
3. **非平凡修复必须留一个可运行检查**。一个分支/循环/解析路径的修复配最小回归测试；没有检查的修复不算完成。
4. **按仓库自己的 AGENTS.md 发版**，别另创流程；本文件只补 AGENTS.md 不写的坑。
5. **tag 漏推 = 远端无 Release**：push 之后必须 `git ls-remote --tags origin | grep <tag>` 确认远端 tag 真的存在，本地 tag / commit / CHANGELOG 全正常也不代表推上去了。

## 流程

### 1. 定位源码与版本差

```bash
<cmd> --version                                   # 部署版
grep -n '^version' packages/<pkg>/pyproject.toml  # 源码版
git -C <monorepo> status --short && git log --oneline -3
```

工作树干净再动手；有未提交改动先问用户。

### 2. 复现 + 定位根因

用最小样本复现，不要一上来改。批量/全量症状先做**逐组件归因**：把管线的每个 pass 单独跑一遍，统计每个 pass「报告的变更数」与「实际改文本的次数」——两个数对不上就是虚报源，根因通常在那里。

### 3. 修 + 回归测试

- 测试断言要验证**收敛**，不是验证**不变**。修幂等 bug 时断言「第二轮零变更」，别断言「第一轮输出等于输入」——后者常与规范本身冲突（如「标点旁空格该删」会让第一轮必然改动），写出来只会制造假失败。
- 写第一版断言跑不过时，先怀疑**自己的预期写错**，再怀疑代码：把冲突的两条规范并排读一遍，确认哪个才是正确终态。
- 行为若有变化（输出形态、空格、顺序），grep 下游消费方（elisp 侧、golden 快照、其他包的副本）确认无人依赖旧形态，再更新受影响的旧测试期望。

### 4. 全量验证

跑仓库 AGENTS.md 列的全量验证（测试套件、selftest、codegen --check、产物 build），外加**真实语料端到端**：用目标数据跑一遍，对比修复前后的计数/规模，预期是「虚报消失、真实问题保留、重复跑结果一致」。

### 5. 版本 + CHANGELOG

Keep a Changelog 格式新增 `## [X.Y.Z] - 日期` 段；`### Fixed` 写清**根因**（哪几个缺陷如何咬合），不只写症状。补一条「实测前后对比」（多少文件/多少处）与一条「受影响的行为变化」——后者是评审时唯一能判断兼容性风险的地方。

### 6. commit

- **`-m` / `-F <file>` 均可传 message**（2026-10 前 agent gate 硬拦「无 `-m` 的 commit」、误伤 `-F`，已整条移除；与 git hook 无关）。多行 body 用多个 `-m` 或 `-F` 消息文件。
- 无 GPG 时 `--no-gpg-sign`。多个 `-m` 时 body 里的换行直接写在参数内。
- LLM 参与按**实际宿主与模型**写 `Co-authored-by`，别照抄仓里示例的字面量（那条 trailer 属于别的宿主）。

### 7. tag + push + 远端自查

```bash
git tag -a <pkg>-vX.Y.Z -m "<pkg> vX.Y.Z"
git push origin main <pkg>-vX.Y.Z
git ls-remote --tags origin | grep <pkg>-vX.Y.Z    # 必须看到，且 ^{} 指向 release commit
```

### 8. 验证 workflow 真的跑了

```bash
gh run list --repo <owner>/<repo> --limit 3
gh release view <tag> --repo <owner>/<repo> --json assets --jq '.assets[].name'
```

看 job 级结果而不是整体状态：build / github-release 成功但 publish-pypi 失败时，产物已交付，失败的是发布渠道配置（如 PyPI trusted publisher 不匹配），如实报告让用户去平台侧修，**不要**因此判定发布失败，也**不要**为了让管道变绿去改无关配置。

### 9. 发布后验证（真实产物，不是源码自校验）

部署位（Guix profile / stow / 宿主插件）不随源码发布自动更新，而它的更新往往需要用户手动跑 `blue home`。要在不碰部署位的前提下验证新版本：

```bash
python3 -m pip install --user --no-deps --force-reinstall <monorepo>/dist/<pkg>/<pkg>-X.Y.Z-py3-none-any.whl
PYTHONPATH=~/.local/lib/python3.12/site-packages <绝对路径>/<cmd> <复现命令>
```

用 wheel 里的代码跑一遍最初的复现命令，拿到前后对比数字；并在汇报里明确区分「已验证（wheel 实测）」与「待部署（`blue home` 之后日常命令才生效）」。

## Pitfalls

- **别把「部署位还是旧版」当成修复无效**。`<cmd> --version` 读到 Guix profile 副本时它当然不变——验证要走新装的产物路径，并提醒用户手动重建部署位。
- **别为了让 workflow 全绿去改 CI/PyPI 配置**。渠道侧失败与代码质量无关，归到「待用户处理」并给出失败 job 的确切报错。
- **`--fix` / `lint` 类工具的改动范围常远超本次任务**。批量跑之前先 `git status --short` 存基线，否则无法区分「我的改动」和「工具自己的改动」，commit message 也无从写实。
- **虚报比漏报更难发现**。一个报「有 N 处问题」但文本不变的工具，会让每轮复检都看到新数字。判定标准只有一条：同一输入连跑两次，第二次是否零变更。
- **monorepo 里一个包改了，其他包可能是镜像副本**。改插件/hook 前先 grep 同名文件（`find . -name '<file>' -not -path './.git/*'`），补上所有副本或确认只有一处实现，否则发布后一半位置还是旧行为。

## references/

（暂无。补发布渠道特有的坑时按主题新增文件，如某语言的打包/签名细节。）
