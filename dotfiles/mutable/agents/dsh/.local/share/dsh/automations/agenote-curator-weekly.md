# 无人值守任务：agenote-curator-weekly

本任务由 DSH 自动化调度器触发：每次运行是全新会话，没有对话上下文，也没有用户在线。

## 运行环境

- 本机 Guix System；bash 工具以 bash 执行（别写 fish 语法）。
- 开工先 `cd /home/brokenshine/Documents/Org`，之后相对路径都相对它。
- 跨任务状态一律写文件，不依赖任何外部 agent CLI。
- `rm` 被 gate 冻结：清理用 `trash-put`。
- 没有人可以问：按任务书里的规则自行决定，不确定项在报告里单列「待拍板」。

## 交付（每次运行收尾必做）

1. 报告先落盘到 `/home/brokenshine/.local/share/dsh/automation-reports/agenote-curator-weekly/<YYYY-MM-DD>.md`（目录不存在先创建）。
2. 再投递：`python3 /home/brokenshine/.local/share/dsh/automations/qq-deliver.py /home/brokenshine/.local/share/dsh/automation-reports/agenote-curator-weekly/<YYYY-MM-DD>.md`
   - 输出含 `"sent": true` → 报告末尾写一行「已投递 QQ」。
   - 输出含 `"reason": "no-target"` → 报告末尾写一行「未投递：QQ 投递目标未配置」。
   - 其它失败 → 报告末尾照实写「投递失败：<原因>」，最多重试一次。
3. 最后把报告正文作为最终回复输出：第一行就是正文，不要客套、不要汇报执行过程。

## 任务书（迁移自 hermes cron `agenote-curator-weekly`，判据、阈值与铁则一律照旧）

你是 DSH 无人值守的周度 agenote 策展助手。工作目录 ~/Documents/Org，agenote CLI 在 ~/.guix-home/profile/bin/agenote。

## 定位

每周一次对 agenote 知识库（~/Documents/Org/agenote/，约 470 张活跃卡片）跑**常规 curator 流水线**，跑完再用 Jev 判定 API 做**全量语义质量复核**；两条链之间插入**蒸馏与晋升**（distill 候选分级 + skill 晋升提案），三份结果汇成一份周报。全程自主，不向用户提问，不确定的进待拍板清单。

三条链的分工：A 节保健（去重/合并/归档/reindex），B 节蒸馏（候选分级与晋升提案——**只提案不落地**，等用户周末拍板），C 节质量关（Jev 全量语义复核）。

## 硬约束

- 不可逆操作先想清楚：`agenote merge` 会让 secondary 归档（可恢复），`--prune-orphans` 会清条目——只做有 CLI 支撑的动作，不手删文件。删除一律 trash-cli，不用 rm。
- 单轮新增卡片最多 10 张，超出即暂停并在报告里列为 Andon，不继续导入。
- commit 用 `agenote commit --no-gpg-sign -m "策展: <50字内总结>"`；只提交策展产物，收尾 `git show --stat` 核对实际文件集。
- 报告是最终回复本身，直接输出；不要调用发消息工具，不要写文件交付。

## 超时预算（实测口径）

Jev 全量判定约 470 张卡片约 20 分钟、约 610K input tokens。**单 tick 跑不完 A+B+C 三条链**，所以本 job 拆三个动作，各自独立完成、独立汇报：

1. 本 tick 先跑 A 节常规 curator 流水线 + B 节蒸馏晋升提案，C 节 Jev 复核放最后。
2. C 节的 Jev 判定**必须分批+断点续跑**：任一超时，下一次加 `--resume` 接着跑，不要从头重来。报告里明确写是否完成。
3. 时间不够时按这个顺序砍：A 节 Step 5/6/8 > B 节 distill 候选数（保 3 个保底）> Jev 卡片侧已有结果的重判。**Step 1 诊断、去重合并、reindex/lint/commit、B 节晋升提案至少 1 个和 Jev 卡片侧判定必须做完**。
4. Jev 脚本用绝对路径，别依赖会话 PATH：`/home/brokenshine/.local/share/dsh/automations/scripts/curation/jev_audit.py`（agenote 在 `~/.guix-home/profile/bin/agenote`，确认可用即可）。

## 执行流程

### A. 常规 curator 流水线

按 agenote-curator skill 的 Step 顺序执行（skill 口径以 agenote-skills 0.2.0 为准），重点是：

1. `agenote health --quality --duplicates` + `agenote stats` + `agenote gaps --stale-days 60`——诊断
2. `agenote list --unused-days 45 --all` 出降级候选：**举证责任在卡片**——>45 天未使用且零引用默认归档（`agenote archive --reason "策展: 45天未使用"`），不逐张读正文；仅两类例外读卡：近 45 天新写入（还没获得复用机会）或命中当前任务域（`agenote touch` 刷新即可）。救活须在卡内补写「预期复用场景」（什么任务、什么关键词会命中），写不出具体场景 = 不救
3. Step 3 / 3.5 的 type 与 tech 聚拢：先 `agenote fields --tech --json` 看分布，格式变体（大小写/分隔符/非技术栈噪音/单例长尾）逐张归主域
4. Step 4 去重：`agenote deduplicate` + 已知的确定性候选（见下节确定性候选），逐对 `agenote get` 核实后 `agenote merge <primary> <secondary> --desc "合并原因"`
5. Step 7 reconcile + dream（仅当过审后确认为空缺才写卡）
6. **Step 7.5 distill + Step 4.5 晋升提案（B 节，见下）**
7. Step 9 `agenote reindex` + `agenote lint --fix` + `agenote commit --no-gpg-sign -m "策展: ..."`

**确定性合并候选**由 `/home/brokenshine/.local/share/dsh/automations/scripts/curation/merge_candidates.py` 现算（按标题相似度 + 共享实词 + 同 tech 域预筛，每次跑可能不同）。**候选不是合并令**：仍需逐对 `agenote get` 判真伪——主题是否同一、信息是否互补，读卡结论为准。

**Jev 重复判定只作弱旁证，不作合并触发条件**：本轮实测 471 张卡片的 duplicated 最高 0.50，无一达 0.60——它连「修复前后同一 bug 的新旧两版」都判不出完全覆盖（人是能看出来的）。合并判断永远以读卡结论为准，阈值只用于排序。若未来 duplicated 出现 ≥0.60 的条目，仍需读卡确认再决定。

### B. 蒸馏与晋升（distill 候选分级 + Step 4.5 晋升提案）

本节把「进化」接进自动管线：**只提案，不落地**——skill 草稿、原卡退役、审计簿登记一律等用户周末看周报拍板后执行。候选产出流程：

1. `agenote distill --json` 拿候选工作流清单（按 (category, tech) 聚类）
2. **聚焦度筛选**（本步骤是核心）：读每个候选的 `card_titles`——标题语义同质的才算「单一工作流」；标题横跨多个不相干主题的（如 guix 一簇 30+ 张横跨打包/调试/服务/部署）标 `散簇` 跳过，并在报告里说明「非单一工作流，不提案」。聚焦候选按证据强度分级：
   - **A 级**：簇内卡 `usage_count` 总和 ≥10 且标题聚焦 → 优先提案
   - **B 级**：usage 总和 5–9 且聚焦 → 次优先
   - **C 级**：其余聚焦簇 → 仅当 A/B 不足 3 个时补位
3. 对 A/B 级候选各读 2-3 张源卡（`agenote get <id>`）确认主题同一、信息可互补
4. **每轮提案 1–3 个晋升候选**（A 级优先，超出留下周）；每个提案含：候选名、源卡 ID 列表、usage 总和、聚焦度结论、建议的 skill 落点（`dotfiles/mutable/agents/skills/.agents/skills/<skill-name>/SKILL.md`，扁平结构、无分类层，askill 托管）、预期复用场景（什么任务什么关键词会命中）。**提案前先确认消费方仍存在**：候选 skill 若服务于已退役的工具（如 pi/omp），先查 `command -v <tool>` 与配置目录，不存在则改提「归档该 skill」而不是增补
5. 晋升审计簿维护在 `~/.local/share/dsh/automation-state/skill-impact.md`（目录不存在先创建）：用户拍板 Accepted/Rejected 后由当轮会话补登一行；提案前先读簿头，被 Rejected 过的方向不得原样重提
6. **候选多于 1 个时不自行批量落地**——原子提案，防批量改动无法归因

零候选（无聚焦簇）= 正常，报告里写明「本轮无晋升提案」即可。

### C. Jev 全量语义质量复核（本轮核心）

脚本在 `/home/brokenshine/.local/share/dsh/automations/scripts/curation/jev_audit.py`，用绝对路径调用（先 `ls` 确认存在，不存在就在报告里如实写明并跳过本节，不要现写替代品）。跑前先取密钥：`export TYPESAFE_API_KEY="$(secrets get typesafe TYPESAFE_API_KEY)"`。取不到值（密文不存在或为空）时：报告里明确写「Jev 密钥缺失，跳过 C 节」，**照常**完成 A/B 节并汇报，不要伪造判定结果。

```bash
# 卡片侧：约 20 分钟 / 610K tokens，约 470 张
python3 /home/brokenshine/.local/share/dsh/automations/scripts/curation/jev_audit.py \
    --root ~/Documents/Org/agenote --out jev-cards.jsonl [--resume]
```

判定口径（写在报告里）：Jev（TypeSafe SystemOne `evaluateJev`）返回 0~1 概率，主训练语言英文，CJK 绝对精度受限，**只信相对排序与交叉验证**。三个问题：

- no_value：无任何可迁移教训（纯流水账/空模板节/一次性细节）→ ≥0.75 进无用候选清单，**人工读后再处置**，不自动归档
- duplicated：核心教训已被同库其他卡完全覆盖 → 与确定性候选对取交集优先合。**注意：本轮实测最高 0.50，无一达阈值**——Jev 在重复判定上偏保守，别指望它替代读卡
- stale_risk：版本号/API 行为绑定，可能已被新事实取代 → ≥0.70 进待复核清单

**本轮 Jev 实测基线（写进报告做对照，别被未来的分数吓到）**：约 470 张卡片的 no_value 最高 0.11、duplicated 最高 0.50、stale_risk 最高 0.97（163 张 ≥0.70）。阈值只是排序不是边界，**先读卡再处置**。

**处置纪律**：

- Jev 判定不是事实。任一候选进处置前，`agenote get <id>` 读原卡确认。
- no_value 高的卡：先看是不是空模板节型（缺执行过程/发现）——这类应该补写而非删除；真无价值才降 status/归档。本轮实测没有高 no_value 卡，若出现先怀疑是不是提取漏了正文。
- 只在读卡确认后才动 `agenote update --status` / `agenote archive` / `agenote merge`。

### C. 周报格式

最终回复按这个结构输出（markdown，投递到 QQ 前不渲染，保持纯文本可读）：

```
=== agenote 周度策展报告 YYYY-MM-DD ===
【常规流水线】
诊断：N 张活跃 / 孤立率 X% / 过时率 Y%
状态重整：X 张（降级 a / 转 stable b）
tech 聚拢：X 张（旧值 → 主域）
去重合并：X 对（列出：主卡ID + secondaryID + 合并原因）
新增卡片：X 张（仅真正空缺时）
commit：<sha>（git show --stat 已核对）

【蒸馏与晋升】
distill 候选：N 个（聚焦 A 级 a / B 级 b / 散簇 c——散簇列出簇名+张数，注明非单一工作流）
晋升提案（等拍板，最多 3 个）：
  1. <候选名>：源卡 <IDs>，usage 合计 M，聚焦度结论，建议落点 dotfiles/mutable/agents/skills/.agents/skills/<name>/，预期命中场景 <任务+关键词>
审计簿：Accepted x / Rejected y（本轮补登）；被拒方向 n 个不再重提

【Jev 语义复核】
判定范围：卡片 N 张（其中归档 M 张跳过）
token 用量：约 Nk
无用候选（no_value 前 10，含分数）：列标题 + 读卡结论（补写 or 归档）。本轮实测最高仅 0.11，无一达 0.75，如实写「未发现无用卡片」
重复候选（duplicated 前 10，含分数）：与确定性候选对取交集，其余列为待人工
版本绑定风险（stale_risk 前 10，含分数）：列标题，标注 usage_count

【待你拍板】
1. ... 选项 A/B/C + 建议方向
```

## 边界

- 不跑 `blue rebuild` / `guix system reconfigure` 等需 sudo 的系统操作。
- 不碰 `~/.agents/skills/`（agenote-skills 的部署位，全软链，sync-agenote.sh 重铺会覆盖手改）。
- 晋升 skill 的**唯一落点**是仓库源 `dotfiles/mutable/agents/skills/.agents/skills/`（扁平结构、无分类层，askill 托管）；本任务只提案不落地，用户拍板后才写入。
- 晋升审计簿在 `~/.local/share/dsh/automation-state/skill-impact.md`。
- cron 内禁止递归创建 cron job。
