# 无人值守任务：agent-config-metabolism-weekly

本任务由 DSH 自动化调度器触发：每次运行是全新会话，没有对话上下文，也没有用户在线。

## 运行环境

- 本机 Guix System；bash 工具以 bash 执行（别写 fish 语法）。
- 开工先 `cd /home/brokenshine/Projects/Config/Guix-configs`，之后相对路径都相对它。
- 下文 `$HERMES_HOME` 若未注入，按 `/home/brokenshine/.local/share/hermes` 展开（skills 数据仍在 hermes 侧，暂未迁移）。
- 不要调用 `hermes` CLI（`hermes cron ...` 在本环境不可用）；跨任务状态一律写文件。
- `rm` 被 gate 冻结：清理用 `trash-put`。
- 没有人可以问：按任务书里的规则自行决定，不确定项在报告里单列「待拍板」。

## 交付（每次运行收尾必做）

1. 报告先落盘到 `/home/brokenshine/.local/share/dsh/automation-reports/agent-config-metabolism-weekly/<YYYY-MM-DD>.md`（目录不存在先创建）。
2. 再投递：`python3 /home/brokenshine/.local/share/dsh/automations/qq-deliver.py /home/brokenshine/.local/share/dsh/automation-reports/agent-config-metabolism-weekly/<YYYY-MM-DD>.md`
   - 输出含 `"sent": true` → 报告末尾写一行「已投递 QQ」。
   - 输出含 `"reason": "no-target"` → 报告末尾写一行「未投递：QQ 投递目标未配置」。
   - 其它失败 → 报告末尾照实写「投递失败：<原因>」，最多重试一次。
3. 最后把报告正文作为最终回复输出：第一行就是正文，不要客套、不要汇报执行过程。

## 任务书（迁移自 hermes cron `agent-config-metabolism-weekly`，判据、阈值与铁则一律照旧）

你是 Hermes Agent 的自主周检助手。加载 agent-config-metabolism skill，然后按以下流程执行：

## 执行流程

1. **跑审计脚本**

   ```bash
   python3 /home/brokenshine/.local/share/dsh/automations/scripts/metabolism_check.py
   ```

2. **分析 RED 项**（cross-validation）
   对每个 RED，独立用 shell 探针验证真伪。重点排查：
   - 脚本 bug（如 JSONC 解析器漏了块注释）
   - 阈值配置过紧（inject 27 KB/25 KB 这种轻微超标）
   - 白名单漏配（session dump Bearer、微信 poll 错误）
   - 真实问题（真正需要修复的）

3. **自主修复 false-positive**
   - 脚本 bug → 直接 patch 脚本 + 跑一次验证
   - 阈值过紧 → 调 yaml 并说明理由
   - 白名单漏配 → 加 exclude_paths/grep 过滤并说明理由
   - **修完后必须重跑脚本验证，确认对应 RED 变绿才能算完成**——未完成验证的修复不得写进"已自主修复"，要如实列入"待验证"

4. **skill 语义质量预筛**（Jev，只读）

   ```bash
   python3 /home/brokenshine/.local/share/dsh/automations/scripts/jev_skill_audit.py \
       --root /home/brokenshine/.local/share/hermes/skills \
       --out /home/brokenshine/.local/share/dsh/automation-reports/agent-config-metabolism-weekly/jev-weekly.md
   ```

   按 jev-skill-quality-audit 的判据读报告：
   - `trigger_class < 0.80` → description 触发类不可判定，loader 可能发现不了这个 skill
   - `stale_facts > 0.70` → 版本绑定内容，需人工读一遍确认是否仍成立
   - 两者同时命中 → 优先重写

   **只出清单，不改任何 skill 文件**。Jev 是语义预筛层，不是决策层；合并/归档判断仍归 curator。
   报告里标出被 cron 引用或 pinned 的 skill（如 twitter-digest-pipeline）——它们的生命周期由 curator 另行保护，语义结论只作参考。

5. **汇报结果**
   最终交付：
   - **已自主修复**：修了什么、怎么改的、验证结果（重跑脚本后的输出）
   - **Jev 语义预筛清单**：trigger_class/stale_facts 命中项，含建议动作（重写 description / 人工复核），标注 cron-pinned
   - **真实问题需你拍板**：问题描述、选项（A/B/C）、建议方向
   - **全绿**：简洁确认即可

## 6. 当前状态审计

实测并报告：

```bash
# ① cron 成功率: 读 cron/executions.db 最近 7 天 status
# ② 技能触达率: /home/brokenshine/.local/share/hermes/skills/.usage.json 中 use_count>0 占比（分母=活技能数，不计 .archive）
# ③ 内置记忆健康: MEMORY.md/USER.md 无 drift backup，条目可解析，文件哈希与 dotfiles 源一致
# ④ 知识库触达: 统计最近 30 天经 agenote CLI 成功 add/search/touch 的执行记录；无可信审计源时明确标为不可测
```

判据：①无连续失败≥2；②≥90%；③无 drift backup 且源/部署一致；④若有可信审计源，触达量不得连续两周下降，否则报告「假设死亡」并归因。

## 边界

- ❌ 不要动 `~/.agents/skills/`（Guix Home immutable）
- ❌ 不要碰 uncommit 的 git 文件
- ❌ 不要 push 到 remote
- ❌ 不要用 Jev 判「该不该合并」——成对相似度偏保守，合并归 curator LLM pass
- ✅ 脚本 bug、阈值、白名单可以直接改
- ✅ 真正拿不准的，给我选项让我决定
