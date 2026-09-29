---
name: web-data-harvesting
description: Use when scraping sites/SPA APIs/archives（抓取/爬取/存档）。
---

# 网页数据采集工程

从「能不能拿」到「拿回来怎么落地」的通道阶梯。先探可达性，再选通道：
能直连就不要上浏览器，能上浏览器就不要挖存档。

适用：给项目补公开数据源、目标站有反爬、站点是 SPA、需要已下线页面/接口的历史数据。

## 0. 开工前 30 秒决策

- **版权口径**：演示引用 vs 持久化入库 vs 整站抓取——先落一条能写进 README 的口径
  （例：「仅限演示引用 + 保留源链接，不整站抓取」）。
- **robots.txt**：`curl <site>/robots.txt`，留意目标路径是否被 Disallow。
- **数据在哪**：静态 HTML / 站内 API（JSON）/ 只有存档里有——这决定走哪一档通道。
- **协议先试对**：老站点/政府站的 HTTPS 常配置有误（TLS handshake failed、
  `ERR_SSL_UNRECOGNIZED_NAME_ALERT`）——先换 `http://` 再试一次，别据此判定站点不可达。

## 1. 通道阶梯（从便宜到贵，逐级降级）

| 档 | 手段 | 适用 | 信号 |
| --- | --- | --- | --- |
| 1 | curl / urllib | 静态页、开放 API | 直接 200 + 数据在响应体里 |
| 2 | 站内 API（从页面 JS 挖端点） | SPA 站、政府开放数据平台 | 页面数据由 fetch/XHR 加载 |
| 3 | headless 浏览器（browser_exec） | 需 JS 渲染、需会话态、需绕反爬 | 直连 403/验证码 |
| 4 | web.archive.org 存档 | 反爬绕不过、页面/接口已下线 | DataDome 类验证码、改版丢数据 |

**反爬识别**：403 + 响应体里出现 `captcha-delivery.com` / `geo.captcha-delivery.com`
= DataDome 等商业风控，**不要试图破解**；直接考虑第 3、4 档。

## 2. 站内 API 逆向（SPA 站的最快路径）

1. 抓页面引用的 JS bundle，grep 端点常量：
   `grep -ohE '"/[a-zA-Z0-9_/]*<关键词>[a-zA-Z0-9_/]*"' *.js | sort -u`
   —— `/catalog/page`、`/irs/front/list` 这类路径常直接写在 bundle 里。
2. 端点有了但**参数不知道** → 浏览器里 hook fetch/XHR，再触发一次 UI 操作，读回真实调用体：
   ```js
   window.__calls = [];
   const of = window.fetch;
   window.fetch = function(...a){ window.__calls.push([String(a[0]), a[1] && String(a[1].body)]); return of.apply(this, a); };
   const oo = XMLHttpRequest.prototype.open, os = XMLHttpRequest.prototype.send;
   XMLHttpRequest.prototype.open = function(m,u){ this.__m=m; this.__u=u; return oo.apply(this,arguments); };
   XMLHttpRequest.prototype.send = function(b){ window.__calls.push([this.__m, this.__u, String(b)]); return os.apply(this,arguments); };
   ```
   「bundle 里的端点 + hook 到的参数」拼起来就是完整调用。
3. **curl 直连返回空 ≠ 接口不可用**：很多站要浏览器会话（cookie/referer/指纹）。
   这种情况在浏览器上下文里循环 fetch；响应里数据为 null 常见原因是参数超限
   （服务端偷偷限 pageSize），先试小值。
4. **无凭据探测端点是否存在**：未登录请求若返回「账号未登录」这类**业务错误码**（JSON），
   说明端点真实存在、只差登录态；若返回 HTML 404/错误页，说明路径根本不存在。
   先这样批量扫一遍候选路径，再决定是否值得去要凭据。
5. **参数形状从请求封装函数读**：站点整包进单个 bundle 时，grep 出 API wrapper
   （形如 `url:"/x/xxx/${e}"` 的模板串）即可看到公共参数；游标参数名去前端组件的
   `data:()=>({offset:{...}})` 初值里找。同时留意 bundle 里的 `baseURL` 覆盖——
   同站功能可能分布在多个域名下，别默认全在主域。

### 2.1 游标翻页与时间窗口（列表接口没有时间参数时）

大量列表接口只给游标（`offset`/`cursor`）、不给时间参数，「取某时间段」只能翻到底再本地过滤：

- **空页 ≠ 到底**：风控会让接口随机返回 `items: []` + `has_more: false`（实测可达三成概率）。
  见到空页先退避重试（`0.5*(i+1)s`、约 6 次）再判定无数据；把一次空页当结束会静默丢整段数据。
- **早停看「整页最早一条」**，不要「遇到一条早于窗口就 break」——页内并非严格按时间有序，
  逐条 break 会漏掉同页后半的目标记录。整页最小值早于窗口起点时才停。
- **晚于截止日的条目要继续翻**（置顶、比抓取时刻新的动态），跳过但不停。- **正文位置不唯一**：同一列表里纯文字、长文、媒体卡、转发原文常落在不同键（甚至内层同构结构）。
  按候选键逐级回退提取，只认一条路径必漏一类内容。
- 游标翻页要设 `seen` 去重：空页重试与接口抖动会让同一页重复返回。

## 3. 存档挖掘（web.archive.org）

- `available` API 只给**最近**快照——新版页面可能已经没数据了（例：评论被换成 AI 摘要）。
  **用时间点导航强制取旧版**：`https://web.archive.org/web/20210601/<url>`（302 到最近的旧快照）。
- CDX API 列快照清单：`collapse=urlkey` 去重；带正则 `filter=original:.*X.*` 的大查询会 504，
  先不带 filter 拉小范围（按域名/路径前缀），关键词收窄放本地做。
- **解析按「页面结构版本」分支**：同一站不同年代的结构共存（老版 `partial_entry` /
  中版 `data-reviewid` / 新版只剩摘要）。分块锚点与正文提取都做「最结构化 → 最宽松」多套兜底。
- 详细配方见 `references/tripadvisor-archive.md`。

## 4. 浏览器内采集与数据回传

- browser_exec 的 JS 在**页面上下文**里执行：同源 fetch 不受 CORS/会话限制，适合直接调站内 API。
- **大批量数据回传磁盘，Blob 下载最稳**：
  ```js
  // Python 侧：cdp('Page.setDownloadBehavior', behavior='allow', downloadPath='/tmp/out')
  // 页面里：new Blob([JSON.stringify(data)]) → URL.createObjectURL → a.download → click
  ```
  次选：CDP 分块读回（token 贵）。**本地 HTTP 服务器回传会被 Chrome 的 PNA
  （Private Network Access）拦成 failed to fetch**，别在那条路上耗时间。
- 执行环境差异：`execute_code` 里的子进程网络可能受限（SSL 校验/沙箱），
  **shell 级抓取一律走 terminal**；浏览器任务先 `ensure_real_tab()`，
  daemon 起不来时用 browser-harness 的 `--reload`。

## 5. 落地纪律

- **原样归档 + README**：外来数据进项目约定的只读区，不改原始内容；
  README 标注来源/许可/字段/用途/抓取日期；抓取与解析脚本保留（可重跑）。
- **缺失如实标注**：抓不到的条目写进文档（「N 个目标在可用存档中无数据」），
  不硬凑、不用合成数据冒充。
- **噪声过滤**：评论区常混进旅游产品价格块（`from $X per adult`）之类，正则剔除并复核条数。
- **行数快照**：入库前设期望条数常量，上游变化时显式更新——防上游被悄悄替换。
- **换数据源要留痕**：新旧源的命名/字段规范常不同（例：「旅游风景区」vs「风景旅游区」），
  **不做名称模糊匹配去重**；新源入构建链、旧文件原地留档并在 README 标注「已被取代」，
  指向旧编号的引用（如 registry_code）显式改指新编号、失配即构建失败。
- **校验职责分层**：构建脚本尽量不依赖项目包（`scripts/` 不在 `sys.path`，import 项目模块会炸）；
  跨层一致性（外键 id、画像 id 是否合法）放 `tests/` 校验，防手写错字静默失效。
- **每批数据跑一遍构建 + 测试**，文档里的条数口径同步更新（一次数据改动会波及多处文档）。

## 6. 字段级补全（表内空缺回填）

- **先统计再动手**：全表逐字段统计空值数，分清「真缺失」与「设计留空」——名录/架子行只要求
  最小字段集、境外条目无某类概念（如国内 A 级等级制度）——设计留空**不要填**，填了就是错数据。
- **补值优先级：表内已有事实（显式关联的其它行）镜像 > 公开权威源 > 描述性标签**；
  逐字段记录来源，汇总成数据 README 里的一张来源表。
- **称号/荣誉类字段宁缺毋滥**：官方称号优先；无官方称号时可用维基/主流媒体公认的标签；
  查不到就留空，不编不凑。
- **外部源先核验口径再入库**：地理类数据尤其——政务/第三方源可能是带偏移的坐标系统
  （BD-09 等，直接使用偏几百米到 1 km），判定后再写入。
- **数据数字变更要全仓库同步**：条数/分组计数常硬编码在测试断言、接口文档与验证命令块里——
  改完数据先 `grep -rn "<旧数字>"` 逐处对齐，不要只改测试。
- **留空清单批量交回**：哪些字段仍空、为什么（设计如此 / 无可核证来源 / 来源缺失），
  收尾一次性列出交用户拍板，不逐条打断。

## 参考

- `references/tripadvisor-archive.md` — Wayback 存档抓评论的完整配方（时间点导航 + 双锚点解析）
- `references/spa-api-discovery.md` — 政府开放数据平台 SPA 的端点逆向实例
- `references/webpack-chunk-manifest.md` — webpack chunk manifest 型 SPA 的端点逆向（双表定位 manifest、`a.js` 后缀坑、`.e()` 爬 chunk 依赖、qid 失效判定）
- `references/geodata-apis.md` — Wikidata / OSM（Overpass・Nominatim）/ 旅游平台 POI 页的地理字段取数配方与限流礼仪
- `references/bilibili-space-dynamics.md` — B 站用户空间动态采集配方（BACNext 文档源、desktop 端点 412 陷阱、空页重试、时间窗口过滤、多键正文提取、评论区 `/x/v2/reply` 链路与「无按 mid 查评论接口」的结构性限制）
- `references/bilibili-message-center.md` — B 站消息中心采集配方（回复/赞/@ 通知接口、bundle 逆向手法、点赞通知的两级翻页、登录态与保留期边界）
