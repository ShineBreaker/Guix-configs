---
name: osu-skin
description: "做或改 osu! 皮肤（尤其判定动画 hitburst）、把 PC 皮肤转成 osu!droid、排查贴图不生效时用；含引擎帧契约、设计取舍与验收方法。"
version: 1.0.0
license: MIT
metadata:
  hermes:
    tags: [osu, skin, hitburst, droid, converter, animation]
    related_skills: []
---

# osu-skin — osu! 皮肤制作与平台转换

聚合自 `osu-droid-skin-conversion`（转换器维护）与 agenote 20260914-003328（hitburst 引擎契约，MERGED_FROM 8 张）。

## When to Use

- 做或改 hitburst / 判定动画（`hit300`、`hit100`、`hit50`、`hit0`）
- 把 .osk / PC 皮肤文件夹转成 osu!droid 可用皮肤
- droid 上贴图/音效没生效（先查白名单与 @2x，再查加载规则）
- 维护 `~/Projects/osu2droid/` 转换器本身

---

# 一、hitburst 引擎契约（做判定动画必读）

以下全部由 ppy/osu 源码 + 实机验证得出，是**硬约束**，不是风格建议：

1. **帧率固定 60 fps**。hitburst 不吃 `skin.ini` 的 `AnimationFramerate`，每张 PNG 播约 16.7 ms。
2. **非循环动画播完冻结在最后一帧**。末帧必须全透明，否则残影会挂到引擎淡出结束。
3. **帧名 `hitX-N.png`，N 必须从 0 开始**。从 -1 起（部分 fancy 皮肤这么干）在 lazer 里整套静默回退默认皮肤。
4. **显示尺寸 = 画布像素 × HitObject.Scale（CS 联动）**。引擎对 burst 不做任何运动变换——位移、缩放、旋转全部烘进帧。画布大小只改变容纳框，不改变内容相对大小。
5. **加载优先级**：`-0` 动画存在则忽略静态 `hitX.png`；`300g`/`300k`/`100k` 是 stable 用的，lazer std 不查。
6. **`particle50/100/300.png` 存在时引擎额外触发 ParticleExplosion**（可选增益）。透明粒子**仍然会触发**该分支，不能用透明图"关闭"，安装时必须备份后移走。
7. `LegacyJudgementPieceNew` 路径还会叠加 0.5 alpha additive 副本，自带一点辉光。

## 关键修正：动画型判定有 120 ms 引擎淡入

**这一条推翻了很多按「第 0 帧最亮」设计的方案。**

osu! 对**动画型**判定贴图施加约 **120 ms 线性淡入，皮肤无法关闭**，stable 与 lazer 都如此：

- lazer `LegacyJudgementPieceNew/Old.PlayAnimation()`：`this.FadeInFromZero(120)` 挂在**整个判定容器**上（含序列帧本体）。紧随的 `if (animation?.FrameCount > 1) return;` 只跳过 scale/rotation 变换，**跳不过淡入**。淡出为 `Delay(500).FadeOut(600)`。
- 三个常量出自 peppy 的 PR "Adjust judgement animations to match stable"（ppy/osu#10890）——是为对齐 stable 而写的。

**设计含义**：

- 把内容强度峰值放在第 0 帧是无效的——会被乘 0。
- **内容峰值锚定在引擎淡入到顶的第 7 帧（117 ms）**。
- **内容不要自己缓升**：引擎已给线性淡入，内容再缓升 = 两层相乘，起手更慢更暗。内容保持满亮时，感知攻势 = 引擎淡入本身 = 引擎允许的最快起手。
- 「运动」由**形状演变**提供：半径一路扩张（感知峰值处仍在生长）、光芒前几帧射满、字形尽早可辨。
- 收尾：峰值后用 4–5 帧（67–83 ms）干脆归零。

**对无淡入客户端的稳健性**：内容平顶意味着若无淡入，感知峰值自然落在 f0–f6。同一份帧在两种客户端都成立，**不要**为迁就淡入把内容整体后移（那会在无淡入环境里变拖沓）。

实测感知曲线（13 帧 / 217 ms，内容不透明度 × 引擎淡入）：

```
f0 0 | f1 .12 | f2 .26 | f3 .41 | f4 .55 | f5 .69 | f6 .83 | f7 .97(峰值) | f8 .82 | f9 .56 | f10 .32 | f11 .12 | f12 0
```

内容时长预算建议 **≤250 ms（约 15 帧）**，使其远早于 500 ms 引擎淡出点死亡。

**适用边界**：std 模式实测验证；mania/taiko 判定图路径不同，未验证。

---

# 二、hitburst 设计取舍：用「实体光爆」而非细环扩张

**不要走「细环从 note 中心向外扩张」的路子**（参考素材 clean 即此路）。两条理由：

1. **需求**：环扩张只是把 note 原生扩张动画（scale 1.0→1.4、240 ms、Easing.Out）重画一遍，不提供新的打击感。
2. **渲染**：note 轮廓是「彩虹带 + 深色凹槽 + 不透明白圈」三道结构。环必须从 note 内部穿到外部，穿越那几帧必然与 note 糊在一起。实测最终半径提到 1.28× note 半径仍读成「note 带彩色光晕」，提到 1.42× 才成立，但此时低判定与高判定的半径差已被压得很窄。

## 实体光爆四层（时间上错开是关键）

1. **判定色光团 bloom（f0–f10）**：饱和判定色柔光团，从 note 中心铺开**并越过 note 边缘**，承担「接替原生扩张」的体量。半径下限 ≥1.30× note 可见半径，否则被 note 白圈吞掉。
2. **细密辐射光芒 radiance（f0–f9）**：n 条渐隐光芒**瞬时射出**（首帧即达 62% 长度）。条数/长度/锐度按判定分级——隐喻「越精准越细密锐利」。
3. **白热核心 hot core（f0–f5）**：一点极亮强光，给出「击中」的一瞬。
4. **判定徽记 glyph（f1–f9）**：判定数字，Miss 用红叉。

**时间分层是必须的，不是美化**：四层同时打满时，白色字形叠在白色闪光上互相抵消，只剩深色描边可见、看起来发暗。f0 由白热核心独占、字形 f1 才起手，问题消失。

## 覆盖度 vs 有机感

- 纯平顶圆盘（大面同不透明度）读成「塑料贴片」；纯渐变球太弱、note 彩虹会透出来混色。
- 可行解：**平顶覆盖（保覆盖）+ 宽外晕 + 微幅高频噪声扰动边缘**（幅度 ±5.5%、频率 6/12/24）。幅度试过 ±13% 会变齿轮/花瓣状，频率低会整体扭曲成三瓣。
- 光芒别开太亮：会把光团的判定色冲成浅蓝泛白（白混比 0.70→0.55 才正常）。
- 光团半径长大（面积增加）会抵消亮度衰减，**不透明度曲线必须比直觉更陡**，让总能量快速回落。实测目标：峰值 f0、50% 落在 83 ms、10% 落在 133 ms、167 ms 归零。

## 量化标尺（能量 = alpha 总和，与参考素材同一套指标）

| 素材 | 峰值帧 | 50% | 10% |
|---|---|---|---|
| clean | f3 | 100 ms | 133 ms |
| fancy | f5 | 300 ms | 433 ms |
| fancy/optimized | f2 | 100 ms | 167 ms |
| 本套（推荐） | f0（内容）/ f7（感知） | 83 ms | 133 ms |

## 几何基准

先量**真实 note** 再定尺寸：`hitcircle.png` 实测 140×140，主体 Alpha 边界约 124 px，半径约 62 px。**画布大小不等于内容大小**。初始实现套用 128 px 默认尺寸、只放大画布解决外圈裁切，会导致「太大」反复返工。

---

# 三、osu!droid 皮肤转换

转换器：`~/Projects/osu2droid/`（`osu2droid.py` 单文件 + `whitelist.py` 白名单 + `osu2droid.sh` GUI 启动脚本）。

## 硬规则（转换正确性的根基）

- **droid 只按白名单加载**：皮肤文件名（去扩展名）必须命中 droid 内置 `assets/gfx` 或 `assets/sfx` 清单，否则直接无视、回退内置默认贴图。精简过度的症状是「手机上元素变默认皮肤」而不是报错。
- **@2x 分场景，别一概而论**：静态贴图（gfx 白名单）与动画帧、comboburst、scorebar-kidanger 都**不读 @2x**——白名单按去扩展名的文件名精确匹配，`hitcircle@2x` 匹配不上 `hitcircle` 就直接回退内置默认；动画帧带 @2x 会被注册成游戏不请求的名字，等于失效。唯一例外是**字体**（`getTextureWithPrefix`）：拼 `<prefix>-0.png` 调 `loadTexture(external=true)`，文件缺失时自动找 `@2x` 并以 `inSampleSize=2` 降采样加载，所以字体原生支持 HD。转换器仍统一降采样：要覆盖静态贴图 + 动画帧这两大块，字体只是顺带统一、无副作用。**PC 皮肤大多 HD-only，这是本工具存在的核心理由。**
- SD 与 @2x 并存时只留 SD；`comboburst` 音效只认 `.wav`；`sliderendcircle(overlay)` 缺失时从 `hitcircle(overlay)` 复制（stable 视觉回退）；全透明 `selection-mods/random/options` 要剔除（PC 皮肤用透明遮罩藏选歌图标，droid 会当真显示）。
- 动画帧（`hit300-0`、`sliderb0`…）、`comboburst`、`scorebar-kidanger(2)`、字体系列（`<prefix>-<0-9/comma/dot/percent/x/d/p>`）不在 gfx 白名单内也必须保留——加载路径不同。完整规则表见 `references/droid-loading-rules.md`。

## 常规流程

1. **CLI 转换**（无 GUI 依赖，最快验证）：`python3 osu2droid.py --cli 皮肤.osk -o 目录`；输出 `<皮肤名> (droid).osk`。
2. **GUI**（含 droid 专项设置表单：滑条提示、disableKiai、combo 缩放、主题色等，写进 skin.json）：`./osu2droid.sh`。
3. **核对输出**：白名单外文件为零（`skin.ini`/`skin.json` 除外）、无 `@2x` 残留、`skin.json` 与 droid 官方 `SkinConversion.kt` 映射语义一致。

## droid 升级后更新白名单

白名单来自 droid 仓库 assets，不是手写的：`git clone --depth 1 https://github.com/osudroid/osu-droid`，对 `assets/gfx` 与 `assets/sfx` 各 `ls` 一遍、去扩展名生成 `whitelist.py` 的 `DROID_GFX`/`DROID_SFX`。同时 diff `ResourceManager.java` 的 `ANIMATABLE_TEXTURES`/`OPTIONAL_TEXTURES` 与 `SkinConversion.kt` 的 ini→json 映射是否变化。

## 在 Guix 下跑 GUI（PyQt6 + Pillow）

- 运行走 `./osu2droid.sh`：`guix shell python-pyqt python-pillow` 一次性环境。
- guix shell 的临时 profile **不会**自动进 `GUIX_PYTHONPATH`，必须在 guix shell 内部展开 `$GUIX_ENVIRONMENT` 拼 site-packages。在外层写 `env GUIX_PYTHONPATH=$GUIX_ENVIRONMENT/…` 展开的是空值。
- 从 agent 工具 subprocess 调 guix shell 时，外层 `PYTHONPATH`（指向内核 venv）会污染 guix python 的 import 路径，可能加载到 ABI 不兼容或缺 libz 的坏 PIL，报 ImportError 但真因是路径污染——测试时清掉 `PYTHONPATH` 或用 `bash -lc`。

---

# 四、验收

## 转换器改动后（三件套全跑）

1. **CLI 回归**：拿任意真实 .osk 全链路转换，检查统计输出（保留数/降采样数/剔除数）。
2. **@2x-only 构造**：复制皮肤目录、删光所有非 `@2x` 的 png 再转换——断言输出尺寸 = 源 @2x 尺寸一半、无 @2x 残留。只测成对 SD/HD 的皮肤会完全漏掉降采样路径。
3. **GUI 冒烟**：`QT_QPA_PLATFORM=offscreen` 下启动 `gui()`，进程活过 4 秒即构建成功（外部 `timeout 4` 判活）。不要在 agent 会话里弹真机 Wayland 窗口验证——事件循环会挂起直到超时。

## hitburst 动画验收

- **动态预览优于静态 contact sheet**：静态图只能看单帧，不能证明节奏和连打重叠。用 `preview.html` 验收原始帧、lazer 淡入模拟、慢放、240 BPM 连打、同点叠打、浅色/杂色背景。
- **生成脚本是唯一入口**：Pillow 在 4× 原稿上绘制再独立下采样出 1×/2×；手工改产物会在下次生成时丢失。
- **安装要可回滚**：`scripts/install.py <skin>` 先 dry-run 再加 `--apply`；把目标皮肤旁的旧判定帧和 particle 备份到时间戳目录，保留 `skin.ini`、note、lighting 和声音。

---

## references

- `references/droid-loading-rules.md` — droid 贴图/音效加载规则全表、skin.ini→skin.json 映射、白名单外死文件清单
