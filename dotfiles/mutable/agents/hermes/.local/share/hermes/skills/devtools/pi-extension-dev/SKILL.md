---
name: pi-extension-dev
description: "开发、修改或排障 pi 扩展；pi 打不开（Failed to load extension）时优先用。"
version: 0.1.0
license: MIT
metadata:
  hermes:
    tags: [pi, extension, typescript, diagnostics, startup-failure]
    related_skills: [hermes-plugin-dev]
---

# pi-extension-dev — pi 扩展的开发、修改与排障

## When to Use

- pi 打不开 / 启动失败，stderr 出现 `Failed to load extension`
- 修改或新增 pi 扩展（`.ts`）后需要验证
- 排查扩展加载的 ParseError / 锁定是哪个扩展出问题

pi 的扩展走 TypeScript，位于 `~/.config/pi/extensions/<name>/`。本机该路径经 symlink 指向 Guix-configs 仓库源（`dotfiles/mutable/agents/pi/.config/pi/extensions/`，改源即生效）；atelier 等扩展是独立 pi-package（git 子模块），有自己的仓库与发布流程。

## 排障：pi 打不开 / 启动失败（最高频）

1. **先拿 stderr，别猜**：跑一条最小非交互请求，扩展加载错误会原样出现在 stderr：

   ```bash
   pi -p --no-session "仅回复 ok"
   ```

   典型输出（扩展名 + 文件:行号）：

   ```
   Error: Failed to load extension ".../extensions/atelier": ParseError: Unexpected token
    .../atelier/runtime/peer.ts:284:1
   Hint: Start without extensions using "pi -ne".
   ```

   `pi --version` 不加载扩展——它通过 ≠ 扩展没问题。

2. **确认锅在扩展侧**：`pi -ne`（禁用扩展发现）可临时进入；能进则问题锁定在某个扩展。
3. **去真实源修**：报错路径可能经 symlink 表达，编辑仓库里的真实源文件。
4. **修后走验证链**（语法 → 真机）：

   ```bash
   # 单文件 / 全量语法检查（抓括号、字符串、注释结构错误）
   node --experimental-strip-types --check <file>.ts
   for f in $(find . -name '*.ts' -not -path './node_modules/*'); do \
     node --experimental-strip-types --check "$f" >/dev/null 2>&1 || echo "FAIL: $f"; done

   # 真机：加载 + 一轮真实对话
   pi -p --no-session "仅回复 ok"

   # 交互 TUI（需要 pty；terminal 工具 pty=true + background=true 起，Ctrl+C 两次退出）
   pi --no-session
   ```

   验收：stderr 无 "Failed to load extension"；TUI 正常渲染出欢迎屏。

## 陷阱（每次编辑必看）

- **扩展加载是硬依赖**：任一扩展源无法解析，pi 拒绝启动（不是跳过坏扩展），TUI 与 -p 全模式一起挂。一个坏扩展 = pi 整体不可用，定位优先于修功能。
- **注释也是语法**：JSDoc 的 `/**` / `*/` 定界符被编辑吞掉后，注释正文成为裸文本行，报 `ParseError: Unexpected token` 且指向该行。**只改注释也必须跑语法检查**——定界符丢失肉眼很难发现。
- `node --check` 只查语法、不查类型；且 `--check` 模式下未导出的 `interface` / `type` 声明会被误报——加 `export` 或用运行模式验证。
- 扩展的提交 / 发版遵守其项目自身流程（如 atelier 仓库 AGENTS.md 的 commit 粒度、CHANGELOG、子模块指针规定），不在本 skill 重复。
