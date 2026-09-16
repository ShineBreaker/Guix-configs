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

## 参考

- `references/tripadvisor-archive.md` — Wayback 存档抓评论的完整配方（时间点导航 + 双锚点解析）
- `references/spa-api-discovery.md` — 政府开放数据平台 SPA 的端点逆向实例
