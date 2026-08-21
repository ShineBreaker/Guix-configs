"""
TTS alignment + concat pipeline for narrated-video-alignment.

For each chapter (Cover + Parts + Outro), the script:
  1. Runs the per-chapter TTS mp3 (caller has already produced these)
  2. atempo-compresses if narration > target * 1.05
  3. Appends silence if narration < target * 0.95
  4. Concatenates into one mp3, using absolute paths in the concat list

Then composes the final MP4 with the original silent video + audio track.

Usage:
    python tts_align.py

Reads config from a small JSON sidecar (or edit CHANNELS below).
"""
import json
import os
import subprocess
from pathlib import Path


def make_silence(seconds: float, out: Path) -> None:
    subprocess.run(
        [
            "ffmpeg", "-y", "-f", "lavfi", "-i", "anullsrc=r=32000:cl=mono",
            "-t", f"{seconds:.3f}", "-q:a", "9", "-acodec", "libmp3lame",
            str(out),
        ],
        check=True, capture_output=True,
    )


def speed_to(src: Path, dest: Path, factor: float) -> None:
    if not 0.5 <= factor <= 2.0:
        raise ValueError(f"atempo {factor} out of 0.5-2.0 single-chain range")
    subprocess.run(
        [
            "ffmpeg", "-y", "-i", str(src),
            "-filter:a", f"atempo={factor:.4f}", str(dest),
        ],
        check=True, capture_output=True,
    )


def probe_s(path: Path) -> float:
    out = subprocess.check_output(
        [
            "ffprobe", "-v", "error", "-show_entries", "format=duration",
            "-of", "default=noprint_wrappers=1:nokey=1", str(path),
        ]
    ).decode().strip()
    return float(out)


def align_chapter(
    src: Path, target_s: float, out: Path, work_dir: Path
) -> None:
    """atempo or pad the source mp3 to match target_s."""
    actual = probe_s(src)
    # Tolerance: pass through if within ±5%
    if abs(actual - target_s) / target_s <= 0.05:
        out.write_bytes(src.read_bytes())
        return
    if actual > target_s:
        # atempo speedup
        factor = actual / target_s
        speed_to(src, out, factor)
    else:
        # append silence
        pad = target_s - actual
        sil = work_dir / f"{src.stem}_silence.mp3"
        make_silence(pad, sil)
        list_path = work_dir / f"{src.stem}_list.txt"
        with open(list_path, "w") as f:
            f.write(f"file '{src.resolve()}'\nfile '{sil.resolve()}'\n")
        subprocess.run(
            [
                "ffmpeg", "-y", "-f", "concat", "-safe", "0",
                "-i", str(list_path), "-c", "copy", str(out),
            ],
            check=True, capture_output=True, cwd=str(work_dir),
        )
    final = probe_s(out)
    drift = abs(final - target_s)
    print(f"  [{src.stem}] {actual:.1f}s -> target {target_s:.0f}s "
          f"-> final {final:.1f}s (drift {drift:.2f}s)")


def main() -> None:
    import argparse
    p = argparse.ArgumentParser()
    p.add_argument("--config", default="align_config.json")
    args = p.parse_args()

    with open(args.config) as f:
        cfg = json.load(f)

    video_in = Path(cfg["video_in"])
    audio_dir = Path(cfg["audio_dir"])      # contains chXX.mp3 per chapter
    work_dir = Path(cfg["work_dir"])        # scratch dir for atempo/padded mp3
    final_mp3 = Path(cfg["final_mp3"])      # narration_aligned.mp3
    final_mp4 = Path(cfg["final_mp4"])      # final-with-audio.mp4 (no subs)

    work_dir.mkdir(parents=True, exist_ok=True)
    plan = cfg["plan"]  # list of {"key", "src", "target_s", "video_start_s"}

    print("=== aligning chapters ===")
    for entry in plan:
        src = audio_dir / entry["src"]
        out = work_dir / f"{entry['key']}.mp3"
        align_chapter(src, entry["target_s"], out, work_dir)

    print("\n=== concat ===")
    list_path = work_dir / "concat_list.txt"
    with open(list_path, "w") as f:
        for entry in plan:
            f.write(f"file '{(work_dir / f'{entry[\"key\"]}.mp3').resolve()}'\n")
    subprocess.run(
        [
            "ffmpeg", "-y", "-f", "concat", "-safe", "0",
            "-i", str(list_path), "-c", "copy", str(final_mp3),
        ],
        check=True, capture_output=True, cwd=str(work_dir),
    )
    print(f"[concat] {final_mp3}  ({probe_s(final_mp3):.1f}s)")

    print("\n=== merge with video ===")
    subprocess.run(
        [
            "ffmpeg", "-y", "-i", str(video_in), "-i", str(final_mp3),
            "-map", "0:v:0", "-map", "1:a:0",
            "-c:v", "copy", "-c:a", "aac", "-b:a", "192k",
            "-shortest", str(final_mp4),
        ],
        check=True, capture_output=True,
    )
    print(f"[merge] {final_mp4}  ({probe_s(final_mp4):.1f}s)")


if __name__ == "__main__":
    main()
