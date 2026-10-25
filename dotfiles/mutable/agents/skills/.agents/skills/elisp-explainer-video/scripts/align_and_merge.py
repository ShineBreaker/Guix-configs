"""
音轨章边界对齐 + 烧录到视频(2026-06-23 从 21 天 Emacs 视频项目沉淀的范式)。

用法:
    python3 align_and_merge.py

约定:
    - 视频章扉页起点 = 音轨章起点(精确对齐)
    - 每章音轨时长不能超出"下章起点 - 本章起点",超出 ffmpeg -t 裁切
    - 视频总长兜底,尾部补静音
    - 输入:
        - audio/narration_chapter_NN.mp3 (7 段)
        - emacs-21-days.mp4 (HyperFrames 渲染的 mp4)
    - 输出:
        - audio/narration_aligned.mp3 (章边界对齐的 880s 音轨)
        - emacs-21-days-final.mp4 (视频+音轨合成版)

修改点(换项目时):
    - CHAPTER_STARTS: 章扉页的**实测视觉起点**,**不要直接抄 index.html 的 data-start**
      (2026-06-23 踩过: data-start 跟视觉起点差 ~1s,凭 data-start 拼会出现
       "声音讲下一章,画面还在上一章"的错位)
    - 拿真值:跑 scripts/probe_chapter_starts.py,1fps 精细采样 + vision 确认
    - VIDEO_DURATION: 跟根元素 data-duration 一致
    - AUDIO_DIR / VIDEO / FINAL: 项目目录

CRITICAL(2026-06-23 实测):不要把 CHAPTER_STARTS 设成 data-start 的数字。
默认占位用的 [25, 175, 305, 405, 555, 740, 800] 就是错的——真实视觉起点是
+1s 后。直接跑这个脚本,音轨会跟画面错位 ~1s。务必先 probe 拿真值。
"""
import os
import json
import subprocess

# === 项目相关常量(改这些适配其它项目) ============================
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
AUDIO_DIR = os.path.join(ROOT, "audio")
VIDEO = os.path.join(ROOT, "emacs-21-days.mp4")
FINAL = os.path.join(ROOT, "emacs-21-days-final.mp4")
# 章扉页的"实测视觉起点"——2026-06-23 emacs-21-days 项目用 probe_chapter_starts.py
# 1fps 采样 + vision 确认拿到。直接用 data-start [25,175,...,800] 是错的(差 ~1s)。
CHAPTER_STARTS = [26, 176, 306, 406, 556, 741, 801]  # 7 个章扉页视觉起点(秒)
VIDEO_DURATION = 880  # 视频总长(秒)

# 兜底"未测就直跑"防御:如果 CHAPTER_STARTS 还是 [25,175,305,405,555,740,800]
# 这套数字(data-start),它跟正确值差 1s,跑出来会跟画面错位。打印醒目警告。
_DEFAULT_DATA_START = [25, 175, 305, 405, 555, 740, 800]
if CHAPTER_STARTS == _DEFAULT_DATA_START:
    import sys
    print(
        "WARN: CHAPTER_STARTS 还是 data-start 数字 [25,175,...] —— 视觉起点差 ~1s!\n"
        "      先跑 scripts/probe_chapter_starts.py 拿真值,再改本脚本顶上的 CHAPTER_STARTS。\n"
        "      详见 SKILL.md 坑 11/12。",
        file=sys.stderr,
    )

# === 工具函数 =====================================================
def get_duration_ms(path: str) -> int:
    """ffprobe 拿精确时长(ms)。比 t2a_v2 返回的 audio_length 更准(边界 ±30-100ms)。"""
    out = subprocess.check_output(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "default=noprint_wrappers=1:nokey=1", path]
    ).decode().strip()
    return int(float(out) * 1000)


def make_silence(seconds: float, path: str):
    """生成指定秒数的静音 mp3。用 anullsrc + libmp3lame,跟 t2a_v2 输出 codec 一致。"""
    subprocess.run([
        "ffmpeg", "-y", "-f", "lavfi",
        "-i", f"anullsrc=r=32000:cl=mono",
        "-t", f"{seconds:.3f}",
        "-q:a", "9", "-acodec", "libmp3lame",
        path,
    ], check=True, capture_output=True)


def clip_chapter(src: str, max_seconds: float, dst: str):
    """ffmpeg -t 裁切到 max_seconds。-c copy 不重编码。"""
    subprocess.run([
        "ffmpeg", "-y", "-i", src,
        "-t", f"{max_seconds:.3f}", "-c", "copy", dst,
    ], check=True, capture_output=True)


# === 拼接方案生成 ================================================
def build_plan():
    """
    返回拼接方案:[(path, duration_s), ...] 按播放顺序。
    每章: 静默(前章末→本扉页) + 章音轨(裁切到下章起点)
    """
    with open(os.path.join(AUDIO_DIR, "durations.json")) as f:
        durations = json.load(f)

    plan = []
    prev_end = 0.0
    for i, ch_start in enumerate(CHAPTER_STARTS):
        pid = i + 1
        ms = durations[str(pid)]["ffprobe_ms"]
        dur = ms / 1000.0

        # 1) 前置静音
        lead_silence = max(0.0, ch_start - prev_end)
        if lead_silence > 0.05:
            sil = os.path.join(AUDIO_DIR, f"silence_lead_{pid:02d}.mp3")
            make_silence(lead_silence, sil)
            plan.append((sil, lead_silence))

        # 2) 章音轨(可能裁切)
        cap = CHAPTER_STARTS[i + 1] if i + 1 < len(CHAPTER_STARTS) else VIDEO_DURATION
        max_allowed = cap - ch_start
        if dur > max_allowed + 0.3:  # +0.3 容忍舍入
            clipped = os.path.join(AUDIO_DIR, f"narration_chapter_{pid:02d}_clipped.mp3")
            clip_chapter(
                os.path.join(AUDIO_DIR, f"narration_chapter_{pid:02d}.mp3"),
                max_allowed, clipped,
            )
            audio = clipped
            use_dur = max_allowed
        else:
            audio = os.path.join(AUDIO_DIR, f"narration_chapter_{pid:02d}.mp3")
            use_dur = dur
        plan.append((audio, use_dur))
        prev_end = ch_start + use_dur

    # 3) 尾部静音
    tail_silence = max(0.0, VIDEO_DURATION - prev_end)
    if tail_silence > 0.05:
        sil = os.path.join(AUDIO_DIR, "silence_tail.mp3")
        make_silence(tail_silence, sil)
        plan.append((sil, tail_silence))

    return plan


# === 主流程 ======================================================
def main():
    plan = build_plan()

    # 打印方案(debug)
    print("=== 拼接方案 ===")
    pos = 0.0
    for path, dur in plan:
        name = os.path.basename(path)
        print(f"  {pos:6.1f}s - {pos+dur:6.1f}s  ({dur:5.1f}s)  {name}")
        pos += dur
    print(f"  总: {pos:.1f}s  (目标 {VIDEO_DURATION}s)")

    # ffmpeg concat 拼接
    concat_list = os.path.join(AUDIO_DIR, "concat_list_aligned.txt")
    with open(concat_list, "w") as f:
        for path, _ in plan:
            f.write(f"file '{os.path.basename(path)}'\n")
    aligned = os.path.join(AUDIO_DIR, "narration_aligned.mp3")
    subprocess.run(
        ["ffmpeg", "-y", "-f", "concat", "-safe", "0",
         "-i", concat_list, "-c", "copy", aligned],
        check=True, capture_output=True,
    )
    print(f"\n[concat] {aligned}  ({get_duration_ms(aligned)/1000:.1f}s)")

    # 烧录到视频(如果存在)
    if os.path.isfile(VIDEO):
        print(f"\n[merge] {VIDEO} + {aligned}  ->  {FINAL}")
        subprocess.run([
            "ffmpeg", "-y",
            "-i", VIDEO,
            "-i", aligned,
            "-map", "0:v:0", "-map", "1:a:0",
            "-c:v", "copy", "-c:a", "aac", "-b:a", "192k",
            "-shortest",
            FINAL,
        ], check=True, capture_output=True)
        print(f"  -> {FINAL}  ({get_duration_ms(FINAL)/1000:.1f}s)")
    else:
        print(f"\n[skip merge] 视频不存在: {VIDEO}")
        print("(先跑 `cd <项目> && npx hyperframes render -o <name>.mp4`)")

    # 存方案,后续重跑直接用
    with open(os.path.join(AUDIO_DIR, "alignment_plan.json"), "w") as f:
        json.dump({
            "video_duration_s": VIDEO_DURATION,
            "chapter_starts": CHAPTER_STARTS,
            "plan": [{"path": p, "duration_s": d} for p, d in plan],
            "aligned_mp3": aligned,
            "final_mp4": FINAL if os.path.isfile(FINAL) else None,
        }, f, indent=2, ensure_ascii=False)


if __name__ == "__main__":
    main()
