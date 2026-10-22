# osu!droid 皮肤加载规则全表

依据 osudroid/osu-droid 源码实证（`ResourceManager.java` / `SkinConversion.kt` / `OsuSkin.java`，commit ba63c7b）。

## 贴图加载路径

`loadCustomSkin()` 遍历 APK 内置 `assets/gfx` 清单（163 个），对每个名字：

- 皮肤文件夹有同名 SD 文件 → 加载皮肤版（SD 优先，@2x 被无视）
- 皮肤只有 @2x → **不加载**，回退 droid 内置默认（这是与 stable 的关键差异）
- 皮肤也没有 → 用内置默认

例外（不在 gfx 清单也加载）：

- 动画帧：`followpoint-` `hit0-` `hit100-` `hit100k-` `hit300-` `hit300g-` `hit300k-` `hit50-` `menu-back-` `play-skip-` `scorebar-colour-` `sliderb`（无连字符，帧名 `sliderb0`…）`sliderfollowcircle-`，帧名 `<前缀><序号>`，序号不限；帧名带 `@2x` 后缀不会被识别为帧（动画失效），必须降采样成 SD 帧名
- `comboburst`、`comboburst-0..9`（png）；音效 `comboburst.wav` 只认 wav 后缀
- `scorebar-kidanger` / `scorebar-kidanger2`；`scorebar-ki` / `scorebar-marker` 属 OPTIONAL——缺失时不回退默认皮肤（直接不显示）
- 字体：skin.ini 的 `HitCirclePrefix`（默认 `default`）、`ScorePrefix` / `ComboPrefix`（默认 `score`）指向的 `<prefix>-<字符>` 系列，字符集 = `0-9` + `comma dot percent x d p`（`SpriteFont`/`ScoreNumber` 运行时按需加载）。**字体是唯一原生支持 @2x 的类别**：`getTextureWithPrefix` 拼 `<prefix>-N.png` 走 `loadTexture(external=true)`，文件不存在会找 `@2x` 并以 `inSampleSize=2` 加载。

## 音效

内置 `assets/sfx`（50 个：normal/soft/drum/nightcore 四套 hitsound + spinner/section/menu 等）同名覆盖。谱面双 sound set（`normal-hitnormal2`）皮肤侧不生效，转换器不处理。

## skin.ini → skin.json（官方 SkinConversion.kt 映射）

- `CursorRotate/CursorTrailRotate` → `Cursor.rotateCursor/rotateCursorTrail`（缺省 true）
- `Combo1..8` → `ComboColor.colors` + `forceOverride: true`
- `SliderTrackOverride` → `sliderBodyColor` + alpha 1 + 不跟随 combo；hint 色 = 轨道各通道 +15（clamp 255）、hint 全开（alpha 1 / 宽 25 / minLength 1）
- `SliderBorder` → `sliderBorderColor`
- `SongSelectActiveText/InactiveText` → `Color.MenuItemSelectedTextColor/MenuItemDefaultTextColor`
- `Fonts` 段三 prefix + overlap 原样进 `Fonts`
- `AnimationFramerate`、`LayeredHitSounds`、`SliderBallFlip`、`SpinnerFrequencyModulate` → `Utils`；`comboTextScale` 固定 0.8
- `Layout`：`useNewLayout: true`、`BackButton.scaleWhenHold: false`、`ModsButton/OptionsButton/RandomButton` 固定 `y: -16`（补偿 droid 默认皮肤按钮底部裁切）
- `Theme.accentColor` 缺省 `#C2CAFF`

skin.json 存在时 droid 只做 `mergeMissing`（ini 值回填），不会覆盖 json 已有键——转换器预生成完整 json 后，用户的 droid 专项设置是安全的。

## 白名单外的名字 = 死文件

PC 皮肤常见但 droid 完全不读的：PC 选歌界面专属贴图、taiko/catch/mania 元素、PC 专属 UI 等——判断一律以 `whitelist.py` 为准，不靠记忆。
