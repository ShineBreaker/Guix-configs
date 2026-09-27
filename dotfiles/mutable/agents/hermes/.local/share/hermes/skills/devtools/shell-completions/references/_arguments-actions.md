# `_arguments` 动作语法速查（zsh）

optspec 形如 `'--长选项[说明]:消息:动作'`，短选项 `'-x[说明]'`。动作段决定 Tab 之后出什么。

## 值列表动作

| 动作写法 | 结果 |
|---|---|
| `{a,b,c}` | 被当 shell 代码求值：完成函数里执行 `a,b,c` → `command not found`，候选为空 |
| `(a b c)`（无消息段，即 `--opt[说明]:(a b c)`） | 静默不生效，候选为空 |
| `消息:(a b c)` | ✓ 逐项列出 |
| 空动作（`'--title[标题]:'`） | ✓ 该选项不补全，也不落到文件补全 |
| `->state` | 交回 `case $state in ...` 分支 |
| `_files` / `_users` / `_hosts` 等 | 交给对应补全函数 |

规则：**列表永远用括号 + 空格分隔，且必须带消息段。** 逗号分隔（`a,b,c`）在括号内是单个字面量，等于没有补全。

## 动态候选模板

```zsh
_arguments -C '1: :->cmds' '*::arg:->args'
case $state in
  cmds) _describe -t cmd '命令' ... ;;
  args) case $words[1] in
          add) _arguments '--type[类型]:类型:(debug workflow)' ;;
          viz) _arguments '--theme[主题]:主题:(light dark auto)' ;;
        esac ;;
esac
```

顶层 `-C` 是必须的：没有它就分不开"第几个位置参数"与"子命令自己的参数"。`args` 分支里的 `$words[1]` 是子命令名。

## 最小隔离实验：脚本问题还是框架问题

```zsh
_c1() { compadd aa bb cc }                          # 对照组：出候选 → 驱动与注册都正常
_c2() { _arguments '--source[src]:{aa,bb,cc}' }     # 候选为空 → 值列表语法错
_c3() { _arguments '--source[src]:src:(aa bb cc)' } # 出候选 → 正确写法
compdef _c1 c1; compdef _c2 c2; compdef _c3 c3
```

配 `scripts/zsh_completion_probe.zsh` 跑 `'c2 --source |aa|bb'` 这类用例，一分钟内即可区分三种原因：补全函数没注册 / 驱动方式不对 / 动作语法错。

## 其余易踩点

- `--opt[说明]:` 这类空动作是**故意**的：它同时挡掉了文件补全，别把它"补全"成 `_files`。
- `_describe` 的条目是 `'值:说明'`，值里含冒号要转义，否则说明被截断。
- 选项说明（`[ ]` 内）里的单引号必须成对转义，否则整个 optspec 会被 zsh 提前截断，症状同样是"候选为空"。
