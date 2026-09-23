#!/usr/bin/env python3
"""把 picked 推文渲染成一张竖向长图（QQ 可读）。

用法:
    digest_render.py render --state-dir DIR [--date YYYY-MM-DD]
                            [--variant A|B|C] [--top N] [--out PATH]

输入: <state>/picked/YYYY-MM-DD.json（jev_score.py 产出）
      <state>/translated/YYYY-MM-DD.json（可选，LLM 产出的中文摘要）
输出: PNG 长图路径（打印到 stdout）

设计约束:
- QQ 无法渲染 markdown，交付物必须是图片
- 图内只放消息内容；执行说明走另一条文字消息
- 图片从网络下载到 state/cache/media，失败则降级为无图卡片
"""
from __future__ import annotations

import argparse
import base64
import html
import json
import os
import re
import subprocess
import sys
import urllib.request
from datetime import datetime
from pathlib import Path

WIDTH = 1080
PAD = 56
CARD_PAD = 32
RADIUS = 20

VARIANTS = {
    "A": {
        "name": "暗色·墨蓝",
        "bg": "#111418", "card": "#1b2027", "border": "#2a313b",
        "title": "#f0f3f7", "body": "#c8cfd8", "muted": "#7d8794",
        "accent": "#6ea8fe", "tag": "#243244", "tagtext": "#9dc2ff",
        "heat": "#f0883e", "quote": "#2a313b",
    },
    "B": {
        "name": "纸感·暖白",
        "bg": "#f5f4ed", "card": "#ffffff", "border": "#e3e0d5",
        "title": "#1B365D", "body": "#3a3f47", "muted": "#8b8578",
        "accent": "#1B365D", "tag": "#eceadf", "tagtext": "#1B365D",
        "heat": "#b3541e", "quote": "#eceadf",
    },
    "C": {
        "name": "冷调·浅灰",
        "bg": "#f7f8fa", "card": "#ffffff", "border": "#e4e7ec",
        "title": "#101828", "body": "#344054", "muted": "#98a2b3",
        "accent": "#1570ef", "tag": "#eff8ff", "tagtext": "#1570ef",
        "heat": "#dc6803", "quote": "#f2f4f7",
    },
    # D 版：kami 设计系统。暖纸底 + 墨蓝单 accent + 衬线标题/无衬线正文。
    # 本机无衬线中文字体（fc-list 只有 Sarasa 黑体族），标题衬线走
    # fontconfig fallback 到楷/宋，没有就退回黑体，靠字重和字号拉层级。
    "D": {
        "name": "纸墨·衬线",
        "bg": "#f5f4ed", "card": "#faf9f5", "border": "#e8e6dc",
        "title": "#1B365D", "body": "#3d3d3a", "muted": "#6b6a64",
        "accent": "#1B365D", "tag": "#E4ECF5", "tagtext": "#1B365D",
        "heat": "#8b4513", "quote": "#e8e6dc",
    },
}

# D 版专用字体栈：标题衬线（CJK fallback 到宋/楷/黑）、正文无衬线
FONT_SERIF = ('"Source Han Serif SC","Noto Serif CJK SC","Noto Serif SC",'
              '"Songti SC","STSong","Sarasa Fixed Slab SC",'
              '"更纱黑体 Slab SC",Georgia,serif')
FONT_SANS = ('"Sarasa Gothic SC","Source Han Sans SC","Noto Sans CJK SC",'
             '"Sarasa UI SC","PingFang SC","Microsoft YaHei",'
             '-apple-system,sans-serif')

# 模板用 @KEY@ 占位，避免 f-string 与 CSS 大括号打架
TEMPLATE = """<!DOCTYPE html>
<html lang="zh"><head><meta charset="utf-8"><style>
*{box-sizing:border-box;margin:0;padding:0}
body{width:@WIDTH@px;background:@bg@;font-family:@BODYFONT@;
  padding:44px @PAD@px 56px;color:@body@;-webkit-font-smoothing:antialiased}
.masthead{display:flex;align-items:baseline;gap:14px}
.masthead h1{font-size:44px;color:@title@;letter-spacing:1px;
  font-family:@SERIF@;font-weight:500}
.masthead .date{font-size:20px;color:@muted@;margin-left:auto}
.rule{height:3px;background:@accent@;width:64px;margin:14px 0 8px}
.sub{font-size:19px;color:@muted@;margin-bottom:34px}
.card{background:@card@;border:1px solid @border@;border-radius:@RADIUS@px;
  padding:@CARD_PAD@px;margin-bottom:26px}
header{display:flex;align-items:center;gap:12px;margin-bottom:14px}
.idx{font-size:22px;color:@muted@;font-family:@SERIF@;font-weight:500}
.who{display:flex;flex-direction:column;line-height:1.25}
.handle{font-size:22px;color:@title@;font-weight:500}
.name{font-size:16px;color:@muted@}
.time{margin-left:auto;font-size:16px;color:@muted@}
h2{font-size:27px;color:@title@;line-height:1.38;margin-bottom:10px;
  font-weight:500;font-family:@SERIF@}
.summary{font-size:21px;line-height:1.6;color:@body@}
.media{position:relative;margin-top:16px;border-radius:14px;overflow:hidden;
  background:@quote@}
.media img{display:block;width:100%}
.vbadge{position:absolute;left:16px;bottom:14px;background:rgba(0,0,0,.72);
  color:#fff;font-size:15px;padding:4px 12px;border-radius:20px}
footer{display:flex;align-items:center;gap:10px;margin-top:16px;font-size:17px;
  color:@muted@}
.spacer{flex:1}
.tag{background:@tag@;color:@tagtext@;font-size:15px;padding:3px 10px;
  border-radius:6px}
.heat{color:@heat@}
.sig{color:@muted@;font-size:15px}
.colophon{margin-top:34px;padding-top:20px;border-top:1px solid @border@;
  font-size:16px;color:@muted@;display:flex;justify-content:space-between}
</style></head><body>
<div class="masthead"><h1>X 每日摘要</h1><span class="date">@DATE@</span></div>
<div class="rule"></div>
<div class="sub">@SUBHEAD@</div>
@CARDS@
<div class="colophon"><span>由 jev 价值筛选</span><span>X · Following Digest</span></div>
</body></html>"""

CARD_TPL = """<article class="card">
  <header><span class="idx">@IDX@</span>
    <div class="who"><span class="handle">@HANDLE@</span>
      <span class="name">@NAME@</span></div>
    <span class="time">@TIME@</span></header>
  <h2>@TITLE@</h2>
  <p class="summary">@SUMMARY@</p>
  @MEDIA@
  <footer>@RT@<span class="spacer"></span>@HEAT@
    <span class="sig">signal @SIG@</span></footer>
</article>"""


def esc(s) -> str:
    # 上游文本可能已含 HTML 实体（Twitter 返回 &amp;），先反转义再转义，
    # 否则渲染出 &amp;amp;
    raw = str(s if s is not None else "")
    return html.escape(html.unescape(raw), quote=True)


def fmt_num(n) -> str:
    try:
        n = int(n)
    except (TypeError, ValueError):
        return "0"
    if n >= 10000:
        return f"{n / 10000:.1f}w"
    if n >= 1000:
        return f"{n / 1000:.1f}k"
    return str(n)


def short_date(s: str) -> str:
    if not s:
        return ""
    try:
        dt = datetime.strptime(s, "%a %b %d %H:%M:%S %z %Y")
    except ValueError:
        return str(s)[:12]
    return dt.astimezone().strftime("%m-%d %H:%M")


def load_translated(state: Path, date: str) -> dict:
    p = state / "translated" / f"{date}.json"
    if not p.exists():
        return {}
    try:
        return json.loads(p.read_text())
    except (ValueError, OSError):
        return {}


def fetch_image(state: Path, url: str, timeout: int = 15) -> str | None:
    """下载图片到本地缓存，返回 data URI；失败 None（降级无图）。"""
    if not url:
        return None
    d = state / "cache" / "media"
    d.mkdir(parents=True, exist_ok=True)
    stem = (url.rsplit("/", 1)[-1].split("?")[0] or "img")
    h = base64.urlsafe_b64encode(url.encode()).decode()[:10]
    p = d / f"{stem.rsplit('.', 1)[0][:40]}-{h}.jpg"
    if not p.exists():
        try:
            req = urllib.request.Request(
                url, headers={"User-Agent": "Mozilla/5.0"})
            with urllib.request.urlopen(req, timeout=timeout) as r:
                p.write_bytes(r.read())
        except Exception:
            return None
    if not p.exists() or p.stat().st_size < 512:
        return None
    return "data:image/jpeg;base64," + base64.b64encode(p.read_bytes()).decode()


def img_style(m: dict) -> str:
    w, h = m.get("w") or 0, m.get("h") or 0
    if w and h:
        ratio = w / h
        if ratio > 1.25:
            return "object-fit:cover;height:300px"
        if ratio < 0.85:
            return "object-fit:cover;max-height:380px"
    return "object-fit:cover;max-height:320px"


def build_cards(tweets: list[dict], state: Path, translated: dict) -> str:
    out = []
    for i, t in enumerate(tweets, 1):
        tr = translated.get(str(t.get("id"))) or {}
        text = t.get("text") or ""
        title = tr.get("title") or (text[:42] + ("…" if len(text) > 42 else ""))
        summary = tr.get("summary") or text

        media_html = ""
        for m in (t.get("media") or [])[:1]:
            uri = fetch_image(state, m.get("url") or "")
            if uri:
                badge = ('<span class="vbadge">▶ 视频</span>'
                         if m.get("type") == "video" else "")
                media_html = (f'<div class="media"><img src="{uri}" alt="" '
                              f'style="{img_style(m)}">{badge}</div>')

        heat = ""
        if t.get("likes"):
            heat += f'<span class="heat">♥ {fmt_num(t["likes"])}</span>'
        if t.get("retweets"):
            heat += f'<span class="heat">↻ {fmt_num(t["retweets"])}</span>'

        c = CARD_TPL
        for k, v in {
            "IDX": f"{i:02d}",
            "HANDLE": "@" + esc(t.get("handle")),
            "NAME": esc(t.get("name") or ""),
            "TIME": esc(short_date(t.get("created_at"))),
            "TITLE": esc(title),
            "SUMMARY": esc(summary),
            "MEDIA": media_html,
            "RT": '<span class="tag">转发</span>' if t.get("is_retweet") else "",
            "HEAT": heat,
            "SIG": esc(t.get("composite", "")),
        }.items():
            c = c.replace(f"@{k}@", v)
        out.append(c)
    return "\n".join(out)


def render_html(tweets: list[dict], date: str, variant: str,
                translated: dict, state: Path) -> str:
    c = VARIANTS[variant]
    cards = build_cards(tweets, state, translated)
    vals = {
        "WIDTH": str(WIDTH), "PAD": str(PAD), "CARD_PAD": str(CARD_PAD),
        "RADIUS": str(RADIUS), "DATE": esc(date),
        "SUBHEAD": f"关注账号 · {len(tweets)} 条精选 · 按相关度排序",
        "CARDS": cards,
    }
    # 配色键同时注册大写与小写两种形式：模板里两种都用了
    for k, v in c.items():
        vals[k.upper()] = str(v)
        vals[k.lower()] = str(v)
    if variant == "D":
        # kami 规范：衬线标题（500 字重）+ 无衬线正文，中文正文 0.3pt 字距
        vals["BODYFONT"] = (f"{FONT_SANS};letter-spacing:.3px;"
                            f"line-height:1.55")
        vals["SERIF"] = FONT_SERIF
    else:
        vals["BODYFONT"] = "sans-serif"
        vals["SERIF"] = "serif"
    out = TEMPLATE
    for k, v in vals.items():
        out = out.replace(f"@{k}@", v)
    # 残留占位符一律清空，避免样式里漏出 @XXX@
    return re.sub(r"@[A-Z_]+@", "", out)


def find_chromium() -> Path | None:
    cands = sorted(Path("/gnu/store").glob("*/bin/chromium"))
    return cands[0] if cands else None


def fontconfig_for_serif() -> dict | None:
    """把 store 里的思源宋体 + home profile 的 emoji 字体喂给 chromium。

    两者都不在 fontconfig 默认扫描路径（store 路径、~/.guix-home/profile），
    所以 chromium 渲染时衬线回退黑体、emoji 变豆腐块。生成一份临时
    fonts.conf 显式 include，随 FONTCONFIG_FILE 传给子进程。
    """
    extra = sorted(Path("/gnu/store").glob(
        "*-font-adobe-source-han-serif-*/share/fonts"))
    # home profile 的字体是软链进 store 的，直接扫 profile 目录
    for prof in (Path.home() / ".guix-home/profile/share/fonts",
                 Path.home() / ".guix-profile/share/fonts"):
        if prof.is_dir():
            extra.append(prof)
    if not extra:
        return None
    dirs = "".join(f"  <dir>{d}</dir>\n" for d in extra)
    conf = Path("/tmp/digest-render/fonts-serif.conf")
    conf.parent.mkdir(parents=True, exist_ok=True)
    cache = Path("/tmp/fontconfig-serif")
    cache.mkdir(parents=True, exist_ok=True)
    conf.write_text(
        '<?xml version="1.0"?>\n'
        '<!DOCTYPE fontconfig SYSTEM "fonts.dtd">\n'
        '<fontconfig>\n'
        f"{dirs}"
        '  <include ignore_missing="yes">/etc/fonts/fonts.conf</include>\n'
        f'  <cachedir>{cache}</cachedir>\n'
        '</fontconfig>\n', encoding="utf-8")
    return {"FONTCONFIG_FILE": str(conf)}


def html_to_png(html_path: Path, png_path: Path, height: int = 120000) -> bool:
    chrome = find_chromium()
    if chrome is None:
        print("[error] 找不到 chromium", file=sys.stderr)
        return False
    env = {**os.environ, **(fontconfig_for_serif() or {})}
    r = subprocess.run(
        [str(chrome), "--headless=new", "--no-sandbox", "--disable-gpu",
         "--hide-scrollbars", f"--screenshot={png_path}",
         f"--window-size={WIDTH},{height}", f"file://{html_path}"],
        capture_output=True, timeout=240, env=env)
    ok = png_path.exists() and png_path.stat().st_size > 1000
    if not ok:
        print(f"[error] 截图失败: {r.stderr.decode()[:300]}", file=sys.stderr)
    return ok


def trim_bottom(png_path: Path) -> None:
    """裁掉底部空白：从下往上找第一行非背景像素。"""
    from PIL import Image
    im = Image.open(png_path).convert("RGB")
    w, h = im.size
    bg = im.getpixel((4, 4))
    px = im.load()
    last = h - 1
    while last > 0:
        if any(sum(abs(px[x, last][i] - bg[i]) for i in range(3)) > 12
               for x in range(0, w, 7)):
            break
        last -= 1
    if last < h - 1:
        im.crop((0, 0, w, min(last + 60, h))).save(png_path)


def cmd_render(args) -> int:
    state = Path(args.state_dir)
    date = args.date or datetime.now().astimezone().strftime("%Y-%m-%d")
    picked_file = state / "picked" / f"{date}.json"
    if not picked_file.exists():
        print(f"[error] 缺少 {picked_file}；先跑 fetch 与 jev_score",
              file=sys.stderr)
        return 1

    raw = json.loads(picked_file.read_text())
    tweets = raw["tweets"] if isinstance(raw, dict) else raw
    tweets = tweets[:args.top]
    if not tweets:
        print(f"[error] {date} 无通过筛选的推文", file=sys.stderr)
        return 1
    if args.variant not in VARIANTS:
        print(f"[error] variant 只能是 {sorted(VARIANTS)}", file=sys.stderr)
        return 1

    translated = load_translated(state, date)
    html_text = render_html(tweets, date, args.variant, translated, state)
    return emit(args, html_text, f"digest-{args.variant}")


def emit(args, html_text: str, stem: str) -> int:
    """写 HTML → 截图 → 裁底，打印成品路径。"""
    work = Path("/tmp/digest-render")
    work.mkdir(parents=True, exist_ok=True)
    html_path = work / f"{stem}.html"
    html_path.write_text(html_text, encoding="utf-8")

    out = Path(args.out) if args.out else work / f"{stem}.png"
    if not html_to_png(html_path, out):
        return 1
    trim_bottom(out)

    from PIL import Image
    im = Image.open(out)
    print(f"{out} {im.size[0]}x{im.size[1]}")
    return 0


# ---------- md 子命令：渲染已加工的中文日报 ----------

MD_TEMPLATE = """<!DOCTYPE html>
<html lang="zh"><head><meta charset="utf-8"><style>
*{box-sizing:border-box;margin:0;padding:0}
body{width:@WIDTH@px;background:@bg@;font-family:@BODYFONT@;
  padding:52px @PAD@px 60px;color:@body@;-webkit-font-smoothing:antialiased}
.masthead{display:flex;align-items:baseline;gap:14px}
.masthead h1{font-size:44px;color:@title@;letter-spacing:1px;
  font-family:@SERIF@;font-weight:500}
.masthead .date{font-size:20px;color:@muted@;margin-left:auto}
.rule{height:3px;background:@accent@;width:64px;margin:14px 0 10px}
.lede{font-size:19px;color:@muted@;margin-bottom:38px}
section{margin-bottom:34px}
h2{font-size:26px;color:@title@;line-height:1.25;margin-bottom:16px;
  font-weight:500;font-family:@SERIF@;
  padding-left:14px;border-left:3px solid @accent@}
ol.headlines{list-style:none;counter-reset:hl}
ol.headlines li{counter-increment:hl;position:relative;
  padding-left:42px;margin-bottom:13px;font-size:21px;line-height:1.5}
ol.headlines li::before{content:counter(hl,decimal-leading-zero);
  position:absolute;left:0;top:1px;font-family:@SERIF@;font-size:19px;
  color:@accent@;font-weight:500}
p.item{font-size:20px;line-height:1.62;margin-bottom:16px;color:@body@}
p.item code{font-family:ui-monospace,Menlo,monospace;font-size:18px;
  background:@quote@;padding:1px 5px;border-radius:3px}
/* 卡片：靠 ivory 填充从暖纸底上浮起，不加闭合描边（kami 规范） */
article.card{position:relative;background:@card@;border-radius:6px;
  padding:22px 24px 24px;margin-bottom:16px}
article.card:last-child{margin-bottom:0}
.cnum{display:block;font-family:@SERIF@;font-size:17px;font-weight:500;
  color:@muted@;margin-bottom:8px;letter-spacing:1px}
article.card .item{margin:0}
figure.fig{position:relative;margin:16px 0 0;border-radius:6px;
  overflow:hidden;background:@quote@}
figure.fig img{display:block;width:100%}
.vbadge{position:absolute;left:14px;bottom:12px;background:rgba(0,0,0,.72);
  color:#fff;font-size:15px;padding:4px 12px;border-radius:20px}
.colophon{margin-top:40px;padding-top:20px;border-top:1px solid @border@;
  font-size:16px;color:@muted@;display:flex;justify-content:space-between}
</style></head><body>
<div class="masthead"><h1>@PAGETITLE@</h1><span class="date">@DATE@</span></div>
<div class="rule"></div>
<div class="lede">@LEDE@</div>
@CONTENT@
<div class="colophon"><span>jev 价值筛选 · 中文摘要</span>
  <span>@COLOPHON@</span></div>
</body></html>"""


def _inline(s: str) -> str:
    """行内 markdown：`code` 与 **bold**。先反转义避免双重转义。"""
    s = esc(html.unescape(s))
    s = re.sub(r"`([^`]+)`", r"<code>\1</code>", s)
    s = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", s)
    return s


def render_item(text: str, state: Path, mmap: dict[int, dict],
                idx: int = 0) -> str:
    """渲染一条正文条目为独立卡片，抽出 ![imgN] 换成下载好的图。

    卡片式排版：序号 + 正文 + 图，一次一张。下载失败的编号直接丢掉，
    不留空框。
    """
    figs = []
    for n in re.findall(r"!\[img(\d+)\]", text):
        m = mmap.get(int(n))
        if not m:
            continue
        uri = fetch_image(state, m.get("url") or "")
        if uri:
            badge = ('<span class="vbadge">▶ 视频</span>'
                     if m.get("type") == "video" else "")
            figs.append(f'<figure class="fig"><img src="{uri}" alt="" '
                        f'style="{img_style(m)}">{badge}</figure>')
    body = _inline(re.sub(r"!\[img\d+\]", "", text).strip())
    num = (f'<span class="cnum">{idx:02d}</span>' if idx else "")
    return (f'<article class="card">{num}'
            f'<p class="item">{body}</p>{"".join(figs)}</article>')


def media_map(state: Path, date: str, top: int) -> tuple[dict[int, dict], int]:
    """按 digest_build.py 的同一规则重建 {编号: media dict}。

    两边都必须按 picked 顺序、URL 去重地编号，LLM 写的 ![imgN] 才对得上。
    返回 (映射, 参与编号的推文数)。
    """
    f = state / "picked" / f"{date}.json"
    if not f.exists():
        return {}, 0
    try:
        raw = json.loads(f.read_text())
        tweets = raw["tweets"] if isinstance(raw, dict) else raw
    except (ValueError, OSError):
        return {}, 0
    tweets = tweets[:top]
    index: dict[str, int] = {}
    for t in tweets:
        for m in (t.get("media") or []):
            u = m.get("url")
            if u and u not in index:
                index[u] = len(index) + 1
    url2media = {m["url"]: m for t in tweets for m in (t.get("media") or [])}
    return ({n: url2media[u] for u, n in index.items() if u in url2media},
            len(tweets))


def parse_digest_md(text: str) -> tuple[str, list[tuple[str, list[str]]]]:
    """把日报 markdown 拆成 (标题, [(组名, [条目])])。

    兼容两种条目：要闻的 `1. xxx` 有序列表，和分组的裸段落行。
    cron 输出文件头部是 job prompt 与执行说明，正文从 `## Response`
    小节开始，`---` 分隔线之后是执行说明，一律排除。
    """
    # cron 输出格式固定：正文在 "## Response" 之后
    m = re.search(r"^## Response\s*$", text, re.M)
    if m:
        text = text[m.end():]

    title = "X 关注账号日报"
    groups: list[tuple[str, list[str]]] = []
    cur_name, cur_items = "", []

    def flush():
        nonlocal cur_name, cur_items
        if cur_items:
            groups.append((cur_name, cur_items))
        cur_name, cur_items = "", []

    for line in text.splitlines():
        s = line.strip()
        if not s:
            continue
        if s == "---":
            break  # 分隔线之后是执行说明，不属于正文
        if s.startswith("# ") and not s.startswith("## "):
            title = s[2:].strip()
            continue
        if s.startswith("## "):
            flush()
            cur_name = s[3:].strip()
            continue
        m = re.match(r"^(\d+)[.、]\s*(.+)$", s)
        if m and cur_name == "要闻":
            cur_items.append(m.group(2).strip())
        elif s.startswith((">", "-", "*")):
            cur_items.append(s.lstrip(">*- ").strip())
        elif not s.startswith("#"):
            cur_items.append(s)
    flush()
    # 无名组是 ## Response 与 # 标题之间的过渡句，不是日报内容
    return title, [(n, items) for n, items in groups if n]


def render_md_html(text: str, variant: str, title_override: str,
                   date_override: str = "", state: Path | None = None,
                   mmap: dict[int, dict] | None = None) -> str:
    c = VARIANTS[variant]
    orig_title, groups = parse_digest_md(text)
    title = title_override or orig_title
    date = date_override
    if not date:
        # 日期优先取原标题里的（"X 关注账号日报 2026-09-22"），
        # 标题被 override 时也不会丢
        m = re.search(r"(\d{4}-\d{2}-\d{2})", orig_title)
        date = m.group(1) if m else ""
    # 2026-09-22 -> 9月22日，手机上比 ISO 日期好读
    m = re.match(r"(\d{4})-(\d{2})-(\d{2})", date)
    if m:
        date = f"{int(m.group(2))}月{int(m.group(3))}日"

    body = []
    for name, items in groups:
        cls = "headlines" if name == "要闻" else ""
        tag = "ol" if cls else "div"
        body.append(f"<section><h2>{esc(name)}</h2><{tag} class=\"{cls}\">")
        for n, it in enumerate(items, 1):
            if cls:
                body.append(f"<li>{_inline(it)}</li>")
            elif state is not None and mmap:
                body.append(render_item(it, state, mmap, n))
            else:
                body.append(render_item(it, Path("."), {}, n))
        body.append(f"</{tag}></section>")

    vals = {
        "WIDTH": str(WIDTH), "PAD": str(PAD),
        "DATE": esc(date), "PAGETITLE": esc(title),
        "LEDE": f"{len(groups)} 个分组 · jev 价值筛选",
        "CONTENT": "\n".join(body),
        "COLOPHON": "X · Following Digest",
    }
    for k, v in c.items():
        vals[k.upper()] = str(v)
        vals[k.lower()] = str(v)
    if variant == "D":
        vals["BODYFONT"] = (f"{FONT_SANS};letter-spacing:.3px;"
                            f"line-height:1.55")
        vals["SERIF"] = FONT_SERIF
    else:
        vals["BODYFONT"] = "sans-serif"
        vals["SERIF"] = "serif"
    out = MD_TEMPLATE
    for k, v in vals.items():
        out = out.replace(f"@{k}@", v)
    return re.sub(r"@[A-Z_]+@", "", out)


def cmd_md(args) -> int:
    src = Path(args.file)
    if not src.exists():
        print(f"[error] 文件不存在: {src}", file=sys.stderr)
        return 1
    state = Path(args.state_dir) if args.state_dir else None
    mmap: dict[int, dict] = {}
    if state:
        date = args.date or datetime.now().astimezone().strftime("%Y-%m-%d")
        mmap, _ = media_map(state, date, args.top)
        if not mmap:
            print(f"[warn] {state}/picked/{date}.json 无可用图片，"
                  f"将渲染纯文字日报", file=sys.stderr)
    html_text = render_md_html(src.read_text(encoding="utf-8"),
                               args.variant, args.title, state=state,
                               mmap=mmap)
    return emit(args, html_text, f"digest-md-{args.variant}")


def main(argv=None) -> int:
    p = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("render", help="渲染图片日报")
    r.add_argument("--state-dir", required=True)
    r.add_argument("--date", default="", help="YYYY-MM-DD，缺省今天")
    r.add_argument("--variant", default="B", choices=sorted(VARIANTS))
    r.add_argument("--top", type=int, default=12)
    r.add_argument("--out", default="")
    r.set_defaults(func=cmd_render)
    m = sub.add_parser("md", help="把已加工的中文日报 markdown 渲染成图")
    m.add_argument("file", help="markdown 文件路径")
    m.add_argument("--variant", default="D", choices=sorted(VARIANTS))
    m.add_argument("--title", default="日报")
    m.add_argument("--out", default="")
    m.add_argument("--state-dir", default="",
                   help="给了才解析条目里的 ![imgN] 并下载图片")
    m.add_argument("--date", default="", help="配合 --state-dir 定位 picked")
    m.add_argument("--top", type=int, default=15,
                   help="与 digest_build.py 的 --top 保持一致")
    m.set_defaults(func=cmd_md)
    args = p.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
