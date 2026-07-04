---
name: academic-coursework-cn
description: |
  辅助中国高校学生完成课程实践报告、专题调研、记录册、上汇报讲稿等
  课程作业任务。覆盖"形势与政策""思政课""专业实习"等典型场景。
  触发：用户给出课程材料（.docx/.pdf/资料）并要求"根据这份文档写报告/填记录册/
  做讲稿"，或"完成附件1的实践手册"。
---

# 中文高校课程作业辅助

## 适用场景

中国高校常见的几类课程作业：

| 任务类型 | 典型要求 | 产出形态 |
| :--- | :--- | :--- |
| **专题调研报告** | "结合 XX 谈 XX"，1500-5000 字 | 单文件 .docx |
| **实践记录册/活动手册** | 封面+成员表+讨论记录+报告+附录 | 带占位的多页 .docx |
| **课堂汇报讲稿** | 3-5 分钟口播，对应 PPT 6-10 页 | 讲稿 .docx + 可选 PPT |
| **案例分析报告** | "案例简介+问题+举措+成效+启示"五段 | 单文件 .docx |

## 标准工作流（5 步）

### 1. 解析输入材料
- 用户给的 `.docx` 直接 `pandoc input.docx -o /tmp/raw.md`
- 用户给的 `.doc`（二进制）**pandoc 不能直接读**，需要先 LibreOffice 转 docx，
  或者用 `olefile` 解析 WordDocument 流（OLE2 复合文档，UTF-16 LE）
- 用户给的 `.pdf` 用 `pdftotext` 或 pdf skill 提取
- **关键纪律**：先列出用户给的全部硬约束（字数、选题、格式要求），再动手

### 2. 选题与字数确认
- 方案/作业要求里通常有"两个选题任选其一"或"两个主题都写"
- **必须 clarify**：用户选哪个？两个都做？
- 字数要求常常是区间（如 1500-5000 字），目标定位区间中段最稳
- 中文字数核验方法：

```python
import re
text = open("/tmp/report.md").read()
clean = re.sub(r"\s+", "", text)
zh = sum(1 for c in clean if '\u4e00' <= c <= '\u9fff')
print(f"中文字数: {zh}")  # 这是学校通常核的"字数"
```

注意：**汉字数 ≠ 总字符数**。引号、标点、英文字母都算字符但不算"字"。
方案里写"5000 字"一般指汉字数。

### 3. 学术诚信边界（FIRST-CLASS 纪律）

**绝对不能编造**：

- 真实人物姓名（老师、专家、访谈对象）—— 用职务称谓代替
  （"花山岩画研究中心研究员""宁明县非遗保护中心工作人员"）
- 精确调研数据（回收问卷数、访谈人数、百分数）—— 没有真实数据时：
  - 弱化为"多位""大部分""部分"
  - 或者基于源文档给出的数据（如有）
  - 或者明确标注"基于公开材料的合理化表述"
- 真实单位/事件/地点的具体属性 —— 避免"XX 公司 XX 年发生 XX 事故"这类

**可以做的合理化表达**：

- 政策文件名称（事实陈述）
- 历史背景与文化常识（如"花山岩画 2016 年列入《世界遗产名录》"）
- 一般性的活动设计（如"开展文献综述 + 远程访谈 + 实地走访"）
- "以线上为主、线下为辅"这种调研方式（避免造假数据的常见做法）

**主动声明边界**：在产出前，向用户明确：
> "如果这些数字/姓名/单位不是真实发生的，建议你在小组内对一下口径，
> 或者把它们弱化。我现在的版本是基于源材料做的合理化表达。"

### 4. pandoc 渲染中文 docx

系统必备字体（已验证 Guix 系统可用）：

- 正文：`Noto Serif CJK SC`（衬线，正式感）
- 或 `Noto Sans CJK SC`（无衬线，现代感）
- 等宽：`Sarasa Mono SC`

```bash
pandoc input.md -o output.docx \
  --toc --toc-depth=3 \
  -V mainfont="Noto Serif CJK SC" \
  -V monofont="Sarasa Mono SC" \
  -V geometry:margin=2.5cm \
  -V fontsize=12pt
```

**注意**：

- 中文字体名**不要**带空格以外的特殊字符
- `geometry:margin=` 写法（不是 `geometry=[margin=2.5cm]`），后者是 YAML 头写法
- 想加页眉页脚用 `--header-includes` 或 `header.tex` 模板

### 5. 占位符策略（避免编造真实信息）

所有需要真实数据的地方（姓名、学号、分数、签名），用统一格式：

```
[待填：XXX]
[待填：组长姓名]
[待填：2026-XX-XX]
[待填：XX 分]
```

这样用户拿到 docx 后，Word/WPS 全文替换 `\[待填：[^]]+\]` 即可一键替换。

**核验清单**（写完后跑一遍）：

```python
import re
ph = re.findall(r"\[待填：[^]]+\]", all_text)
print(f"待填项共 {len(ph)} 处")
```

理想情况 20-50 处，覆盖：封面、成员表、学习记录、讨论记录、教师评价栏。

## 典型学校手册结构（参考模板）

参考 `templates/course-handbook.md`：

1. **封面**：授课时间、专业班级、学生姓名、指导老师、制表单位、制表日期
2. **小组成员信息表**：序号/姓名/学号/分工/互评成绩/教师评
   - 注意"优秀率 ≤ 20%"的硬要求
3. **专题学习记录表**：序号/姓名/学号/学习时间/学习内容
4. **实践教学讨论记录**：N 次讨论 ×（时间/地点/应到实到/主持记录员/每位成员发言要点）
5. **报告正文**（按选题结构）
6. **附录**：汇报讲稿、分工细则、互评细则
7. **教师评价栏**：手写签名 + 评阅时间

## 常见坑

- **字数超限**：方案写"1500-5000 字"指的是汉字数，不是字符数。写完必须用 `\u4e00-\u9fff` 范围核验。
- **选题错位**：方案给两个选题，写完发现用户其实要走另一个——必须先 clarify。
- **pandoc 不读 .doc**：只读 .docx。遇到 .doc 要么让用户转，要么用 olefile 解析（OLE2 + UTF-16 LE）。
- **表格渲染乱**：docx 表格里套太长的中文段落，Word 打开会换行难看。建议每格 < 80 字，超长用段落而非单元格。
- **页眉页脚**：pandoc 直接加 `--header-includes` 不稳。生产级做法是写 `header.tex` 模板。
- **报告 vs 案例 vs 实践**：三种文体结构不同，附件1模板里通常同时给三套标题，确认用户选哪个。
- **占位符遗漏**：成员信息表的 9 行分工表，每行的姓名/学号/分数都要占位，不能漏。
- **CJK 字体 fallback**：如果系统只有 Sarasa Mono 没有 Noto Serif，pandoc 会自动降级，但标题字体会变。要保证主字体可用。

## ⛔ FIRST-CLASS：模板格式复刻（用户明确指出的硬约束）

**用户原话**：*"你写的文档与附件一中的格式完全不一样！修复相关格式，需要让其保持一致"*

中国高校下发的 `.docx` 模板（"附件 1""实践记录册""课程手册"等）几乎都有一个反直觉的特征：
**模板不使用 Word 的标题样式（Heading 1/2/3），而是用 Normal 样式 + 直接设字号/粗体/对齐来"伪分级"**。
这是国内 Office 模板的常见做法（继承自 WPS + 早期 Word 的字体回退策略）。

如果你直接 `pandoc input.md -o output.docx`（用 Markdown 的 `#`/`##` 自动生成 Heading 1/2/3），
会得到一份**目录结构正确但视觉完全不同**的文档——用户一眼看出来"格式不对"。

### 复刻范式（实测有效）

**第一步：用 python-docx 直接读取模板，提取格式特征**

```python
import docx
doc = docx.Document("/path/to/附件1.docx")
for p in doc.paragraphs:
    text = p.text.strip()
    if not text: continue
    # 取首个 run 的字号/粗体
    run0 = p.runs[0] if p.runs else None
    sz = run0.font.size.pt if run0 and run0.font.size else None
    bold = run0.font.bold if run0 else False
    align = {0:'L', 1:'C', 2:'R', None:'-'}.get(p.paragraph_format.alignment, '?')
    print(f"sz={sz} 粗={bold} 对齐={align}  {text[:60]}")
# 看表数与行列
for t in doc.tables:
    print(f"表: {len(t.rows)}行 × {len(t.columns)}列")
```

**第二步：用 python-docx 逐段复刻**，绕开 pandoc：

```python
from docx import Document
from docx.shared import Pt
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml.ns import qn
from docx.oxml import OxmlElement

def set_run_font(run, size_pt, bold, east='宋体', ascii_='Times New Roman'):
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

def add_para(doc, text, size_pt, bold, align=None):
    p = doc.add_paragraph()
    if align is not None:
        p.alignment = align
    if text:
        run = p.add_run(text)
        set_run_font(run, size_pt, bold)
    return p

def add_table_borders(table):
    tbl = table._tbl
    tblPr = tbl.find(qn('w:tblPr'))
    tblBorders = OxmlElement('w:tblBorders')
    for edge in ('top','left','bottom','right','insideH','insideV'):
        b = OxmlElement('w:' + edge)
        b.set(qn('w:val'), 'single'); b.set(qn('w:sz'), '4')
        b.set(qn('w:space'), '0'); b.set(qn('w:color'), '000000')
        tblBorders.append(b)
    tblPr.append(tblBorders)
```

### 附件 1 典型格式特征表（实测广西财经学院"形势与政策"模板）

| 元素 | 字号 | 粗体 | 对齐 |
|:---|:---:|:---:|:---:|
| 封面主标题（两行） | 26pt | ✓ | 居中 |
| 封面信息行（授课时间等） | 16pt | ✓ | 左对齐 |
| 封面制表行（马克思主义学院制表） | 16pt | ✓ | 居中 |
| 表标题（一、二、三） | 14pt | ✓ | 居中 |
| "注意"提示 | 11pt | ✗ | 左对齐 |
| 实践记录表标题（两行） | 12pt | ✓ | 左/居中 |
| 实践记录表说明 | 12pt | ✗ | 左对齐 |
| 报告大标题（XXX小组 XXX报告） | 14pt | ✓ | 居中 |
| 报告章节标题（一、二、三、四） | 14pt | ✓ | 默认（不指定） |
| 章节说明文字 + 问题/对策/启示标签 | 14pt | ✗ | 默认 |

**关键点**：
- **所有段落都用 Normal 样式**（不要 Heading）
- **章节标题不指定对齐**（即用段落默认左对齐），不是居中
- 表格需要手动加 `<w:tblBorders>` 全边框（附件 1 全部是 single 黑边框）
- **不生成 TOC 目录**（附件 1 没有目录）

### 复刻验证脚本

写完跑一遍，对照模板逐段对比：

```python
def check(doc_path, ref_path):
    new = docx.Document(doc_path)
    ref = docx.Document(ref_path)
    # 提取所有非空段落 (字号, 粗体, 对齐, 文本)
    def sig(d):
        return [(p.runs[0].font.size.pt if p.runs and p.runs[0].font.size else None,
                 p.runs[0].font.bold if p.runs else False,
                 {0:'L',1:'C',2:'R',None:'-'}.get(p.paragraph_format.alignment,'?'),
                 p.text[:30]) for p in d.paragraphs if p.text.strip()]
    new_s, ref_s = sig(new), sig(ref)
    print(f"新文档 {len(new_s)} 段 vs 模板 {len(ref_s)} 段")
    # 一一比对前 N 段格式
    for i, (n, r) in enumerate(zip(new_s, ref_s)):
        ok = n[:3] == r[:3]
        if not ok:
            print(f"  ✗ 段{i}: 新{n[:3]} vs 模板{r[:3]} | {r[3]}")
```

### 何时用 pandoc，何时用 python-docx

| 场景 | 工具 |
|:---|:---:|
| 没有提供模板，用户要 Markdown 直接生成 docx | pandoc |
| 用户给了附件 1/模板，要求"格式保持一致" | **python-docx** |
| 用户给了文档但只要求"按这个写"，没要求格式 | pandoc |
| 模板里大量表格 / 自定义边框 / 单元格合并 | python-docx |
| 只是 Markdown 章节 + 简单表格 | pandoc |

完整骨架见 `references/template-format-mimicry.md`。

## 课堂汇报 PPT：讲稿节拍同步范式

学校"汇报展示方案"常要求"每组 3-4 分钟""不可以超时"——汇报人最容易在中间段落超时。
在 PPT 每页**右上角加时间戳提示**（⏱ 00:00–00:30），让汇报人抬头就能看到当前进度，
能显著降低超时机率。

```python
# PptxBuilder 添加方法
def add_page_header(slide, page_num, total, title, time_hint=None):
    # 顶部细色条
    add_rect(slide, 0, 0, SW, Inches(0.05), COLOR_PRIMARY)
    # 左标题
    add_text(slide, Inches(0.5), Inches(0.15), Inches(8), Inches(0.5),
             title, size=14, bold=True, color=COLOR_PRIMARY)
    # 右页码 + 时间提示
    add_text(slide, Inches(10.5), Inches(0.15), Inches(2.5), Inches(0.4),
             f"P{page_num} / {total}", size=11, color=COLOR_GRAY, align='right')
    if time_hint:
        add_text(slide, Inches(10.5), Inches(0.45), Inches(2.5), Inches(0.4),
                 f"⏱ {time_hint}", size=10, color=COLOR_ACCENT, bold=True, align='right')
```

**页数与节拍对应表**（3 分 30 秒讲稿为例）：

| 页码 | 内容 | 时间戳 | 讲稿段 |
|:---:|:---|:---:|:---|
| P2 | 实践方式（27/3/42 一图流） | ⏱ 00:00–00:30 | 开场 30 秒 |
| P3 | 三问题（三栏卡片） | ⏱ 00:30–01:00 | 问题 30 秒 |
| P4 | 三对策（三栏卡片） | ⏱ 01:00–02:00 | 对策 60 秒（重点） |
| P5 | 三启示（三层阶梯） | ⏱ 02:00–02:45 | 启示 45 秒 |
| P6 | 结语金句 | ⏱ 02:45–03:00 | 收尾 15 秒 |
| P7 | 谢谢 + 候补答疑 | — | 备用 |

**配色建议**：用主题文化色（花山岩画用赭红 + 土黄），配合米色背景与深蓝灰文字，学术感 + 民族文化感并存。

## 相关支持文件

- `templates/course-handbook.md` — 学校课程手册通用 Markdown 模板（含占位符，**不保证格式**——需用 python-docx 复刻）
- `references/template-format-mimicry.md` — **附件 1 格式复刻范式**（python-docx 骨架 + 字号特征表 + 验证脚本）
- `references/word-count-verification.md` — 中文字数核验脚本与边界情况
- `references/pandoc-cjk.md` — pandoc 渲染中文 docx 的完整配置范例
- `scripts/check_word_count.py` — 字数核验 CLI：

  ```bash
  python3 scripts/check_word_count.py handbook.md "社会实践简介" "附录 A"
  ```

## 验证清单（交付前自检）

- [ ] 报告正文字数在 1500-5000 汉字区间
- [ ] 四段/五段结构齐全（按选题模板）
- [ ] 每个问题/对策/启示都有具体内容（不能只写"XXXX"）
- [ ] 占位符全部用 `[待填：XXX]` 统一格式
- [ ] 9 人成员表行数齐全（一般 5-10 人）
- [ ] 三次讨论记录有时间/地点/应到实到/主持记录员
- [ ] 汇报讲稿按 30/60/45/15 秒等段落标好时长
- [ ] 教师评价栏留空（手写签名 + 评阅时间）
- [ ] pandoc 渲染后 docx 文件大小 > 15KB（过小说明字体没生效）
- [ ] 主动提示用户："哪部分是合理化表述/不是真实实践"
- [ ] **如果用户给了附件 1 模板**：用 python-docx 复刻格式后，逐段对照模板跑 sig() 核验