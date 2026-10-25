# 中文字数核验脚本

## 核心方法

中国高校作业的"字数"通常指**汉字数**（不含标点、空白、英文字母、数字）。
但不同学校、不同老师核法不同，下面给出三种粒度。

## 三种字数核验

```python
import re

text = open("/tmp/report.md").read()

# 1. 中文字数（最常见）
clean = re.sub(r"\s+", "", text)
zh_only = sum(1 for c in clean if '\u4e00' <= c <= '\u9fff')
print(f"汉字数: {zh_only}")

# 2. 含标点的中文字符（汉字 + 中文标点）
zh_with_punct = sum(1 for c in clean
                    if '\u4e00' <= c <= '\u9fff'
                    or c in '，。、；：？！""''【】（）《》—…·')
print(f"汉字+中文标点: {zh_with_punct}")

# 3. 去空白后所有字符
print(f"字符数(去空白): {len(clean)}")
```

## 区间定位经验值

| 字数要求 | 目标定位 |
| :--- | :--- |
| 800-1500 字 | 1200 字左右 |
| 1500-3000 字 | 2300 字左右 |
| 1500-5000 字 | 3300-4000 字最稳 |
| 3000-5000 字 | 4200 字左右 |
| 5000 字以上 | 5500-6500 字 |

**为什么不在上限**：超字数容易被扣分或要求删减，留余地给润色。

## 范围界定

汉字 Unicode 范围：

- 基本汉字：`\u4e00` - `\u9fff`（覆盖 99% 的现代中文）
- 扩展 A：`\u3400` - `\u4dbf`（生僻字）
- 扩展 B-F：`\u{20000}` - `\u{2FA1F}`（罕用字）

绝大多数场景 `\u4e00-\u9fff` 就够了，遇到生僻字再扩展。

## Word 里的"字数统计"算法

Word 的"字数（不计空格）"统计的是**所有字符**（包括字母、数字、标点），
但**不算空格**。

所以 Word 显示 "3278 字" ≠ Python `\u4e00-\u9fff` 算出的汉字数。

**经验法则**：Word 显示字数 ≈ Python 算出的中文字数 × 1.2 ~ 1.4
（取决于标点和英文比例）。

如果用户说"Word 显示 4400 字"，实际 Python `\u4e00-\u9fff` 算出的大概 3100-3600。

## docx 后置核验

写完 .docx 后，用 python-docx 重新读一遍统计：

```python
import docx, re

doc = docx.Document("/tmp/handbook.docx")
all_text = "\n".join(p.text for p in doc.paragraphs)
for t in doc.tables:
    for row in t.rows:
        for cell in row.cells:
            all_text += "\n" + cell.text

# 找到报告正文区间
m_start = all_text.find("报告正文起始关键字")
m_end = all_text.find("附录起始关键字")
body = all_text[m_start:m_end]

clean = re.sub(r"\s+", "", body)
zh = sum(1 for c in clean if '\u4e00' <= c <= '\u9fff')
print(f"报告正文汉字数: {zh}")
```

## 常见踩坑

1. **把字符数当字数**——包含标点符号的字符数总比汉字数大 30-50%
2. **markdown 标记算字数**——`#` `*` `_` 等语法字符要预先去除
3. **英文单词算 1 字**——大多数学校会把 "AI" 算 2 字（按字母数），少数算 1 字
4. **引号导致字数膨胀**——"全角引号"比"直引号"字符大 3 倍
5. **重叠表格不合并**——核验时不要把表格 + 段落合在一起算