# Wayback 存档抓评论：TripAdvisor 配方

实战背景：给一个文旅推荐项目补真实游客评论（原为 0 条），目标 30 个景区。
TA 直连被 DataDome 拦住，改走 web.archive.org 公开存档。最终 164 条唯一评论、
覆盖 19 个景区。

## 第一步：找到每个目标的 TA 页面 URL

TA 页面 URL 形如
`tripadvisor.com/Attraction_Review-g<geo>-d<dest>-Reviews-<Name>-<City>_<Province>.html`。
用搜索引擎查（`<景点英文名> tripadvisor`），比猜 URL 快。

## 第二步：拿快照——要害是「旧版才有完整内容」

- `archive.org/wayback/available?url=<u>` 返回**最近**快照，通常是 2024+ 新版：
  页面只剩「AI 摘要」1-3 条，**没有完整评论列表**。
- **时间点导航强制取旧版**：
  ```
  https://web.archive.org/web/20210601/https://www.tripadvisor.com/Attraction_Review-...html
  ```
  curl 加 `-L` 跟随 302；`-w "%{url_effective}"` 能拿到实际快照时间戳（用于日志与去重）。
  2021-2022 年的快照保留完整评论区块（每页约 10 条）。
- 同一年份可能没有快照（curl 拿到 404 页），多试几个时间点：`20210601 / 20220601 /
  20190601 / 20230601`；脚本里设「拿到 ≥8 条就停」。
- **CDX 列清单**：`web.archive.org/cdx/search/cdx?url=<domain>/<path>*&collapse=urlkey&limit=N&fl=original,timestamp`
  —— 正则 `filter=original:.*X.*` 的大查询会 504，少用。

## 第三步：解析——双锚点 + 四正文模式

同一站点的页面结构按年代分版，**单一锚点/单一正文模式只能覆盖一部分**：

**分块锚点**（取命中数多的那套）：
- 2019 老结构：`href="...ShowUserReviews-...-r<id>-..."` 链接
- 2021 中结构：`data-reviewid="<id>"`

**正文模式**（按「最结构化 → 最宽松」兜底）：
1. `<p class="partial_entry">...</p>`（2019；注意是截断摘要，尾部有 `More`）
2. `<q ...>...</q>`（2021）
3. `class="pIRBV"` 容器内的 `<span class="NejBf">`
4. 块内第二个 `class="NejBf"` span（最宽松兜底）

**标题**：`data-test-target="review-title"` → `div.quote a` → `span.noQuotes` → 块内首个 NejBf
**日期**：`Date of experience:` → `span.ratingDate` → `class="eRduX"` / `class="fEDvV"`
**作者**：`/Profile/<name>` → `div.info_text > div`

**源链接**：从页面里抠该条评论的真实 `ShowUserReviews-...-r<id>-...html`
（去掉 `/web/<ts>/` 前缀），作为 `source` 落库——比自拼 URL 可靠。

## 坑

- **噪声**：旅游产品价格块（`from $X per adult (price varies by group size)`）会落进锚点
  范围，正则剔除（`per adult`、`from \$`、`price varies`、`Book now`）并复核条数。
- **边界**：分块区间取 `到下一个锚点` 或 `起点 + 20000 字符`（防止最后一条吃掉整页）。
- **去重**：同一条评论在不同年份快照里重复出现，用 review id 去重。
- **页面长度阈值**：下载后 `< 5000` 字节基本是 404/空页，直接跳过别解析。
- **覆盖面要如实**：确实拿不到的目标（无快照/全是新版）在 README 里写清楚，不要硬凑。
- **多语言不可强求**：TA 的本地化站（tripadvisor.co.id / .com.vn）的景点存档要么没有、
  要么同为新版结构、评论本身也多为英文——想拿东南亚语言评论要换数据源。

## 可复用断言

解析器交付前跑一个小自检：对已知快照（含两种结构各一个）断言「每条评论有
非空 body、长度 ≥ 40、rid 唯一」，并打印按景点的条数分布。
