# literal-config

`emacs.org` 单文件 tangle 出的 Emacs 配置,围绕 8 个顶层功能域(章节)与外置 `lisp/<name>.el` 模块组织;模块间通过「`defvar` 注入点 + Lisp-2 同名共存」解耦。本文件只收录该项目特有的领域词汇。

## Language

**域(domain)**:
`emacs.org` 顶层 `*` 章节对应的功能分区,共 8 个:启动与基础设施 / 界面与外观 / 编辑与文本 / 编程与开发 / 项目与导航 / Org 与知识库 / 键位与补全 / 系统工具与实验性。
_Avoid_: 模块,子系统,层(layer)

**模块(module)**:
`lisp/<name>.el` 外置文件,提供独立可 `require` 的子系统(如 `literal-bootstrap` / `literal-dashboard`);与「域」正交——一个模块可被多个域引用,一个域可引用多个模块。
_Avoid_: 域(domain),包(package),subsystem

**注入点(injection point)**:
`defvar` 形式的占位变量,后加载模块把函数塞入对应 `defvar`(典型形式 `(defvar literal/<callback-fn-name> nil)`)。
_Avoid_: hook(易与 `*-hook` 后缀的 hook 变量混淆),callback 槽(slot)

**辅助函数(helper)**:
基础设施域提供的低层原语,如 `literal/set-key` / `literal/add-frame-hook` / `literal/call-process`,被其他域直接调用。
_Avoid_: util,工具函数(tool function)

**跨域注入(cross-domain injection)**:
A 域使用 B 域已定义的函数,经注入点延时绑定的过程;典型例 = Dashboard(系统工具域)注入知识库(Org 与知识库域)的 `literal/knowledge--collect-org-files`。
_Avoid_: 依赖注入(dependency injection,易与 OOP 概念混淆)

**Lisp-2 同名共存(Lisp-2 symbol co-existence)**:
Emacs Lisp 双命名空间下 `defun`(函数)与 `defvar`(变量)可同名(如 `literal/add-frame-hook` 既是被调函数、又是 color-scheme 头部声明的占位变量)。
_Avoid_: 命名冲突(name collision,描述角度不同)

**tangle / detangle**:
Org src 块 → 文件(tangle)与 文件 → Org src 块(detangle,需 `org-src-source-buffer` 等)的导出/回导过程;本项目当前 8 个域统一 tangle 到 `main.el`。
_Avoid_: 生成(generate,概念过宽),编译(compile)

**加载顺序敏感(loading-order sensitive)**:
require 顺序改变会破坏功能的代码段;典型例 = `literal/register-pending-wk-descs` 必须在 which-key `:config` 阶段才被调用,提前会找不到 which-key 状态。
_Avoid_: 顺序敏感(order-sensitive,丢失「加载」语境)
