#!/usr/bin/env python3
"""
probe_chapter_starts.py — 探测 HyperFrames 渲染视频的章扉页视觉起点。

为什么需要:index.html 里的 `data-start` 是 clip 起点,但 GSAP 入场动画 +
前一章"end" clip 停留,导致章扉页大标题真正在画面上呈现的瞬间比
`data-start` 晚约 1 秒(不是早先估的 3-6s,那是因为采样粒度太粗被
过校正了)。配 TTS 旁白时不能信 data-start,必须看实际帧。

用法:
  python3 scripts/probe_chapter_starts.py <video.mp4> \\
    --candidates 25 175 305 405 555 740 800 \\
    --output probed_starts.json

工作流程:
  1) 对每个候选 data-start,在 [t-3 .. t+3] 1fps 采 7 帧 (jpg)
     —— 关键: 步长必须 ≤ 1s,粗采样(3-5s 步长)会跨过真实切换点,
        产生过校正(看着像修对了其实错更远)
  2) 用主模型 vision 看每张帧,判别"画面是 PART NN 章节扉页吗"
  3) 找到最早一个被判定为"扉页"的 t,作为该章的视觉起点
  4) 输出 json,下游 align_and_merge.py 直接用这个

前置:
  - ffmpeg / ffprobe 在 PATH
  - 主模型有原生 vision 能力(MiniMax-M3 / GPT-4V 类)—— 不要绕道给子模型

实测参考 (2026-06-23 emacs-21-days, 1fps 精细采样):
  data-start  →  视觉起点  (延迟)
       25     →     26     (+1)
      175     →    176     (+1)
      305     →    306     (+1)
      405     →    406     (+1)
      555     →    556     (+1)
      740     →    741     (+1)
      800     →    801     (+1)
—— 全章一致 +1s。这是 HyperFrames GSAP 入场动画的标准延迟,
   新视频大概率也是这个值,但**仍然必须实测,不能直接套**。

(2026-06-23 之前曾记录为 +3..+6s,系 3s 步长采样的过校正结果,
已废弃。详见 SKILL.md 坑 11/12。)
"""
import argparse
import json
import os
import subprocess
import sys
import tempfile


def probe_duration(video: str) -> float:
    out = subprocess.check_output(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "default=noprint_wrappers=1:nokey=1", video]
    ).decode().strip()
    return float(out)


def extract_frame(video: str, t: float, out_path: str):
    subprocess.run([
        "ffmpeg", "-y", "-ss", f"{t:.2f}", "-i", video,
        "-frames:v", "1", "-q:v", "3", out_path,
    ], check=True, capture_output=True)


def is_chapter_title(model_call, image_path: str, expected_n: int) -> bool:
    """问 vision:画面是不是 PART NN 章节扉页?返回 bool。

    model_call 是 (image_path, question) -> str 的可调用对象,
    由外部注入(主模型 vision_analyze 或自己的视觉能力)。
    """
    q = (
        f"这张图里右上角或中央是否有大字号 PART 0{expected_n} "
        f"的章节标题(可能带副标题)?如果是章节扉页(章节标题页),"
        f"回答 YES;如果还是上一章的结尾内容,回答 NO。只回 YES 或 NO。"
    )
    answer = model_call(image_path, q).strip().upper()
    return answer.startswith("Y")


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("video", help="HyperFrames 渲染的 mp4")
    ap.add_argument("--candidates", type=int, nargs="+", required=True,
                    help="index.html 里的 data-start 列表(秒)")
    ap.add_argument("--offsets", type=int, nargs="+", default=list(range(-3, 4)),
                    help="每个候选的采样偏移(秒),默认 -3..+3 1fps 7 帧。"
                         "绝对不要用 3-5s 步长——会跨过真实切换点(详见 SKILL.md 坑 12)")
    ap.add_argument("--output", default="probed_starts.json")
    args = ap.parse_args()

    if not os.path.isfile(args.video):
        print(f"FATAL: video not found: {args.video}", file=sys.stderr)
        sys.exit(1)

    duration = probe_duration(args.video)
    print(f"video duration: {duration:.1f}s")

    with tempfile.TemporaryDirectory() as tmp:
        results = {}
        for n, cand in enumerate(args.candidates, start=1):
            print(f"\n[probe] PART {n:02d} candidate data-start={cand}s")
            frames = []
            for off in args.offsets:
                t = cand + off
                if t < 0 or t > duration:
                    continue
                fp = os.path.join(tmp, f"p{n:02d}_t{t:.0f}.jpg")
                extract_frame(args.video, t, fp)
                frames.append((t, fp))

            # 找到最早的"YES"帧
            visual_start = None
            for t, fp in frames:
                # model_call 必须在外部注入(主对话里)
                # 这里只打印提示,真正的判别由调用方在循环里调
                # 框架版直接调 vision_analyze
                try:
                    from hermes_tools import vision_analyze  # type: ignore
                    ans = vision_analyze(
                        image_url=fp,
                        question=(
                            f"这张图里是否有大字号 PART 0{n} 的章节标题"
                            f"(可能带副标题)?是章节扉页回 YES,还是上一章"
                            f"结尾回 NO?只回 YES 或 NO。"
                        ),
                    )
                    yes = str(ans).strip().upper().startswith("Y")
                except Exception as e:
                    print(f"  vision_analyze 失败: {e}", file=sys.stderr)
                    yes = False
                print(f"  t={t:4}s  YES={yes}")
                if yes and visual_start is None:
                    visual_start = t
                    break

            if visual_start is None:
                print(f"  WARN: 没找到 PART {n} 扉页(检查 candidate 范围)")
                visual_start = cand + 3  # 兜底用 data-start + 3

            results[f"part_{n}"] = {
                "data_start": cand,
                "visual_start": visual_start,
                "delay_s": round(visual_start - cand, 1),
            }
            print(f"  → 视觉起点: {visual_start}s (延迟 {visual_start - cand:+.1f}s)")

    out = {
        "video": os.path.abspath(args.video),
        "duration_s": duration,
        "results": results,
        "visual_starts": [r["visual_start"] for r in results.values()],
    }
    with open(args.output, "w") as f:
        json.dump(out, f, indent=2, ensure_ascii=False)
    print(f"\n[done] {args.output}")
    print(f"visual_starts = {out['visual_starts']}")


if __name__ == "__main__":
    main()
