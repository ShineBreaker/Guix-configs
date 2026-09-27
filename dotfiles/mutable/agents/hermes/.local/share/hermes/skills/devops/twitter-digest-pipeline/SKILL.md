---
name: twitter-digest-pipeline
description: "X 日报管道的维护与调优：信息源、jev 阈值设计、出图与预览验收。"
---

# X（推特）日报管道

每日从关注账号抓推文 → jev 价值判定 → 组装中文日报 markdown → 渲染成一张竖长图投递到 QQ。

## 位置

- 脚本：`$HERMES_HOME/scripts/twitter-digest/`（dotfiles 源在 Guix-configs `dotfiles/mutable/agents/hermes/.local/share/hermes/scripts/twitter-digest/`，stow 直链，改源即生效）
- 状态：`$HERMES_HOME/state/twitter-digest/{new,scored,picked,raw,trends,errors}/`
  - `trends/YYYY-MM-DD.json` 是 `explore` 子命令产出的趋势与 Today's News 标题，不是推文，喂不进 jev

- cron prompt 源：`dotfiles/mutable/agents/hermes/.local/share/hermes/cron-prompts/twitter-digest.md`
- cron job（**拆成两个：抓取与投递分离**）：
  - `twitter-digest-nightly`（抓取 + jev + 加工 + 渲染）：每天 03:00，`--deliver local`（不投递）。渲染完必须把成品路径写进本 job notepad：
    ```bash
    hermes cron notepad <job_id> set last_image /tmp/digest-render/digest-md-D.png
    hermes cron notepad <job_id> set last_date "$(date +%F)"
    ```
  - `twitter-digest-deliver`（投递）：每天 08:00，`--deliver qqbot`。读 notepad → 校验路径非空、文件存在且 >10KB → 最终回复就是 `MEDIA:<路径>`；校验不过报 `[日报投递失败] <原因>（期望路径：<path>）`，不拿旧图顶上、不自己重跑管道。
  - 拆开的原因：抓取跑十几分钟到半小时（几百个账号分批 + jev 逐批调 API），若 08:00 才开始跑，用户收到图可能是八九点；凌晨跑完、早上只做文件检查，8 点整准时。
  - prompt 源：`cron-prompts/twitter-digest.md`（抓取）、`cron-prompts/twitter-digest-deliver.md`（投递）
- **cron job 存内联 prompt 快照**：改 prompt 源后必须 `hermes cron edit <id> --prompt "$(cat <prompt 源>)"` 才生效（`$HERMES_HOME/cron/jobs.json` 是权威源，executions.db 无 prompt 列）。id 用 `hermes cron list | grep twitter-digest` 查。
- **cron prompt 与脚本子命令必须同步**：脚本删掉 `fetch` 子命令（2026-09-26，被 `feed --source following` 取代）后，prompt 里若还写着 `twitter_batch.sh`，job 会执行一个不存在的脚本。改脚本入口的同时改 prompt 源并重新 `hermes cron edit`。
- 报 `git commit 必须使用 -m 指定提交信息`：仓库的 `~/.config/git/hooks/prepare-commit-msg` 指向已不存在的 agenote 插件路径，`-F` 被拦。用 `-m` 分段提交。

## 信息源清单（现有 `fetch` 只用了第 1 个）

qid 会随 X 发版失效；失效时按 `web-data-harvesting` 的 `references/webpack-chunk-manifest.md` 重挖。

| 源 | 端点 | 登录态 | 实测规模 |
| --- | --- | --- | --- |
| 关注账号时间线 | `UserTweets` `jeAA-59Y9FL7FmjgBNIVPw` | 必须 | 每账号 ~20 条，224 账号分批 |
| For You 个性化推荐 | `HomeTimeline` `og4a4SdSF3WiQkkwaPCdPg` | 必须 | 单次 ~38 条，多数来自非关注账号 |
| Following 时间线 | `HomeLatestTimeline` `OQPHTgwczzp9RMAPt6BH9A` | 必须 | 单次 ~113 条，与 UserTweets 高度重叠但一次拿全 |
| 趋势 + Today's News | `ExplorePage` `7JBlImZfRkZIptknshoqCA` | 必须 | 30 条趋势 + AI 新闻标题 + 高热推文 |
| 趋势（轻量） | `1.1/trends/place.json?id=<woeid>` | guest 可 | 全球 1 / 美国 23424977 / 日本 23424856 |

- **推荐流条目带 `injectionType`**（`ForYouPhoenixRetrieval` / `ForYouSimclusters` / `ForYouInNetwork`），这是区分「算法推荐」与「关注网络」的唯一字段；引入推荐流时按它过滤或标注，别把两类混成同一条。
- 新端点响应与 `UserTweets` 结构兼容（`legacy.full_text` / `favorite_count` / `extended_entities.media` / `core.user_results`），`_extract_media()` 可直接复用；推荐流多一个 `views` 字段，现有 state 未存。
- **`ExplorePage` 的 Today's News 是 `is_ai_trend` 的 `TimelineTrend`，不是推文**：没有 `full_text` 和媒体，不能直接当日报条目，只能当要闻线索。要展开成正文需 `SearchTimeline`，该端点已 404。
- **guest 态 `UserTweets` 只返回账号精选/pinned 面板**（高赞老帖、约 98 条封顶），不是最新时间线。缺 cookie 时日报会静默变成老内容——显式报「凭据缺失，跳过本次」，不要退 guest 糊盖。

## 三个信息源

| 子命令 | 端点 | 特点 |
|---|---|---|
| `fetch` | UserTweets（逐账号） | 224 账号分批 + 断点续跑；慢但可恢复 |
| `feed --source for-you` | HomeTimeline | 一次拿整条推荐流，**含非关注账号**；只有一页，不能续跑 |
| `feed --source following` | HomeLatestTimeline | 关注账号最新推文，一次拿全；与 fetch 高度重叠 |
| `explore` | ExplorePage | 趋势 + AI 生成的 Today's News + 高热推文；趋势单独存 `trends/` |

```bash
python3 $HERMES_HOME/scripts/twitter-digest/twitter_fetch.py feed \
  --state-dir $HERMES_HOME/state/twitter-digest --source for-you --count 40
python3 $HERMES_HOME/scripts/twitter-digest/twitter_fetch.py explore \
  --state-dir $HERMES_HOME/state/twitter-digest
```

- 除 `fetch`（guest 只能拿精选面板）外都**必须登录态**：先 `secrets decrypt twitter-x`。
- 推荐流实测：约 48 条抓取中约三分之一来自非关注账号，jev 过筛约 21 条——关注列表外的
  AI 工具/生态内容主要靠它补。
- queryId 会随 X 发布滚动失效（404 且 body 为空）。更新办法见
  `web-data-harvesting` skill 的 `references/webpack-chunk-manifest.md`。
- **逐账号抓取已废**：`fetch` 子命令与 `twitter_batch.sh` 于 2026-09-26 删除。
  224 账号 × 2s 分批跑实测每天只覆盖 11 到 14 个账号（9 天才一轮），而
  `feed --source following` 一次调用拿到 99 条、覆盖全部活跃账号。别再把
  分批机制加回来。
- **`promoted-` 前缀的 entry 是广告**，与普通推文同为 `TimelineTweet`，只能靠
  entryId 挡；`test_feed_parse.py` 里有对应断言。

### 预览 / 试跑一条扩充后的日报

用户临时要看某天效果时，不必等 cron：手动跑 `digest_build --top N` 拿素材 → 写中文日报
markdown → `digest_render.py` 出图 → 直接以 `MEDIA:<png>` 作为最终回复（走 QQ 投递）。
注意别把 notepad 的 `last_image` 指向这张预览图，否则次日 08:00 的投递 job 会重发它。

## 四步流程

```bash
python3 $HERMES_HOME/scripts/twitter-digest/twitter_fetch.py fetch \
  --state-dir $HERMES_HOME/state/twitter-digest --since-days 2 --count 20 --logged-in --resume --interval 2
python3 $HERMES_HOME/scripts/twitter-digest/jev_score.py score \
  --input $HERMES_HOME/state/twitter-digest/new/<date>.json --state-dir $HERMES_HOME/state/twitter-digest
python3 $HERMES_HOME/scripts/twitter-digest/digest_build.py build \
  --state-dir $HERMES_HOME/state/twitter-digest --top N
python3 $HERMES_HOME/scripts/twitter-digest/digest_render.py md daily.md \
  --variant D --title 日报 --state-dir $HERMES_HOME/state/twitter-digest --date <date> --top N --out <png>
```

- 抓取分批断点续跑（`--resume`）：progress 里已完成的账号会被跳过，想全量重抓先清断点文件。
- **`--top` 两边必须同值**：`digest_build` 导出的图片编号与 `digest_render` 渲染时重算的编号按同一算法（picked 顺序 + URL 去重）各自计算，不一致就图文错位。prompt 里把同一个数写死。
- 渲染细节（HTML 模板、chromium headless 截图、Guix 字体、HTML 实体双重转义）见 `hermes-cron-ops` 的 `references/image-report-rendering.md`，此处不重复。
- **成品长图必须逐段 vision 验收后才发**：竖长图动辄 7000+ px，整图丢给 vision 会被降采样，小字和图内截图全糊。用 PIL 切成 2~3 段（每段 ≤2400 px 高）分别检查：文字截断/溢出、分组标题、`![imgN]` 是否嵌对位置、有无缺字形方块。验收通过才发 `MEDIA:`。
- **临时预览不要污染 notepad**：手动渲染一张给用户看效果时，别把 `last_image` 指向它，否则次日 08:00 的投递 job 会重发这张预览图。
- **成品长图要逐段 vision 验收再发**：竖长图动辄 7000+ px，整图丢给 vision 会被降采样，
  小字和图内截图全糊。用 PIL 切成 2~3 段（每段 ≤2400 px 高）分别看：文字截断/溢出、
  分组标题、`![imgN]` 是否嵌对位置、有无缺字形方块。验收通过才发 `MEDIA:`。

## jev 阈值设计（最容易被改坏的部分）

判据按踩过的坑排列，全部有实测支撑：

1. **score 类型返回 0~2 连续置信度，不是 0/1/2 三档离散分**（实测 217 条仅 13 条落整数档）。`signal >= 1.0` 的语义是「置信度 ≥ 50%」，不是「满分」。
2. **主观质量判断没有决策边界**。「值得读吗 / 新信息量多少」头部与中部只差 0.2，jev 给平滑连续值。要改问**可判定的硬问题**：有没有硬事实、是不是新闻、是不是官宣。
3. **不设主题门槛**。日报不限领域：政策、法律、商业、健康、社会事件只要有信息量就进。判据是「发生了某件可陈述的事实」，不是「是否与某主题相关」。用受众相关性做门槛会把重大新闻整批挡掉。
4. **「无数字但有实质」不能设硬门槛**。架构说明、工具改版、踩坑记录的 noul 天然给低分但有工程价值；这类信号只参与 composite 排序，不设准入门槛。
5. **官宣必须走旁路**。"X is now available" 这类发布句式信息密度天然低，signal/worth 双保底叠加会把发布事实本身卡掉——实测发布日只剩测评进日报、官宣反被淘汰。设 `is_release` 判定，命中即绕过 signal/worth。
6. **官宣的后续侧面靠 `is_news` 高分区放行，不要靠 `is_release` 碰线**。榜单成绩、官方说明、实测反馈本身不是官宣，`is_release` 常判成 0.1~0.5；jev 给的是连续置信度，0.49 与 0.51 没有实质区别，把旁路门槛压在 0.5 会随机漏。加一条 `is_news >= 0.85` 同样走旁路（发布事件的各侧面都放进来，由 prompt 的合并规则收成一条）。
7. **单账号批量灌水靠账号级 mute，不靠 jev**。"JUST IN:" 快讯号一次能贡献十几条同质内容，逐条判断挡不住这种规模。mute 放在 `cmd_fetch` 的唯一入口（`--handles` 显式传入也拦得住），mute 表每条写清理由。
8. **composite 归一到 0~1**：signal/novelty 是 0~2 量纲，不归一化排序会被量纲带着跑。

改完阈值后的验证流程见 `references/jev-calibration.md`。

## 日报加工规则（写进 cron prompt 的铁则）

- **同一事件只出一条**。官宣、官方说明、评测、实测、体验说的若是同一件事，合成一条：先写事件本身（什么、何时、关键参数），再补各方提供的新增信息并标注来源。判断标准是「读者是否会觉得在读同一条新闻的重复」。
- **不设字数上限**。有价值的消息多就多写，图长一点不影响阅读。删条目的唯一标准是「没有信息量」，不是「太长了」。
- **分组名按当天实际内容自定**，不写死 AI 专属分组名；出现政策/商业/健康/社会新闻就用对应组名。宁可分组少，不要硬凑。
- 「要闻」保持编号列表（30 秒速览区），正文分组才用卡片。
- 图内只放消息内容，执行说明不发；成品一律单张整图，不分割。

## 卡片式排版

每条正文独立卡片：ivory 填充从暖纸底浮起、无闭合描边、6px 圆角。序号做成正文上方的小标签（17px 灰），**不要**用右上角绝对定位的大数字——长文案会逼文字让位，且低透明度下几乎看不见。

## Pitfalls

- **先看排期再看内容**。排查「为什么发了三次」这类问题时，`hermes cron list` 的 schedule 是第一现场：排期是 `0 1,3,5,7,9,11 * * *` 就会一天发六次，四份产出 md5 不同是四轮独立抓取，不是重复投递。调试期为多轮验证临时放宽的排期，调试结束要缩回去；改 job 名字为 nightly 就要核对排期是否真的一天一次。
- 后台 / nohup 起的进程 PATH 可能不含 `~/.local/bin`，`hermes` 命令要用绝对路径 `$HERMES_HOME/hermes-agent/venv/bin/hermes`。
- **仓库里 `git commit -F <file>` 可能被 hook 链拦死**：`core.hooksPath` 指向的 `prepare-commit-msg` 等软链若目标缺失，`-F` 会被判成「必须使用 -m」而提交失败，报错与 message 内容无关。直接用多条 `-m` 分段提交绕开失效 hook。
- `hermes cron run` 报 "already being fired by the scheduler"：先 `hermes cron history <id>` 看有没有 running 实例。父 shell 退出后实例可能变成孤儿继续跑，也可能被 terminal 进程清理连带杀死、执行记录永久卡 `running` 且无产出。调度器状态不可靠时直接手动跑四步更稳。
- 新建脚本在部署位不会自动建软链（stow 只认已有文件），手工补链后提醒用户跑 `blue home` 让 stow 认领。
- **仓库里 `git commit -F <file>` 可能被 hook 链拦死**：`core.hooksPath` 指向的
  `prepare-commit-msg` 等软链若目标缺失，`-F` 会被判成「必须使用 -m」而提交失败。
  直接用 `git commit --no-gpg-sign -m "<title>" -m "<body>"`（多条 `-m` 分段），
  绕开失效 hook。
- **ExplorePage 的 `SearchTimeline` 打不通**（404，X 已挪端点）：趋势名拿得到，但
  "点进趋势看推文"这条链断了。趋势只能当要闻线索，正文仍靠 feed/explore 的推文。
- **ExplorePage 的 `trending` 段返回空**（`GenericTimelineById` 对 trending/news/sports
  的 timelineId 全返回 0 entries 或 Internal server error），只有 `initialTimeline`
  的 for_you 段有数据。别在这上面浪费时间。
- **`CombinedLists` 需要 viewer userId**（422 `variable "userId" must be defined`），
  本账号实测无 list，未继续挖 ListLatestTweetsTimeline。
