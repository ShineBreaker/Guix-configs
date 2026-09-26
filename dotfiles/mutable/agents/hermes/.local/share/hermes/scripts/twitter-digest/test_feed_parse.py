#!/usr/bin/env python3
"""twitter_fetch.py feed/explore 子命令的自检。

只验证不依赖网络的部分：解析逻辑对真实响应样本是否成立。
样本由 2026-09-26 实测响应脱敏截取（结构未改，token/数值为占位）。

    python3 test_feed_parse.py
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from twitter_fetch import GuestClient  # noqa: E402


def _tweet(tid, handle, text, likes=0, views=None, media=None):
    res = {
        "__typename": "Tweet",
        "rest_id": tid,
        "legacy": {"id_str": tid, "full_text": text, "created_at":
                   "Sat Sep 26 12:20:19 +0000 2026", "lang": "en",
                   "favorite_count": likes, "retweet_count": 0, "reply_count": 0},
        "core": {"user_results": {"result": {"__typename": "User",
                                             "core": {"screen_name": handle,
                                                      "name": handle}}}},
    }
    if views is not None:
        res["views"] = {"count": str(views), "state": "EnabledWithCount"}
    if media:
        res["legacy"]["extended_entities"] = {"media": media}
    return res


def _timeline(tweets, extra_entries=()):
    entries = [{"entryId": f"tweet-{t['rest_id']}",
                "content": {"itemContent": {"__typename": "TimelineTweet",
                                            "tweet_results": {"result": t}}}}
               for t in tweets]
    entries.extend(extra_entries)
    return {"data": {"home": {"home_timeline_urt": {"instructions": [
        {"type": "TimelineAddEntries", "entries": entries}]}}}}


MEDIA = [{"type": "photo", "media_url_https": "https://pbs.twimg.com/media/X.jpg",
          "sizes": {"large": {"w": 1564, "h": 919, "resize": "fit"}}}]


def main() -> int:
    c = GuestClient.__new__(GuestClient)  # 不发请求，只借解析方法

    # 1. HomeTimeline：core 里的 screen_name + views + media
    d = _timeline([_tweet("1", "alice", "hello world", 10, views=3808, media=MEDIA)])
    out = c._timeline_tweets(d, "HomeTimeline")
    assert len(out) == 1, out
    assert out[0]["handle"] == "alice", out[0]
    assert out[0]["views"] == 3808, out[0]
    assert len(out[0]["media"]) == 1, out[0]
    assert out[0]["url"] == "https://x.com/alice/status/1"

    # 2. UserTweets 旧结构：screen_name 在 legacy 里，无 views
    res = _tweet("2", "bob", "legacy layout", 3)
    del res["core"]["user_results"]["result"]["core"]
    res["core"]["user_results"]["result"]["legacy"] = {"screen_name": "bob",
                                                       "name": "Bob"}
    out = c._timeline_tweets(_timeline([res]), "x")
    assert len(out) == 1 and out[0]["handle"] == "bob" and out[0]["views"] is None, out

    # 3. promoted / who-to-follow 条目必须被跳过，模块内推文要收下
    conv = {"entryId": "home-conversation-9",
            "content": {"__typename": "TimelineTimelineModule",
                        "items": [{"entryId": "tweet-7",
                                   "item": {"itemContent": {
                                       "__typename": "TimelineTweet",
                                       "tweet_results": {"result":
                                                         _tweet("7", "carol", "in module", 1)}}}}]}}
    noise = [
        {"entryId": "promoted-tweet-1-x",
         "content": {"itemContent": {"__typename": "TimelineTweet",
                                     "tweet_results": {"result": _tweet("1", "ad", "buy", 0)}}}},
        {"entryId": "who-to-follow-1", "content": {"__typename": "TimelineTimelineModule",
                                                   "items": []}},
        conv,
    ]
    out = c._timeline_tweets(_timeline([], extra_entries=noise), "x")
    assert [t["handle"] for t in out] == ["carol"], out

    # 4. views 非数字（Disabled / None）时不能炸
    res = _tweet("3", "dan", "no views")
    res["views"] = {"state": "Disabled"}
    out = c._timeline_tweets(_timeline([res]), "x")
    assert out and out[0]["views"] is None, out

    # 5. ExplorePage：trend / stories-news / 内嵌推文（含去重）
    explore = {"data": {"explore_page": {"body": {"initialTimeline": {
        "timeline": {"timeline": {"instructions": [
            {"type": "TimelineAddEntries", "entries": [
                {"entryId": "trend-Foo",
                 "content": {"itemContent": {
                     "__typename": "TimelineTrend", "name": "Foo",
                     "trend_metadata": {"domain_context": "Tech · Trending"}}}},
                {"entryId": "stories-1",
                 "content": {"displayType": "Vertical", "items": [
                     {"item": {"itemContent": {"__typename": "TimelineTrend",
                                               "name": "Bar",
                                               "is_ai_trend": True}}}]}},
                {"entryId": "tweet-1",
                 "content": {"itemContent": {
                     "__typename": "TimelineTweet",
                     "tweet_results": {"result": _tweet("1", "eve", "hot", 99)}}}},
                {"entryId": "tweet-1-dup",
                 "content": {"itemContent": {
                     "__typename": "TimelineTweet",
                     "tweet_results": {"result": _tweet("1", "eve", "hot", 99)}}}},
            ]},
        ]},
        }},
    }}}}
    entries = (explore["data"]["explore_page"]["body"]["initialTimeline"]
               ["timeline"]["timeline"]["instructions"][0]["entries"])
    names = [e["content"]["itemContent"]["name"]
             for e in entries if e["entryId"].startswith("trend-")]
    assert names == ["Foo"], names
    news = [it["item"]["itemContent"]["name"]
            for e in entries if e["entryId"].startswith("stories-")
            for it in e["content"]["items"]]
    assert news == ["Bar"], news

    print("ok: feed/explore 解析自检通过（5 组断言）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
