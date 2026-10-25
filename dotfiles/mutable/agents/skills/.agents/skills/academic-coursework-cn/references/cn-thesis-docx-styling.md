# 国内论文排版规范 docx 生成与验证（实测管线）

适用：没有下发格式模板，但要求「符合国内大学论文排版规范」的 markdown → docx 任务。
路线：pandoc 生成骨架 → python-docx 后处理排版 → 三层核验。

## 0. 工具准备（Guix）

```bash
guix package -p /tmp/docx-profile -i python python-docx
# 坑：只装 python-docx 不会带入 python 解释器（不传递），必须显式 -i python
PYTHONPATH=/tmp/docx-profile/lib/python3.12/site-packages /tmp/docx-profile/bin/python3 脚本.py
```

## 1. pandoc 生成骨架

```bash
pandoc input.md -o output.docx
```

- pandoc 的 Heading 样式默认是**蓝色**——国内规范要求黑色，后处理必须改。
- `-V mainfont/geometry` 等变量只对 PDF/LaTeX 生效，docx 输出静默忽略。

## 2. python-docx 后处理（实测目标值）

| 元素 | 目标 |
|---|---|
| 主标题/一级标题（一、二、…） | 黑体(Noto Sans CJK SC) 16pt 加粗 居中 |
| 二级标题（（一）…） | 黑体 14pt 加粗 |
| 正文 | 宋体(Noto Serif CJK SC) 12pt(小四) 首行缩进2字符 1.5倍行距 |
| 表格 | 10.5pt(五号) 宋体 + 黑色单线全边框 + 表头加粗 |
| 页面 | A4 21.0×29.7cm，边距上下 2.54cm 左右 3.17cm |
| 标题颜色 | RGBColor(0,0,0)，覆盖 pandoc 蓝色 |

```python
import docx
from docx.shared import Pt, Cm, RGBColor
from docx.enum.text import WD_LINE_SPACING
from docx.oxml.ns import qn
from docx.oxml import OxmlElement

def set_run(run, size, bold, east, ascii_='Times New Roman'):
    run.font.name = ascii_; run.font.size = Pt(size); run.font.bold = bold
    rPr = run._element.get_or_add_rPr()
    rFonts = rPr.find(qn('w:rFonts'))
    if rFonts is None:
        rFonts = OxmlElement('w:rFonts'); rPr.append(rFonts)
    rFonts.set(qn('w:ascii'), ascii_); rFonts.set(qn('w:hAnsi'), ascii_)
    rFonts.set(qn('w:eastAsia'), east); rFonts.set(qn('w:cs'), ascii_)

def fmt(p, size, bold, east, align=None, indent_chars=0, line=1.5):
    if align is not None: p.alignment = align
    pf = p.paragraph_format
    if indent_chars: pf.first_line_indent = Pt(size * indent_chars)  # 2字符≈Pt(24)@12pt
    pf.line_spacing_rule = WD_LINE_SPACING.MULTIPLE; pf.line_spacing = line
    for r in p.runs:
        set_run(r, size, bold, east)
        r.font.color.rgb = RGBColor(0, 0, 0)  # 标题必须改黑
```

关键点：

- **中文字体必须写 `w:rFonts/@w:eastAsia`**：`run.font.name` 只写 ascii/hAnsi，
  对中文无效。
- 标题层级按中文标号文字判定（`一、`/`（一）`前缀）比依赖 Word Heading 样式更稳
  （模板类文档常见 Normal+伪分级，见 template-format-mimicry.md）。
- 表格边框：`<w:tblBorders>` 六向 single/sz=4/color=000000，复用
  template-format-mimicry.md 的 `add_table_borders()`；顺带表头行加粗。

## 3. 核验（三层，层层便宜过一层贵）

1. **格式签名抽查**：python-docx 重开文档，打印各段
   `(字号, 粗体, eastAsia, 首行缩进, 行距)`——标题黑体居中、正文缩进 24pt。
2. **内容往返**：`pandoc out.docx -t markdown -o /tmp/roundtrip.md`，比对汉字数
   （`\u4e00-\u9fff`）与标题结构，应与源 md 一致。
3. **视觉渲染抽查**（最终一关，必做）：
   - 宿主无 LibreOffice 时，用 distrobox 容器内的 soffice 渲染。容器（如
     my-distrobox/Arch）带 WPS/LibreOffice 且有**中易宋体/黑体**（simsun.ttc/
     msyh.ttc）——正是国内论文标准字体，比宿主 Guix 的 Noto CJK 更接近真实观感：
     ```bash
     distrobox-enter -n my-distrobox -- \
       soffice --headless --convert-to pdf <docx> --outdir /tmp/x
     ```
     注意路径：容器与宿主共享 `$HOME`，用容器内的 `~/Projects/...` 路径。
   - pymupdf 把 PDF 首页+含表页+末两页转 PNG（110dpi）：
     `guix package -p <profile> -i python python-pymupdf`
   - vision 检查项：标题黑体加粗居中？正文首行缩进？乱码/溢出/对齐？
     **标题是否还是蓝色**（pandoc 默认色漏改）？表格边框完整？

## 4. 实战记录

2026-09-03 AI焦虑调研报告（7598 汉字 / 11 页）全程用此管线；vision 抽查发现
pandoc 蓝色标题与表格无边框两处问题并修复。