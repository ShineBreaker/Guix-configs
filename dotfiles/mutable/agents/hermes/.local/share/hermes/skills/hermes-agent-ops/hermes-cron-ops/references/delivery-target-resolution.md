# Cron 投递目标解析与多平台路由

适用：排查「job 投到了没想到的平台」、决定新 job 的 `deliver` 取值、或评估「统一只投一个平台」的结构性改法。

## 解析链路（读码结论）

`cron/scheduler_delivery.py`：

1. `_delivery_lane_value` 取 `deliver`；失败通知另走 `failure_deliver`，未设则跟随 `deliver`。
2. `_normalize_deliver_value` 归一化：None/空 → `local`；list/tuple 拍平成逗号串——手改 jobs.json 写成 `["telegram"]` 会得到字面量 `['telegram']` 而静默解析失败。
3. `deliver == "local"` → 无目标，输出仍落 `last_output`。
4. 逗号分段，每段进 `_resolve_single_delivery_target`：
   - `local` → 丢弃
   - `bot-chat[:profile]` → 本地 Bot Chat
   - `origin` → 有 origin 用 origin；**无 origin 则遍历 `_iter_home_target_platforms()`，取第一个 `_get_home_target_chat_id()` 非空的平台**
   - `platform:chat_id[:thread]` → 显式目标
   - 裸平台名 → 该平台 home channel（origin 同平台时优先 home，无 home 才回落 origin chat）
5. 按 `(platform, chat_id, thread_id)` 去重。

## origin fallback 的顺序陷阱

`_iter_home_target_platforms()` yield 的是 `_HOME_TARGET_ENV_VARS` 这个 dict 字面量的**声明顺序**（外加插件平台）：

```
matrix, telegram, discord, slack, signal, mattermost, sms, email,
dingtalk, feishu, wecom, weixin, bluebubbles, qqbot, whatsapp, whatsapp_cloud
```

**`weixin` 在 `qqbot` 之前。** 本机 `.env` 同时配了 `WEIXIN_HOME_CHANNEL` 与 `QQBOT_HOME_CHANNEL` 时，任何 `deliver=origin` 且 `origin=None` 的 job，第一个候选就是微信——选中顺序与用户偏好无关，是字典序撞运气。

home 解析优先级：env var（operator 覆盖优先）→ legacy env var → `config.yaml` 的 `platforms.<p>.home_channel`。

## 复现与验证（不改 jobs.json）

在 gateway 同环境跑解析函数，直接看每个 job 选中哪个平台：

```bash
cd "$HERMES_HOME" && ./hermes-agent/venv/bin/python - <<'PY'
import sys, json; sys.path.insert(0, 'hermes-agent')
from hermes_cli.env_loader import load_hermes_dotenv
load_hermes_dotenv(hermes_home='.')
from cron.scheduler_delivery import (
    _resolve_delivery_targets, _iter_home_target_platforms, _get_home_target_chat_id)
jobs = json.load(open('cron/jobs.json'))['jobs']
for j in jobs:
    t = _resolve_delivery_targets(j)
    print(j['id'], j.get('deliver'), '->',
          [(x['platform'], x['chat_id'], x['_resolved_from']) for x in t])
for p in _iter_home_target_platforms():
    cid = _get_home_target_chat_id(p)
    if cid: print('home:', p, '->', cid)
PY
```

把某个 job 的 `deliver` 临时改成 `origin` 再跑一遍，即可复现历史投递路径。注意 jobs.json 的结构是 `{"jobs": [...], "updated_at": ...}`，条目 key 是 `id` 不是 `job_id`（`cron list` 显示的 `job_id` 是投影字段）。

## 结构性改法（按代价排序）

| 方案 | 做法 | 代价 |
| --- | --- | --- |
| 每个 job 显式写 `deliver=qqbot` | 建 job 时写死，巡检时核对 | 零；不防新建 job 漏写 |
| 从 `.env` 删 `WEIXIN_HOME_CHANNEL` | 微信无 home channel，fallback 自然跳过 | 一行环境变量；微信端彻底收不到 cron |
| patch `scheduler_delivery.py` | 让 fallback 优先读偏好平台（如新增 `HERMES_HOME_PLATFORM`） | 上游代码，升级被覆盖，需提 issue |

用户口径是「全部投到 QQ」时，前两条组合足够。`.env` 是用户凭据文件，改前先说明再动。

## 相关

- QQ 侧配置与在线确认：`qqbot-delivery.md`
- `deliver=origin` 无 origin 且无任何 home channel 时按 local 处理（不报错）
