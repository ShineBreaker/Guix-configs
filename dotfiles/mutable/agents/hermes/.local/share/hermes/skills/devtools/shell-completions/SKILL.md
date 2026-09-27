---
name: shell-completions
description: Author, regenerate, or debug bash/zsh/fish completions.
---

# shell-completions

补全脚本的编写、再生成与运行时验证。

**触发信号**：Tab 补不出来 / 候选为空 / completion 静默失效 / 新增选项要加补全 / 重新生成 `completions/*` / 用户抱怨某个 `--opt` 补不出来。

三条硬规则先摆这里：

1. **生成器是唯一事实源。** 手改 `completions/_agenote` 这类静态文件，下次生成时会被覆盖。要改行为就改生成器，然后重新生成全部 shell 的静态产物。
2. **语法检查不等于可用。** `zsh -n` / `bash -n` / `fish -n` 全绿时，补全仍可能一个候选都不出（见下）。出结论必须用真实 shell 驱动一次 Tab。
3. **缺 shell 不许标 UNVERIFIED。** 本机没装 zsh / fish 时用 `guix shell zsh -- zsh ...` 临时提供再验；"没装" 和 "未验证" 是两件事，别把前者写成后者。

## 链路：生成器 → 静态产物 → 派生测试

- 生成入口是 CLI 子命令（agenote 为 `agenote completions <bash|zsh|fish>`，生成函数在 `src/agenote/completions.py:generate(shell)`），stdout 即整份脚本：
  ```bash
  PYTHONPATH=$PWD/src .venv/bin/python -m agenote.cli completions zsh > completions/_agenote
  ```
- 三个 shell 一起重生成；通常只有被改的那个会变，用 `git diff --stat completions/` 确认没误伤。
- 有测试直接断言 `静态文件内容 == generate(shell)`，所以改了生成器不重生成必红。
- 派生测试常把**当前输出的字符串形式**当期望值（例如 `assert ":domain:(human,agenote)" in zsh`）。这类断言在你修正形式后会失败，说明它钉的是旧形式：改成钉新形式，并在 docstring 里写明 "为什么必须是这个形式"，否则下一个人会把它改回去。
- 修正形式后，只为旧形态存在的 helper（如逗号连接器）要顺手删掉——留着就是下一次误用的入口。

## zsh：`_arguments` 动作语法（最容易静默失效的点）

optspec 是 `'--长选项[说明]:消息:动作'`。值列表动作必须是**括号 + 空格分隔 + 带消息段**：

| 写法 | 实际行为 |
|---|---|
| `':{a,b,c}'` | 被当 shell 代码求值 → 完成时 `command not found: a,b,c`，**候选为空，且不回显到终端** |
| `':(a b c)'`（省消息段） | 静默不生效，候选为空 |
| `':消息:(a b c)'` | ✓ 逐项列出 |
| `':->state'` | ✓ 交回 `case $state` 分支动态生成 |
| `':'(空动作)` | ✓ 该选项不补全、也不落到文件补全 |

连带结论：凡是 `",".join(...)` 的值表都是错的——括号里逗号不是分隔符，整串会变成单个字面量。改成空格分隔。

细节、动态候选模板与最小隔离实验见 `references/_arguments-actions.md`。

## 运行时验证

**zsh** —— 真 pty 驱动 ZLE，脚本已备好：`scripts/zsh_completion_probe.zsh`

```bash
guix shell zsh -- zsh -f scripts/zsh_completion_probe.zsh ./completions \
  'agenote |extract|reconcile' \
  'agenote extract --source |opencode|zcode' \
  'agenote memory --type |feedback|reference'
```

第一个参数是补全函数所在目录（加进 `fpath`），其后每条用例写 `键入文本|期望候选1|期望候选2`，逐条 PASS/FAIL，任一失败退出码非零。

判读与坑：

- 先做**前缀展开**这一最廉价的检查：`agenote comp` + Tab 应变成 `agenote completions`。它通过说明 ZLE 与补全函数注册都正常，问题就落在 `_arguments` 语法上，不必再怀疑驱动方式。
- 写 `键入文本` 与写 `\t` 之间留 ~0.3s，读回窗口 ~2s。整行连 Tab 一次性写完再立刻读，候选会被吞掉，表现为"用例失败但脚本其实没错"。
- 设 `COLUMNS=200`：窄 pty 会把候选分栏/截断，看起来像没有候选。
- 值补全全体不出候选时，用最小对照函数定位是脚本还是框架：`_c1() { compadd aa bb cc }` 能出候选 → 驱动正常，去查 `_arguments` 语法。

**bash** —— 不需要 pty：`source` 脚本后注入 `COMP_WORDS` / `COMP_CWORD` 再调用完成函数，把 `COMPREPLY` 打出来即可（agenote 的 `tests/test_completions_derived.py` 有可直接照抄的运行时用例；bash 值列表用 `compgen -W "a b c"`，空格分隔）。

**fish** —— 先 `fish --no-config -n <file>` 过语法，再取实际候选：`fish --no-config -c 'complete -C"cmd --opt "'`（用 `guix shell fish --` 提供）。

## 收尾清单

- [ ] 生成器已改；`completions/*` 三个文件按生成器重生成并 `git diff --stat` 复核
- [ ] `zsh -n` / `bash -n` / `fish -n` 全绿
- [ ] 真实 shell 里逐条 Tab 验证过，新增/修改的选项都有候选
- [ ] 钉旧字符串形式的派生测试已改为钉新形式并注明理由
- [ ] 只服务旧形态的死代码已删
