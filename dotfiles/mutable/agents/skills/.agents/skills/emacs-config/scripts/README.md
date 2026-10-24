# scripts/ — elisp 验证脚本

> 4 个 shell 脚本,通过 `emacsclient` 走本机 Emacs daemon 做
> byte-compile / reload / 跑测试 / 清理 .elc。
> 详细文档见 `../references/E-validating-elisp.md`。

## 脚本速查

| 脚本                | 一句话                                              | 退出码含义                          |
| ------------------- | --------------------------------------------------- | ----------------------------------- |
| `elisp-compile.sh`  | byte-compile 单个 .el,成功后删 .elc                | 0 ok / 1 not found / 2 compile fail / 3 emacsclient 失败 |
| `elisp-reload.sh`   | `load-file` 到运行中的 daemon                       | 0 ok / 1 not found / 3 emacsclient 失败 |
| `run-tests.sh`      | 跑 ERT 测试,返回失败数作为退出码                   | 0 全过 / 1 有失败 / 2 调用错 / 3 emacsclient 失败 |
| `clean-up-elc.sh`   | 删 .elc 产物(纯文件操作)                           | 0 ok / 1 路径不是 .el/.elc           |

## 默认值

```
REPO_ROOT = $(scripts/../..) = ~/.agents/skills/    # skill 容器根
```

这是**默认锚点**,实际使用几乎都用 ENV 覆盖。

## 环境变量

| 变量                       | 默认值          | 作用                                |
| -------------------------- | --------------- | ----------------------------------- |
| `EMACS_CONFIG_LOAD_PATH`   | `REPO_ROOT`     | 加入 `load-path` 的目录(编译/测试) |
| `EMACS_TEST_DIR`           | `REPO_ROOT/tests` | ERT 测试文件查找目录                |
| `EMACSCLIENT_EXECUTABLE`   | `emacsclient`   | emacsclient 可执行路径              |

## 典型用法

```sh
# 编译 user 自己的 init.el
EMACS_CONFIG_LOAD_PATH=~/.config/emacs \
  ./elisp-compile.sh ~/.config/emacs/init.el

# 加载到 daemon(改完想看效果)
./elisp-reload.sh ~/.config/emacs/init.el

# 跑所有测试
EMACS_TEST_DIR=~/myproject/tests \
EMACS_CONFIG_LOAD_PATH=~/myproject \
  ./run-tests.sh

# 跑指定测试
./run-tests.sh --test-file foo-tests.el

# 清理产物
./clean-up-elc.sh init.el
```

## 与 `emacsclient` skill 的关系

本 skill 里的所有脚本都遵循 `~/.agents/skills/emacsclient/SKILL.md` 的
硬约束:**所有 Emacs 操作走 daemon,禁 `emacs --batch`**。

脚本内部是 `emacsclient --eval` 的薄包装,跑测试时用 `(ert-run-tests t)`
而非 `ert-run-tests-batch-and-exit`(后者会杀 daemon)。

如果 daemon 没启,脚本会显式提示 `is the daemon running?` 并以退出码 3 退出。

## 路径解析规则

所有 `FILE` 参数支持:

1. **绝对路径** —— 直接用
2. **相对路径** —— 相对于 `REPO_ROOT`(默认 `~/.agents/skills/`)
3. **basename** —— `run-tests.sh --test-file foo-tests.el` 时,fallback 到
   `EMACS_TEST_DIR/foo-tests.el`
