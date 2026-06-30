## 格式规范

卡片格式为 **Org mode**，不是 Markdown。

### 代码块 — 用 `#+begin_src`，禁止 ` ``` `

错误（Markdown）：

````markdown
```elisp
(message "hello")
```
````

正确（Org mode）：

```org
#+begin_src elisp
(message "hello")
#+end_src
```

### 强调 — 用 `*text*`，禁止 `**text**`

错误：`**粗体**`

正确：`*粗体*`

注意：`** 任务描述`（`**` 后有空格）是 Org 二级标题，不是粗体。

### 标题层级

```org
* DONE 标题
** 任务描述
```

### Markdown → Org 速查表

| Markdown        | Org mode                         | 说明     |
| --------------- | -------------------------------- | -------- |
| ` ```lang ``` ` | `#+begin_src lang ... #+end_src` | 代码块   |
| `**bold**`      | `*bold*`                         | 粗体     |
| `## heading`    | `*** heading`                    | 子标题   |
| `- item`        | `+ item`                         | 无序列表 |
| `` `code` ``    | `~code~`                         | 行内代码 |
