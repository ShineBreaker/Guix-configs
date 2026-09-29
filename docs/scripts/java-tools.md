<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# java_tools — jdk / jbuild / jrun 学习与切换辅助

- 源码：`dotfiles/immutable/terminal/.config/fish/functions/java_tools.fish`
- 部署：`~/.config/fish/functions/java_tools.fish`（immutable，改后需 `blue home`）
- 调用方：手动调用；补全 `completions/{jdk,jbuild,jrun}.fish`；`jdk set` 依赖 `conf.d/05-java.fish` 定义的 `__set_jdk`

## 用法

```text
jdk set <version>   # 切 JDK（经 __set_jdk → guix build openjdk@<ver>）
jdk current         # 显示记录版本与 JAVA_HOME
jdk                 # 用法

jbuild <Class>      # javac -d bin src/<Class>.java（自动建 bin/）
jrun <Class>        # java -cp bin <Class>（要求 bin/<Class>.class 存在）
```

## 依赖

`__set_jdk`（`conf.d/05-java.fish` 中定义并注册为 `JDK_VERSION_FILE`/`JDK_PATH_FILE`/`JDK_DEFAULT_VERSION`）、`javac`/`java`、guix（`__set_jdk` 内部）。

## 设计决策与不变量

- `jdk` 的持久化在 `conf.d/05-java.fish`：启动时按 `$JDK_PATH_FILE` → `$JDK_VERSION_FILE` 重建 → 默认版本的顺序回放。
- `jbuild`/`jrun` 是教学向薄封装：错误信息写 **stdout**（非 stderr），调用方/补全据此展示。
- 文件不以 `.java` 扩展名传入：`jbuild Hello` 对应 `src/Hello.java`。

## 变更记录

- 2026-09-29：注释压缩、`fish_indent` 规范化（行为不变）。
