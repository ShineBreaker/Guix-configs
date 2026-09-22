#!/usr/bin/env bash
# 夜间抓取一批关注账号（cron 每次调用跑一批，靠 progress.json 跨次续跑）。
#
# 为什么分批：224 个账号 × 2s 间隔约 8 分钟本身可接受，但 X 侧限流不可预测，
# 单次 cron 只有 3 分钟硬上限。故把「抓一整轮」拆成多次 cron tick：
#   每 tick 抓 BATCH_SIZE 个账号，progress.json 记录断点，
#   抓完一轮自动清断点，下一轮从头开始。
#
# 依赖：secrets decrypt twitter-x 已由 cron prompt 前置步骤产出明文。
# 输出：stdout 汇总行，供 agent 判断进度。

set -euo pipefail

STATE="${TWITTER_DIGEST_STATE:-$HOME/.local/share/hermes/state/twitter-digest}"
SCRIPTS="$HOME/.local/share/hermes/scripts/twitter-digest"
BATCH_SIZE="${TWITTER_DIGEST_BATCH:-25}"

FOLLOWING="$STATE/following.json"
[[ -f "$FOLLOWING" ]] || { echo "SKIP: 无 $FOLLOWING，先跑 sync-following"; exit 0; }

# 从断点算出本批该抓哪些账号
python3 - "$STATE" "$BATCH_SIZE" <<'PY' > /tmp/twitter-batch.$$
import json, sys
from pathlib import Path
state, batch = Path(sys.argv[1]), int(sys.argv[2])
names = json.loads((state / "following.json").read_text())
prog = state / "progress.json"
done = json.loads(prog.read_text())["done"] if prog.exists() else []
todo = [n for n in names if n not in set(done)]
print(json.dumps(todo[:batch]))
PY

BATCH=$(cat /tmp/twitter-batch.$$); rm -f /tmp/twitter-batch.$$
[[ "$BATCH" == "[]" ]] && { echo "一轮已抓完，无待抓账号"; exit 0; }

python3 "$SCRIPTS/twitter_fetch.py" fetch \
  --state-dir "$STATE" \
  --handles "$(python3 -c "import json,sys;print(','.join(json.loads(sys.argv[1])))" "$BATCH")" \
  --since-days 2 --count 20 --logged-in --resume --interval 2
