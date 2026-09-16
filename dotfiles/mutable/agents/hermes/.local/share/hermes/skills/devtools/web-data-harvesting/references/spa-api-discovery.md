# SPA 站内 API 逆向：政府开放数据平台实例

背景：需要广西全区 A 级景区名录。旧平台已下线，新平台（`gxsjkf.dsjfzj.gxzf.gov.cn:8183`）
是 SPA，页面数据全部由 AJAX 加载，目录列表在未登录/配置错位时显示为空。

## 路线图

### 1. 先看 robots / 首页，确认平台还在服役

区政府公开数据平台常见“新旧平台双轨”：旧域名会 301/404，首页弹条“已升级，请到新平台”。

### 2. SPA 的“页面为空”不等于数据拿不到

该平台的目录页调用的 API 基址被配置成内网 IP（`http://192.168.x.x:82/athena`），
浏览器里请求全挂。**但同一套 API 在公网域名下也存在**：
把路径换成相对路径 `/athena/...` 在页面上下文 fetch 就通了。

→ 教训：先用 `performance.getEntriesByType('resource')` 看前端实际请求的 URL，
把“内网基址 + 路径”拆开，再用公网基址试同一路径。

### 3. 端点常量从 JS bundle 里抠

```
curl -sS "<base>/opendata/static/js/Directory.js" -o d.js
curl -sS "<base>/opendata/static/js/app.js" -o app.js
grep -ohE '"/[a-zA-Z][a-zA-Z0-9_/]{3,50}"' d.js | sort -u | head -60
```
实测到 `/catalog/page`、`/catalog/getDetails`、`/catalog/getData` 等端点
（webpack bundle 里是纯字符串常量，grep 就能拿到）。

### 4. 参数从“真实调用”里抓

端点有了但参数名不知道（试 `iid`/`catalogCode`/`id` 全部返回 `发生异常`）。
可靠做法：浏览器里 hook fetch/XHR（见 SKILL.md §2），然后**触发一次真实 UI 交互**
（在搜索框回车、点分页“下一页”），读回真实调用体拿到完整参数（含 `channel_id`、
`site_id`、`tableName` 这类看不见的常量）。

### 5. 分页与限额

- 服务端会偷偷限 `pageSize`：传 50 返回 `data.list: null`，传 30 正常。
- **分页循环放在浏览器上下文里**（同源 fetch），每批 3-8 页并发；
  批太大触发 harness 超时（IPC 5s），批小了多跑几轮。
- 多轮抓取会拿到重复数据，最后按主键去重，并与页面显示的总数对账。

### 6. 数据回传：Blob 下载

浏览器上下文里的数据回磁盘，最稳的是 Blob 下载（见 SKILL.md §4）。
当时试过本地 HTTP 服务器回传（`127.0.0.1:8123`）→ Chrome PNA 拦成 `Failed to fetch`；
curl 直连该服务器正常，但浏览器不行——不要在这条路上继续。

## 另一个平台的教训：目录能列、数据拿不到

同一平台的“数据预览”接口需要登录态（`getData` 返回 `data: null`），
无论参数怎么试。这类情况下：换数据源（本例改用文旅厅官网的便民查询接口）
比继续磨登录墙划算。

判断标准：如果一个平台的**目录元数据接口开放、但数据接口要登录**，
先花 10 分钟找该数据的其他公开出处（主管厅局官网、地市政府网站的对应栏目）。
