#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
# SPDX-License-Identifier: MIT
"""
MiniMax T2A 同步语音合成批量脚本(2026-06-23 实测通)。

从 ~/.local/share/hermes/.env 读 MINIMAX_CN_API_KEY,
逐段调 https://api-bj.minimaxi.com/v1/t2a_v2,
hex 解码返回 audio 字段,写成 mp3 文件。

输入:voiceover.segments.tsv,每行 3 列:
    chapter_index<TAB>start_seconds<TAB>text

输出:voice/chapter-NN.mp3(每章一段) + voice/segments.json(时间戳元数据)

用法:
    python3 scripts/minimax-tts.py \\
        --segments voiceover.segments.tsv \\
        --out-dir voice \\
        --voice male-qn-qingse \\
        --model speech-2.8-hd

坑提示(已踩过):
- execute_code 是独立子进程,父进程 env 不继承,key 必须在脚本内手动 load
- 不要写 voice_id="male-qn-qingse " 带空格,validate 会报 2013
- 流式(stream=true)只支持 hex 输出,非流支持 hex 和 url(url 24h 有效)
- 教程类首选 male-qn-qingse(清爽青年),其它 4 个实测音色见
  references/voiceover-and-captions.md "中文男声音色" 节
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
from pathlib import Path

import requests

DEFAULT_ENDPOINT = "https://api-bj.minimaxi.com/v1/t2a_v2"
DEFAULT_VOICE = "male-qn-qingse"
DEFAULT_MODEL = "speech-2.8-hd"
HERMES_ENV_PATH = Path.home() / ".local" / "hermes" / ".env"


def load_minimax_key() -> str:
    """从 hermes .env 加载 MINIMAX_CN_API_KEY。

    不把 key 落到任何脚本/文件里,只在当前进程内存里使用。
    """
    candidates = [
        HERMES_ENV_PATH,
        Path.cwd() / ".env",
        Path.cwd() / ".." / ".env",
    ]
    for path in candidates:
        if not path.is_file():
            continue
        for line in path.read_text().splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, _, v = line.partition("=")
            if k.strip() == "MINIMAX_CN_API_KEY" and v.strip():
                return v.strip()
    # 退而求其次:从 env 读(hermes 启动时已注入)
    env_key = os.environ.get("MINIMAX_CN_API_KEY")
    if env_key:
        return env_key
    sys.exit(
        "FATAL: 找不到 MINIMAX_CN_API_KEY。\n"
        f"  期望位置:{HERMES_ENV_PATH}\n"
        "  或环境变量 MINIMAX_CN_API_KEY 已设置。"
    )


def tts_synthesize(
    text: str,
    voice_id: str,
    api_key: str,
    endpoint: str = DEFAULT_ENDPOINT,
    model: str = DEFAULT_MODEL,
    speed: float = 1.0,
    sample_rate: int = 32000,
    bitrate: int = 128000,
    language_boost: str = "Chinese",
    max_retries: int = 3,
) -> bytes:
    """调一次 MiniMax T2A 同步接口,返回 mp3 bytes。"""
    payload = {
        "model": model,
        "text": text,
        "stream": False,
        "voice_setting": {
            "voice_id": voice_id,
            "speed": speed,
            "vol": 1.0,
            "pitch": 0,
        },
        "audio_setting": {
            "sample_rate": sample_rate,
            "bitrate": bitrate,
            "format": "mp3",
            "channel": 1,
        },
        "language_boost": language_boost,
        "output_format": "hex",
    }
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
    }
    last_err: Exception | None = None
    for attempt in range(1, max_retries + 1):
        try:
            r = requests.post(endpoint, json=payload, headers=headers, timeout=60)
            if r.status_code != 200:
                raise RuntimeError(f"HTTP {r.status_code}: {r.text[:200]}")
            j = r.json()
            base = j.get("base_resp", {})
            if base.get("status_code") != 0:
                raise RuntimeError(f"API error: {base} (trace_id={j.get('trace_id')})")
            return bytes.fromhex(j["data"]["audio"])
        except Exception as e:
            last_err = e
            if attempt < max_retries:
                wait = 2 ** attempt
                print(f"  [重试] attempt {attempt} 失败:{e} | {wait}s 后重试", file=sys.stderr)
                time.sleep(wait)
    raise RuntimeError(f"TTS 失败({max_retries} 次):{last_err}")


def parse_segments(path: Path) -> list[dict]:
    """读 TSV:idx<TAB>start_sec<TAB>text。支持空行和 # 注释。"""
    segments = []
    for line in path.read_text().splitlines():
        line = line.rstrip()
        if not line or line.lstrip().startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) < 3:
            # 也支持 | 分隔
            parts = line.split("|", 2)
        if len(parts) < 3:
            print(f"[warn] 跳过格式不合法行:{line[:80]!r}", file=sys.stderr)
            continue
        idx, start, text = parts[0].strip(), parts[1].strip(), parts[2].strip()
        try:
            segments.append(
                {
                    "index": int(idx),
                    "start_sec": float(start),
                    "text": text,
                }
            )
        except ValueError as e:
            print(f"[warn] 跳过数值解析失败行:{line[:80]!r} ({e})", file=sys.stderr)
    return segments


def estimate_duration_ms(mp3_bytes: bytes) -> int:
    """从 mp3 头粗估时长(用于 segments.json 元数据)。mp3sync 不可靠,
    实际值以 extra_info.audio_length 为准——如果是从 t2a_v2 直接拿到的 bytes,
    调用方应该额外保存 extra_info。这里给一个 0 占位,ffmpeg 拼轨时按 segments.start_sec
    对齐即可。"""
    return 0


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--segments", required=True, type=Path, help="voiceover.segments.tsv 路径")
    ap.add_argument("--out-dir", required=True, type=Path, help="输出目录(会建 chapter-NN.mp3)")
    ap.add_argument("--voice", default=DEFAULT_VOICE, help=f"voice_id(默认 {DEFAULT_VOICE})")
    ap.add_argument("--model", default=DEFAULT_MODEL, help=f"模型(默认 {DEFAULT_MODEL})")
    ap.add_argument("--speed", type=float, default=1.0, help="语速 0.5..2(默认 1.0)")
    ap.add_argument("--language-boost", default="Chinese", help="language_boost(默认 Chinese)")
    ap.add_argument("--endpoint", default=DEFAULT_ENDPOINT, help="API 端点")
    ap.add_argument("--dry-run", action="store_true", help="只打印计划,不调 API")
    args = ap.parse_args()

    if not args.segments.is_file():
        sys.exit(f"FATAL: 段表文件不存在:{args.segments}")

    segments = parse_segments(args.segments)
    if not segments:
        sys.exit("FATAL: 段表为空,检查格式(idx<TAB>start_sec<TAB>text)")

    args.out_dir.mkdir(parents=True, exist_ok=True)

    print(f"[plan] {len(segments)} 段, voice={args.voice}, model={args.model}, speed={args.speed}")
    total_chars = sum(len(s["text"]) for s in segments)
    print(f"[plan] 总字符数:{total_chars} (粗估费用按 ¥0.001/字符计)")

    if args.dry_run:
        for s in segments:
            print(f"  [{s['index']:02d}] t={s['start_sec']:.1f}s  {len(s['text'])} 字  {s['text'][:40]!r}...")
        return

    key = load_minimax_key()
    print(f"[key] loaded ({len(key)} chars)")

    meta = []
    for s in segments:
        out_path = args.out_dir / f"chapter-{s['index']:02d}.mp3"
        print(f"[{s['index']:02d}] t={s['start_sec']:.1f}s  → {out_path.name}  ({len(s['text'])} 字)")
        t0 = time.time()
        try:
            mp3 = tts_synthesize(
                text=s["text"],
                voice_id=args.voice,
                api_key=key,
                endpoint=args.endpoint,
                model=args.model,
                speed=args.speed,
                language_boost=args.language_boost,
            )
            out_path.write_bytes(mp3)
            dt = time.time() - t0
            print(f"       ok  {len(mp3):,}B  {dt:.2f}s")
            meta.append(
                {
                    **s,
                    "path": str(out_path),
                    "size_bytes": len(mp3),
                    "elapsed_sec": round(dt, 2),
                    "voice": args.voice,
                    "model": args.model,
                }
            )
        except Exception as e:
            print(f"       FAIL: {e}", file=sys.stderr)
            meta.append({**s, "error": str(e)})

    meta_path = args.out_dir / "segments.json"
    meta_path.write_text(json.dumps(meta, ensure_ascii=False, indent=2))
    print(f"\n[done] {len([m for m in meta if 'error' not in m])}/{len(meta)} 段成功,元数据: {meta_path}")
    print(f"[next] 用 ffmpeg 拼回主音轨,详见 SKILL.md '阶段 5:配音 + 字幕' 段")


if __name__ == "__main__":
    main()
