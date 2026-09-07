# hub 第三方 skill 安装与安全裁决（hermes skills tap/install 路线）

> `hermes-skill-curation` §1.7 三源里 **hub 区**的补充参考：`hermes skills install` 装进 hub 的第三方 skill 工作流、skills-guard-v2 拦截后的裁决协议、生态调研要点。`~/.config/agents/skills/` 锁内条目走 askill（见 `askill-third-party-skills.md`），两者不混。

## 1. hub 安装速查（2026-09-06 实测，Hermes v0.21.0）

```bash
hermes skills tap add <owner/repo>          # 注册 GitHub repo 为 skill 源（默认扫 skills/ 路径）
hermes skills tap list
hermes skills inspect <owner/repo>/<path>   # 装前预览（frontmatter + SKILL.md 头部）
hermes skills install <owner/repo>/<path> --yes    # 扫描 → 装进 hub 区
hermes skills install ... --force           # 覆盖 blocked 裁决（protected，必须用户拍板）
hermes skills uninstall <name>              # 仅 hub-installed 接受
```

install 时自动跑 **skills-guard-v2** 扫描（含 context_exfil / deception_hide / send_to_url 等正则规则）；community 源 + caution verdict（≥2 findings）即 blocked，输出 scan provenance + sha256。

## 2. guard 拦截裁决协议

1. blocked 后**先人工审读 SKILL.md 全文**再谈 force——很多 blocked 是误报。
2. 规则正则定义在 hermes-agent 源码 `tools/skills_guard.py`（按规则 id grep；插件侧同类在 `tools/plugin_guard.py`）。
3. 用源码里的正则原文 + `re.finditer` 在已下载的 SKILL.md 上复现，精确定位触发行。**一条命令一个动作**：curl 下载和 python 复现分开跑，混在一条管道里容易被审批门拦截超时。
4. 扫描 findings **不落盘**（无报告文件可查），证据只能靠 inspect 输出 + 源码规则复现。
5. force 与否是用户决定，agent 只交证据链（审读结论 + 触发原文 + 规则语义）。
6. 典型误报形态：安全/治理类文档的祈使句——「Do not share context…」「never paste catalog dumps」这类**防御性表述**会命中 exfil/deception 正则。
7. 装完第三方 skill 后建议跑 `hermes-attestation-guardian`（clawsec，已装于 hermes-agent-ops/）生成 attestation 留档。

## 3. 生态调研要点（2026-09 快照，star 数会漂移）

- **权威索引**：`0xNyk/awesome-hermes-agent`（独立维护，带 maturity 标签 + trust boundary 清单）——找生态项目先看这里，别信引流帖。
- **引流帖验证**：先逐个 web_extract 确认仓库存在，再核对文案与 README 是否相符（实例：colleague-skill 条目链接指向 distilly，描述与仓库本体不符）。
- **oh-my-hermes（OMH）模型机制**——若后续要装，这些是已核实的关键事实：
  - OMH **从不直接调用模型**；路由只是写 Hermes delegation keys，执行走本机已配 provider（zai/open.bigmodel.cn 等）。
  - setup 不 confirm 任何模型 → `status: defaulted` **零写入**，现有模型配置原样不动。
  - 日常调模型组合入口 = `~/.omh/routing/model-chains.json`（每 category 一条「模型+effort」链，头部不可用自动滑向下一条）；或 `omh coding category-maestro set`。
  - `glm-5.3` / `glm-5.3-flash` / kimi / grok / qwen 均为一级校准家族（有专属提示校准块）——z-ai + opencode 渠道的模型全被正式支持。
  - 模型变更必须 `--model-setup` preview → digest → `--apply` 两步确认，无静默改写。
  - ⚠ 未验证风险：OMH 文档路径全用 `~/.hermes/`，本机 `HERMES_HOME=~/.local/share/hermes`——装完第一件事验证落点；不对就 `omh uninstall --registration-only` 回收。
  - 安装面选择：tap 单装 skill = 试水（零 CLI）；`omh setup --core` = 完整最小面（装 CLI + 注册 plugin/MCP，侵入性强，建议先临时 profile 试）。
- **官方 self-evolution**（5.3k★）：`pip install -e` 违反用户的包管理规范，Phase 1 才落地，观望。
- **clawsec / hermes-attestation-guardian**（Prompt Security/SentinelOne）：已手装进 stow 源 `hermes-agent-ops/`，纯本地只读、输出路径 fail-closed 锁定 `~/.local/share/hermes/security/attestations/`——装任何社区 skill 前可用它的 `guarded_skill_verify.mjs` 查签名 advisory。
