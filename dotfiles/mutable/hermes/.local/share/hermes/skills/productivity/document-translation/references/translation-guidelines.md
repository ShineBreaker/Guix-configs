# 翻译约定（技术文档 → 中文 markdown）

适用于文档翻译任务（如 GNU Guix Cookbook 之类的英文技术手册）。

## 必须保留原文的项
- 代码块、Shell 命令、包名、Crate 名、`crate-source` 等标识符。
- REPL 符号：`⇒`（求值结果）、`⊣`（打印输出）、`` ` ``（准引用）、`,`（取消引用）。
- 人名（如 Sami Kerola、Andreas Enge）、手册名（《GNU Guix Reference Manual》）。
- 文件路径、URL、Git 提交哈希、store 路径（`/gnu/store/...`）。
- 模块名、Scheme 过程名（`modify-phases`、`substitute*` 等）。

## 术语处理
- 首次出现附英文：S-表达式 (s-expression)、过程 (procedure)、G-表达式 (G-expression)、
  引用 (quote)、准引用 (quasiquote)、代码暂存 (code staging)、频道 (channel)、
  继承 (inherit)、代码片段 (snippet)、解包 (unbundle)、用户输入 (native-inputs)、
  传播输入 (propagated-inputs)。
- 后续仅用中文。
- 与官方译文冲突时，以官方译法为准（见下方「与官方对齐」）。

## 与官方译文对齐（基准来源）
若用户提供或能找到该文档的官方简体中文译文，以其为标准术语表：
- Scheme 急就（A Scheme Crash Course）
- 可魔改（hackable）
- 频道（channel）
- 继承（inherit / inheritance）
- 代码片段（snippet）
- 解包（unbundle，指去除捆绑依赖）
- 用户 profile（user profile）
- 替代物 / 替代（substitute，预构建二进制）
- 代际（generation，profile 历史代）
- 头节点 / 计算节点（head node / compute node）
- 双因素认证（2FA）
- 可复现研究（reproducible research）

发现自己的译稿与官方不一致时：改术语表 + 回改已译切片，保证全书统一。

## 标题层级
按 PDF 字号定位，不要按嵌套逻辑猜：
- `#` = H1（章，≈17.2pt）
- `##` = H2（节，≈14.3pt）
- `###` = H3（子节，≈13.1pt；留在所属 H2 切片内，不要拆成独立文件）

## 代码块内联注释
可译为中文（样板文件中已译）；若用户要求可回退英文。保留注释结构。

## 链接
原文中的 URL 保持可点；参考手册交叉引用（如 "see Section X in GNU Guix
Reference Manual"）译为中文并保留链接。

## 列表与要点
- 无序列表用 `-`。
- 嵌套步骤（如 Rust 打包 1/2/3/4）用有序列表 `1.`；子步骤缩进。
- `>` 注记块（Note / 注）保留为引用块，开头可加「**注：**」。

## 增量润色（已有 agent 草稿，对照官方润色）

出现第二种工作流：**不是你从英文翻译，而是给一份已完成的 agent 中文译稿做对齐+润色**。典型场景：用户提供两份文件，一份官方（部分或仅章节标题），一份 agent 完整中文稿。

### 操作三段

1. **标题比对（最高优先级）**：用结构化对比（按编号 `2.1.5`、`3.4.1` 配对）。官方已翻的标题直接覆盖；官方留英文但 agent 给了中文的、且正文是中文——**保留 agent 中文**（中英混排标题比纯英文更难看）。

2. **官方词汇细节对齐**：注意小连词的差异。常见分歧：
   - 和/与、订户/用户、参考/参考资料、引导加载器/启动器、后端/后端程序、包/软件包
   - 章节编号风格：「6 进阶包管理」(官方) vs「6 高级软件包管理」(agent) → 锁官方
   - 「2.1.5 可编程**和**自动化的包定义」——官方的"和"是锚点

3. **正文润色（最小动作原则）**：agent 译稿质量通常已经够用。只在以下情况动笔：
   - **漏译英文词**——`spurious 生成的 OTP 码` → `无端生成的 OTP 码`。可扫脚本：含中文标点的行若紧跟 ≥4 个 ≥4 字母英文词长串，大概率是残留。
   - **生硬刻译**——`最简化` for minimal → `最小化`。
   - **过期交叉引用**——改了章节标题后，所有 `参见 §X.Y 节 [旧标题]` 的方括号需要同步。

### 源码真相位置（关键！）

永远改 `translated/<id>.zh.md` 切片文件，**不要直接改汇编产物**（`book.zh.md`）。原因：

- 切片是单一真相源；下次跑 `assemble.py` 会重新生成汇编产物
- 直接改汇编产物，下一次 `assemble.py` 运行会被覆盖
- **例外**：如果 `assemble.py` 里硬编码了文档总标题（H1），那改 H1 要同时打 `assemble.py` 的补丁——否则下次汇编又恢复

### 旧工具 / helper 钩子

```python
# 漏译英文检测（扫 `translated/*.zh.md`）
import os, re
hit = []
for fn in sorted(os.listdir('translated')):
    if not fn.endswith('.zh.md'): continue
    with open(f'translated/{fn}') as f:
        in_code = False
        for ln, line in enumerate(f, 1):
            s = line.lstrip()
            if s.startswith('```'):
                in_code = not in_code; continue
            if in_code or s.startswith('#') or s.startswith('<!--'): continue
            # 中文标点后跟 ≥3 个 ≥4 字母英文词（常见漏译）
            m = re.search(
                r'[\u4e00-\u9fff，、。！？；：]\s*'
                r'([a-zA-Z]{4,})(?:\s+[a-zA-Z]{4,}){2,}', line)
            if m:
                hit.append(f'{fn}:{ln}: {line.strip()[:120]}')
for h in hit: print(h)
```

由 polisher 自己拷贝到 `scripts/polish_scan.py` 或 inline 在临时脚本里跑。

### 何时停手

不是每章都必须润色。如果官方只翻译了 TOC/章节标题、没有正文，**正文不应该瞎改**——你只能改章节标题和极少数漏译。润色过头比润色不足更糟。
