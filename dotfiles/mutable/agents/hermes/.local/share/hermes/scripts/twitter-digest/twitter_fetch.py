#!/usr/bin/env python3
"""Twitter/X 推文抓取（guest 通道）。

复用 X 网页版内部 GraphQL 的公开 bearer + guest token：无需账号、无需 API key、
无需付费额度。只读公开推文，不登录、不碰私信。

关注清单：X 已无免登录的 following 列表接口（v1.1 friends/list 与 GraphQL
Following 在 guest 态均 404），故由脚本顶部 FOLLOWING 常量手动维护；
`sync-following` 子命令把它导出成 JSON 供人核对。

用法:
    twitter_fetch.py fetch --state-dir DIR [--handles a,b] [--since-days 2] [--count 40]
    twitter_fetch.py sync-following --state-dir DIR

产出:
    <state>/raw/YYYY-MM-DD.json   当日抓到的原始推文（时间窗内全量）
    <state>/seen_ids.json         已处理推文 id 集合（跨日去重，保留最近 2 万条）
    <state>/new/YYYY-MM-DD.json   去重后的新推文 —— 喂给 jev 的输入
    <state>/errors/YYYY-MM-DD.log 抓取失败明细（stdout 只有汇总）
"""
from __future__ import annotations

import argparse
import base64
import gzip
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path

# X 网页版公开 bearer（web client 常量，非用户凭据）
BEARER = ("AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs="
          "1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA")
API = "https://api.twitter.com"
UA = ("Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36")

# 手动维护的关注清单（screen_name，不带 @）
FOLLOWING = [
    "naval",
    "karpathy",
]

QID_USER_BY_SCREEN_NAME = "4S2ihIKfF3xhp-ENxvUAfQ"
QID_USER_TWEETS = "jeAA-59Y9FL7FmjgBNIVPw"      # 2026-09-22 从登录态 bundle 抓取
QID_FOLLOWING = "-Mn4uN7C-vxXBwUKtSwS6A"        # 同上

FEATURES = {
    "rweb_tipjar_consumption_enabled": True,
    "responsive_web_graphql_exclude_directive_enabled": True,
    "verified_phone_label_enabled": False,
    "creator_subscriptions_tweet_preview_api_enabled": True,
    "responsive_web_graphql_timeline_navigation_enabled": True,
    "responsive_web_graphql_skip_user_profile_image_extensions_enabled": False,
    "communities_web_enable_tweet_community_results_fetch": True,
    "c9s_tweet_anatomy_moderator_badge_enabled": True,
    "articles_preview_enabled": True,
    "responsive_web_edit_tweet_api_enabled": True,
    "graphql_is_translatable_rweb_tweet_is_translatable_enabled": True,
    "view_counts_everywhere_api_enabled": True,
    "longform_notetweets_consumption_enabled": True,
    "responsive_web_twitter_article_tweet_consumption_enabled": True,
    "tweet_awards_web_tipping_enabled": False,
    "creator_subscriptions_quote_tweet_preview_enabled": False,
    "freedom_of_speech_not_reach_fetch_enabled": True,
    "standardized_nudges_misinfo": True,
    "tweet_with_visibility_results_prefer_gql_limited_actions_policy_enabled": True,
    "rweb_video_timestamps_enabled": True,
    "longform_notetweets_rich_text_read_enabled": True,
    "longform_notetweets_inline_media_enabled": True,
    "responsive_web_enhance_cards_enabled": False,
}

SEEN_CAP = 20000


class XError(RuntimeError):
    """X 侧错误（HTTP 非 2xx / 结构不符合预期）。"""


class XRateLimited(XError):
    """429，带 X 侧限流重置时间戳（epoch 秒）。"""

    def __init__(self, reset_at: float | None, body: bytes):
        self.reset_at = reset_at
        super().__init__(f"HTTP 429: {body[:200]!r}")


def _get_json(url: str, headers: dict, retries: int = 3) -> dict:
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers=headers)
            with urllib.request.urlopen(req, timeout=30) as resp:
                raw = resp.read()
                if resp.headers.get("Content-Encoding") == "gzip":
                    raw = gzip.decompress(raw)
                return json.loads(raw)
        except urllib.error.HTTPError as e:
            body = e.read()
            # 429 不盲目退避，按 X 给的 reset 时间等（通常 60~900s）
            if e.code == 429:
                reset = e.headers.get("x-rate-limit-reset")
                raise XRateLimited(float(reset) if reset else None, body) from e
            if e.code in (500, 502, 503, 529) and attempt < retries - 1:
                time.sleep(5 * (2 ** attempt))
                continue
            raise XError(f"HTTP {e.code}: {body[:300]!r}") from e
        except (urllib.error.URLError, TimeoutError, OSError) as e:
            if attempt < retries - 1:
                time.sleep(5 * (2 ** attempt))
                continue
            raise XError(f"network: {e}") from e
    raise XError("unreachable after retries")


def _user_result(d: dict, what: str) -> dict:
    """从 GraphQL 响应里取 user.result。

    X 对不存在的账号返回 {"data": {"user": {}}}（无 result 键），
    直接下标访问会 KeyError 崩掉整个批跑 —— 账号级失败必须降级成
    单账号错误，不能让一个坏 handle 中断剩下 223 个。
    """
    user = (d.get("data") or {}).get("user") or {}
    result = user.get("result") or user
    if not result or result.get("__typename") == "UserUnavailable":
        raise XError(f"user unavailable: {what}")
    return result


class GuestClient:
    """guest token 客户端。token 约数小时过期，失效时自动重取一次重试。

    局限（2026-09-22 实测）：guest 态 UserTweets 只返回账号「精选/pinned」
    面板（高赞老帖，98 条封顶），不是最新时间线 —— 日报必须走 LoggedInClient。
    """

    def __init__(self) -> None:
        self._base = {
            "Authorization": f"Bearer {BEARER}",
            "User-Agent": UA,
            "Accept": "*/*",
            "x-twitter-active-user": "yes",
            "x-twitter-client-language": "en",
        }
        self._token: str | None = None

    def _activate(self) -> None:
        req = urllib.request.Request(
            f"{API}/1.1/guest/activate.json",
            data=b"", headers=self._base, method="POST")
        with urllib.request.urlopen(req, timeout=30) as resp:
            self._token = json.load(resp)["guest_token"]

    def get(self, url: str) -> dict:
        # 登录态：token 已由 __init__ 置为 ct0，直接用 cookie 头请求
        if self._token is None:
            self._activate()
        headers = ({**self._base, "x-guest-token": self._token}
                   if self._token != getattr(self, "_ct0", None)
                   else dict(self._base))
        try:
            return _get_json(url, headers)
        except XError:
            # guest token 过期 / 被踢：重取一次再试，仍失败则上抛
            if self._token == getattr(self, "_ct0", None):
                raise
            self._activate()
            headers = {**self._base, "x-guest-token": self._token}
            return _get_json(url, headers)

    def rest_id(self, screen_name: str) -> str:
        q = urllib.parse.urlencode({
            "variables": json.dumps({"screen_name": screen_name,
                                     "withHighlightedLabel": True}),
            "features": json.dumps({
                "hidden_profile_subscriptions_enabled": True,
                "responsive_web_graphql_exclude_directive_enabled": True,
            })})
        d = self.get(f"{API}/graphql/{QID_USER_BY_SCREEN_NAME}/UserByScreenName?{q}")
        user = _user_result(d, screen_name)
        return base64.b64decode(user["id"]).decode().rsplit(":", 1)[-1]

    def user_tweets(self, screen_name: str, count: int = 40) -> list[dict]:
        uid = self.rest_id(screen_name)
        q = urllib.parse.urlencode({
            "variables": json.dumps({
                "userId": uid, "count": count,
                "includePromotedContent": False,
                "withQuickPromoteEligibilityTweetFields": True,
                "withVoice": True}, separators=(",", ":")),
            "features": json.dumps(FEATURES),
            "fieldToggles": json.dumps({"withArticlePlainText": False}),
        })
        d = self.get(f"{API}/graphql/{QID_USER_TWEETS}/UserTweets?{q}")
        result = _user_result(d, screen_name)
        timeline = result.get("timeline") or {}
        out: list[dict] = []
        for ins in timeline.get("timeline", {}).get("instructions", []):
            if ins.get("type") != "TimelineAddEntries":
                continue
            for entry in ins.get("entries", []):
                item = entry.get("content", {}).get("itemContent") or {}
                if item.get("__typename") != "TimelineTweet":
                    continue
                res = item.get("tweet_results", {}).get("result", {})
                if res.get("__typename") not in ("Tweet", "TweetWithVisibilityResults"):
                    continue
                leg = res.get("legacy", {})
                user = res.get("core", {}).get("user_results", {}).get("result", {})
                uleg = user.get("legacy", {})
                text = leg.get("full_text") or ""
                tid = leg.get("id_str") or res.get("rest_id")
                if not text.strip() or not tid:
                    continue
                handle = uleg.get("screen_name") or screen_name
                out.append({
                    "id": tid,
                    "handle": handle,
                    "name": uleg.get("name") or handle,
                    "text": text,
                    "created_at": leg.get("created_at"),
                    "lang": leg.get("lang"),
                    "likes": leg.get("favorite_count", 0),
                    "retweets": leg.get("retweet_count", 0),
                    "replies": leg.get("reply_count", 0),
                    # 登录态 RT：legacy 带 retweeted_status_result 而不带
                    # retweeted_status_id_str；正文前缀仅作最后兜底
                    "is_retweet": ("retweeted_status_result" in leg
                                   or bool(leg.get("retweeted_status_id_str"))
                                   or text.startswith("RT @")),
                    "is_reply": bool(leg.get("in_reply_to_status_id_str")),
                    "url": f"https://x.com/{handle}/status/{tid}",
                })
        return out


class LoggedInClient(GuestClient):
    """登录态客户端：用浏览器导出的 auth_token + ct0 cookie 打同一套 GraphQL。

    cookie 来源（用户在浏览器登录 x.com 后，DevTools → Application → Cookies）：
        auth_token  长期会话令牌
        ct0         CSRF 令牌，同时作为 x-csrf-token 头

   凭据来源（按优先级，均为 tmpfs/加密态，绝不落仓库明文）:
        $XDG_RUNTIME_DIR/secrets-decrypted/twitter-x   `secrets decrypt twitter-x`
                                                    产出，age 密文在 Guix-configs 仓库
        <state>/cookies.json                          兜底：手动放的裸 JSON（0600）

    格式二者一致: {"auth_token": "...", "ct0": "..."}
    文件权限保持 0600；本脚本只读不写该文件。
    """

    @staticmethod
    def _load_creds(cookie_file: Path) -> dict:
        """优先读 secrets 解密产物（tmpfs），兜底读 cookie_file。"""
        secrets_plain = Path(os.environ.get("XDG_RUNTIME_DIR", "/run/user/1000")) \
            / "secrets-decrypted" / "twitter-x"
        if secrets_plain.exists():
            return json.loads(secrets_plain.read_text())
        if cookie_file.exists():
            return json.loads(cookie_file.read_text())
        raise XError(
            f"缺少登录凭据：既无 {secrets_plain} 也无 {cookie_file}。\n"
            "先 `secrets decrypt twitter-x`（密文在 Guix-configs 仓库），"
            "或按 cookie_file 路径放裸 JSON 并 chmod 600")

    def __init__(self, cookie_file: Path) -> None:
        super().__init__()
        creds = self._load_creds(cookie_file)
        auth, ct0 = creds.get("auth_token", ""), creds.get("ct0", "")
        if not auth or not ct0:
            raise XError(f"{cookie_file} 缺少 auth_token / ct0 字段")
        self._base = {
            "Authorization": f"Bearer {BEARER}",
            "User-Agent": UA,
            "Accept": "*/*",
            "x-twitter-active-user": "yes",
            "x-twitter-client-language": "en",
            "x-csrf-token": ct0,
            "x-twitter-auth-type": "OAuth2Session",
            "Cookie": f"auth_token={auth}; ct0={ct0}",
        }
        self._token = ct0  # 登录态复用 ct0 作为 csrf，无需 guest activate
        self._ct0 = ct0    # 标记登录态，get() 据此跳过 guest 头与重激活

    def _activate(self) -> None:  # guest activate 在登录态下不需要
        raise XError("登录态不应调用 guest activate")

    def following(self, screen_name: str, count: int = 200) -> list[str]:
        """抓账号的 following 列表，返回 screen_name 列表（自动翻页）。"""
        uid = self.rest_id(screen_name)
        out: list[str] = []
        cursor = None
        for _ in range(20):  # 上限 20 页 ≈ 4000 关注
            v: dict = {"userId": uid, "count": count, "includePromotedContent": False}
            if cursor:
                v["cursor"] = cursor
            q = urllib.parse.urlencode({
                "variables": json.dumps(v, separators=(",", ":")),
                "features": json.dumps({
                    "rweb_tipjar_consumption_enabled": True,
                    "responsive_web_graphql_exclude_directive_enabled": True,
                })})
            d = self.get(f"{API}/graphql/{QID_FOLLOWING}/Following?{q}")
            result = _user_result(d, screen_name)
            instructions = ((result.get("timeline") or {}).get("timeline") or {}
                            ).get("instructions", [])
            entries: list[dict] = []
            for ins in instructions:
                if ins.get("type") == "TimelineAddEntries":
                    entries += ins.get("entries", [])
            for e in entries:
                content = e.get("content") or {}
                # 外层 content 是 TimelineTimelineItem；用户条目看 itemContent
                item = content.get("itemContent") or {}
                if item.get("__typename") != "TimelineUser":
                    continue
                ur = item.get("user_results", {}).get("result", {})
                # Following 返回的新版 user 结构：screen_name 在 core 里，无 legacy
                core = ur.get("core") or {}
                name = core.get("screen_name")
                if name:
                    out.append(name)
            cursor = None
            for e in entries:
                # cursor 也是 TimelineAddEntries 里的一个 entry
                content = e.get("content") or {}
                if content.get("__typename") == "TimelineTimelineCursor" \
                        and content.get("cursorType") == "Bottom":
                    cursor = content.get("value")
                    break
            if not cursor:
                break
        return out


def parse_created_at(s: str | None) -> datetime | None:
    """X 的 'Wed Oct 10 20:19:24 +0000 2018' → aware datetime。"""
    if not s:
        return None
    try:
        return datetime.strptime(s, "%a %b %d %H:%M:%S %z %Y")
    except ValueError:
        return None


# 自己的 X handle（following 列表只能抓本人的）
SELF_HANDLE = "breaker_shine"


def load_following(state: Path) -> list[str]:
    """读 following.json；文件不存在时退回脚本顶部 FOLLOWING 常量。"""
    f = state / "following.json"
    if f.exists():
        names = [h.strip().lstrip("@") for h in json.loads(f.read_text()) if h.strip()]
        if names:
            return names
    return list(FOLLOWING)


def cookie_available(state: Path) -> bool:
    """secrets 解密产物或裸 cookie 文件任一存在即可。"""
    secrets_plain = Path(os.environ.get("XDG_RUNTIME_DIR", "/run/user/1000")) \
        / "secrets-decrypted" / "twitter-x"
    return secrets_plain.exists() or (state / "cookies.json").exists()


def cmd_fetch(args) -> int:
    state = Path(args.state_dir)
    for sub in ("raw", "new", "errors"):
        (state / sub).mkdir(parents=True, exist_ok=True)

    seen_path = state / "seen_ids.json"
    seen: set[str] = set(json.loads(seen_path.read_text())) if seen_path.exists() else set()

    handles = ([h.strip().lstrip("@") for h in args.handles.split(",") if h.strip()]
               if args.handles else load_following(state))
    if not handles:
        print("[error] 关注清单为空：先跑 sync-following 或用 --handles 指定",
              file=sys.stderr)
        return 1

    cutoff = datetime.now(timezone.utc) - timedelta(days=args.since_days)
    resumed = 0

    # 增量抓取：只碰 last_seen_handle 之后的账号，让限流中断后能从断点续跑
    progress = state / "progress.json"
    done: list[str] = []
    if args.resume and progress.exists():
        done = json.loads(progress.read_text()).get("done", [])
        if done:
            handles = [h for h in handles if h not in set(done)]
            resumed = len(done)
            print(f"[resume] 跳过已完成 {resumed} 个账号，剩 {len(handles)}")
    if not handles:
        print("所有账号均已抓取过（--resume）")
        return 0

    # 有 cookie 走登录态（真实时间线 + 关注列表），否则退回 guest（仅精选面板）
    cookie_file = Path(args.state_dir) / "cookies.json"
    if args.logged_in and cookie_available(state):
        client: GuestClient = LoggedInClient(Path(args.state_dir) / "cookies.json")
        mode = "logged-in"
    else:
        client = GuestClient()
        mode = "guest(仅精选面板，缺最新推文)" if args.logged_in else "guest"
    if args.logged_in and mode.startswith("guest"):
        print("[warn] --logged-in 已请求但缺少有效 cookies.json，退回 guest 模式",
              file=sys.stderr)

    collected: list[dict] = []
    err_path = state / "errors" / f"{datetime.now(timezone.utc).astimezone().strftime('%Y-%m-%d')}.log"

    def log_error(msg: str) -> None:
        """即时追加落盘：进程若在写盘前被杀，失败记录不随之消失。
        限流静默丢账号会让日报'正常地'缺内容，且无迹可查。"""
        stamp = datetime.now(timezone.utc).astimezone().strftime("%H:%M:%S")
        with err_path.open("a") as f:
            f.write(f"{stamp} {msg}\n")

    def save_progress(names: list[str]) -> None:
        if args.resume:
            progress.write_text(json.dumps({"done": names}, ensure_ascii=False))

    for handle in handles:
        try:
            tweets = client.user_tweets(handle, count=args.count)
        except XRateLimited as e:
            # 限流：睡到 X 给的重置时刻，再重试同一账号一次
            wait = (e.reset_at - time.time() + 5) if e.reset_at else 120
            if wait <= 0 or wait > args.max_wait:
                log_error(f"{handle}: 限流且重置时间超限 ({wait:.0f}s)")
                print(f"[warn] {handle}: 限流，等待 {wait:.0f}s 超过上限，跳过",
                      file=sys.stderr)
                done.append(handle)
                save_progress(done)
                continue
            print(f"[ratelimit] 睡 {wait:.0f}s 后重试 {handle}", file=sys.stderr)
            time.sleep(wait)
            try:
                tweets = client.user_tweets(handle, count=args.count)
            except XError as e2:
                log_error(f"{handle}: {e2}")
                print(f"[warn] {handle}: {e2}", file=sys.stderr)
                done.append(handle)
                save_progress(done)
                continue
        except XError as e:
            log_error(f"{handle}: {e}")
            print(f"[warn] {handle}: {e}", file=sys.stderr)
            done.append(handle)
            save_progress(done)
            continue
        for t in tweets:
            dt = parse_created_at(t["created_at"])
            if dt is None or dt < cutoff:
                continue
            t["fetched_at"] = datetime.now(timezone.utc).isoformat()
            collected.append(t)
        done.append(handle)
        save_progress(done)
        time.sleep(args.interval)  # 账号间隔，224 个 × 2s ≈ 7.5 分钟

    # ponytail: 抓完即清断点；中断时保留，靠 --resume 续跑
    if args.resume and progress.exists() and len(done) == resumed + len(handles):
        progress.unlink()

    # 跨夜/分批跑必须追加而非覆盖，否则后一批会把前一批的 raw/new 冲掉。
    # 同一 (id) 只保留首次出现的那份。
    today = datetime.now(timezone.utc).astimezone().strftime("%Y-%m-%d")
    raw_path = state / "raw" / f"{today}.json"
    prev_raw = json.loads(raw_path.read_text()) if raw_path.exists() else []
    merged: dict[str, dict] = {}
    for t in prev_raw + collected:
        merged.setdefault(t["id"], t)
    raw_all = sorted(merged.values(), key=lambda t: t["id"])
    raw_path.write_text(json.dumps(raw_all, ensure_ascii=False, indent=2))

    fresh = [t for t in raw_all if t["id"] not in seen]
    seen.update(t["id"] for t in raw_all)
    if len(seen) > SEEN_CAP:
        seen = set(sorted(seen)[-SEEN_CAP // 2:])
    seen_path.write_text(json.dumps(sorted(seen)))

    new_path = state / "new" / f"{today}.json"
    prev_new = json.loads(new_path.read_text()) if new_path.exists() else []
    by_id = {t["id"]: t for t in prev_new}
    for t in fresh:
        by_id.setdefault(t["id"], t)
    new_path.write_text(json.dumps(list(by_id.values()), ensure_ascii=False, indent=2))

    n_err = len(err_path.read_text().splitlines()) if err_path.exists() else 0
    print(f"mode={mode} handles={len(handles)} fetched={len(collected)} "
          f"new={len(fresh)} errlog_lines={n_err} state={state}")
    # 抓取阶段恒为 0：单账号失败不等于任务失败，缺数据由日报阶段呈现
    return 0


def cmd_sync_following(args) -> int:
    """登录态抓自己的 following 列表 → following.json。"""
    state = Path(args.state_dir)
    state.mkdir(parents=True, exist_ok=True)
    cookie_file = state / "cookies.json"
    if not cookie_available(state):
        print("[error] 缺少登录凭据：先 `secrets decrypt twitter-x`，"
              f"或放置 {cookie_file}（guest 态看不到关注列表）", file=sys.stderr)
        return 1
    try:
        client = LoggedInClient(cookie_file)
        names = client.following(SELF_HANDLE)
    except XError as e:
        print(f"[error] 抓取关注列表失败: {e}", file=sys.stderr)
        return 1
    if not names:
        print("[error] 关注列表为空（cookie 失效或接口变更）", file=sys.stderr)
        return 1
    # 保留旧文件便于比对新增/取关
    out = state / "following.json"
    if out.exists():
        old = set(json.loads(out.read_text()))
        print(f"新增 {len(set(names) - old)}，取关 {len(old - set(names))}")
    out.write_text(json.dumps(names, ensure_ascii=False, indent=2) + "\n")
    print(f"synced {len(names)} accounts -> {out}")
    return 0


def main(argv=None) -> int:
    p = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)

    f = sub.add_parser("fetch", help="抓取关注账号的时间窗内新推文")
    f.add_argument("--state-dir", required=True)
    f.add_argument("--handles", default="",
                   help="逗号分隔 handle；缺省用脚本顶部 FOLLOWING")
    f.add_argument("--since-days", type=int, default=2,
                   help="只保留最近 N 天的推文（默认 2，容忍一次漏跑）")
    f.add_argument("--count", type=int, default=40, help="每账号最多抓取条数")
    f.add_argument("--logged-in", action="store_true",
                   help="有 cookies.json 时走登录态（真实时间线）；缺省 guest")
    f.add_argument("--resume", action="store_true",
                   help="断点续跑：跳过 progress.json 里已抓完的账号")
    f.add_argument("--interval", type=float, default=2.0,
                   help="账号间隔秒数，默认 2（224 账号约 7.5 分钟）")
    f.add_argument("--max-wait", type=float, default=960.0,
                   help="单次限流最长等待秒数，超过则跳过该账号，默认 960")
    f.set_defaults(func=cmd_fetch)

    s = sub.add_parser("sync-following", help="导出当前关注清单 JSON")
    s.add_argument("--state-dir", required=True)
    s.set_defaults(func=cmd_sync_following)

    args = p.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
