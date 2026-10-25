# webpack chunk manifest 型 SPA 的端点逆向

适用：站点把 GraphQL/REST 的 `queryId` 藏在运行时按需加载的 webpack chunk 里，
`main.*.js` 里只有部分 operation，直接 grep 主包找不到目标端点。X（twitter.com）
2026-09-26 实测。

## 流程

1. **登录态抓 HTML**（cookie 必需，logged-out HTML 只有 entry 引导脚本）：

   ```python
   html = urlopen(Request("https://x.com/home", headers={"Cookie": f"auth_token={a}; ct0={c}"})).read()
   ```

2. **拿 sha**：`__META_DATA__=` 里的 `"sha":"<40 hex>"`，即本次发布的构建号。

3. **双表定位 manifest**。HTML 内联 webpack runtime 里有两张表，顺序固定：

   | 表 | 形态 | 内容 |
   |---|---|---|
   | 名字表 | `(\d+):"([A-Za-z0-9~._\-]+)"` | chunk id → `bundle.HomeTimeline` 这类名字 |
   | hash 表 | `(\d+):"([a-f0-9]{16})"` | chunk id → 内容 hash |

   hash 表在名字表**之后**，定位锚点用 hash 表第一个条目（如 `85:"c340ed7eb9a2188b"`）的
   index：`html[:idx]` 抽名字表，`html[idx:idx+80000]` 抽 hash 表。

4. **下载 URL 的坑**：不是 `<name>.<hash>.js`，而是 **`<name>.<hash>a.js`**
   （runtime 收尾是 `})[e]+"a.js"`）。少了 `a` 一律 404，且 404 body 为空，
   容易被误判成"端点不存在"。

5. **chunk 名筛目标**：`Search|Explore|Trend|Timeline|Home|List|Connect|Urt` 等。
   命中后下载、grep：

   ```python
   ops = re.findall(r'queryId:\s*"([^"]+)",\s*operationName:\s*"([^"]+)"', raw)
   ```

6. **目标 chunk 里没有 ops 时爬依赖**：chunk 内的 `\.e\((\d+)\)` 是它引用的其他
   chunk id，递归下载扫。`shared~bundle.Compose~bundle.HomeTimeline~...` 这种
   共享 chunk 常是 ops 的真正所在地。

## qid 失效判定

- `HTTP 404` 且 **body 为空** → qid 随发布失效，回到步骤 1 重新抽。
- `HTTP 422` + `GRAPHQL_VALIDATION_FAILED` + `variable "xxx" must be defined`
  → qid 还有效，是 variables 缺字段（补 `userId` / `includePromotedContent` 等）。
- `data` 为空但 `errors` 缺失 → 端点认了请求但拒答（如 ExplorePage 的 guest 态）。

**别把 404 当"接口关了"**：本次实测 `SearchTimeline` 用 main.js 里的旧 qid 打是
404，换新 qid 后仍不通（X 把它挪到未公开端点），而 `HomeTimeline` 同批就正常。
逐个端点分别验证，不要一次失败就推广到全部。

## features 参数

新 qid 的 `metadata.featureSwitches` 列在 chunk 里，抽出来直接当 features 用：

```python
m = re.search(r'queryId:"'+qid+r'",operationName:"[^"]+",operationType:"[^"]+",'
              r'metadata:\{featureSwitches:\[([^\]]*)\]', chunk_txt)
feat = {k.strip('"'): True for k in m.group(1).split(",")}
```

老脚本里已有的 `FEATURES` 字典常常也够用（本次实测 HomeTimeline / HomeLatestTimeline /
ExplorePage 用旧 FEATURES 全通），先试现成的再抽新的。
