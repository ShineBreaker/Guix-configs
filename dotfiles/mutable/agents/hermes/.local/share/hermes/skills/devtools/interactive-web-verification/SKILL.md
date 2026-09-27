---
name: interactive-web-verification
description: Verify interactive HTML and Canvas claims in a browser.
version: 1.0.0
metadata:
  hermes:
    tags: [web, html, canvas, browser, testing, accessibility, localStorage]
---

# 互动网页交付验证

用于验证单文件 HTML、Canvas、作品展示页，以及任何声明“可直接打开、可点击、可键盘操作、可持久化、响应式、尊重减少动态效果”的交付物。目标不是让测试变绿，而是让每条对外声明都有真实浏览器证据。

## 核心规则

1. **测试真实交互，不测替身。** `element.click()` 和合成 `KeyboardEvent` 只证明监听器能响应；用户能否点到、按键能否送达，要用 WebDriver/W3C Actions 的真实 pointer 与 key 事件。
2. **每条声明都要有反例。** happy path 通过后，主动注入恶意文本、存储异常、损坏数据、遮挡层、跨视口变化和 reduced-motion。
3. **持久化成功才算提交成功。** 写入失败时保留输入、回滚内存状态并显示失败，不允许清空输入后假装“已留下”。
4. **屏幕渲染和持久化语义分开。** viewport 变化可以改变像素坐标，但不能改写用户内容的归一化坐标、顺序或身份。
5. **CSS motion 停了不等于动画停了。** Canvas 帧循环、粒子、闪烁和惯性也必须在 `prefers-reduced-motion` 下停止。
6. **修复后重跑完整攻击集。** 验证器变长、事件类型变化或产品 hash 改变时，旧绿灯立即失效。

## 工作流程

### 1. 固定交付基线

- 记录交付物的 SHA-256、行数、bytes。
- 列出每条对外声明：打开方式、交互、持久化、兼容性、可访问性、隐私。
- 不在 review 期间继续改交付物；若必须修改，修改后重新记录基线并重跑全部门禁。

### 2. 验证两种打开路径

对静态作品分别验证：

- `file://` 直接打开；
- 真实静态服务器路径。

每条路径都检查标题、关键 DOM、canvas/图形初始化和未捕获异常。`file://` 可用不代表 HTTP 路径可用，反之亦然。

再检查资源表：自包含作品不应偷偷请求远程脚本、字体、样式或图片；用户输入只能进入 `textContent` 等安全 sink，禁止 `innerHTML`、`eval` 和动态脚本注入。

### 3. 攻击输入与存储

- 提交 `<svg/onload=1>`，断言显示的是文字，未生成 SVG 节点。
- 强制 `localStorage.setItem` 抛 `QuotaExceededError`，断言输入保留、临时状态回滚、失败提示准确、旧数据未被破坏。
- 写入损坏 JSON 后重载，断言页面仍能运行；再恢复数据，确认恢复操作不会二次破坏。
- 每次刷新都核对持久化值，不只检查对象存在。

### 4. 攻击真实指针与遮挡

1. 从页面状态或持久化数据取得目标坐标。
2. 换算为当前 viewport 的屏幕坐标。
3. 用真实 pointerMove/pointerDown/pointerUp 点击。
4. 点击前用 `elementFromPoint` 确认命中目标或其子元素。
5. 点击后确认实际内容出现。

页脚、说明文字和装饰层不得盖住交互区。纯装饰层使用 `pointer-events: none`，不要只凭 z-index 猜是否可点。

### 5. 攻击键盘与焦点

- 聚焦目标后发送真实 Enter/Tab/Space，不直接 dispatch KeyboardEvent。
- 隐藏弹层同时设置 `aria-hidden="true"`、`inert`，并把内部可聚焦控件设为 `tabIndex=-1`。
- 关闭弹层后把焦点还给触发它的稳定控件。
- 连续 Tab 一轮，确认隐藏控件没有进入焦点顺序。

### 6. 验证响应式坐标不变量

若作品保存归一化位置：

1. 桌面视口创建至少两个不同位置的对象并保存 `x/y`。
2. 缩到手机宽度并重载。
3. 断言存储中的 `x/y` 完全不变。
4. 在手机视口新增对象并再次保存，断言旧对象坐标仍不变。

同时检查目标宽度无横向溢出、布局模式符合媒体查询、按钮和关闭控件达到可触达尺寸。

### 7. 验证 reduced motion

- 启用真实浏览器的 reduced-motion 模拟。
- 间隔一小段时间比较两张完整截图，必须相同。
- reduced-motion 下新增状态变化后，确认画面静态刷新一次，随后不再变化。
- resize 可触发一次静态重绘，但不得重新启动无限 `requestAnimationFrame` 循环。

### 8. 视觉与证据

至少保留：

- 桌面主截图；
- 手机主截图；
- 关键交互后的截图；
- reduced-motion 前后/间隔对比证据。

视觉检查关注遮挡、裁切、横向溢出、字号、触控尺寸和层级，不用“页面能打开”替代视觉结论。

### 9. 报告门控

- 所有攻击项 `PASS`：可以声明完工，并列出命令和产物。
- 任一攻击项 `FAIL`：撤回完工声明，修复后重跑完整集合。
- reviewer 或截图若早于最后一次产品写入，结论只作线索，不直接引用。
- 外部独立审查发现新反例时，把它升级为新的可执行断言，而不是只做一次性手工修补。

## 常见假绿

- 只测标题、DOM 和一个 happy path。
- 用合成事件代替真实鼠标或键盘。
- 只看 localStorage 有一条记录，不测写入异常。
- 只测同一 viewport，不测位置持久化。
- 隐藏元素仍能 Tab 到。
- reduced-motion 只关 CSS animation，Canvas 仍逐帧变化。
- verifier 修改产品行为却没有独立 reviewer 复核。

## 深入参考

需要 WebDriver 攻击清单和断言样例时，读 `references/interactive-ui-verification.md`。