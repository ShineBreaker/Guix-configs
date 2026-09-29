# B 站消息中心采集配方（收到的回复 / 赞 / @）

目标形态：抓某个账号「收到的互动」——回复我的、赞了我的、@我的，带时间戳，可卡时间段。

**这套接口在任何 API 文档库里都没有收录**（BACNext、SocialSisterYi/bilibili-API-collect 及其
backup 仓、pskdje 复刻全部缺失），只能从消息中心前端 bundle 逆。

## 1. 端点清单（全部需登录 cookie）

统一封装：`url = /x/msgfeed/<name>`，公共参数 `platform=web&build=0&mobi_app=web`。

| 目标 | 端点 | 游标参数 | 结束判据 |
| --- | --- | --- | --- |
| 回复我的 | `/x/msgfeed/reply` | `id` + `reply_time` | `data.cursor.is_end` |
| 收到的赞 | `/x/msgfeed/like` | `id` + `like_time` | `data.cursor.is_end` |
| @我的 | `/x/msgfeed/at` | `id` + `at_time` | `data.cursor.is_end` |
| 单条赞的点赞者 | `/x/msgfeed/like_detail` | `card_id` + `pn` + `last_mid` | `data.page.is_end` |

三个 feed 的**游标参数名各不相同**（`reply_time`/`like_time`/`at_time`），别复用同一个。

## 2. 逆向手法（无文档时的标准路径）

1. 抓消息中心页面 HTML，找到主 bundle（`message-pc/static/js/index.<hash>.js`，整包无懒加载 chunk）。
2. grep 请求封装函数：模板串 `url:`/x/msgfeed/${e}`` + 紧跟的 `params:{...t,platform:"web",build:0,mobi_app:"web"}`
   ——一次性拿到全部 feed 端点与公共参数。
3. 逐个 feed 的 Vue 组件里读 `data:()=>({offset:{...}})` 初值与
   `this.offset={id:a.id.toString(),<xxx>_time:a.time}` 赋值，得到游标字段名。
4. **域名要单独确认**：`/x/msgfeed/*` 在 `api.bilibili.com`，
   但 `/x/sys-msg/*` 的 baseURL 是 `//message.bilibili.com`，`/x/im/*` 在 `api.vc.bilibili.com`。
   同站功能跨域是常态，先找到 baseURL 常量再发请求。
5. **无凭据端点存在性探测**：未登录请求返回 JSON `{"code":-101,"message":"账号未登录"}`
   = 端点真实存在、只差登录；返回 HTML 404 页 = 路径不存在。据此筛候选路径，别逐个猜。

## 3. 数据结构与两级翻页

### 3.1 reply / at（一级就是明细）

`data.items[].item`：

| 字段 | 含义 |
| --- |
| `source_id` | 对方评论 rpid |
| `target_id` | 被回复的评论 rpid，**>0 表示回复的是我自己的评论** |
| `root_id` / `subject_id` | 根评论 / 主体（稿件或动态）id |
| `business_id` | `1`=视频评论、`11`=动态评论、`17`=动态 |
| `type` | `"danmu"` 表示弹幕，此时带 `danmu.aid` / `danmu.progress` |
| `source_content` | 对方发言原文 |
| `target_reply_content` | 我被回复的那条原文 |
| `uri` | 可跳回原文的链接 |
| `uri` + `at_details` | at 类通知里 @ 位置的结构化标注 |

`data.items[].user` 是回复者（`mid` / `nickname` / `avatar`），`reply_time` / `at_time` 是时间戳。
弹幕的赞与回复**也走 `/x/msgfeed/reply`**，不用另找接口。

### 3.2 like（聚合卡片，必须二次翻页）

`/x/msgfeed/like` 返回的是**聚合通知**：

- `data.total.items[]` 是历史聚合卡片，`data.latest.items[]` 是最新一批（UI 上分开渲染，抓取时两处都要取）。
- 每张卡片 `users[]` **只给前 2 个点赞者**，`counts` 是总赞数，`item_id` / `item.uri` / `item.title` / `item.image` 指向被赞内容，`item.target_reply_content` 是被赞的那条我的评论。
- **要点：拿全部点赞者必须对每张卡片再打 `/x/msgfeed/like_detail?card_id=<item.id>`**，
  用 `pn` 翻页、`last_mid` 传上一页最后一个用户的 mid，`data.items[].user` 是点赞者明细。
  所以一个 N 赞的内容会变成 `1 + ceil(N/page)` 次请求——预估请求量时按这个算。

### 3.3 系统通知（另一套，独立游标）

`https://message.bilibili.com/x/sys-msg/query_notify_list?cursor=<上页最后一个 cursor>&data_type=1`
（游标是**列表最后一条的 `cursor` 字段**，不是 id）；首页还要并行打
`query_unified_notify?page_size=10` 与 `query_user_notify?page_size=20`。

## 4. 必须讲清的边界（动手前告知用户）

1. **只对登录账号自己有效**：语义是「我的消息」，不是「查任意用户收到的互动」。
   要抓 UID X 的回复/赞，前提是登录态就是 X——这与公开的动态抓取完全不同。
2. **有保留期**：消息中心不返回无限历史，翻到底就没有了。要更早的只能当初持续抓。
3. **删过的通知不复返**：`/x/msgfeed/del`（`tp=0` 赞 / `tp=2` 回复）删除后，除非有新互动才重新出现。
4. **凭据处理**：cookie 走环境变量或本地文件，不要贴进对话；写清脚本从哪读。
5. `/x/msgfeed/notice` 是 POST 设置免打扰（`notice_state`），不是读列表，别当分页接口用。

## 5. 公开路径对照（已封）

`/x/space/like/video?vmid=<uid>`（用户点赞过的视频）实测返回
`53013 用户隐私设置未公开`——想从公开侧拿「点赞关系」这条路是堵的，只能走登录态。

## 6. 落地

- 输出 jsonl，字段至少：`kind`（reply/like/at）、`ts`、`actor_mid`、`actor_name`、
  `subject_id`、`business_id`、`source_id`、`target_id`、`source_content`、`target_reply_content`、`uri`。
- like 类要把「聚合卡片 + 点赞者明细」两级都落，或至少记录 `card_id` 以便补抓。
- 采集类结论落地后写进 agenote 经验卡（category=datacompx、type=reference），下次直接检索复用。

