# 写审计/检查脚本的具体技巧库

跟 SKILL.md §3 「❌ 用 exclude 绕过真实问题」配套。这里给出**怎么直接解决问题**而不是把噪音路径藏起来的具体实现。

每节结构:**症状** → **真原因** → **修法**(代码示例)→ **踩过的坑**。

---

## §1 JSONC 解析(TypeScript/VSCode 生态的 de-facto 标准)

### 症状
脚本扫到 `lsp/node_modules/yaml-language-server/tsconfig.json` 报 `JSONDecodeError: Expecting property name enclosed in double quotes`,第一次反应是加 `exclude: ["lsp/**"]`。

### 真原因
这个文件**不是损坏的 JSON**,是 **JSONC** — TypeScript/VSCode 生态的标准扩展:
- 支持 `//` 单行注释
- 支持 trailing comma(对象/数组的最后一项后跟 `,`)
- 文件名通常是 `tsconfig.json` / `tsdoc-metadata.json` / `.eslintrc.json`

加 exclude 等于把 hermes LSP 工具装的所有 TS/JS 工程配置全部藏起来 —— 哪天真正的 JSON 损坏也看不到。

### 修法:写一个 lenient parser

```python
import json
import re

def parse_json_lenient(text: str) -> tuple[bool, str]:
    """Parse JSON with JSONC tolerance.
    
    - strips // line comments (preserves // inside strings)
    - removes trailing commas in objects/arrays
    Returns (ok, error_msg_or_empty).
    """
    out_lines = []
    for line in text.split("\n"):
        in_str, esc, cleaned = False, False, []
        i = 0
        while i < len(line):
            ch = line[i]
            if esc:
                cleaned.append(ch); esc = False
            elif ch == "\\":
                cleaned.append(ch); esc = True
            elif ch == '"':
                in_str = not in_str; cleaned.append(ch)
            elif not in_str and i + 1 < len(line) and line[i] == "/" and line[i+1] == "/":
                break  # rest of line is comment
            else:
                cleaned.append(ch)
            i += 1
        out_lines.append("".join(cleaned))
    cleaned = "\n".join(out_lines)
    cleaned = re.sub(r",(\s*[\]}])", r"\1", cleaned)  # trailing comma
    try:
        json.loads(cleaned)
        return True, ""
    except (json.JSONDecodeError, ValueError) as e:
        return False, f"{type(e).__name__}: {e}"
```

### 验证
```python
# 这些都该通过
parse_json_lenient('{"a": 1, "b": [1, 2]}')        # standard JSON
parse_json_lenient('{"a": 1, // comment\n}')         # JSONC with comment
parse_json_lenient('{"a": 1,}')                      # JSONC with trailing comma

# 这些该报错
parse_json_lenient('{not valid json')                # truly broken
```

### 踩过的坑
- 不要用 `re.sub(r"//.*", "", text)` 一刀切,字符串内的 `//` 也会被吃掉 → 上面的状态机保留 `in_str` 标志
- 不要忘了 trailing comma 也要处理(`{a: 1,}` 和 `{a: 1, // comment}` 都不合法)
- 处理后**再次** `json.loads` 才算成功 —— 中间态文本不是合法 JSON,不要 flag 它"已 parse"就 return

---

## §2 Traceback tail 提取(异常类型是关键信号)

### 症状
脚本扫日志,看到 `Traceback` 行就累计 `error_count`,报告 `errors 26246 (47 unique sigs: ::Traceback×N)`,用户完全看不出根因。

### 真原因
Traceback 是个**多行结构**:
```
Traceback (most recent call last):
  File "/nix/store/.../web_server.py", line 7594, in _call_cron_for_profile
    from cron import jobs as cron_jobs
ImportError: cannot import name 'jobs' from 'cron' (/nix/store/...)
2026-06-25 05:33:13,864 ERROR hermes_cli.web_server: Failed to list cron jobs for profile default
```

**真正重要的是最后一行的异常类名**(`ImportError` / `ModuleNotFoundError` / `RuntimeError` 等)。只看到 "Traceback" 等于把所有不同错误类型折叠成一坨。

### 修法:逐行 walk,定位 column-0 异常行

```python
def extract_exception_from_traceback(text: str) -> str:
    """For each Traceback block in text, return its column-0 exception class name."""
    exceptions = []
    lines = text.split("\n")
    i = 0
    while i < len(lines):
        if lines[i].startswith("Traceback (most recent call last):"):
            # walk forward; indented lines are frames; column-0 line is the exception
            j = i + 1
            tail = None
            while j < len(lines):
                if lines[j] and not lines[j][0].isspace():
                    em = re.match(
                        r"^([\w.]+(?:Error|Exception|Warning|Failure|Interrupt))",
                        lines[j],
                    )
                    if em:
                        tail = em.group(1)
                    break  # column-0 line — leave block either way
                j += 1
            exceptions.append(tail or "Traceback")
            i = j + 1
        else:
            i += 1
    return exceptions
```

然后用 `tail` 作为 signature 一部分:`sig = f"{log.name}::{tail}"`,而不是 `sig = f"{log.name}::Traceback"`。

### 真信号 vs 假信号
- **真**: `gui.log::ImportError×7893` → 立刻看出 web_server 有 ImportError 重复 7893 次,根因明确
- **真**: `mcp-stderr.log::ModuleNotFoundError×175` → 立刻看出 agenote MCP 找不到 `mcp` 包
- **假**: `gui.log::Traceback×7893` → 完全不知道根因,只会问"为什么有 traceback"

### 踩过的坑
- **不要用 `re.findall(r"Traceback.*?(?=\nTraceback|\Z)", text, re.S)` 抓整个 block 然后 `split("\n")[-1]`** —— python logger 在 traceback 后**紧跟**一条 ERROR 行(如 `2026-... ERROR hermes_cli.web_server: Failed to ...`),会被当成"traceback 的最后一行",正则把异常类名盖掉了
- 上面那个 walk-line 算法是**手写状态机**,比正则鲁棒 —— 因为它只看 column-0 的异常行,不依赖"块边界 = 下一个 Traceback"的假设
- 不要试图在多行 regex 里用 `(?:[ \t].*\n)*` 抓 frames —— 加 `re.S` 嵌套无界量词会 catastrophic backtracking(见 §5)

---

## §3 yaml/CHECKS key parity(避免静默 empty-cfg 灾难)

### 症状
脚本里写了:
```python
CHECKS = [
    ("1", "inject", check_inject),
    ("2", "skill_count", check_skill_count),
    ("3", "symlinks", check_broken_symlinks),  # ← 这里
    # ...
]

def run():
    for num, key, fn in CHECKS:
        cfg = thresholds.get(key, {})  # ← 这里
        status, detail = fn(cfg)
```

而 yaml 里 section 叫:
```yaml
broken_symlinks:    # ← 跟 "symlinks" 不匹配!
  enabled: true
  max: 0
```

结果:`thresholds.get("symlinks", {})` 返回 `{}`,`check_broken_symlinks(cfg)` 拿到空 cfg 跑,fallback 到默认值。**整个 check 一直在用默认参数,用户的 yaml 配置从来不被加载**。如果默认值碰巧过得去,check 就永远 GREEN —— 看上去"一切正常",实际是 silent fail。

### 真原因
yaml section 名(用户配置文件)和 code-side key string(开发者写死的 string literal)是**两个独立的 source of truth**,没人保证它们对齐。半年后另一个会话照着 SKILL.md 复制实现,**新写的 yaml 跟着 `symlinks` 走 → 又一个 silent fail**。

### 修法 1:yaml 当 canonical,代码 string 从 yaml 生成

写一个 `gen_checks.py`:
```python
import yaml, pathlib
cfg = yaml.safe_load(pathlib.Path("metabolism_thresholds.yaml").read_text())
# 输出 Python source: CHECKS = [("1", "inject", check_inject), ...]
keys = [k for k in cfg if k != "output"]  # output 不是 check
# 按 yaml 里出现的顺序,生成 tuple
print("CHECKS = [")
for k in keys:
    fn_name = "check_" + k.replace("json_parseable", "json")  # 别名映射
    print(f'    ("{idx}", "{k}", {fn_name}),')
print("]")
```

每次 yaml 改了跑一次,生成的 Python 粘到 metabolism_check.py。

### 修法 2:在脚本里加 parity check(运行时断言)

```python
def load_thresholds() -> dict:
    if not THRESHOLDS_PATH.exists():
        sys.exit(f"ERROR: thresholds not found at {THRESHOLDS_PATH}")
    try:
        import yaml
        with THRESHOLDS_PATH.open() as f:
            cfg = yaml.safe_load(f) or {}
    except ImportError:
        with THRESHOLDS_PATH.open() as f:
            cfg = _yaml_fallback(f.read())
    
    # Parity check: every CHECKS key must exist in yaml
    missing = [k for _, k, _ in CHECKS if k not in cfg]
    if missing:
        sys.exit(
            f"ERROR: yaml missing sections for these checks: {missing}. "
            f"Either add them to {THRESHOLDS_PATH} or update CHECKS in the script."
        )
    return cfg
```

这要求 SKILL.md §"Verification" 步骤也写明:"改 yaml 或 CHECKS 后必须跑 parity check"。

### 修法 3:在 SKILL.md 写明 dual-source-of-truth 警告

```markdown
## Pitfalls

- **yaml section 名跟 CHECKS key 必须一致**。改任意一边前 grep
  `<key> in cfg` 确认另一边没漂。详见 `references/audit-patterns.md` §3。
```

### 踩过的坑
- `cfg = thresholds.get(key, {})` 的 **silent fallback 是真正的元凶** —— 拿不到 cfg 也不报错。要么显式 raise,要么 SKILL.md 把"键名一致性"作为硬约束写下来
- 不要试图在 `check_xxx()` 函数内部做 parity 检查 —— 太晚,已经跑空 cfg 半天了。parity 必须在 `load_thresholds()` 阶段
- **跨 skill 复用代码时最容易翻车**:把 A skill 的 CHECKS 复制到 B skill,但 B skill 的 yaml section 名跟 A 不一样,直接 silent fail

---

## §4 文件截断陷阱(`head[:N]` 不能当全文本)

### 症状
解析 SKILL.md frontmatter,正则匹配 `description:` 字段:
```python
text = p.read_text(errors="ignore")[:600]  # ← 只读前 600 字节!
m = re.search(r"^description\s*:\s*(.*?)(?=\n[a-zA-Z_][\w-]*\s*:|\Z)", block, re.M | re.S)
```

fixture 写了 1000 字节的 description,脚本算出来只 567B。Inject size 严重低估。

### 真原因
YAML frontmatter 的 description 字段常常超 600 字节(尤其是 multiline quoted string 或 `|` block scalar)。`[:600]` 把 description 截断,正则回溯到截断点也没找到 "下一个 top-level field",返回的 group 是残缺的。

### 修法
- 小文件直接全文:`text = p.read_text(errors="ignore")`(SKILL.md 通常 < 100KB,无成本)
- 或至少 4KB:`text = p.read_text(errors="ignore")[:4096]`(覆盖典型 frontmatter)
- **真正的"读 N 字节"应该用 `head = p.open().read(N)`,而不是 `text[:N]`** —— 后者隐含"全文已加载,只是裁剪",前者明确"我只读了 N 字节"

### 验证
```python
# fixture: description 1000B
expected = "X" * 1000
p.write_text(f'---\nname: x\ndescription: "{expected}"\n---\nbody\n')

# 错的:
text = p.read_text()[:600]
desc = re.search(r"^description\s*:\s*(.*?)(?=\n[a-zA-Z_]\w*\s*:|\Z)", text, re.M | re.S).group(1)
# desc 现在是 "...XXXXXXXX" (约 567B),被截断

# 对的:
text = p.read_text()[:4096]  # 或者全文
```

### 踩过的坑
- **头部截断对 inject 大小这种"sum all values"类统计伤害最大** —— 你以为一个 description 是 600B,实际是 1500B,inject 总和少算 900B
- **头部截断对 frontmatter 字段检测影响最小** —— 因为检测的是 "字段存在与否",不是 "字段值是什么"
- 如果文件特别大(> 1MB),先 `wc -l` 看看,再决定要不要全文加载

---

## §5 灾难性回溯陷阱(`(?:.*\n)*` + `re.S`)

### 症状
写了一段多行 Traceback block 提取的 regex:
```python
tb_re = re.compile(
    r"Traceback \(most recent call last\):\n"
    r"(?:[ \t].*\n)*"            # ← 嵌套无界量词!
    r"([\w.]+(?:Error|Exception|Warning|Failure|Interrupt)[^\n]*)",
    re.S,
)
for m in tb_re.finditer(text):
    ...
```

跑 agent.log(2647 个 traceback,文件 ~5MB)直接 **timeout 180s**,python regex engine 在 nested `(?:.*\n)*` 上做指数级回溯。

### 真原因
- `.*` 在 `re.S` 下匹配任意字符包括换行
- `(?:...)*` 是无界量词,可以匹配 0、1、2、...、N 次
- 当 regex engine 尝试匹配失败要回溯时,它把外层 `*` 拆 0/1/2/...次,内层 `.*` 再试各种分割 —— 复杂度 O(2^N)

### 修法
- **手写 walk-line 状态机**(见 §2 修法),完全避免 regex
- 或者在量词上加 `+?` / `*?` 强制非贪婪 + 加 anchor:`r"\n([\w.]+(?:Error)...)[^\n]*\Z"` 锚定到文件末尾或下一个 Traceback
- 或者用 `regex` 库(支持 atomic groups 和 possessive quantifier,Python stdlib `re` 不支持)

### 验证
```python
import re, time
text = "Traceback...\n  File x\nImportError: y\n" * 5000  # 5MB

# 错的:timeout
start = time.time()
re.compile(r"Traceback.*?\n([\w.]+Error).*?(?=\nTraceback|\Z)", re.S).findall(text)
print(f"slow regex: {time.time()-start:.1f}s")

# 对的:walk-line
start = time.time()
# ... walk-line state machine ...
print(f"walk: {time.time()-start:.1f}s")
```

### 踩过的坑
- regex 在小文本(<10KB)看不出问题,大文本(>1MB)才暴露 —— **总是先在 production-size fixture 上跑一遍**
- `re.S` 让 `.` 匹配 `\n` —— 这是 regex 灾难回溯的最大单一来源。需要 multi-line matching 时,显式用 `[\s\S]` 配 `[^\n]` 替代 `.*`,避免意外回溯
- 不要相信"`(?:x)*` 后面有 anchor 就安全" —— anchor 只在最终匹配位置生效,中间过程的回溯还是指数级

---

## 附录:verify 脚本的 fixture 设计教训

写 verify 脚本时,**fixture 期望值不要写死字符串,要写语义性断言**。否则一旦脚本输出微调(比如加空格、改格式、加新字段),verify 全部 FAIL 但其实行为是对的。

**错**:
```python
check("Check 9 RED", line9.startswith("[RED]"))  # 太死板
```

**对**:
```python
# parse the structured output, assert on meaning
m = re.search(r"errors (\d+) \((\d+) unique sigs:", line9)
assert m, f"can't parse line9: {line9}"
err_count, unique_count = int(m.group(1)), int(m.group(2))
check("Check 9 surfaces per-Traceback exception types",
      "ImportError" in line9 and "ModuleNotFoundError" in line9
      and unique_count >= 3,
      f"err={err_count} unique={unique_count} line={line9}")
```

**另一个踩坑**:fixture 里写 `"X" * 700` 期望脚本输出 `desc=700B`,实际脚本输出 `desc=702B`(加了引号)。要么 fixture 算清楚"实际字节 = string 长度 + 包装",要么用 `< {实际值}` 范围断言而不是 `==`。