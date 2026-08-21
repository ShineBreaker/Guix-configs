# 配音 / 字幕工作流(从 "21 天 Emacs" 视频实战整理)

Elisp Explainer 视频做完后通常还要加配音 + 字幕,否则只是无声动画。这一步有三条容易踩死的坑,都是这回视频里真实遇到过的。

## 整体管线(5 步)

```bash
# 1. 写配音稿:voiceover.md,每段对应一个 clip 的 [data-start, data-start+data-duration]
# 2. 装环境(Kokoro 本地,免 token):
pip3 install --user kokoro-onnx soundfile
# 关键:中文必须装 espeak-ng 系统库(下面"坑 1"详述)

# 3. 逐段 TTS(走 hyperframes tts,因为是本地 Kokoro 路径):
mkdir -p voice
while IFS= read -r section; do
  idx=$(echo "$section" | cut -d'|' -f1)
  text=$(echo "$section" | cut -d'|' -f2-)
  npx hyperframes tts -v zf_xiaobei -o "voice/clip-${idx}.wav" "$text"
done < voiceover.segments.tsv

# 4. 用 ffmpeg 按时间戳拼回 880s 主音轨(详细 ffmpeg 脚本见下面)

# 5. mux 进 mp4
ffmpeg -i renders/video.mp4 -i voice/main.wav -c:v copy -c:a aac voice.mp4
```

## 配音稿结构(voiceover.md 范本)

按 `data-start..data-start+data-duration` 一段一段写,跟 GSAP 时间轴对齐:

```markdown
## CLIP 01 — 封面 (0..25s, 实际配到 0..20s)
今天我们用 13 分钟,把 21 天学会 Emacs 的精华串成一条线。

## CLIP 02 — Part 1 标题 (25..35s)
第一部分,基础筑基。学三件事 — 改键、帮助系统、以及 Elisp 是怎么求值的。

## CLIP 03 — Day 1 改键 (35..75s)
先把小拇指救下来。Windows 上,把左 Win 改成 Alt...
```

完整 25 段见 `~/emacs-21-days/voiceover.md`(21 天教程的实拍稿)。

**三原则**:
- **画外音,不是念屏**。屏幕上画了什么,稿子里就**不**再说什么;只补画面没说的逻辑、动机、对比。
- **语速 4-5 字/秒中文**。880s 视频大概 8000-10000 字。短句比长句顺,逗号比句号多。
- **英文术语保留**:Emacs / M-x / vertico / consult / use-package / init.el 之类不翻。硬翻会念得奇奇怪怪。

## 坑 1:Kokoro 中文走 espeak 失败(最常见)

跑 `npx hyperframes tts -v zf_xiaobei` 下载完 27MB 中文声模后会报:

```
RuntimeError: language "zh" is not supported by the espeak backend
```

根因:Kokoro 中文(zf_xiaobei 之类)走 espeak 做音素化,本机没装 espeak-ng → zh 失败。

**修复**:
```bash
# Debian/Ubuntu
apt-get install espeak-ng
# macOS
brew install espeak-ng
# NixOS
nix-env -iA nixpkgs.espeak-ng
# Guix(用户级)
guix install espeak-ng
```

装完**重启 shell** 让 PATH 生效,重跑 `npx hyperframes tts`。

Kokoro 本身有 `misaki` 路径不依赖 espeak,但 hyperframes 0.7.3 的 CLI 没接这条路,只能装 espeak-ng。

## 坑 2:`npx hyperframes tts` 吞云端 key

**这条最坑**。`npx hyperframes tts` 的 `--help` 写得像是"自动检测 HeyGen / ElevenLabs / Kokoro",但实际**只走 Kokoro 本地**。即使 `$HEYGEN_API_KEY` 设了,这条 CLI 也会静默走本地 Kokoro。

要真正用 HeyGen / ElevenLabs,得用 `hyperframes-media` skill 的统一入口:

```bash
node ~/.local/share/hermes/skills/hyperframes-media/scripts/audio.mjs \
  --request ./audio_request.json \
  --hyperframes . \
  --out ./audio_meta.json
```

或者用单次 HeyGen 调用:

```bash
node ~/.local/share/hermes/skills/hyperframes-media/scripts/heygen-tts.mjs \
  "Welcome to HyperFrames" -o narration.wav --words narration.words.json
```

这条 CLI 调用 REST,带 word timestamp,一次性出字幕数据。

## 坑 3(已解决):MiniMax `t2a_v2` TTS,2026-06 实测通

**修正**:之前这条说"Hermes 没有 MiniMax 封装、别凭印象写 endpoint"——2026-06-23 跟用户一起实测发现:**MiniMax(深圳那家 MiniMax 公司)的 `t2a_v2` 同步语音合成 API 完全可以直连**,key 在 `~/.local/share/hermes/.env` 的 `MINIMAX_CN_API_KEY` 里就有。整个链路 5 分钟接通。下面是真实跑通的细节,后续做视频直接抄。

### 端点 & 鉴权

```
POST https://api-bj.minimaxi.com/v1/t2a_v2
Authorization: Bearer <MINIMAX_CN_API_KEY>
Content-Type: application/json
```

备用域:`api.minimaxi.com` / `api-bj.minimaxi.com` 都行,北京机房。

### 请求体(最常用字段)

```json
{
  "model": "speech-2.8-hd",                       // 或 2.8-turbo / 2.6-hd / 02-hd / 01-hd
  "text": "欢迎来到《21 天精通 Emacs》系列视频",   // <10000 字符;>3000 字符建议 stream
  "stream": false,                                  // true 走 SSE
  "voice_setting": {
    "voice_id": "male-qn-qingse",                 // 见下表
    "speed": 1.0,                                  // 0.5..2
    "vol": 1.0,                                    // 0..10
    "pitch": 0                                     // -12..12
  },
  "audio_setting": {
    "sample_rate": 32000,                          // 8000/16000/22050/24000/32000/44100
    "bitrate": 128000,                             // 32000/64000/128000/256000
    "format": "mp3",                               // mp3/pcm/flac/wav/opus
    "channel": 1                                   // 1=mono, 2=stereo
  },
  "language_boost": "Chinese",                     // 或 null 让模型自选
  "output_format": "hex",                          // hex (非流) / url (24h 有效) / hex (流)
  "subtitle_enable": false                         // 同步出字幕,词级时间戳
}
```

### 返回(非流,成功)

```json
{
  "data": {"audio": "<hex 编码的 mp3>", "status": 2},
  "extra_info": {
    "audio_length": 11016,        // 毫秒
    "audio_size": 177972,         // 字节
    "audio_sample_rate": 32000,
    "audio_format": "mp3",
    "audio_channel": 1,
    "usage_characters": 26,       // 计费字符数
    "word_count": 22              // 已发音字数
  },
  "base_resp": {"status_code": 0, "status_msg": "success"},
  "trace_id": "01b8bf9b..."
}
```

解码:`bytes.fromhex(j["data"]["audio"])` → 直接 `open(path, "wb").write()` 就是 mp3 文件。

### 文本语法糖(做教程视频很有用)

- **停顿**:`<#0.6#>` 文本里塞这个,模型在那个位置停 0.6 秒(0.01..99.99)。教程里用来给画面切换留节奏。
- **行内发音覆盖**:拼音带声调数字 `处理/(chu3)(li3)` / IPA `(lɪv)` / 粤拼 `(sung3)`。专治术语多音字。
- **语气词标签**(仅 `speech-2.8-hd` / `2.8-turbo` 支持):`(laughs)` `(sighs)` `(breath)` `(coughs)` `(humming)` `(emm)` 等 18 个。让旁白有呼吸感,不要滥用。

### 中文男声音色(实测 4 个)

试听 mp3 在 `~/emacs-21-days/voice_demos/`,用同一段话对比:

| 标签 | voice_id | 风格 | 适用 |
|---|---|---|---|
| 清爽青年 | `male-qn-qingse` | 年轻、节奏感 | 教程主推,口语化 |
| 精英 | `male-qn-jingying` | 沉稳、商务 | 严肃讲解 |
| 抒情 | `Chinese (Mandarin)_Lyrical_Voice` | 慢、文艺 | 偏旁白/故事 |
| 空姐 | `Chinese (Mandarin)_HK_Flight_Attendant` | 圆润、广播感 | 国粤混合(`language_boost=Chinese,Yue`) |

教程类**首选 `male-qn-qingse`**(清爽青年),字正腔圆、节奏自然,带 `(laughs)` 也不出戏。完整系统音色列表调 `POST /v1/voice/list` 拉,或查官方 FAQ。

### 错误码(踩过的)

- `1002` 触发限流 → 退避重试
- `1004` 鉴权失败 → 检查 `MINIMAX_CN_API_KEY` 长度(实测 125 字符是正常的)
- `1039` 触发 TPM 限流 → 降速
- `1042` 非法字符 >10% → 文本里有 emoji/控制字符,清掉
- `2013` 入参错误 → 多半是 `voice_id` 写错(音色列表没拉全)

### 可复用的 Python 脚本

见 `~/emacs-21-days/scripts/minimax-tts.py`(skill 目录的 `scripts/minimax-tts.py` 也存了一份),核心是从 hermes `.env` 加载 key(关键:**`execute_code` 是独立子进程,父进程 env 不继承,必须在脚本里手动 load**)+ 批量调 TTS + hex 解码 + 按时间戳写 wav 头。

### 整条管线(MiniMax 版)

```bash
# 1. 写 7 段配音稿(中文,每章 1 段,4-5 字/秒)
# 2. 跑批量合成
python3 scripts/minimax-tts.py --segments voiceover.segments.tsv --out voice/chapter-{:02d}.mp3
# 3. ffmpeg 拼回 880s 主音轨 + 烧进 mp4(用上面"拼音轨 ffmpeg 片段"里的 amix 模板)
ffmpeg -i renders/video.mp4 -i voice/main.wav -c:v copy -c:a aac emacs-21-days-final.mp4
```

走 MiniMax 的话比 Kokoro 本地快得多(云端 RTF ~0.1,本地 Kokoro 慢 3-5 倍),质量也明显好,适合正式交付。

## 坑 4:完整系统音色 + 查询端点路径(2026-06-23 实测)

### 查询端点是 **POST `/v1/get_voice`**,不是 GET,也不是 `/v1/voice_list`

直连试错记录(都返回 404 page not found):

```
GET  /v1/get_voice       404
GET  /v1/voice_list      404
GET  /v1/voices          404
GET  /v1/t2a_v2/voices   404
```

正确路径:

```bash
POST https://api-bj.minimaxi.com/v1/get_voice
Content-Type: application/json
Authorization: Bearer <MINIMAX_CN_API_KEY>
{"voice_type": "all"}   # system | voice_cloning | voice_generation | all
```

返回的 `system_voice` 数组里 `voice_id` / `voice_name` / `description` 直接喂给 t2a_v2 用。账号下没有 cloning/generation 音色时,这两个数组是空(实测空数组 + status_code 0)。

### 中文女声 / 其它音色(2026-06-23 实测 13 个)

之前只试过 4 个男声——后续做面向新手的教程时,女声也是合理选择。`/v1/get_voice` 拉到的中文/粤语 system_voice(全部 voice_id 都在该账号可调,直接喂 `voice_setting.voice_id`):

| 标签 | voice_id | 实测风格 |
|---|---|---|
| 少女 | `female-shaonv` | 偏年轻明亮,降调 (pitch=-30) 后可接受 |
| 御姐 | `female-yujie` | 沉稳,自带停顿偏慢(实测 30 字 12.4s) |
| 成熟女性 | `female-chengshu` | 中年正式感 |
| 甜美女性 | `female-tianmei` | 偏甜偏快,适合轻松内容 |
| 淡雅学姐 | `danya_xuejie` | 气质沉,直接可用的"低一点"女声 |
| 软软女孩 | `Chinese (Mandarin)_Soft_Girl` | 温和不尖 |
| 温柔学姐 | `Chinese (Mandarin)_Gentle_Senior` | **教程主推,成熟温柔,新人友好**(2026-06-23 选定) |
| 温暖少女 | `Chinese (Mandarin)_Warm_Girl` | 偏暖的年轻女声 |
| 嗲嗲学妹 | `diadia_xuemei` | 偏甜偏萌,可能尖 |
| 俏皮萌妹 | `qiaopi_mengmei` | 偏活泼 |
| 清脆少女 | `Chinese (Mandarin)_Crisp_Girl` | 偏高,跟"少女降调"反方向 |
| 温润青年 | `Chinese (Mandarin)_Gentle_Youth` | 男,温润但偏年轻 |
| 温润男声 | `Chinese (Mandarin)_Gentleman` | 男,正式温润,适合严肃讲解 |

完整账号可用列表约 200+ 条 system_voice(含英文/日文/韩文/西/法/俄/葡/意/阿/土/乌/印尼/荷兰/越南),`/v1/get_voice` 一次拉全存到本地 JSON 复用,不要在 t2a_v2 调用时一个个试错(`2013` 错误码就是入参问题)。

### 试听工作流(用户偏好固化)

**别让用户盲选**。音色试听必须实跑:

1. 准备 4-8 个候选,跑 `t2a_v2` 同一段 30 字样文(中英混排 + 1 停顿 + 1 语气词)对比
2. 输出 mp3 落到 `voice_demos/<voice_id>.mp3`,让用户直接听
3. 候选不设上限,用户说"都不行"就换一批,直到选定
4. 选定后再批量合成 7 段,不要在选定前烧太多 API 配额

**判定用户偏好"低 / 沉稳 / 成熟"**:除了换音色,还可以用 `voice_modify` 在不换 voice_id 的前提下微调:

```json
"voice_modify": {
  "pitch": -30,         // [-100, 100] 数值越低越低沉
  "intensity": -10,     // [-100, 100] 越负越柔和
  "timbre": 0           // [-100, 100] 越正越清脆
}
```

`voice_modify` 仅 mp3 / wav / flac 非流场景 + 全部 mp3 流场景支持。**对"少女降调"用例实测有效**(`female-shaonv` + `pitch=-30, intensity=-10` 出来可用,但不如直接换 `danya_xuejie` 自然)。

## 坑 5:章边界对齐必须**裁切**,不能"自然溢出"(2026-06-23 踩过)

视频 7 章的章扉页起点 = 各段音轨的绝对起点,音轨长度 = `ffprobe` 实测毫秒(不要用 t2a_v2 返回的 `audio_length`,**边界上有 30-100ms 偏差**)。

### 错误做法(我第一次写的)

`prev_end += audio_duration`,不裁切,溢出的音直接覆盖下一章扉页。**结果**:Part 3 音轨 106.2s > 视频章区间 100s,溢出 6.2s 覆盖了 Part 4 扉页;Part 5 溢出 8.6s,Part 7 溢出 8.2s。**画面已经切到下章,声音还在讲上一章尾巴**——很难受。

### 正确做法

每章音轨时长 = `min(实测时长, 下章起点 - 本章起点)`。多出的部分用 ffmpeg `-t` 裁切:

```python
cap = next_chapter_start  # 视频里下章扉页起点(秒)
max_allowed = cap - ch_start
if audio_duration > max_allowed + 0.3:  # +0.3 容忍舍入
    subprocess.run([
        "ffmpeg", "-y", "-i", chapter.mp3,
        "-t", f"{max_allowed:.3f}", "-c", "copy", chapter_clipped.mp3,
    ], check=True)
```

裁切到下章起点,音轨**精确**落在 `[章起点, 下章起点]` 区间。最后一章兜底为视频总长(880s),多出的尾部填静音。

### 拼接脚本范本

```python
# 整体方案: 静默 + 章1音轨 + 静默 + 章2音轨 + ... + 静默(到 880s)
plan = []
prev_end = 0.0
for i, ch_start in enumerate(CHAPTER_STARTS):
    pid = i + 1
    dur = probe_ms(chapter_mp3) / 1000.0
    # 1) 章 i 之前补静音
    lead = max(0.0, ch_start - prev_end)
    if lead > 0.05:
        make_silence(lead, "silence_lead.mp3")
        plan.append(("silence_lead.mp3", lead))
    # 2) 章 i 音轨,溢出裁切
    cap = CHAPTER_STARTS[i+1] if i+1 < len(CHAPTER_STARTS) else VIDEO_DURATION
    max_allowed = cap - ch_start
    if dur > max_allowed + 0.3:
        clip_chapter(chapter_mp3, max_allowed, f"chapter_{pid}_clipped.mp3")
        use_dur = max_allowed
    else:
        use_dur = dur
    plan.append((chapter_path, use_dur))
    prev_end = ch_start + use_dur
# 3) 尾部静音补到视频总长
tail = max(0.0, VIDEO_DURATION - prev_end)
if tail > 0.05:
    make_silence(tail, "silence_tail.mp3")
    plan.append(("silence_tail.mp3", tail))
```

`make_silence` 用 `ffmpeg -f lavfi -i anullsrc=r=32000:cl=mono -t <秒> -acodec libmp3lame` 生成 mp3 静音(别用 wav,concat 时 codec 不一致会出错)。

## 坑 6:实测语速 6.5 字/秒,跟"4-5 字/秒"偏差大,时长预算要按实测

之前文档写"4-5 字/秒中文"——这是 Kokoro 本地 / 偏慢音色的速。**温柔学姐 `speech-2.8-hd` 1.0 速实测**:

| 章节 | 字数 | 实测时长 | 字/秒 |
|---|---|---|---|
| Part 1 | 829 | 129.6s | 6.4 |
| Part 2 | 891 | 126.6s | 7.0 |
| Part 3 | 728 | 106.2s | 6.9 |
| Part 4 | 1014 | 146.7s | 6.9 |
| Part 5 | 1348 | 193.6s | 7.0 |
| Part 6 | 378 | 59.3s | 6.4 |
| Part 7 | 260 | 38.2s | 6.8 |
| **平均** | — | — | **6.6** |

**时长预算 = 目标秒数 × 6.6 字**(`speed: 1.0` 温柔学姐 / speech-2.8-hd)。Male 音色可能略快 0.5-1 字/秒,实测前先跑 30 字样文估速。

语速可调:`voice_setting.speed: 0.5..2`。教程**不建议低于 0.85 或高于 1.15**——再慢听感拖沓,再快新人跟不上。

## 稿件详细度三档(用户偏好固化)

| 档 | 目标 | 字数估算 | 教学风格 | 适用 |
|---|---|---|---|---|
| **概览** | 已懂基础的快速回顾 | 880s × 2-3 = 1760-2640 字 | 念屏式,关键术语快速过 | 老用户改用别的工具时 |
| **入门**(默认) | 完全新手可跟 | 880s × 6-7 = 5300-6200 字 | 概念白话定义 → 例子 → 过渡 | 21 天 Emacs 这种**教程主推** |
| **手把手** | 完全零基础逐步跟做 | 880s × 9-11 = 8000-9700 字 | 每步停下来解释为什么,多举例 | 极简引导类(第一次装系统之类) |

**用户明确说"面向初学者/完全新手水平"时,选"入门"档**——温柔学姐 1.0 速 880s 视频,稿子 **~5500-6000 字**,每章 600-1300 字,留 80-100s 给纯画面/转场/章扉页。

**用户说"按视频时长对齐"**(2026-06-23 显式偏好)→ 改稿子而非改视频。稿子超/欠 → 加/减内容 → 再合成,迭代到每章误差 < 5s。**不要"先出稿子再硬调视频时长"**——视频是按章设计的,改视频破坏 GSAP 时间线和可视化 motif。

**稿子微调 vs 重新合成的 ROI**:改 < 50 字(改 1-2 句)→ 用 `synthesize_narration.py` 只重跑那一章,不要全跑;改 > 200 字(整章)→ 整章重跑;调音色/语速 → 7 章全跑(参数在脚本顶,改一次就行)。每次合成 ~3s/章 + 1-2s/章网络,7 章总 < 30s,不算贵。

## 其它小修正

- **`output_format: url`** 返回的 mp3 URL 24h 有效,适合批量合成后**延迟烧录**(比如先把所有 url 存 JSON,过几小时再下载)。流式场景只支持 hex。
- **`language_boost: "Chinese"`**(而不是 `"auto"` / `null`)对中文教程**显著更稳**,自动选偶尔会把术语切到英文发音。
- **`aigc_watermark: true`** 会在音频末尾加节奏标识(防深度伪造水印),正式发布建议开;内部测试可关。

## 拼音轨 ffmpeg 片段

```bash
# 输入:voice/clip-01.wav ... voice/clip-25.wav,每段 ~ 时长
# 输出:880s 主音轨
ffmpeg -y \
  -f lavfi -t 880 -i anullsrc=r=24000:cl=mono \
  -i voice/clip-01.wav -i voice/clip-02.wav ... \
  -filter_complex "
    [0:a]volume=0[bg];
    [1:a]adelay=0|0[a1];
    [2:a]adelay=20000|20000[a2];
    ...
    [bg][a1][a2]...[a25]amix=inputs=26:duration=longest:dropout_transition=0
  " \
  -ar 24000 -ac 1 -c:a pcm_s16le voice/main.wav
```

更稳的做法是:每段算出 delay 后用 `-i` + `-filter_complex` 串联,而不是 amix 叠加(避免双声道混响)。

## 字幕轨道(可选)

`npx hyperframes transcribe voice/main.wav --model small` 出 word-level 时间戳,转成 `.srt` / `.vtt` 烧进 mp4,或者作为独立轨道:

```bash
ffmpeg -i renders/video.mp4 -i voice/main.wav \
  -i voice/main.vtt -c:v copy -c:a aac -c:s mov_text voice.mp4
```
