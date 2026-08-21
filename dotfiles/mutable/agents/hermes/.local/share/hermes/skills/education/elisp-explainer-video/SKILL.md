---
name: elisp-explainer-video
description: 用 HyperFrames 制作 Emacs Lisp 教学视频的完整工作流——从文档提取概念→设计可视化(画数据结构+算法流程)→编写 HTML/SVG/GSAP 时间线→渲染 MP4。
category: video
---

# ELisp Explainer Video 工作流

把一份 Emacs Lisp 教程文档变成 13-16 分钟的教学视频,让**概念本身被画出来**而不是只贴文字。

## 配套资产

- `references/svg-state-machine-and-graph-patterns.md` — SVG 状态机/网络图布局(Evil 7 状态、Org Roam 9 节点)
- `references/voiceover-and-captions.md` — TTS 配音 + 字幕工作流,含 MiniMax `t2a_v2` 完整对接(2026-06 实测) + 章边界对齐 + 语速预算 + 稿件详细度三档
- `references/tts-intent-disambiguation.md` — 用户说"minimax"时的三种指代 + 三步判别法
- `scripts/minimax-tts.py` — MiniMax 同步语音合成批量脚本(从 hermes `.env` 加载 key,hex 解码,可选 `--dry-run`)
- `scripts/synthesize_narration.py` — 解说稿 md → 7 章 mp3 批量合成(温柔学姐 / speech-2.8-hd)
- `scripts/align_and_merge.py` — 章边界对齐拼接 + 烧录到视频(裁切溢出,补静音)
- `scripts/probe_chapter_starts.py` — ffmpeg 抽帧 + vision 探测章扉页真实视觉起点(解决 GSAP 入场延迟导致的 data-start 偏差)
- `templates/narration-script.md` — 解说稿 md 模板(7 段结构 + 停顿标签 + 三原则 + 反模式)

## 核心理念:画数据结构,而不是贴卡片

教学视频常见的陷阱是把文档的段落"搬"到屏幕上——4 行定义就 4 张卡片,两段说明就两段文字。这不是可视化,这是幻灯片。真正的讲解视频应该让观众**亲眼看到**代码背后发生了什么。

| 概念 | 错误做法 | 正确可视化 |
|---|---|---|
| S-表达式求值 | 4 个步骤说明文字 | **求值树**:根节点 `+` 从源代码飞出,边生长后叶子 `1` `2` 降入树,脉冲粒子沿边流动,结果 `3` 落回结果框 |
| 数据类型 | 类型名称 + 例子文字 | **内存布局**:整数=单格单元格、字符串=6 个字符格子排成行、布尔=t vs nil 双框、符号=指针→interned 入口 |
| 变量定义 | 4 张代码卡片 | **变量表**:左 4 行代码 + 右 obarray 风格表,`setq` 写入闪烁,`defvar` 灰化跳过,`defconst` 加锁,`defcustom` 齿轮旋转 |
| cons cell | 文字说明"链表的每个节点" | **真 SVG 链表**:双格矩形(数据域+指针域)+ 紫色箭头 → nil |
| 宏展开 | "宏在编译时展开"一行字 | 源代码→`↓ macroexpand-1`→展开后的 `(progn (set ...) (set ...))` 代码块 |

## 阶段 0:规划可视化

在看文档前先问:每个概念在"具象世界"里长什么样?

- **求值** → 树/图遍历
- **作用域** → 栈帧/作用域链
- **列表** → 链表节点/流水线
- **错误处理** → 流程图/传播路径

用 beat-direction 的思路给每章定节奏: `build-HOLD-SLAM-build-hold-CTA`,每章 30-50 秒。

## 阶段 1:搭建 HyperFrames 项目

```bash
npx hyperframes init <project-name> --non-interactive --skip-skills --example=blank
```

关键 meta:
- 根元素 `data-duration` 为最终总时长(秒)
- 每个 section 加 `class="clip"`,加 `data-start`/`data-duration`/`data-track-index`
- 必须注册 `window.__timelines["<composition-id>"] = tl`

## 阶段 2:用 HTML + SVG 构建"具象画布"

**原则":Layout Before Animation——先写静态 CSS 布局再补 GSAP。**

每章的技术选型:

| 场景类型 | 实现方式 | 示例 |
|---|---|---|
| 树/图 | SVG `<rect>`/`<circle>`/`<line>` + GSAP strokeDash | 求值树、决策菱形、cons cell 链表 |
| 卡片网格 | CSS Grid + GSAP stagger | 4 数据类型卡片 |
| 流水线 | flex + GSAP fromTo | dolist 管道、mapcar 流水线 |
| 时间轴 | flex + GSAP set/to 光标移动 | save-excursion、with-eval-after-load |
| 状态表 | CSS Grid + classList 切换 | 变量表、features chip |

CSS 设计模式:
- 深色背景 `#0d1117` + 网格纹理(`repeating-linear-gradient` 1px)
- 字体:Inter(标题) + JetBrains Mono(代码,系统自带不额外下载)
- 主色:#7ee787(绿,Emacs 注释) / #d2a8ff(紫,Lisp 关键字) / #ffa657(琥珀,字符串/数字)
- 代码块:`background: #161b22; border: 1px solid #30363d; border-radius: 12px;`
- 透明度+边框做层次,不依赖过度 shadow

## 阶段 3:GSAP 时间线——让每一拍都有意义

**每章的 GSAP 写法则:**

1. 章扉页(5s):`tl.set(id,{opacity:1})` + stagger 元素入场
2. 主体(20-35s):3-5 个"拍",每拍 4-10 秒
3. 不设 exit 动画——由 clip 系统处理

**动画动词选择:**

| 效果 | 动词 | 参数 |
|---|---|---|
| 树节点飞入 | `fromTo({opacity:0,scale:0,...},{scale:1,opacity:1})` | `ease:"back.out(1.7)"` |
| 边生长 | `fromTo({strokeDasharray:220,strokeDashoffset:220},{strokeDashoffset:0})` | `duration:0.6` |
| 脉冲高亮 | `fromTo({},{scale:1.15,duration:0.25,yoyo:true,repeat:1})` | `ease:"power2.inOut"` |
| 列表节点延迟出现 | `forEach` + `stagger` | `i*0.25` |
| 类打字机 | `fromTo({opacity:0},{opacity:1,stagger:0.08})` | span 级别的 stagger |
| 颜色过渡 | `to({color:"#7ee787",duration:0.3})` | 配合 CSS transition |

## 避免的陷阱:
- 不要用 `textContent:` 写入含 `<b>`,请用 `innerHTML:`
- GSAP `from({opacity:0})` 要求 CSS 里**没有** `opacity:0`(否则永远看不到)
- 模板字符串 selector `` querySelector(`#${id}`) `` 会被 lint 拒绝 → 用字符串拼接 `'#' + id`

### 从实战来的 7 个工程坑(踩过的)
1. **SVG `<circle>` 必须有显式 `cx`/`cy`/`r`**,即使你打算用 GSAP `attr:{cx:...}` 改它。`npx hyperframes validate` 用 headless Chrome 解析 SVG,缺 cx/cy 直接报 "Unexpected end of attribute" → 整段渲染失败。Particle/ring 元素也照此办理。
2. **不要 `tl.to(...)` 紧跟 `tl.fromTo(...)` 同一元素同一时间点同一通道**(`tl.to({opacity:1})` + `tl.fromTo({opacity:0},{opacity:1})` 在 t=0.4)→ lint 报 `overlapping_gsap_tweens`,删掉冗余那个。
3. **`fromTo(opacity:0.95)` 后再 `to(opacity:0)`** 也会触发 overlap warning。两者都是合法连续动画,加 `overwrite:'auto'` 即可。
4. **`font-family` 出现在 CSS 但没有 `@font-face` → validate 报 `font_family_without_font_face`(error 不是 warning!)**。HyperFrames 自动解析的字体只覆盖: Inter / Segoe UI / JetBrains Mono / DejaVu Sans Mono / Consolas / monospace / sans-serif。**不要写** "PingFang SC" / "Microsoft YaHei" / "Noto Sans CJK SC" / "Noto Sans Mono CJK SC" / "Consolas"——后两个我刚踩过,等本地有 .woff2 再说。
5. **同 track 的 clip `data-start + data-duration` 不能跟任何 clip 边界相切**——lint 把"315+30=345"跟"345+0=345"视为 overlap。永远错开 1 秒,或者把后面的 `data-start` 设为前一个 `+ duration` + 0.1(更安全:`+ duration`)。
6. **"prime initial state" 模式陷阱**:如果用 GSAP 改 `height` / `scale` / `x` 显现元素,不要把它也写进 `opacity:0` 的 prime 列表,否则 GSAP 改了 height 它们还是 opacity:0(柱状图、扇形进度条、放大缩入的 logo 都是高发区)。只 prime 你打算用 opacity 显现的元素。
7. **根元素 `data-duration` 必须 ≥ 最后一个 clip 的 `data-start + data-duration`**,改完子 clip 边界要顺手更新根。否则最后一段会被无声裁切。`npx hyperframes info` 会显示 root duration,改前看一眼。
8. **"换 minimax" = 大概率 TTS,不是模型切换**。用户上下文是视频工作流时,说"用 minimax" 90% 指 MiniMax 厂商的 `t2a_v2` 同步语音 API,不是切对话/视觉模型。判别三步法(看上下文 / 看动词 / 看"那个"指向)见 `references/tts-intent-disambiguation.md`。这条踩过一次(2026-06),二次 clarify 才到位,代价是 1-2 轮会话。
9. **章边界对齐必须裁切,不能"自然溢出"**(2026-06-23 踩过)。每章音轨时长 = `min(实测时长, 下章扉页起点 - 本章扉页起点)`,溢出用 ffmpeg `-t` 裁切。否则音轨溢出到下章扉页,画面已经切到下章但声音还在讲上一章尾巴——很难受。完整拼接范式见 `references/voiceover-and-captions.md` 坑 5 + `scripts/align_and_merge.py`。
10. **温柔学姐 1.0 速实测 6.6 字/秒,不是文档里写的 4-5**(2026-06-23 实测)。Kokoro 本地 / 偏慢音色的速才是 4-5,云端 speech-2.8-hd 明显更快。时长预算 = 目标秒数 × 6.6 字,不要按 4-5 估。其它音色实测前先跑 30 字样文估速。7 段详细字数 vs 时长对照表见 `references/voiceover-and-captions.md` 坑 6。
11. **章扉页视觉起点 ≠ `data-start`**(2026-06-23 实测踩过,**经过两轮修正才得到真值**)。`data-start` 是 clip 起点,GSAP 入场动画(`fromTo({opacity:0, ...})` 等)会让扉页大标题真正出现在画面上的时间**比 `data-start` 晚约 1 秒**(不是之前估的 3-6s)。配 TTS 旁白时,如果按 `data-start` 拼音轨,会出现"声音讲下一章,画面还在上一章"的错位。**绝对不要信 `data-start`,必须用 ffmpeg 抽帧 + vision 看实际帧定边界**。实测 7 个章扉页:`data-start=[25,175,305,405,555,740,800]` → 视觉 `[26,176,306,406,556,741,801]`(全章一律 +1s)。脚本范式见 `scripts/probe_chapter_starts.py`。
12. **采样粒度陷阱:不要用 3s 步长**(2026-06-23 二次踩过)。第一次"修正"用了 3 秒一帧 + vision 看,结果估成"+3s",实际是 "+1s"——3s 步长会跨过真实切换点,产生**过校正**,看着像修对了其实错更远(用户当时直接说"还是完全没对上轴!请你小心、细致、仔细地再尝试一遍")。第二次改 1fps 精细采样(每过渡点 ±10s 共 21 帧)才拿到真值。**凡是"对准视频视觉边界"的工作,采样必须 ≤ 1fps**,配合 PIL 算帧间灰度差找候选切换点,再用 vision 逐帧确认"切到了哪个画面"。`scripts/probe_chapter_starts.py` 的 1fps 分支就是这个范式。

## 阶段 2.5:SVG 状态机 / 网络图布局(Evil / Roam)

带圆圈 + 标签的状态机,标签很容易掉进圆内触发 `inspect` 的 `content_overlap` warning;Org Roam 风格的双向链接图也有自己的节点+边+脉冲环范式。完整 SVG 模板、圆/标签坐标避让规则、5 类节点配色、GSAP 进场顺序见 `references/svg-state-machine-and-graph-patterns.md`。

## 阶段 4:质量门控流水线

```bash
hyperframes lint    # 0 errors required
hyperframes validate # 0 errors required; 对比度 warning 可选
hyperframes inspect  # 0 layout issues
hyperframes render --output renders/video.mp4
```

- `lint` 的 `gsap_from_opacity_noop` 非常常见——CSS opacity:0 + gsap.from opacity:0 = 永远不可见
- `template_literal_selector` 解决:不用 `${}` 写 querySelector
- 开始渲染前做个 `npx hyperframes doctor`

## 阶段 5:配音 + 字幕(可选,通常是必选)

视频没有配音等于幻灯片。完整 TTS / 字幕 / 引擎降级 / ffmpeg 拼轨写在 `references/voiceover-and-captions.md`,关键四点先记在脑子里:

1. **走 `hyperframes-media` skill,不要直接用 `npx hyperframes tts`**。`npx hyperframes tts` 是 Kokoro-only 本地降级版本,HeyGen/ElevenLabs 即使 env 有 key 也会被它**静默吞掉**。统一入口是 `skills/hyperframes-media/scripts/audio.mjs`。
2. **中文(zh)必须装 `espeak-ng` 系统库**,否则 Kokoro 在 `phonemizer` 阶段会报 `language "zh" is not supported by the espeak backend` → TTS 失败。`pip install kokoro-onnx` 不带 espeak-ng,得 `apt-get install espeak-ng` / `brew install espeak-ng` / guix 用户 profile `guix install espeak-ng`。装完**重启 shell** 让 PATH 生效。
3. **字幕稿是"画外音"不是"念屏"**。每段对应一个 `data-start..data-duration` 的 clip,语速 4-5 字/秒中文,英文术语保留不翻(M-x / use-package / vertico),开头带过渡词接上段。逐段生成 wav 后用 ffmpeg 按时间戳拼回 880s 主轨,mux 进 mp4。
4. **如果用户说"用 minimax / MiniMax 做音频"—— 90% 是 TTS,直接调 MiniMax `t2a_v2`**(端点 + 鉴权 + 完整请求 schema 见 `references/voiceover-and-captions.md` 坑 3 节)。Key 在 `~/.local/share/hermes/.env` 的 `MINIMAX_CN_API_KEY`,可复用脚本在 `scripts/minimax-tts.py`。**别凭印象编 endpoint**(这一条以前的 skill 自己写过反话,被实测打脸了)。

`references/voiceover-and-captions.md` 里有 25 段 Elisp 教程的真实配音稿范本(可直接套用)、踩过的坑(Kokoro 中文走 espeak 失败 / hyperframes CLI 吞云端 key / MiniMax 厂商 vs 模型意图混淆 / `execute_code` 子进程不继承 env),以及 4 个实测中文男声音色试听路径。

如果用户用"minimax"一词模糊,先看 `references/tts-intent-disambiguation.md` 三步法再动手。

## 常用模板

### 封面
```html
<div class="title"><span class="emacs">Emacs</span> <span class="lisp">Lisp</span></div>
<div class="subtitle">求值 · 变量 · 函数</div>
```

### 章扉页
```html
<div class="chapter">
  <div class="chapter-num">Chapter 01</div>
  <div class="chapter-title stamp">标题</div>
  <div class="chapter-en">副标题</div>
  <div class="chapter-bar"></div>
</div>
```

### SVG 决策树节点
```svg
<polygon points="280,200 360,270 280,340 200,270" fill="#1c2128" stroke="#d2a8ff" stroke-width="3"/>
<text x="280" y="265" text-anchor="middle" font-family="JetBrains Mono" font-size="20" fill="#d2a8ff">COND</text>
```

### 代码块
```html
<div class="code-block" style="background:#161b22; border:1px solid #30363d; border-radius:12px; padding:20px 28px; font-family:JetBrains Mono; font-size:22px;">
  <span class="k">(defun</span> <span style="color:#7ee787">my/greet</span> ...
</div>
```

## 章节节奏速查表

| 内容量 | 总时长 | 场景数 | 每场景时长 |
|---|---|---|---|
| 15-20 章 | 13 分钟 | ~35 个 | ~22 秒 |
| 8-10 章 | 6 分钟 | ~18 个 | ~20 秒 |
| 3 章(试水) | 2:40 | 11 个 | ~14 秒 |

每章 = 扉页(5s) + 1-3 个内容场景(30-50s)
