# 互动网页对抗性验证参考

本文件提供自包含 HTML / Canvas 作品的具体攻击清单。实现可使用 Selenium WebDriver、Playwright 或等价 W3C WebDriver；目标是真实输入通道和可重复证据，不是绑定某个库。

## 真实指针动作

```python
actions = {
    "actions": [{
        "type": "pointer",
        "id": "mouse",
        "parameters": {"pointerType": "mouse"},
        "actions": [
            {"type": "pointerMove", "duration": 0, "origin": "viewport", "x": x, "y": y},
            {"type": "pointerDown", "button": 0},
            {"type": "pointerUp", "button": 0},
        ],
    }]
}
driver.execute("actions", actions)
```

点击前先确认命中目标：

```js
document.elementFromPoint(x, y).closest('#target')?.id === 'target'
```

## 真实键盘动作

W3C Actions 的 `keyDown` / `keyUp` 值应使用 WebDriver 规定的键编码，而不是页面显示字符。发送前断言 `document.activeElement` 确实是目标控件。隐藏弹层检查：

```js
({
  ariaHidden: message.getAttribute('aria-hidden'),
  inert: message.hasAttribute('inert'),
  closeTabIndex: close.tabIndex,
  activeAfterClose: document.activeElement.id,
})
```

## 存储失败

```js
const original = Storage.prototype.setItem;
Storage.prototype.setItem = () => {
  throw new DOMException('full', 'QuotaExceededError');
};
try {
  form.requestSubmit();
} finally {
  Storage.prototype.setItem = original;
}
```

必须同时断言：输入值仍在、内存没有残留新对象、旧存储仍可读、界面显示失败而非成功。

## 坐标不变量

```python
desktop = browser.execute_script(
    "return localStorage.getItem(STORE_KEY)"
)
browser.set_window_size(390, 844)
browser.get(URL)
mobile = browser.execute_script(
    "return localStorage.getItem(STORE_KEY)"
)
assert mobile == desktop
```

创建自由布局对象时，持久化 `x/y` 应是布局无关的归一化语义值。屏幕像素位置由当前容器和 viewport 重新计算。

## reduced motion

优先使用浏览器真实媒体模拟。若只能通过 Chrome 启动参数，至少用：

```text
--force-prefers-reduced-motion=reduce
```

然后：

1. 截完整页面帧 A；
2. 等待 250ms；
3. 截帧 B；
4. 断言 A == B；
5. 修改页面状态并触发一次静态重绘；
6. 再次间隔截图，断言仍相同。

## 完成证据模板

```text
PASS file-open
PASS no-external-resources
PASS hostile-input
PASS storage-quota-failure
PASS broken-storage
PASS persisted-coordinate-invariants
PASS real-pointer-and-hit-testing
PASS real-keyboard-and-focus
PASS responsive-no-overflow
PASS reduced-motion-static
Evidence: <artifact path/hash>, <command output>, <screenshot paths>
```
