"""
Subtitle timing without Whisper.

ffmpeg silencedetect → sentence-level phrases. Combine with a known script
(markdown) where sentences are separated by `<#X#>` pause markers. The
function reconciles the two and writes a usable SRT.

Usage:
    python silencedetect_phrases.py <chapter_mp3> <script_md_section_name>

Outputs SRT to stdout. Adjust min_d (silence threshold, seconds) per
chapter if reconciliation looks off.

Reconciliation rules (in priority order):
    1. phrases == sentences → zip directly
    2. phrases > sentences  → merge trailing phrase tail into last sentence
    3. phrases < sentences  → split longest phrases proportionally to char count
"""
import re
import subprocess
import sys
from pathlib import Path


def get_silences(path: str, min_d: float = 0.4) -> list[tuple[float, float]]:
    out = subprocess.run(
        [
            "ffmpeg", "-i", str(path),
            "-af", f"silencedetect=noise=-30dB:d={min_d}",
            "-f", "null", "-",
        ],
        capture_output=True, text=True, check=True,
    )
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


def to_sentence_phrases(
    silences: list[tuple[float, float]], total_dur: float
) -> list[tuple[float, float]]:
    phrases, prev = [], 0.0
    for ss, se in silences:
        if ss > prev:
            phrases.append((prev, ss))
        prev = se
    if prev < total_dur:
        phrases.append((prev, total_dur))
    return phrases


def probe_ms(path: str) -> float:
    out = subprocess.check_output(
        [
            "ffprobe", "-v", "error", "-show_entries", "format=duration",
            "-of", "default=noprint_wrappers=1:nokey=1", str(path),
        ]
    ).decode().strip()
    return float(out)


def parse_script(md: str, section: str) -> list[str]:
    """Extract sentences from a `## <section>` block. Sentences are
    separated by `<#X.X#>` markers."""
    pattern = re.compile(
        rf"^## {re.escape(section)}[^\n]*\n(.*?)(?=^## |\Z)",
        re.MULTILINE | re.DOTALL,
    )
    m = pattern.search(md)
    if not m:
        raise ValueError(f"section {section!r} not found in script")
    body = m.group(1)
    body = re.sub(r"^>.*\n", "", body, flags=re.MULTILINE)
    body = body.split("---", 1)[0].strip()
    body = re.sub(r"\([^)]*\d+s[^)]*\)", "", body)
    body = re.sub(r"\(含[^\)]*\)", "", body)
    sents = re.split(r"<#\d+\.\d+#>", body)
    sents = [s.strip() for s in sents if s.strip()]
    return sents


def reconcile(
    phrases: list[tuple[float, float]],
    sentences: list[str],
) -> list[tuple[float, float, str]]:
    n_t, n_p = len(sentences), len(phrases)
    if n_p == 0 or n_t == 0:
        return []
    if n_p == n_t:
        return [(s, e, t) for (s, e), t in zip(phrases, sentences)]
    if n_p > n_t:
        # Merge trailing tail into the last sentence
        keep = phrases[: n_t - 1]
        last = (phrases[n_t - 1][0], phrases[-1][1])
        return [(s, e, t) for (s, e), t in zip(keep + [last], sentences)]
    # n_p < n_t: split longest phrases proportionally to char count
    # Compute target duration per sentence from char count
    weights = [len(t) for t in sentences]
    total_w = sum(weights)
    total_dur = phrases[-1][1] - phrases[0][0]
    # Walk through phrases, allocate sentences whose char weight fits
    # within the phrase's duration (scaled by global char-per-second rate)
    rate = total_w / total_dur
    out = []
    cur_phrase_idx = 0
    cur_phrase_start = phrases[0][0]
    remaining_phrase_dur = phrases[0][1] - phrases[0][0]
    for sent, w in zip(sentences, weights):
        target = w / rate
        # If target fits in remaining phrase, use it; otherwise advance
        if target <= remaining_phrase_dur + 0.05:
            seg_end = cur_phrase_start + target
            out.append((cur_phrase_start, seg_end, sent))
            remaining_phrase_dur -= target
            cur_phrase_start = seg_end
        else:
            # Use the rest of the current phrase, then advance
            out.append((cur_phrase_start, phrases[cur_phrase_idx][1], sent))
            cur_phrase_idx += 1
            if cur_phrase_idx >= len(phrases):
                cur_phrase_start = phrases[-1][1]
                remaining_phrase_dur = 0
            else:
                cur_phrase_start = phrases[cur_phrase_idx][0]
                remaining_phrase_dur = (
                    phrases[cur_phrase_idx][1] - phrases[cur_phrase_idx][0]
                )
    return out


def fmt_t(t: float) -> str:
    h = int(t // 3600)
    m = int((t % 3600) // 60)
    s = t % 60
    return f"{h:02d}:{m:02d}:{s:06.3f}"


def main() -> None:
    if len(sys.argv) < 3:
        print(__doc__, file=sys.stderr)
        sys.exit(1)
    audio = sys.argv[1]
    script_md = sys.argv[2]
    section = sys.argv[3] if len(sys.argv) > 3 else None

    if section is None:
        # Auto-pick: read all section names from the md
        with open(script_md) as f:
            md = f.read()
        sections = re.findall(r"^## ([^\n]+)", md, re.MULTILINE)
        if len(sections) != 1:
            print("multiple sections, pick one:", sections, file=sys.stderr)
            sys.exit(1)
        section = sections[0]

    with open(script_md) as f:
        md = f.read()
    sentences = parse_script(md, section)
    total = probe_ms(audio)
    silences = get_silences(audio)
    phrases = to_sentence_phrases(silences, total)
    aligned = reconcile(phrases, sentences)
    # Clean text and emit SRT
    for i, (s, e, text) in enumerate(aligned, 1):
        text = re.sub(r"[\*\`~#]", "", text)
        text = re.sub(r"\s+", " ", text).strip()
        if not text:
            continue
        print(f"{i}\n{fmt_t(s)} --> {fmt_t(e)}\n{text}\n")


if __name__ == "__main__":
    main()
