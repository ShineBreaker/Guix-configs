#!/usr/bin/env bash
# anim-capture.sh — record a LIVE-session region while a trigger runs, then
# extract timestamped frames. For sub-300ms animation verification (see
# references/headless-verification.md §4.8).
#
# Usage:
#   anim-capture.sh <outdir> <region "x,y WxH"> <settle_s> <tail_s> -- <trigger...>
#
# Region coordinates are the LIVE compositor's LOGICAL pixels (derive the
# nested window's rectangle from a get_desktop_state capture; physical =
# logical x scale). Requires wf-recorder + ffmpeg on PATH — wrap the call:
#   guix shell wf-recorder ffmpeg -- anim-capture.sh ...
#
# Example:
#   anim-capture.sh /tmp/frames/osd "274,12 1208x1073" 1.5 2.0 -- \
#     bash -c 'qs volume increase'
set -uo pipefail
OUT="$1"; REGION="$2"; SETTLE="$3"; TAIL="$4"; shift 4
[ "${1:-}" = "--" ] && shift
mkdir -p "$OUT"

wf-recorder -y -c libx264 -g "$REGION" -f "$OUT/rec.mp4" &
REC=$!
sleep "$SETTLE"
"$@"
sleep "$TAIL"
kill -INT "$REC" 2>/dev/null
wait "$REC" 2>/dev/null
sleep 0.5

ffmpeg -v error -y -i "$OUT/rec.mp4" -vsync 0 "$OUT/f-%03d.png" 2>/dev/null
ffprobe -v error -select_streams v -show_entries frame=pts_time -of csv=p=0 \
  "$OUT/rec.mp4" > "$OUT/pts.txt"
echo "frames: $(ls "$OUT" | grep -c '^f-') -> $OUT"
