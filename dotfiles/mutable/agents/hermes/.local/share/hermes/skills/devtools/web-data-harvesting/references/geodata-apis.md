# 地理数据取数配方：Wikidata / OSM / 旅游平台

补地理位置、行政区、称号类字段时的公开源与用法。全部走直连 HTTP（通道 1 档），
带统一 UA（带用途标识），遵守限流。

## Wikidata（坐标 / 行政区 / 遗产称号）

- 两步走：先搜实体拿 QID，再批量取属性。
  1. 搜：`wbsearchentities`（`action=wbsearchentities&search=<名>&language=zh|en&limit=4`）。
     **英文名通常更准**；中文名常命中同名异地（搜景点名可能命中外省同名景点），
     用返回的 `description` 判别歧义。
  2. 取：`wbgetentities`（`ids=Q1|Q2|...`，≤ 50 个/次）`props=claims|labels|descriptions`，
     `languages=zh|en`。
- 常用属性：`P625` 坐标 / `P131` 所在行政区 / `P1435` 遗产保护状况 / `P17` 国家 / `P276` 位置。
  `P131` / `P1435` 的值是 QID，需再批量查一次标签（≤ 40 个/次）才能读出中文名。
- **限流**：连续请求几次就 429。请求间隔 ≥ 2s；429 时指数退避重试（3/6/9s）。
  能用批量接口（wbgetentities）就不要逐个打点。

## OSM（坐标对照真值 + 地理编码）

- **Overpass**（overpass-api.de）：
  - 名称精确匹配 + bbox 限定：`nwr["name"="全名"](南,西,北,东); out center;`
    模糊匹配 `~"关键词"` 会命中同名异地，污染结果。
  - `is_in(lat, lon)` 可反查某点所属行政区链条。
  - 504 / 429 是常态：间隔 5–8s 重试 2–3 次；大查询拆成小批。
- **Nominatim**（地理编码）：中文地名 `q=<地名>&format=jsonv2&accept-language=zh`；
  村/屯级覆盖稀疏，查不到属正常——不硬凑。
- OSM 即 WGS-84 事实标准，是判定其它数据源坐标系时的对照真值。

## 旅游平台 POI 页（双坐标对照素材）

- 部分平台 POI 详情页内嵌 context JSON，含 `googlePoint` / `baiduPoint` 双坐标——
  坐标系判定的现成素材（两值解码到 WGS-84 应收敛同一点）；注意其 `googlePoint` 实为 GCJ-02。
- 地图站（高德 / 百度）的网页搜索接口对脚本与无头浏览器风控严：拿不到时转 POI 页、
  站内联想接口或搜索引文，别在地图站本身上耗时间。

## 百科与搜索（称号 / 地址类字段）

- 百度百科 PC 页对脚本直连常 403：改用 `wapbaike.baidu.com` 移动版（内容少但可读）
  或 web_search 引文核对，不在绕反爬上耗时间。
- 称号类字段以官方公告为准（政府网站、行业主管部门公告）；媒体常用标签作次选，
  二者都查不到就留空。
