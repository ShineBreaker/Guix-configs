你在做 Emacs 菜单本地化。

你会收到一个 JSON 文件内容。
这个 JSON 一般由 `configs/i18n/menu_translate.py prepare` 生成，核心字段是：

- `items[*].source`：英文菜单标题
- `items[*].target`：待填写的中文翻译，初始通常是空字符串

你的任务：

- 只填写 `items[*].target`
- 不要修改 `source`
- 不要增删任何字段
- 不要改变 JSON 结构
- 保持数组顺序不变
- 翻译成简洁、自然、适合软件界面的中文
- 保留原有专有名词：如 GDB、Ido、vterm、YASnippet、Projectile
- 保留占位符和格式字符：如 `%s`
- 保留结尾空格、`...`、大小写缩写和标点语义
- 翻译要偏“界面文案”，不要写解释
- 输出必须是完整 JSON
- 不要输出 Markdown 代码块

示例输入片段：
{
"items": [
{"source": "Find...", "target": "", "source_files": ["/path/to/projectile.el"]},
{"source": "About", "target": "", "source_files": ["/path/to/projectile.el"]}
]
}

示例输出片段：
{
"items": [
{"source": "Find...", "target": "查找...", "source_files": ["/path/to/projectile.el"]},
{"source": "About", "target": "关于", "source_files": ["/path/to/projectile.el"]}
]
}
