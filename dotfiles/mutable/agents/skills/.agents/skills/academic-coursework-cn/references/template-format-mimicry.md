# 附件 1 模板格式复刻范式

> 适用场景：用户给了"附件 1""实践记录册""课程手册"等高校下发的 `.docx` 模板，
> 要求产出文档"格式与附件 1 保持一致"。

## 为什么 pandoc 搞不定

中国高校下发的 `.docx` 模板（实测广西财经学院"形势与政策"模板、马列学院制发的实践手册等）几乎都有一个反直觉的特征：

**模板不使用 Word 的标题样式（Heading 1/2/3），而是用 Normal 样式 + 直接设字号/粗体/对齐来"伪分级"。**

这是国内 Office 模板的常见做法（继承自 WPS + 早期 Word 的字体回退策略）。
docDefaults 里通常只有 Normal 一个默认样式，没有 Heading 1/2/3。

如果你直接 `pandoc input.md -o output.docx`（用 Markdown 的 `#`/`##` 自动生成 Heading 1/2/3），
会得到一份**目录结构正确但视觉完全不同**的文档——用户一眼看出来"格式不对"。

## 解决方案：python-docx 逐段复刻

绕开 pandoc 的样式映射，直接用 python-docx 读模板 + 写新文档。

### 第一步：读取模板格式特征

```python
import docx

doc = docx.Document("/path/to/附件1.docx")

print("=== 段落格式 ===")
for i, p in enumerate(doc.paragraphs):
    text = p.text.strip()
    if not text:
        continue
    run0 = p.runs[0] if p.runs else None
    sz = run0.font.size.pt if run0 and run0.font.size else None
    bold = run0.font.bold if run0 else False
    align = {0: 'L', 1: 'C', 2: 'R', None: '-'}
    a = align.get(p.paragraph_format.alignment, '?')
    print(f"  [{i:3d}] sz={sz} 粗={bold} 对齐={a}  {text[:60]}")

print(f"\n=== 表格 ===\n共 {len(doc.tables)} 张")
for ti, t in enumerate(doc.tables):
    print(f"  表 {ti+1}: {len(t.rows)} 行 × {len(t.columns)} 列")
    # 看表头
    for ci, cell in enumerate(t.rows[0].cells):
        print(f"    表头[{ci}]: {cell.text[:30]}")
```

### 第二步：用 python-docx 写新文档

最小骨架（实测可用）：

```python
from docx import Document
from docx.shared import Pt, Cm
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_ALIGN_VERTICAL
from docx.oxml.ns import qn
from docx.oxml import OxmlElement


def set_run_font(run, size_pt, bold=False, east='宋体', ascii_='Times New Roman'):
    """设置 run 的字体（中英文分别指定）"""
    run.font.name = ascii_
    run.font.size = Pt(size_pt)
    run.font.bold = bold
    rPr = run._element.get_or_add_rPr()
    rFonts = OxmlElement('w:rFonts')
    rFonts.set(qn('w:ascii'), ascii_)
    rFonts.set(qn('w:hAnsi'), ascii_)
    rFonts.set(qn('w:eastAsia'), east)
    rFonts.set(qn('w:cs'), ascii_)
    rPr.append(rFonts)


def add_para(doc, text, size_pt=14, bold=False, align=None):
    """添加段落（不指定 align 时用段落默认左对齐）"""
    p = doc.add_paragraph()
    if align is not None:
        p.alignment = align
    if text:
        run = p.add_run(text)
        set_run_font(run, size_pt, bold)
    return p


def add_table_borders(table):
    """给表格加全边框（黑色 single 1pt）"""
    tbl = table._tbl
    tblPr = tbl.find(qn('w:tblPr'))
    tblBorders = OxmlElement('w:tblBorders')
    for edge in ('top', 'left', 'bottom', 'right', 'insideH', 'insideV'):
        b = OxmlElement('w:' + edge)
        b.set(qn('w:val'), 'single')
        b.set(qn('w:sz'), '4')
        b.set(qn('w:space'), '0')
        b.set(qn('w:color'), '000000')
        tblBorders.append(b)
    tblPr.append(tblBorders)


def set_cell_text(cell, text, size_pt=14, bold=False,
                  align=WD_ALIGN_PARAGRAPH.CENTER,
                  vertical=WD_ALIGN_VERTICAL.CENTER):
    """填表格单元格，支持 \\n 分隔多行"""
    cell.vertical_alignment = vertical
    # 清空原段落
    for p in cell.paragraphs:
        p._element.getparent().remove(p._element)
    # 新建段落
    for line in text.split('\n'):
        p = cell.add_paragraph()
        p.alignment = align
        pf = p.paragraph_format
        pf.space_before = Pt(0)
        pf.space_after = Pt(0)
        run = p.add_run(line)
        set_run_font(run, size_pt, bold)


# 创建文档
doc = Document()

# 页面边距（按需调整）
section = doc.sections[0]
section.top_margin = Cm(2.54)
section.bottom_margin = Cm(2.54)
section.left_margin = Cm(3.18)
section.right_margin = Cm(3.18)

# Normal 样式默认字体（与 docDefaults 一致）
normal = doc.styles['Normal']
normal.font.name = 'Times New Roman'
normal.font.size = Pt(10.5)
normal_rPr = normal.element.get_or_add_rPr()
rFonts = OxmlElement('w:rFonts')
rFonts.set(qn('w:ascii'), 'Times New Roman')
rFonts.set(qn('w:hAnsi'), 'Times New Roman')
rFonts.set(qn('w:eastAsia'), '宋体')
rFonts.set(qn('w:cs'), 'Times New Roman')
normal_rPr.append(rFonts)

# ... 添加内容 ...

doc.save("/path/to/output.docx")
```

### 第三步：复刻验证

写完跑一遍，对照模板逐段对比格式：

```python
def verify_format(new_path, ref_path):
    new = docx.Document(new_path)
    ref = docx.Document(ref_path)

    def sig(d):
        """提取 (字号, 粗体, 对齐, 文本) 四元组"""
        out = []
        for p in d.paragraphs:
            text = p.text.strip()
            if not text:
                continue
            run0 = p.runs[0] if p.runs else None
            sz = run0.font.size.pt if run0 and run0.font.size else None
            bold = run0.font.bold if run0 else False
            a = {0: 'L', 1: 'C', 2: 'R', None: '-'}
            align = a.get(p.paragraph_format.alignment, '?')
            out.append((sz, bold, align, text[:30]))
        return out

    new_s, ref_s = sig(new), sig(ref)
    print(f"新文档 {len(new_s)} 段 vs 模板 {len(ref_s)} 段")

    mismatches = 0
    for i, (n, r) in enumerate(zip(new_s, ref_s)):
        if n[:3] != r[:3]:  # 字号/粗体/对齐
            print(f"  ✗ 段{i}: 新{n[:3]} vs 模板{r[:3]} | {r[3]}")
            mismatches += 1

    if mismatches == 0:
        print("✓ 所有段落格式与模板一致")
    else:
        print(f"共 {mismatches} 处不一致，需修复")

    # 表对比
    print(f"\n新文档 {len(new.tables)} 张表 vs 模板 {len(ref.tables)} 张表")
    for i, (n_t, r_t) in enumerate(zip(new.tables, ref.tables)):
        if len(n_t.rows) != len(r_t.rows) or len(n_t.columns) != len(r_t.columns):
            print(f"  ✗ 表{i+1}: 新{len(n_t.rows)}x{len(n_t.columns)} vs 模板{len(r_t.rows)}x{len(r_t.columns)}")
        else:
            print(f"  ✓ 表{i+1}: {len(r_t.rows)}x{len(r_t.columns)} 一致")
```

## 附件 1 典型格式特征表（实测广西财经学院"形势与政策"模板）

| 元素 | 字号 | 粗体 | 对齐 |
|:---|:---:|:---:|:---:|
| 封面主标题（两行） | 26pt | ✓ | 居中 |
| 封面信息行（授课时间/专业班级/学生姓名/指导老师） | 16pt | ✓ | 左对齐 |
| 封面制表行（马克思主义学院制表 + 时间） | 16pt | ✓ | 居中 |
| 表标题（一、二、三） | 14pt | ✓ | 居中 |
| "注意"提示段落 | 11pt | ✗ | 左对齐 |
| 实践记录表标题第一行（"守护瑰宝..."） | 12pt | ✓ | 左对齐 |
| 实践记录表标题第二行（"实践教学记录表"） | 12pt | ✓ | 居中 |
| 实践记录表说明文字 | 12pt | ✗ | 左对齐 |
| 报告大标题（XXX小组 XXX报告） | 14pt | ✓ | 居中 |
| 报告章节标题（一、二、三、四） | 14pt | ✓ | 默认（不指定） |
| 章节说明文字（"可从..."等占位说明） | 14pt | ✗ | 默认 |
| 问题/对策/启示标签（问题一：XXX 等） | 14pt | ✗ | 默认 |

## 关键陷阱

1. **章节标题不指定对齐**：附件 1 里"一、社会实践简介"这种标题的对齐方式是 **DEFAULT**（即段落默认左对齐），不是 LEFT 也不是 CENTER。如果你显式设了 `align=WD_ALIGN_PARAGRAPH.LEFT`，理论上等价，但有些 Word 版本会判定为"显式设置"，与"未指定"不一致。**最佳实践：不传 align 参数**。

2. **表格行数要严格对齐**：附件 1 表 3（讨论记录表）实际是 **22 行**，不是常见的 20 或 21；表 4（教师评价表）是 **15 行**（前 14 行也是"讨\n论\n记\n录"占位，最后一行才是评价）。这两张表看似可以合并，但附件 1 实际是分开的——保留原结构。

3. **cell 中的竖排文字**：用 `'讨\n论\n记\n录'`（在 Python 字符串里就是 4 个 `\n` 分隔），让 Word 单元格自动竖排显示。

4. **不要用 Heading 样式**：不要给任何段落设置 `style.name = 'Heading 1'`。即使视觉上"看起来像标题"，也要用 Normal 样式 + 直接设字号。

5. **docDefaults 别动**：附件 1 的 docDefaults 只有 Normal 样式，没有 Heading 1/2/3 定义。如果你手动加 Heading 样式，会破坏模板的隐含约定。

## 何时该用 pandoc vs python-docx

| 场景 | 推荐工具 |
|:---|:---:|
| 没有提供模板，用户要 Markdown 直接生成 docx | pandoc |
| **用户给了附件 1/模板，要求"格式保持一致"** | **python-docx** |
| 用户给了文档但只要求"按这个写"，没要求格式 | pandoc |
| 模板里大量表格 / 自定义边框 / 单元格合并 | python-docx |
| 只是 Markdown 章节 + 简单表格 | pandoc |
| 需要嵌入图片、页眉页脚、复杂排版 | python-docx |
| 用户最后会自己用 Word/WPS 编辑 | python-docx（pandoc 输出的 docx 在 Word 中样式易乱） |

## 完整可运行示例

`templates/course-handbook.md` 是 pandoc 友好的 Markdown 模板（结构占位用），
但**实际产出必须用 python-docx 复刻模板的格式**。复刻流程：

1. 读取用户给的附件 1 → 用上面的"第一步"脚本提取格式特征表
2. 用 python-docx 按格式特征表 + 报告正文内容生成新文档
3. 用"第三步"验证脚本对照模板逐段比对
4. 不一致的地方回到代码里调整对应参数（通常是 align / size_pt / bold）

## 反模式（不要这样做）

- ❌ 用 `pandoc -t docx --reference-doc=附件1.docx` 试图"借"模板样式
  → 参考文档的样式映射对"伪分级"模板完全失效，Heading 1/2/3 还是会用参考文档里的（或者新建）
- ❌ 把 Markdown 写成 `## 一、社会实践简介` 然后转 docx
  → 会得到 Heading 2 样式，附件 1 用的是 Normal + 14pt 粗体
- ❌ 偷懒把字号统一设成 12pt
  → 附件 1 的封面是 26pt、信息行是 16pt、表格标题是 14pt、提示是 11pt，必须分层

## 验证清单

- [ ] docDefaults 没动（只设 Normal 样式）
- [ ] 所有段落都用 Normal 样式（没有 Heading 1/2/3）
- [ ] 封面主标题 26pt 粗体居中
- [ ] 信息行 16pt 粗体左对齐
- [ ] 表标题 14pt 粗体居中
- [ ] 报告章节标题 14pt 粗体（不指定对齐）
- [ ] 表格加了全边框（黑色 single 1pt）
- [ ] 表格行数与模板一致（特别是 22 行讨论表 + 15 行评价表）
- [ ] 没有自动生成 TOC 目录