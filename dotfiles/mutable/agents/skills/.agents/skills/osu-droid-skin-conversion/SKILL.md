---
name: osu-droid-skin-conversion
description: Use when 转换 osu! 皮肤到 osu!droid、排查贴图不加载、或维护 osu2droid 转换器。
version: 1.0
author: Hermes (glm-5.3-flash)
license: MIT
metadata:
  hermes:
    tags: [osu, droid, skin, converter]
    related_skills: []
---

# osu!(PC) skin → osu!droid 转换器

## When to Use

- 用户要把 .osk / PC 皮肤文件夹转成 osu!droid 可用的皮肤
- 用户反馈 droid 上贴图/音效没生效（先查白名单与 @2x，再查加载规则）
- droid 版本升级后需要更新转换器的白名单
- 维护或扩展 ~/Projects/osu2droid/ 转换器本身

转换器：`~/Projects/osu2droid/`（`osu2droid.py` 单文件 + `whitelist.py` 白名单 + `osu2droid.sh` GUI 启动脚本）。

## 硬规则（转换正确性的根基）

- **droid 只按白名单加载**：皮肤文件名（去扩展名）必须命中 droid 内置 `assets/gfx` 或 `assets/sfx` 清单，否则 droid 直接无视、回退内置默认贴图。精简超度的症状是「手机上元素变默认皮肤」而不是报错。
- **@2x 分场景，别一概而论**：静态贴图（gfx 白名单）与动画帧、comboburst、scorebar-kidanger 都**不读 @2x**——白名单按去扩展名的文件名精确匹配，`hitcircle@2x` 匹配不上 `hitcircle` 就直接回退内置默认；动画帧带 @2x 会被注册成游戏不请求的名字，等于失效。唯一例外是**字体**（`getTextureWithPrefix`）：它拼 `<prefix>-0.png` 调 `loadTexture(external=true)`，文件缺失时会自动找 `@2x` 并以 `inSampleSize=2` 降采样加载（`QualityFileBitmapSource`），所以字体原生支持 HD。转换器仍统一降采样：要覆盖静态贴图 + 动画帧这两大块，字体只是顺带统一、无副作用。PC 皮肤大多 HD-only，这是本工具存在的核心理由，不是可选项。
- SD 与 @2x 并存时只留 SD；`comboburst` 音效只认 `.wav`；`sliderendcircle(overlay)` 缺失时从 `hitcircle(overlay)` 复制（stable 视觉回退）；全透明 `selection-mods/random/options` 要剔除（PC 皮肤用透明遮罩藏选歌图标，droid 会当真显示）。
- 动画帧（`hit300-0`、`sliderb0`…）、`comboburst`、`scorebar-kidanger(2)`、字体系列（`<prefix>-<0-9/comma/dot/percent/x/d/p>`）不在 gfx 白名单内也必须保留——加载路径不同。完整规则表见 `references/droid-loading-rules.md`。

## 常规流程

1. CLI 转换（无 GUI 依赖，最快验证）：`python3 osu2droid.py --cli 皮肤.osk -o 目录`；输出为 `<皮肤名> (droid).osk`。
2. GUI（含 droid 专项设置表单：滑条提示、disableKiai、combo 缩放、主题色等，写进 skin.json）：`./osu2droid.sh`。
3. 完成后核对输出：白名单外文件为零（`skin.ini`/`skin.json` 除外）、无 `@2x` 残留、`skin.json` 与 droid 官方 `SkinConversion.kt` 映射语义一致。

## droid 升级后更新白名单

白名单来自 droid 仓库 assets，不是手写的：`git clone --depth 1 https://github.com/osudroid/osu-droid`，对 `assets/gfx` 与 `assets/sfx` 各 `ls` 一遍、去扩展名生成 `whitelist.py` 的 `DROID_GFX`/`DROID_SFX`。同时 diff 一下 `src/ru/nsu/ccfit/zuev/osu/ResourceManager.java` 的 `ANIMATABLE_TEXTURES`/`OPTIONAL_TEXTURES` 和 `src/com/osudroid/ui/skinning/SkinConversion.kt` 的 ini→json 映射是否变化。

## 测试三件套（改动后全跑）

1. **CLI 回归**：拿任意真实 .osk 全链路转换，检查统计输出（保留数/降采样数/剔除数）。
2. **@2x-only 构造**：复制皮肤目录、删光所有非 `@2x` 的 png 再转换——断言输出尺寸 = 源 @2x 尺寸一半、无 @2x 残留。只测成对 SD/HD 的皮肤会完全漏掉降采样路径。
3. **GUI 冒烟**：`QT_QPA_PLATFORM=offscreen` 下启动 gui()，进程活过 4 秒即构建成功（外部 `timeout 4` 判活，窗口事件循环不退出是正常的）。不要在 agent 会话里弹真机 Wayland 窗口验证——事件循环会挂起直到超时。

## 在 guix 下跑 GUI（PyQt6 + Pillow）

- 运行走 `./osu2droid.sh`：`guix shell python-pyqt python-pillow` 一次性环境。
- guix shell 的临时 profile **不会**自动进 `GUIX_PYTHONPATH`，必须在 guix shell 内部展开 `$GUIX_ENVIRONMENT` 拼 site-packages（脚本里已经是 `sh -c 'export GUIX_PYTHONPATH="$GUIX_ENVIRONMENT/lib/python3.X/site-packages…"; exec python3 …'` 的形态）。在外层 shell 写 `env GUIX_PYTHONPATH=$GUIX_ENVIRONMENT/…` 展开的是空值，包找不到。
- 从 agent 工具（hermes 内核）subprocess 调 guix shell 时，外层的 `PYTHONPATH`（指向内核 venv）会污染 guix python 的 import 路径，可能加载到 ABI 不兼容或缺 libz 的坏 PIL，报 ImportError 但真因是路径污染——测试时从 env 里清掉 `PYTHONPATH`，或用 `bash -lc` 登录 shell 跑。
