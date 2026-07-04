---
name: narrated-video-alignment
description: "Repair or assemble the audio+subtitle track for an already-rendered, segmented video (HyperFrames explainer, slide deck, course video, screencast) so narration matches the picture exactly. Trigger on 音频和视频对不上, 配音和画面不匹配, narration drift, voiceover out of sync, 音画不同步, 重做配音, 重新对位, 补字幕, 烧字幕, or any task where a finished video needs a TTS-scripted voiceover + burned-in subtitles built to match its visual chapter boundaries. Covers topic drift, length drift, and boundary drift. Pipeline: 1fps probe → visual inventory → script rewrite → TTS → atempo/padding alignment → silencedetect SRT → ffmpeg subtitles burn-in. Use when the deliverable is a single MP4 with audio+subs; for new authoring, route to /faceless-explainer or /general-video."
---

# Narrated Video Alignment

Take a finished, segmented, **silent** video and produce a new MP4 where the TTS narration, audio bed, and burned-in subtitles line up with the visual chapter boundaries.

This is **not** a video-creation skill. The video already exists. Your job is the **post-production audio/subtitle track**.

## When to use this skill

The user says one of:

- "Audio and video don't match" / "音画不同步" / "对不上轨"
- "Rewrite the script so the narration matches what's on screen"
- "Add a voiceover to this silent HyperFrames / slide / screencast"
- "Burn Chinese (or any) subtitles into the video"
- "My TTS track is 30s short of the video length — fix it without re-rendering"

You are NOT authoring the visuals. Don't rewrite the HTML composition; don't touch the GSAP timeline. The video is the source of truth.

## The diagnostic you must run first

Before any rewrite, prove the misalignment with evidence. **The user is usually right that "it doesn't match"** — the question is *what kind* of mismatch.

### 1. 1fps frame probe + visual chapter inventory

The design's `data-start` for chapter clips is **NOT** the visual chapter start. Chapter title cards animate in over 1-10s after `data-start`, and the previous chapter's tail can run long. Always:

```bash
# 1fps dump of the whole video, scaled
ffmpeg -y -i input.mp4 -vf "fps=1,scale=640:-1" -q:v 4 frames/f%04d.jpg
```

Then **look at the actual frames around each design-claimed chapter boundary**. Build a table:

| chapter | design start | actual visual start | actual visual end | what's on screen |
|---|---|---|---|---|
| 01 | 25s | 27s | 35s | "PART 01 · 基础筑基 · Day 01-03" |
| 02 | 35s | 35s | 75s | Day 01 改键 (Mac/Win 改键 + 6组光标) |

Use the **actual** times downstream. The design `data-start` is a hint, not a contract.

### 2. TTS character-count vs actual duration

`speech-2.8-hd` and similar Chinese TTS at 1.0 speed run **~0.148-0.157 s/char** including `<#0.4#>`-style pause markers. Plan for **0.155 s/char** as the safe estimate. If you need exact, run one short TTS test (~140 chars) and divide.

| TTS engine | speed | s/char (Chinese) |
|---|---|---|
| MiniMax speech-2.8-hd (温柔学姐) | 1.0 | ~0.155 |
| HeyGen Starfish | 1.0 | ~0.150 |
| ElevenLabs (zh) | 1.0 | ~0.180-0.220 |
| Kokoro-82M local | 1.0 | ~0.170 |

### 3. The three classic misalignments

After 1+2, your fix path is one of three (usually in combination):

**A. Topic drift** — narration mentions a feature the screen does NOT show, or skips a feature the screen DOES show. Fix: rewrite the script so each chapter's narration matches the visual inventory. The visual inventory is the source of truth.

**B. Length drift** — narration is 30s shorter or longer than the visual chapter. Fix: write a 5-10% safety margin; if still off, use `atempo=actual/target` (range 0.5-2.0, single chain) to compress, or append silence with `anullsrc` to extend.

**C. Boundary drift** — narration crosses a chapter title card (the speaker is talking about chapter N+1 while the title card for chapter N is still animating in). Fix: shift the chapter TTS start to *before* the title card animation begins (i.e. ~2-3s before the visual chapter start), so the transition phrase plays during the title card animation.

All three are usually present at once. A clean repair handles A by rewriting, then addresses B+C by alignment.

## Script rewrite (path A)

Use the **voiceover.md** style — one section per visual chapter, with explicit `(video Ns .. Ms)` tags showing which scene it covers. Cross-check each section against the visual inventory from step 1; if narration says "we'll cover X" but the visual chapter shows Y, **change narration**, not the visuals.

```markdown
## Part 1 — 基础筑基 (视频 25-175s, 目标 150s)
> 内容必须严格匹配: 25-35s 标题 + 35-75s Day 01 改键 + 75-95s Day 02 帮助
> + 95-155s Day 03 Elisp 求值 + 155-175s Day 03 Org-mode

第一部分,基础筑基。<#0.4#>
学三件事 — 改键、帮助系统,以及 Elisp 是怎么求值的。<#0.4#>
... (每段讲对应 Day 的内容, 不能跨越 Day 边界)
```

Pause markers (`<#0.4#>` 句内, `<#1.5#>` 段间) help the TTS engine produce silence for chapter transitions. Encode them in the script.

## TTS + alignment pipeline (paths B + C)

Use any TTS provider. Provider-specific quirks are NOT in this skill; consult `hyperframes-media` for the engine, or write a one-off `requests.post(...)` script.

```python
# Pattern: for each chapter
#   1. If narration > chapter length * 1.05: atempo to fit
#   2. If narration < chapter length * 0.95: append silence to fill
#   3. If |narration - chapter| within +/-5%: pass through

# Padding silence:
ffmpeg -y -f lavfi -i anullsrc=r=32000:cl=mono -t <pad_s> -q:a 9 -acodec libmp3lame sil.mp3

# atempo (single chain, 0.5-2.0):
ffmpeg -y -i chapter.mp3 -filter:a "atempo=<factor>" chapter_fit.mp3
# If factor > 2.0, chain: atempo=2.0,atempo=2.0,atempo=<factor/4>

# Concat into the full track:
# Use ABSOLUTE paths in the concat list file — relative paths fail when
# cwd != the directory of the list file. Always set cwd=work_dir in the
# subprocess.run call.
echo "file '/abs/path/to/ch00_cover.mp3'" > list.txt
echo "file '/abs/path/to/ch01.mp3'" >> list.txt
ffmpeg -y -f concat -safe 0 -i list.txt -c copy aligned.mp3
```

**Bug to avoid**: `ffmpeg concat` with relative paths silently fails with "No such file" if your Python `subprocess.run` doesn't `cwd=` into the right directory. Always use absolute paths OR pin `cwd=work_dir`.

## Subtitle generation without whisper

Whisper is the gold standard but not always installed. **Cheap fallback using ffmpeg only:**

```python
import subprocess, re

def get_silences(path, min_d=0.4):
    """Returns list of (silence_start, silence_end) where silence > min_d."""
    out = subprocess.run([
        "ffmpeg", "-i", str(path),
        "-af", f"silencedetect=noise=-30dB:d={min_d}",
        "-f", "null", "-"
    ], capture_output=True, text=True)
    events = re.findall(r"silence_(start|end): ([\d.]+)", out.stderr)
    ses, cur_s = [], None
    for kind, t in events:
        ts = float(t)
        if kind == "start":
            cur_s = ts
        else:
            if cur_s is not None:
                ses.append((cur_s, ts))
            cur_s = None
    return ses

def to_sentence_phrases(silences, total_dur):
    """Convert silence events into (start, end) voice phrases."""
    phrases, prev = [], 0.0
    for ss, se in silences:
        if ss > prev:
            phrases.append((prev, ss))
        prev = se
    if prev < total_dur:
        phrases.append((prev, total_dur))
    return phrases
```

This gives you **sentence-level** timings (not word-level). It's rough — long pauses become separate "sentences" — but it's enough for clean SRT.

**Reconcile phrase count vs script sentence count.** The two will not match exactly (long pauses split a sentence, a single sentence may have no detectable pause). Three rules:

- If `len(phrases) > len(sentences)`: merge trailing phrase tail into the last sentence's slot
- If `len(phrases) < len(sentences)`: split the longest phrases proportionally to sentence character counts
- If they match: zip directly

The first iteration is rough. **Validate by spot-checking 3-5 frames** at known times — does the subtitle text match the on-screen topic at that moment? If the subtitle says "Day 04" but the screen shows "Day 05", the alignment is broken.

## Burn-in subtitles into the MP4

```bash
# Use ffmpeg's subtitles filter (NOT -vf ass= — that's for SSA only).
# Convert SRT commas to dots first (ffmpeg subtitle parser is strict).
sed -i 's/,/./g' input.srt

# Pick a font that exists on the system. On Guix with Sarasa installed:
FONT=/run/current-system/profile/share/fonts/truetype/Sarasa-Regular.ttc

ffmpeg -y -i input.mp4 \
  -vf "subtitles=input.srt:force_style='FontName=Sarasa Gothic SC,FontSize=36,PrimaryColour=&H00FFFFFF,OutlineColour=&H00000000,BackColour=&H80000000,Outline=2,Shadow=1,BorderStyle=4,MarginV=80,Alignment=2'" \
  -c:v libx264 -crf 20 -preset fast \
  -c:a copy \
  output.mp4
```

`BorderStyle=4` is opaque box (good for dark backgrounds). `BorderStyle=1` is outline only (better for bright/complex backgrounds but harder to read). Pick by content.

## Final assembly

```bash
# Combine narration track (no subs) with the original silent video
ffmpeg -y -i silent.mp4 -i aligned.mp3 \
  -map 0:v:0 -map 1:a:0 \
  -c:v copy -c:a aac -b:a 192k \
  -shortest \
  final.mp4
```

`-shortest` clips whichever stream ends first. Verify the result is the video length, not the audio length — if audio is shorter, **pad it to video length** with `apad` or silence first.

## The iteration loop

After each pass:

1. Pick 3-5 timestamps from critical moments (chapter boundaries, key visual changes)
2. Extract those frames
3. Read the on-screen topic AND the subtitle text at that moment
4. Verify: does the subtitle match the screen?
5. Verify: does the audio (listen if possible) match the screen?

If the subtitle at 175s says "Day 05" while the screen at 175s is still "Day 04", the alignment is off. Recalibrate phrase-to-sentence mapping.

## Files you'll produce

```
project/
  frames/f0001.jpg ... f0880.jpg          # 1fps dump
  audio/v2/ch00.mp3 ... ch07.mp3          # per-chapter TTS
  audio/v2/work/ch00.mp3 ... ch07.mp3     # atempo/padded
  audio/v2/concat_list.txt                # absolute paths
  audio/v2/narration_aligned.mp3          # full track
  subtitles.srt                            # ~130 entries typical for 14-min video
  final-with-subs.mp4                     # deliverable
```

## Pitfalls

- **Trusting `data-start` for chapter boundaries**: always 1fps probe. Chapter title cards animate 1-10s past `data-start`.
- **Trusting TTS-returned audio_length**: it usually reports a slightly different number than `ffprobe` says for the same file. Use `ffprobe` for the final alignment.
- **`ffmpeg concat` relative paths**: see the bug-to-avoid above.
- **`atempo` 0.5-2.0 limit**: outside this range, the audio pitch shifts badly. For 0.5x-2x, single chain is fine. Beyond 2x, chain `atempo=2.0,atempo=2.0,...`. Below 0.5x, similar chaining.
- **Hardcoding chapter starts from a voiceover.md**: voiceover.md is a design doc, not a measurement. The 1fps probe is the measurement.
- **Skipping visual QA after a rewrite**: after any script change, re-render and re-spot-check at the new chapter boundaries — drift compounds.
- **Not handling the cover frame**: a 20-30s static cover with no audio is the #1 user complaint. Always write a cover narration or insert BGM.
- **Recursing too deep on diagnostics**: one diagnostic pass (1fps probe + character count + 3-frame spot check) is usually enough. Don't keep iterating; the first pass identifies the *type* of misalignment and the fix path is the same every time.
- **Letting the script exceed the chapter by >50%**: a 1.5x atempo starts sounding rushed; past that, rewrite shorter. Don't ship a 2x-sped-up voiceover.
- **Trusting `silencedetect` threshold across chapters**: TTS engines vary in their natural pause lengths. If phrase/sentence reconciliation fails for one chapter, try `min_d=0.3` or `min_d=0.5` — don't force a single global threshold.

## When to stop and ask the user

- The visual inventory shows a chapter that has no obvious narration topic (e.g. a "skip" day in the design). Ask whether to fill it or leave it.
- A chapter's atempo factor would exceed 1.5x (sounds rushed). Ask whether to rewrite shorter or accept the speedup.
- The script has controversial claims / personal opinions that the user might want to edit. Don't regenerate without confirming.
- You discover the source video itself is broken (e.g. corrupted file, wrong dimensions, hard cuts mid-chapter). Surface that finding — alignment cannot fix a broken source.

## Bundled scripts and templates

- `scripts/silencedetect_phrases.py` — extracts sentence-level timings from a TTS mp3 using `ffmpeg silencedetect`, reconciles with a markdown script, emits SRT. Use when no Whisper is available.
- `scripts/tts_align.py` — runs atempo-compress / silence-pad for each chapter, then concats into one narration mp3 and merges with the silent video. Reads `align_config.json` for the plan.
- `templates/align_config.example.json` — starter config for `tts_align.py`.
