#!/usr/bin/env python3
"""校验视频容器指标，并从最终文件抽取代表帧。"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path


def run(command: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, check=False, text=True, capture_output=True)


def parse_rate(value: str) -> float:
    numerator, denominator = value.split("/", 1)
    return float(numerator) / float(denominator)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("video", type=Path)
    parser.add_argument("--width", type=int, required=True)
    parser.add_argument("--height", type=int, required=True)
    parser.add_argument("--fps", type=float, required=True)
    parser.add_argument("--duration", type=float, required=True)
    parser.add_argument("--times", default="0.8,4.2,5.8,7.95")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    if not args.video.is_file() or args.video.stat().st_size == 0:
        print("视频文件不存在或为空", file=sys.stderr)
        return 1

    probe = run([
        "ffprobe", "-v", "error", "-show_entries",
        "format=duration,size:stream=codec_type,codec_name,width,height,r_frame_rate,nb_frames",
        "-of", "json", str(args.video),
    ])
    if probe.returncode != 0:
        print(probe.stderr, file=sys.stderr)
        return 1

    payload = json.loads(probe.stdout)
    streams = payload.get("streams", [])
    video_stream = next((item for item in streams if item.get("codec_type") == "video"), None)
    if video_stream is None:
        print("没有视频流", file=sys.stderr)
        return 1

    actual = {
        "codec": video_stream.get("codec_name"),
        "width": video_stream.get("width"),
        "height": video_stream.get("height"),
        "fps": parse_rate(video_stream.get("r_frame_rate", "0/0")),
        "frames": int(video_stream.get("nb_frames", "0")),
        "duration": float(payload.get("format", {}).get("duration", "0")),
        "size": int(payload.get("format", {}).get("size", "0")),
    }
    expected = {
        "width": args.width,
        "height": args.height,
        "fps": args.fps,
        "duration": args.duration,
    }
    errors = []
    for key, value in expected.items():
        tolerance = 0.05 if key in {"fps", "duration"} else 0
        if abs(float(actual[key]) - float(value)) > tolerance:
            errors.append(f"{key}: 期望 {value}，实际 {actual[key]}")

    output_dir = args.output or args.video.with_name("verification-frames")
    output_dir.mkdir(parents=True, exist_ok=True)
    extracted = []
    for raw_time in args.times.split(","):
        timestamp = float(raw_time)
        if not 0 <= timestamp <= actual["duration"]:
            errors.append(f"抽帧时间越界: {timestamp}")
            continue
        frame = output_dir / f"frame-{timestamp:g}s.png"
        extract = run([
            "ffmpeg", "-v", "error", "-ss", str(timestamp), "-i", str(args.video),
            "-frames:v", "1", "-y", str(frame),
        ])
        if extract.returncode != 0 or not frame.is_file() or frame.stat().st_size == 0:
            errors.append(f"抽帧失败: {timestamp}s: {extract.stderr.strip()}")
        else:
            extracted.append(str(frame.resolve()))

    result = {"ok": not errors, "actual": actual, "expected": expected, "frames": extracted, "errors": errors}
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if not errors else 1


if __name__ == "__main__":
    raise SystemExit(main())
