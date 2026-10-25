# B 站用户空间动态采集配方

目标形态：抓某个 UP 主（uid）一段时间内的所有动态（发言），输出结构化 jsonl。

## 1. API 文档来源

- **BACNext/BACNext**（`openapi/*.json`，OpenAPI 3.1）：主站 / 直播 / VC / passport 四个文件、
  约 150 个接口的请求参数与响应 schema。**没有现成的「按用户+时间段」发言接口**，要自己拼。
- 已归档的 markdown 版（结构更可读，含示例响应）在
  `BACNext/bilibili-API-collect-backup` 的 `docs/dynamic/space.md`、`docs/user/space.md`。
- 相关接口：`/x/polymer/web-dynamic/v1/name-to-uid`（用户名→uid）、
  `/x/polymer/web-dynamic/{v1,desktop/v1}/feed/space`（用户动态流）、
  `/x/polymer/web-dynamic/v1/detail`（单条详情）。

## 2. 端点与鉴权的实际行为

- **未登录下 `v1/feed/space` 直接 412**（风控页，返回 HTML 而非 JSON）。
- **`desktop/v1/feed/space` 未登录可通**：带 `User-Agent` + `Referer: https://space.bilibili.com/<uid>/dynamic`
  即可，`host_mid` 为被查 uid。v1 的 WBI 签名路径在未登录场景无意义，别在那上面耗时间。
- 关键参数：`features=<逗号分隔功能位>`、`offset=<上一页返回的 offset>`、
  `platform=web`、`web_location=333.1387`、`timezone_offset=-480`。
- 页面大小约 9–12 条/页，`data.has_more` + `data.offset` 决定继续翻。

## 3. 时间窗口过滤

`feed/space` **没有时间参数**，只有游标翻页。做法：从第一页往后翻，逐条取
`modules[].module_author.pub_ts` 与窗口 `[起始日 00:00, 截止日 23:59:59]` 比较。

- 早停用「整页最小 pub_ts < 窗口起点」，不要逐条 break（页内时间非严格有序）。
- 晚于截止日的跳过但继续翻（置顶与新动态）。

## 4. 空页抖动（最大的坑）

desktop 端点会**随机返回空页**：`{"code":0,"data":{"items":[],"has_more":false,"offset":""}}`，
与「真的没有动态」完全同形，实测约三成请求命中。

- 单页重试：最多 6 次，退避 `0.5*(i+1)` 秒；连续空页才判定到底。
- 空页会把 `offset` 清空，若不重试而按空 offset 停，会静默只拿到第一页。
- 用 `seen` 集合按 `id_str` 去重，防止重试造成同页重复入库。

## 5. 正文提取：四个位置都要兜底

desktop 端点返回的是 `modules[]` 数组（v1 是对象键），同一条动态的正文分散在：

| 内容 | 位置 |
| --- | --- |
| 普通文字动态 | `module_dynamic.desc.text` |
| 投票 / 长文 | `module_desc.rich_text_nodes[].orig_text` |
| 投稿视频 | `module_dynamic.dyn_archive`（`bvid`、`title`、`stat`） |
| 图文 | `module_dynamic.dyn_draw.items[]`（图片数） |
| 转发动态 | `module_dynamic.dyn_forward.item` —— **内层是同构动态**，递归取它的 modules |

时间戳只在 `module_author.pub_ts`；`pub_text` 是「投稿了视频」这类动作说明，不能当正文。

## 6. 抓取后的落地

- 输出 jsonl：`id / ts / time / type / url(t.bilibili.com/<id>) / desc`，每行一条、UTF-8。
- 自检至少覆盖：单日窗口 ⊆ 整窗结果、子窗口结果与整窗对应段一致、
  每条至少有正文或动作说明。上游翻页逻辑的边界 bug 都体现在这三条上。
- 未登录抓取有频率不确定性，`--selfcheck` 式的固定样例校验要能重跑。

## 7. 评论区发言（同一 uid 的另一半）

**B 站没有「按 mid 查全站评论」的接口**，评论只能逐稿件遍历后按 `member.mid` 本地过滤。
文档 BACNext 未收录 comment 模块，去 `SocialSisterYi/bilibili-API-collect`（或其 backup 仓）的
`docs/comment/list.md`、`docs/comment/readme.md`（评论区类型码表）。

### 7.1 评论接口（未登录实测可用）

| 目标 | 端点 | 翻页 |
| --- | --- | --- |
| 一级评论 | `GET /x/v2/reply/main?type=1&oid=<aid>&mode=3&next=<n>` | 游标 `data.cursor.next`，`is_end` 结束 |
| 一级评论（旧版） | `GET /x/v2/reply?type=1&oid=<aid>&sort=0|1|2&ps<=20&pn=<页码>` | 页码，`data.page.count` 算总页数 |
| 楼中楼 | `GET /x/v2/reply/detail?type=1&oid=<aid>&root=<一级rpid>&ps=20&next=<楼号>` | 游标 `data.cursor.next`，`is_end` 结束 |

`mode`：`2`=最新、`3`=最热（`data.cursor.name` 会回显）。每条评论带 `member.mid` / `member.uname` /
`ctime` / `content.message` / `rpid`；楼中楼取 `data.root.replies[]`。

### 7.2 评论区类型码（type 参数）

`1`=视频（oid=avid）、`11`=相簿/图文动态（oid=相簿 id，即动态 `basic.rid_str`）、
`17`=动态（oid=动态 id，**实测 -404，不可用**——动态评论要用 11 或从 opus 页另找）。

### 7.3 拿 oid 的前置：绕开被风控的空间页接口

- `/x/space/arc/search` 未登录频繁 `-799 请求过于频繁` 或 412；
  `/x/space/wbi/arc/search` 未登录 `-352 风控校验失败`（需 WBI 签名）。
- **不要在这两个上面耗时间**：目标用户的视频 aid 直接从第 2 节的动态流里取
  `module_dynamic.dyn_archive.aid`——既是稿件列表，又自带时间戳，一并解决翻页和时间过滤。

### 7.4 覆盖面的结构性限制（先讲清再动手）

逐稿件遍历只能覆盖「该用户**自己稿件下**的评论」。他在别人视频下留的言，
除非把全站热门稿件都遍历一遍，否则抓不到——这是接口设计决定的，没有干净解法。
开工前把这个边界明确告诉用户，别等交付后才发现缺一大块。

### 7.5 被回复 / 被点赞：走消息中心（需登录 cookie）

想拿「收到的回复和赞」时，不要继续在稿件评论区里绕——B 站消息中心有成套接口，
**但 BACNext 与 bilibili-API-collect 均未收录**，只能从 `message.bilibili.com` 的前端
bundle 逆。抓法见 `references/bilibili-message-center.md`。

现成实现参考：`linyuye/Bilibili_crawler`（动态列表→评论批量爬，逻辑最贴近，
但它用的 `v1/feed/space` 现在未登录 412、且硬依赖 cookie，只能借结构不能直接用）；
`Ghauster/BilibiliCommentScraper`（Selenium 滚动，2024 后停更）；
`eggry/BiliReplyDetailCrawler`（楼中楼 API 封装，2021 停更）。

## 8. 上游边界

- 登录态（`SESSDATA`）能提高限额与稳定性，但需要用户提供 cookie；未登录路径上面各节已实测标注。
- 采集类结论落地后写进 agenote 经验卡（category=datacompx、type=reference），下次直接检索复用。

