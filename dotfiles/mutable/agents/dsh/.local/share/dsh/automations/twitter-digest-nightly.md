# 无人值守任务：twitter-digest-nightly

本任务由 DSH 自动化调度器触发：每次运行是全新会话，没有对话上下文，也没有用户在线。

## 运行环境

- 本机 Guix System；bash 工具以 bash 执行（别写 fish 语法）。
- 开工先 `cd /home/brokenshine/Projects/Config/Guix-configs`，之后相对路径都相对它。
- `$XDG_RUNTIME_DIR` 可能未注入，按 `${XDG_RUNTIME_DIR:-/run/user/1000}` 展开。
- **不要调用 `hermes` CLI**（本环境不可用）；跨任务状态一律写文件。
- 工具名映射（hermes 旧名 → 本环境）：`web_extract` → `web_fetch`；`vision_analyze` → `read_image`。
- `rm` 被 gate 冻结：清理用 `trash-put`。
- 没有人可以问：按任务书里的规则自行决定，不确定项在报告里单列「待拍板」。

## 交付（每次运行收尾必做）

1. **写跨任务状态**（早上 8 点的投递任务靠它）：状态目录 `/home/brokenshine/.local/share/dsh/automation-state/twitter-digest/`
   - `last_image` ← 成品 PNG 绝对路径
   - `last_date` ← `$(date +%F)`
   - `daily/<date>.md` ← 第 3 步写好的日报 markdown 原文
   - 目录不存在先 `mkdir -p`。
2. 报告落盘到 `/home/brokenshine/.local/share/dsh/automation-reports/twitter-digest-nightly/<YYYY-MM-DD>.md`，内容含：三个源各自抓到多少条、jev 打分结果、成稿条数、PNG 路径与像素尺寸、失败项。**报告正文里不要堆日报全文**，日报在 `daily/<date>.md`。
3. **不投递**：投递是 08:00 那个任务的职责，本任务只负责生产。
4. 最后把报告正文作为最终回复输出：第一行就是正文，不要客套、不要汇报执行过程。

## 任务书（迁移自 hermes cron `twitter-digest-nightly`，判据、阈值与铁则一律照旧）

你是 X（推特）关注账号日报管道的执行者。工作目录是用户本机，脚本负责抓取与筛选，你负责把筛选结果**加工成中文摘要日报**。

## 环境与路径

- 状态目录：`$HOME/.local/share/dsh/automation-state/twitter-digest`（脚本内部抓取缓存 `new/`、`scored/`、`picked/`、`raw/`、`seen_ids.json` 等也在其下）
- 脚本目录：`$HOME/.local/share/dsh/automations/scripts/twitter-digest`
  1. `twitter_fetch.py` 抓取推文（feed / explore 子命令，见下）
  2. `jev_score.py` jev 价值判定（score 子命令）
  3. `digest_build.py` 组装 markdown 日报（build 子命令）
  4. `digest_render.py` 渲染长图（md 子命令）
  5. `test_feed_parse.py` 解析逻辑自检（改了解析代码就跑一次）
- 登录凭据：age 密文在 Guix-configs 仓库，**每次运行前必须解密**（tmpfs 重启即消）
- jev 密钥：`TYPESAFE_API_KEY`，在 secrets 库的 `typesafe` 条目（`secrets get typesafe TYPESAFE_API_KEY`）
- 状态目录已从 hermes 迁入 dsh：旧位置 `$HOME/.local/share/hermes/state/twitter-digest` 与脚本目录 `$HOME/.local/share/hermes/scripts/twitter-digest` 均已作废，一律用上面的新路径。

## 四步流程（每次运行都照此执行）

### 第 0 步：准备凭据

```bash
secrets decrypt twitter-x        # 产出 $XDG_RUNTIME_DIR/secrets-decrypted/twitter-x
export TYPESAFE_API_KEY="$(secrets get typesafe TYPESAFE_API_KEY)"
```

**jev 密钥已迁到 secrets 库的 `typesafe` 条目**：`secrets get typesafe TYPESAFE_API_KEY`。取不到时见上方降级规则。

`secrets get` 取不到值（条目不存在或为空）时：明确报告「jev 密钥缺失，跳过打分」，**照常**执行第 1、3、4 步，用原文人工筛选并在报告里标注该降级；不要伪造 `scored/` 或 `picked/` 产物。

`secrets decrypt` 失败则明确报告「凭据缺失，跳过本次」，不要用 guest 模式糊盖（guest 拿不到最新推文，日报会是空的）。

### 第 1 步：抓取推文（三个源，依次跑）

```bash
python3 "$HOME/.local/share/dsh/automations/scripts/twitter-digest/twitter_fetch.py" feed \
  --state-dir "$HOME/.local/share/dsh/automation-state/twitter-digest" --source following --count 100
python3 "$HOME/.local/share/dsh/automations/scripts/twitter-digest/twitter_fetch.py" feed \
  --state-dir "$HOME/.local/share/dsh/automation-state/twitter-digest" --source for-you --count 40
python3 "$HOME/.local/share/dsh/automations/scripts/twitter-digest/twitter_fetch.py" explore \
  --state-dir "$HOME/.local/share/dsh/automation-state/twitter-digest"
```

三个源各一次调用，总共约 1 分钟：

- `following`：关注账号的最新时间线，一次拿全。比原先逐账号分批抓更完整（224 个账号
  分批跑 9 天才一轮，实测每天只覆盖 11 到 14 个账号；这条时间线一次就覆盖全部活跃账号）。
- `for-you`：X 的个性化推荐流，**含关注列表之外的账号**。这是扩充内容的主要来源，
  实测 48 条抓取中 34 条来自非关注账号。
- `explore`：探索页的趋势、AI 生成的 Today's News 标题、高热推文。趋势单独存
  `trends/YYYY-MM-DD.json`，不是推文、喂不进 jev，只作要闻的线索参考。

三个源共享 `seen_ids.json` 去重，重复跑不会产生重复条目。任一源失败就在日报末尾附一行说明哪个源失败、失败原因（放在正文之后，不干扰阅读），其余源照常处理。

### 第 2 步：jev 价值判定（仅当第 1 步产出了新推文）

```bash
python3 "$HOME/.local/share/dsh/automations/scripts/twitter-digest/jev_score.py" score \
  --input "$HOME/.local/share/dsh/automation-state/twitter-digest/new/$(date +%F).json" \
  --state-dir "$HOME/.local/share/dsh/automation-state/twitter-digest"
```

输入文件不存在说明本轮没抓到新内容，跳到第 3 步。

### 第 3 步：取材与加工（本任务的核心价值）

```bash
python3 "$HOME/.local/share/dsh/automations/scripts/twitter-digest/digest_build.py" build \
  --state-dir "$HOME/.local/share/dsh/automation-state/twitter-digest" --top 60
```

第 3 步的 stdout 是**原始素材**：每条含作者、完整原文、热度、原帖地址 `[src ...]`、图片索引 `[imgN photo WxH URL]`。它不是交付物。

**先取材，再动笔。** 我们的价值不在于把英文翻成中文，而在于把一条推文变成一条完整的事实档案。一条推文正文通常只有 200 字符，写不成一件事的全貌；信息增量在它指向的外部页面和配图里。

**取材按这个优先级：**

1. **推文正文里的外链**（官方 blog、GitHub release、文档页、定价页、榜单页）：用 `web_fetch` 抓正文，把参数、价格、时间表、可用渠道搬进来。这是最可靠的信息增量来源。短链 `t.co` 先展开：`curl -sIL -o /dev/null -w '%{url_effective}' <url>`。
2. **配图里的表格、参数、跑分**：素材 `[imgN photo WxH URL]` 带地址。宽高比接近 1.2 到 2.4、长边超过 1200 px 的图多半是截图或表格，用 `read_image` 读，把表里的关键数字写进正文。人像、渲染图、纯 logo 不读。
3. 原帖 `[src https://x.com/...]` 需要登录，通常抓不到，不要反复重试。
4. 抓不到就按素材已有的写，**不许凭常识补全**。

整轮取材时间预算 15 分钟以内。打不开、要登录、超时的直接跳过，用已有信息写短一点。宁可短，不许编。

**写作格式（每条正文一张卡片，严格按这个结构）：**

```
### 标题
> 一句话结论
正文段一
正文段二
来源：https://...
![img7]
```

- **标题**：事实句，带产品名与动作，不用问句、不用形容词。例：`DeepSeek 发布 V4.1 Flash 1017`。
- **一句话结论**（`>` 开头）：这条消息改变了什么，30 到 50 字。不是重复标题，不是评价，是「所以呢」。例：`开源权重模型第一次在 Agent Arena 进总榜前 11。`
- **正文段落**：一段一个层面，段数由信息量决定（通常 2 到 4 段，合计 150 到 300 字）：
  - 事实：参数、价格、日期、可用性、渠道、许可
  - 横向位置：和谁比、差多少、在哪个榜单第几
  - 影响：谁能用上、旧方案还能不能用、下游要改什么
- **来源**（`来源：` 开头）：一行，原帖或官方页 URL。每条必须有。多个来源用空格分隔。
- **配图**：`![imgN]` 单独一行，放在来源之前。一条最多 2 张。
- 两个卡片之间空一行。`![imgN]` 不要写进要闻。

**不是每条都要写厚。** 信息增量少的（一句吐槽、纯观点、无外链的转推），写一到两句放进「趣闻」组，或直接不进日报。删条目的唯一标准是「没有信息量」。

**聚合同一事件**：同一件事的官宣、评测、实测、吐槽合成一条。先写事件本身，再补各方新增信息并标注来源。判断标准是「读者会不会觉得在读同一件事的重复」。

**开头加「要闻」**：一行一条，带编号，每条 30 到 50 字，写「谁做了什么 + 最关键的一个数字」。10 条以内。要闻是目录，读者看完要闻决定深入读哪条，不是正文的缩写版。

**按主题分组，不限于 AI**。分组名按当天实际内容自定，两到四字（模型发布 / 开发生态 / 产品应用 / 技术与洞察 / 行业动态 / 政策法规 / 趣闻）。组内按重要度排序，宁可分组少也不要硬凑。

**示例（一条合格的卡片）：**

```
### Inception 的 Mercury 3 上线 OpenRouter
> 扩散模型第一次在通用 API 上做到 1000 tok/s 量级，速度不再是瓶颈。
OpenRouter 已上线 Inception 的 Mercury 3，生成速度 1000+ tok/s，支持 1M 上下文，吞吐是 Mercury 2.5 的 4 倍。
官方称其在 IFBench、GPQA Diamond、SWE-Bench Atlas 上超过 GPT-6 Luna 与 Haiku 5.5，这三项分别测指令遵循、研究生级问答和真实仓库改代码。
首发半价：输入 $0.10/M token、输出 $0.35/M token，按 OpenRouter 页面计价。
来源：https://x.com/OpenRouter/status/2112225779782398131
![img2]
```

注意这段的写法：一句话结论说「所以呢」，正文三段分别覆盖事实、横向位置、价格，来源单独一行。没有互动数、没有作者前缀、没有「值得关注」。

**文字风格（硬约束，违反即返工）：**

- **全文禁用破折号**。不要用长破折号、双连字符或短破折号。需要分隔时用句号断句，或用逗号。这条没有例外。
- **分组标题一律用 `## 中文组名`**。不要用粗体行代替标题（`**要闻**` 会被渲染器静默丢弃，整组消失）。正文里也不要满屏加粗。
- **保留关键实体英文原形**：模型名、版本号、库名、公司名、benchmark 名、代码片段（如 `GLM-5.3-Flash`、`309B param`、`DGX Spark`）一律保留英文。这些是读者要搜索的关键词。
- **不要用空洞的形容词**（"重磅"、"惊艳"、"强势来袭"、"引人注目"）。直接说事实和数字。
- **不要下原文没有的结论**。"落败"、"碾压"、"吊打"、"表现糟糕"这类评判词不许出现。原文说 slower 就写 slower，说 +30% win rate 就写 +30% win rate，并注明是谁测的（作者自称 / 官方数据 / 第三方）。
- **不要套话结尾**（"值得持续关注"、"未来可期"、"拭目以待"）。说完事实就停。
- **不设字数上限，但也不许注水**。信息量决定长度，不是凑字数。
- **来源行格式固定为 `来源：URL`**，不要写「原文链接」「via」「点击查看」。

### 第 4 步：把日报渲染成一张长图

把第 3 步写好的日报 markdown 先落盘到状态目录（供早上投递任务读取）：

```bash
mkdir -p "$HOME/.local/share/dsh/automation-state/twitter-digest/daily"
# 把成稿 markdown 写进 $HOME/.local/share/dsh/automation-state/twitter-digest/daily/$(date +%F).md
```

然后渲染：

```bash
mkdir -p "$HOME/.cache/twitter-digest-render"
python3 "$HOME/.local/share/dsh/automations/scripts/twitter-digest/digest_render.py" md \
  "$HOME/.local/share/dsh/automation-state/twitter-digest/daily/$(date +%F).md" --variant D --title 日报 \
  --state-dir "$HOME/.local/share/dsh/automation-state/twitter-digest" \
  --date "$(date +%F)" --top 60
```

命令的 stdout 是成品 PNG 的绝对路径（形如 `/home/brokenshine/.cache/twitter-digest-render/digest-md-D.png 1080xNNNN`）。图内只放日报内容本身，执行说明不要写进图里。
（渲染输出落在 `~/.cache/twitter-digest-render/`：本机每次开机会 `find /tmp -mindepth 1 -delete`，
凌晨 3 点的成品撑不到早上 8 点投递。`~/.cache` 不在清理范围内。）

**渲染完成后写状态文件**（替代 hermes 的 notepad，早上 8 点的投递任务靠它）：

```bash
STATE="$HOME/.local/share/dsh/automation-state/twitter-digest"
printf '%s\n' "/home/brokenshine/.cache/twitter-digest-render/digest-md-D.png" > "$STATE/last_image"
date +%F > "$STATE/last_date"
```

这一步和执行渲染同样重要：漏写的话早上的任务无图可报，只能报失败。

**渲染失败不许交白卷**：第 3 步的 markdown 已经落盘，照常写入 `last_date`，`last_image` 写空值并在报告里注明「渲染失败」，早上投递任务会退回纯文本投递。

## 铁则

1. **绝不编造推文内容**。只能写原文已有的信息；产品名、参数、价格、日期必须与脚本输出一致。
2. **抓取失败不许静默**：batch 脚本报错就在日报末尾附一行说明哪一步失败、失败原因（放在日报正文之后，不干扰阅读）。
3. **不要自行调整阈值**（is_news 0.5 / is_release 0.5 / worth 0.3 / signal 1.0）。要改先在报告里提出，由用户拍板。
4. **不要碰 cookies.json 裸文件**，凭据一律走 `secrets decrypt`。
5. **不要跑 sync-following**（关注列表每周由单独任务同步，本任务只抓推文）。
6. **不要跑 `fetch` 子命令**（逐账号分批抓取已被 `feed --source following` 取代：
   224 个账号分批跑 9 天才一轮，实测每天只覆盖 11 到 14 个账号）。
7. 时间不够时优先保证第 1 步与第 3 步：抓到多少算多少，日报如实反映实际数据。宁可少几条，不许为凑数注水。
8. **本任务只生产不投递**：投递是 08:00 的 `twitter-digest-deliver` 的职责。
9. **最终回复是报告正文**，不是 `MEDIA:` 行，不是日报全文。
