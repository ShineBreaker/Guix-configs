---
name: remap-keymap-from-screenshot
version: 0.1.0
license: MIT
description: "Use when layout screenshots must become keymap config edits."
metadata:
  hermes:
    tags: [kanata, keymap, keyboard, screenshot, vision, qmk]
    related_skills: [guix-configs-workflow]
---
# remap-keymap-from-screenshot — 从布局截图反推键位改动

> 用户贴一张（或两张）键盘映射配置界面的截图，要求据此更新本机配置。核心难点不在改文件，而在**从图里精确读出键位**与**把键位映射到目标配置的行列坐标**。

## When to Use

- 用户贴键盘布局图 + 「帮我更新一下 X 的设置」
- 需要比对同一界面的两个 layer（默认层 / Fn 层）找出差异
- 报错形如 `Layer <name> has N item(s), but requires M to match defsrc`

## 工作流

### 1. 先定位配置源与运行态（并行）

```bash
pgrep -af <tool>            # 从 cmdline 拿实际生效的配置文件路径
```

配置源常与运行态不同（例：org 块 tangle 出的 tmp 产物被 `--cfg` 引用）。**改源，不改运行态文件**——运行态文件是构建产物，改完会被重新生成覆盖。

### 2. 读图：先 diff，后逐行

两张同界面截图（两个 layer）不要凭肉眼扫。用 PIL 做像素 diff 定位差异区，再逐区放大读：

```python
diff = np.abs(arr_a - arr_b).sum(axis=2)
mask = diff > 30
```

按 8 邻域 BFS 找连通区，得到若干边界框。**每个框只对应一个真实差异**；光标指针、按钮选中态、悬停高亮也会成框，逐框用 `vision_analyze` 放大确认内容后再采信。

判读要点：
- **按钮选中态可用像素均值判**：选中按钮是浅底深字（均值高），未选中是深底浅字。据此判断哪张图是哪个 layer，别信文件名或截图顺序。
- **键的背景色变化是有效信号**：一个键在两张图里底色不同（深→灰）通常表示它在另一层被重映射。
- 行内标签被 diff 拆成多个小框（如一个汉字拆成 2-3 框）是正常的，按 y 坐标聚回同一键。

### 3. 把键位映射到目标配置的行列

布局图按行展示，目标配置（kanata `deflayer`）也按行展示，但**两者行不一定同序**——先数出各自的每行键数，再按键数配对：

```python
# 逐行 token 数不可靠：'[' ']' 等单字符键与 '(layer-while-held fn)' 多 token 动作
# 会被 split() 拆散。kanata 的 item 计数才是真相。
```

kanata 的报错 `Layer <name> has N item(s), but requires M` 是**唯一权威计数**：先让校验器跑一次拿到 M，再据此反推该加/删哪一行。

### 4. 硬件层功能不可映射要明说

图上出现「背光开关」「背光亮度+/-」这类**外设固件/驱动层的专用功能**时，kanata 的 `defsrc` 里没有对应键位，硬写会破坏配置。**如实告诉用户这条实现不了，不要静默跳过，也不要用一个标准键糊一个假映射**。同时把映射表里这一行标注为未实现，便于日后驱动暴露成标准键位时补。

### 5. 校验必须用工具本体

`blue check` / 语法检查只覆盖 scheme 类块，**对 conf / 键位配置零覆盖**。抽出块体后用工具自己的校验器：

```bash
<tool> --check --cfg <抽出的文件>
```

判据是输出里的 `config file is valid`，不要看退出码（某些工具校验失败也返回 0）。

**从 org 块抽体的通用做法**：按块头到块尾切一段、去掉首尾两行。块头正则里的 tangle 路径要与源文件**字节级一致**（写错就静默抽出空文件）。若源文件在 Guix-configs 的 `source/config.org`，也可用 `blue block-show <name>` 取块（其产物前两行是语言与 noweb 标记，喂给校验器前先剥掉）。

### 6. 让改动生效

配置常由 home-shepherd 起的 daemon 持有，改源后需 `blue home` + `herd restart <service>` 两步；daemon 不重启就仍读旧配置。若 `blue home` 涉及 sudo 或用户明确要自己执行，把命令交给用户，不要代跑。

## 陷阱

- **不要按截图顺序认定 layer**。文件名、粘贴顺序都可能与内容相反；用按钮选中态的像素特征定。
- **不要用 token 数当键位数**。单字符符号键与多词动作的 split 结果不同，导致行内加减后项数算错，报错信息与真实差一行。
- **改一个键位时不要顺带删邻行的占位项**。`deflayer` 每行末尾常有一个语义占位（如 Backspace 位），删了会让整层项数短少，报错指向的却是另一行。改完立刻跑校验器，别攒多个改动一起验。
- **抽出块体的匹配串要与块头字节级一致**。tangle 路径写错就静默抽出空文件，校验器对空配置也可能报 valid，造成假阳性。抽出后先 `wc -l` 确认非空。
- **不要凭记忆写硬件功能键**。没在 `defsrc` 里见过的键名先查文档，不要猜。

## 参考

- 若配置源在 Guix-configs 仓库的 `source/config.org`：先读 `guix-configs-workflow`（§1 部署三步、§9 改 config.org 的安全协议、§9.2 坑 7 非 scheme 块零覆盖）。
- 若外设有自己的配置界面（Via / Vial / 厂商网页工具）：其层名与键名与 kanata 不同名，映射时先建一张对照表再动手。
