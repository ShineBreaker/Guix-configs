# pandoc 渲染中文 docx 完整配置

## 最小可用命令

```bash
pandoc input.md -o output.docx \
  -V mainfont="Noto Serif CJK SC" \
  -V monofont="Sarasa Mono SC"
```

这会渲染出能用的中文 docx，但格式简陋。

## 完整推荐配置

### 方式 A：YAML 头 + 命令行参数

```markdown
---
title: "课程实践手册"
geometry: [margin=2.5cm]
fontsize: 12pt
mainfont: Noto Serif CJK SC
monofont: Sarasa Mono SC
---

# 内容...
```

```bash
pandoc input.md -o output.docx --toc --toc-depth=3
```

### 方式 B：reference.docx 自定义模板

如果想完全控制 Word 样式（标题字体、表格样式、页眉页脚）：

1. 用 Word 创建一个空白 .docx，手动设置好样式
2. 命名为 `reference.docx`
3. 用 `-R reference.docx` 调用：

```bash
pandoc input.md -o output.docx \
  --reference-doc=reference.docx \
  --toc --toc-depth=3
```

### 方式 C：header.tex 自定义页眉页脚

```latex
% header.tex
\usepackage{fancyhdr}
\pagestyle{fancy}
\fancyhf{}
\rhead{\thepage}
\lhead{广西左江花山岩画实践报告}
```

```bash
pandoc input.md -o output.docx \
  --include-in-header=header.tex \
  -V mainfont="Noto Serif CJK SC"
```

## 中文字体配置

### Linux (Guix / Debian / Ubuntu)

```bash
# 检查可用字体
fc-list :lang=zh

# 常见可用字体
# Noto Serif CJK SC     - 衬线，最正式
# Noto Sans CJK SC      - 无衬线，现代
# Sarasa Mono SC        - 等宽，用于代码/表格
# 思源宋体 / 思源黑体   - Adobe 版本
```

### macOS

```bash
-V mainfont="Songti SC"
-V mainfont="PingFang SC"
```

### Windows

```bash
-V mainfont="SimSun"
-V mainfont="Microsoft YaHei"
```

## 字体优先级

如果 `-V mainfont` 指定的字体不存在，pandoc 会用系统默认（多半是 Latin 字体），
中文会"豆腐块"。

**降级方案**：

```bash
# 同时指定多个字体候选（pandoc 不支持 fallback，但可以在系统侧做）
# 或者用 reference.docx 嵌入字体
```

## 表格样式

pandoc 默认表格是简单边框。要彩色或斑马纹，用：

```markdown
| A | B |
|:-:|:-:|
| 1 | 2 |
```

或者在 YAML 里：

```yaml
table-style: "Table Grid"
```

但要生效必须配合 reference.docx。

## 章节与分页

```markdown
\newpage
```

## 编号列表与项目符号

```markdown
1. 第一
2. 第二
   - 子项
   - 子项
3. 第三
```

## 引用与脚注

```markdown
参见 [@smith2020, p. 15]。

[^1]: 脚注内容
```

需要 `references.bib` 和 `--citeproc` 参数。

## 嵌入图片

```markdown
![Alt text](image.png)
```

docx 输出后图片会被嵌入。

## 常见错误

### 错误 1：字体没生效，docx 里中文是方框

原因：fontconfig 找不到指定字体。检查 `fc-list | grep "字体名"`。

### 错误 2：表格在 docx 里换行混乱

pandoc 表格单元格内的多行内容用 `<br>` 或段落分隔，不是 `\n`。

### 错误 3：公式渲染失败

需要在 preamble 加：

```latex
\usepackage{amsmath}
\usepackage{amssymb}
```

并用 `pandoc input.md -o output.docx --pdf-engine=xelatex`（输出 PDF 时）。

docx 公式直接用 LaTeX 语法，pandoc 会转成 OMML。

### 错误 4：中文标点变成英文

pandoc 不会自动转换标点。Markdown 里手动用中文标点：

```markdown
"中文双引号"  ← 全角
'中文单引号'  ← 全角
,。；：？！  ← 全角
```

或者用 pandoc 插件 `smart` 扩展（默认开启）：

```bash
pandoc input.md -o output.docx  # 默认已开启 smart
```

### 错误 5：标题样式混乱

在 reference.docx 里手动设置 H1/H2/H3 样式，否则 pandoc 用默认（一律 Calibri Light）。

## 批量渲染脚本

```bash
#!/bin/bash
# render-all.sh
for md in chapters/*.md; do
  name=$(basename "$md" .md)
  pandoc "$md" -o "output/${name}.docx" \
    -V mainfont="Noto Serif CJK SC" \
    -V monofont="Sarasa Mono SC" \
    --toc --toc-depth=2
done
```

## 与 python-docx 联动

如果需要做 pandoc 做不到的精细操作（如加水印、加图章），先生成基础 docx，
再用 python-docx 后处理：

```python
import docx
from docx.shared import Inches

doc = docx.Document("base.docx")

# 加水印
section = doc.sections[0]
section.different_first_page_header_footer = True

# 加页眉图片
header = section.header
para = header.paragraphs[0]
run = para.add_run()
run.add_picture("logo.png", width=Inches(1.0))

doc.save("final.docx")
```