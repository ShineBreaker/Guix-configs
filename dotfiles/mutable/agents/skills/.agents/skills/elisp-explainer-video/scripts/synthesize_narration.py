"""
解说稿 md → 7 章 mp3 + 总轨的批量 TTS 合成(2026-06-23 沉淀)。

输入:audio/narration_script.md(## Part N 段)
输出:audio/narration_chapter_NN.mp3 + audio/durations.json + audio/narration_full.mp3

调 MiniMax t2a_v2 同步语音合成。key 从 ~/.local/share/hermes/.env 的
MINIMAX_CN_API_KEY 读,不落地。
"""
import os
import re
import time
import json
import requests
import subprocess

# === 项目相关常量 ===============================================
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPT_PATH = os.path.join(ROOT, "audio", "narration_script.md")
AUDIO_DIR = os.path.join(ROOT, "audio")
DURATION_LOG = os.path.join(AUDIO_DIR, "durations.json")

# === TTS 参数(改这些换音色/语速/模型) =========================
VOICE = "Chinese (Mandarin)_Gentle_Senior"  # 温柔学姐,教程主推
MODEL = "speech-2.8-hd"
SPEED = 1.0
PITCH = 0  # -12..12


# === 加载 key(子进程不继承 env) ================================
def load_api_key():
    env_path = os.path.expanduser("~/.local/share/hermes/.env")
    with open(env_path) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                if k == "MINIMAX_CN_API_KEY":
                    return v
    raise RuntimeError("MINIMAX_CN_API_KEY not found in ~/.local/share/hermes/.env")


# === 解析 md → 章列表 =========================================
def parse_chapters(md: str):
    """
    按 '## Part N — 标题' 切分,每章正文取 '---' 上方的内容。
    返回:[(n, title, body_text), ...]
    """
    chapters = []
    pattern = re.compile(
        r"^## Part (\d+)\s*[—–-]\s*([^\n]+)\n(.*?)(?=^## Part|\Z)",
        re.MULTILINE | re.DOTALL,
    )
    for m in pattern.finditer(md):
        n = int(m.group(1))
        title = m.group(2).strip()
        body = m.group(3)
        # 去掉 '>' 引用行(整体说明)
        body = re.sub(r"^>.*\n", "", body, flags=re.MULTILINE)
        # 截到第一个 '---'
        body = body.split("---", 1)[0]
        # 清理 md 标记
        body = re.sub(r"^\*+ ", "", body, flags=re.MULTILINE)
        # 多空行合一
        body = re.sub(r"\n{2,}", "\n", body).strip()
        chapters.append((n, title, body))
    return chapters


# === 调 TTS ====================================================
def synth(text: str, out_path: str, key: str) -> int:
    """调一次 t2a_v2,写 hex mp3 到 out_path,返回毫秒时长。"""
    url = "https://api-bj.minimaxi.com/v1/t2a_v2"
    payload = {
        "model": MODEL,
        "text": text,
        "stream": False,
        "voice_setting": {"voice_id": VOICE, "speed": SPEED, "vol": 1.0, "pitch": PITCH},
        "audio_setting": {"sample_rate": 32000, "bitrate": 128000, "format": "mp3", "channel": 1},
        "language_boost": "Chinese",
        "output_format": "hex",
    }
    headers = {"Authorization": f"Bearer {key}", "Content-Type": "application/json"}
    r = requests.post(url, json=payload, headers=headers, timeout=120)
    r.raise_for_status()
    j = r.json()
    if j.get("base_resp", {}).get("status_code") != 0:
        raise RuntimeError(f"TTS API error: {j.get('base_resp')}")
    audio_bytes = bytes.fromhex(j["data"]["audio"])
    with open(out_path, "wb") as f:
        f.write(audio_bytes)
    return j["extra_info"]["audio_length"]


def probe_duration_ms(path: str) -> int:
    """ffprobe 拿精确时长(ms)。比 t2a_v2 返回的 audio_length 边界更准。"""
    out = subprocess.check_output(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "default=noprint_wrappers=1:nokey=1", path]
    ).decode().strip()
    return int(float(out) * 1000)


# === 主流程 ====================================================
def main():
    os.makedirs(AUDIO_DIR, exist_ok=True)

    with open(SCRIPT_PATH) as f:
        md = f.read()
    chapters = parse_chapters(md)
    print(f"parsed {len(chapters)} chapters")

    key = load_api_key()
    durations = {}
    for n, title, body in chapters:
        out = os.path.join(AUDIO_DIR, f"narration_chapter_{n:02d}.mp3")
        print(f"\n[synth] Part {n}: {title}  ({len(body)} chars)")
        t0 = time.time()
        ms = synth(body, out, key)
        ms_probe = probe_duration_ms(out)
        durations[n] = {"title": title, "chars": len(body),
                        "tts_length_ms": ms, "ffprobe_ms": ms_probe,
                        "out": out, "dt_s": time.time() - t0}
        print(f"  -> {ms_probe}ms ({ms_probe/1000:.1f}s),  {time.time()-t0:.2f}s wall")

    # 拼总轨
    concat_list = os.path.join(AUDIO_DIR, "concat_list.txt")
    with open(concat_list, "w") as f:
        for n in sorted(durations):
            f.write(f"file 'narration_chapter_{n:02d}.mp3'\n")
    full_out = os.path.join(AUDIO_DIR, "narration_full.mp3")
    subprocess.run(
        ["ffmpeg", "-y", "-f", "concat", "-safe", "0", "-i", concat_list,
         "-c", "copy", full_out],
        check=True, capture_output=True,
    )
    full_ms = probe_duration_ms(full_out)
    print(f"\n[concat] narration_full.mp3  {full_ms}ms ({full_ms/1000:.1f}s)")

    durations["__full__"] = {"total_ms": full_ms, "out": full_out}
    with open(DURATION_LOG, "w") as f:
        json.dump(durations, f, indent=2, ensure_ascii=False)
    print(f"\nlog: {DURATION_LOG}")


if __name__ == "__main__":
    main()
