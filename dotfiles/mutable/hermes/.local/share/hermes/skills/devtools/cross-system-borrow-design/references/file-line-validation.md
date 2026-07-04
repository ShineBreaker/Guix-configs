# file:line 引用校验脚本

> PLAN.md 里所有 `path:line` 引用必须能被 grep 验证存在。本文件是
> 实际跑过的脚本片段,直接用即可。

## 反模式(常见坑)

```bash
# ❌ 错误:grep 抓到的"路径"会被反引号或括号污染
grep -oE '/path/[A-Za-z0-9./_-]+:[0-9-]+' PLAN.md

# 实际:用户写 `src/foo.ts:42` 在 markdown 里,grep 会抓到
# `src/foo.ts:42` ✅;但如果用户写 `src/foo.ts(完整文件):42` 或
# `src/foo.ts:42 行` 就会被截断
```

## 正确做法(2026-06-29 实战)

```bash
# Step 1:提取所有 file:line 模式(允许路径含反引号、括号、行号范围)
grep -oE '/[A-Za-z0-9./_-]+:[0-9]+(-[0-9]+)?' PLAN.md | sort -u > /tmp/refs.txt

# Step 2:逐个验证 path 存在 + line 范围合法
while read -r ref; do
  path=$(echo "$ref" | cut -d: -f1)
  line_spec=$(echo "$ref" | cut -d: -f2)
  start_line=$(echo "$line_spec" | cut -d- -f1)
  end_line=$(echo "$line_spec" | cut -d- -f2)
  end_line="${end_line:-$start_line}"

  if [ ! -e "$path" ]; then
    echo "MISSING PATH: $ref"
    continue
  fi

  file_lines=$(wc -l < "$path")
  if [ "$end_line" -gt "$file_lines" ]; then
    echo "BAD LINE: $ref (file has $file_lines lines)"
  fi
done < /tmp/refs.txt
```

## 已知陷阱

### 1. 绝对路径前缀

`grep -oE '/[A-Za-z0-9./_-]+:[0-9]+'` 要求路径以 `/` 开头。如果文档用
`packages/opencode/src/...`(相对),这种不会被捕获。**强制要求所有
引用用绝对路径**(在 PLAN.md 写作规范里硬约束)。

### 2. 反引号嵌套的"语义路径"

```markdown
| 概念 | 参考 |
|---|---|
| Schema | `/path/foo.ts`(完整文件) |
```

grep 抓到的是 `/path/foo.ts`(完整文件):...` 里的`/path/foo.ts` 不带行号,
不构成可校验引用。**校验脚本会跳过**,人工 review。

### 3. 行号超出范围

文件 A 1500 行,你写 `A:1700`。脚本会报 BAD LINE。**git 改文件后
行号会变,需要重新校验**。

### 4. 多个文件同名

```bash
# 不同路径下两个同名文件
/home/a/proj/src/foo.ts
/home/b/proj/src/foo.ts

# PLAN.md 引用要带绝对路径,否则校验脚本只看 path 不看 line
```

## 写文档时的工作流

1. **写每个 file:line 引用之前**:打开那个文件,跳到目标行,**亲手看**。
   别靠记忆,别靠 grep 找完就写。
2. **写完之后**:跑上面的脚本,所有 MISSING / BAD LINE 修掉。
3. **commit 前**:再跑一次(可能你编辑时改了文件,导致引用失效)。

## 替代方案:用 rg + Python

```python
import re, pathlib, subprocess

# 提取所有引用
content = pathlib.Path("PLAN.md").read_text()
refs = re.findall(r'(/[A-Za-z0-9./_-]+\.\w+):(\d+)(?:-(\d+))?', content)

# 验证
errors = []
for path, start, end in refs:
    p = pathlib.Path(path)
    if not p.exists():
        errors.append(f"MISSING: {path}:{start}")
        continue
    total = sum(1 for _ in p.open())
    end = int(end) if end else int(start)
    if end > total:
        errors.append(f"BAD LINE: {path}:{start}-{end} (file has {total} lines)")

if errors:
    for e in errors:
        print(e)
    raise SystemExit(1)
print(f"All {len(refs)} references valid ✓")
```

## 文档内嵌一段"可重现"声明

在 PLAN.md 末尾加一节:

```markdown
## 引用验证

本文档所有 file:line 引用已通过以下脚本验证(2026-06-29):

```bash
./references/file-line-validation.md  # 见 cross-system-borrow-design skill
```

最后验证结果:49 个引用,0 missing,0 bad line。
```
