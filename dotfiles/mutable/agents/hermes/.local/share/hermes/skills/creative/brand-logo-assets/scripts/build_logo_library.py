#!/usr/bin/env python3
"""build_logo_library.py — 抓取/上色/归一化/验证品牌 logo 资产库。

用法:
    python3 scripts/build_logo_library.py <manifest.json> [--root <输出根>] \
        [--size 1024] [--redownload] [--verify-only]

manifest 形状见 templates/manifest.example.json。root 缺省取 manifest 里的
"root" 字段，其次 ./laptop-stickers。

每项产出: <root>/<category>/<name>/icon.<ext> + sticker-<size>.png + meta.json
幂等: 重复执行只重建变化项; 已下载的源默认不重下(--redownload 强制)。
"""
import argparse
import concurrent.futures as cf
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.request

UA = {"User-Agent": "Mozilla/5.0 (X11; Linux x86_64) Hermes/1.0"}


def fetch(url, dest=None, timeout=30):
    """下载; 调用方按文件头判定真身。返回 (ok, bytes_or_err)。"""
    try:
        req = urllib.request.Request(url, headers=UA)
        with urllib.request.urlopen(req, timeout=timeout) as r:
            data = r.read()
        if dest:
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            tmp = dest + ".part"
            with open(tmp, "wb") as f:
                f.write(data)
            shutil.move(tmp, dest)
        return True, data
    except urllib.error.HTTPError as e:
        return False, f"HTTP {e.code}"
    except Exception as e:  # noqa: BLE001
        return False, f"{type(e).__name__}: {e}"[:80]


def head_kind(data: bytes) -> str:
    h = data[:400].lstrip().lower()
    if h.startswith(b"<svg") or b"<svg" in h:
        return "svg"
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        return "png"
    if data[:4] == b"\x00\x00\x01\x00":
        return "ico"
    if data[:4] == b"RIFF" and b"WEBP" in data[:16]:
        return "webp"
    return ""


HEXRE = re.compile(r"[0-9A-Fa-f]{6}")


def inject_fill(path, hexv):
    """给无 fill 的 SVG 根元素注入品牌色属性。CSS 注入 librsvg 不吃。"""
    t = open(path).read()
    t = re.sub(r"<style>\{svg\{fill:[#0-9A-Fa-f]+\}\}</style>", "", t)
    has_color = re.search(r'(fill|stroke)\s*=\s*["\']#[0-9A-Fa-f]{3,8}["\']', t) or "fill:" in t
    if has_color:
        return False
    t2 = re.sub(r"<svg\b", f'<svg fill="#{hexv.upper()}"', t, count=1)
    open(path, "w").write(t2)
    return True


def square_pad(src, dst, size):
    """位图归一化到 size×size 透明画布居中。"""
    from PIL import Image
    im = Image.open(src).convert("RGBA")
    im.thumbnail((size, size), Image.LANCZOS)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.paste(im, ((size - im.width) // 2, (size - im.height) // 2), im)
    canvas.save(dst)
    return canvas.size


def svg_to_png(src, dst, size):
    """SVG → size×size 透明 PNG。"""
    subprocess.run(
        ["rsvg-convert", "-w", str(size), "-h", str(size),
         "--keep-aspect-ratio", "-b", "transparent", src, "-o", dst],
        check=True, timeout=120,
    )
    from PIL import Image
    im = Image.open(dst)
    if im.size != (size, size):
        canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        im = im.convert("RGBA")
        canvas.paste(im, ((size - im.width) // 2, (size - im.height) // 2), im)
        canvas.save(dst)
    return im.size


def process(item, root, size, redownload):
    cat, name = item["category"], item["name"]
    d = os.path.join(root, cat, name)
    os.makedirs(d, exist_ok=True)
    meta_path = os.path.join(d, "meta.json")
    meta = json.load(open(meta_path)) if os.path.exists(meta_path) else {}
    meta.update(name=name, category=cat, note=item.get("note", ""))
    meta.setdefault("brand_color", item.get("brand_color") or "")
    err = None
    ext = "svg"
    try:
        kind = item["kind"]
        if kind == "simple-icons":
            ext = "svg"
            dst = os.path.join(d, "icon." + ext)
            if redownload or not os.path.exists(dst):
                url = f"https://cdn.jsdelivr.net/npm/simple-icons@latest/icons/{item['src']}.svg"
                ok, data = fetch(url, dst)
                if not ok or head_kind(data) != "svg":
                    raise RuntimeError(f"simple-icons fetch: {data if not ok else 'not svg'}")
            meta["source"] = f"simple-icons ({item['src']})"
        elif kind == "local":
            src = item["src"]
            if not src or not os.path.exists(src):
                raise FileNotFoundError(f"local source missing: {src}")
            ext = os.path.splitext(src)[1].lstrip(".") or "svg"
            shutil.copy2(src, os.path.join(d, "icon." + ext))
            meta["source"] = f"local: {src}"
        elif kind == "url":
            url = item["src"]
            ext = os.path.splitext(url.split("?")[0])[1].lstrip(".") or "svg"
            dst = os.path.join(d, "icon." + ext)
            if redownload or not os.path.exists(dst):
                ok, data = fetch(url, dst)
                if not ok or not head_kind(data):
                    raise RuntimeError(f"url fetch: {data if not ok else 'unrecognized header'}")
            meta["source"] = url
        else:
            raise ValueError(f"unknown kind: {kind}")

        icon = os.path.join(d, f"icon.{ext}")
        if ext == "svg" and meta.get("brand_color") and HEXRE.fullmatch(meta["brand_color"]):
            if inject_fill(icon, meta["brand_color"]):
                meta["colorized_hex"] = meta["brand_color"].upper()
        out = os.path.join(d, f"sticker-{size}.png")
        got = svg_to_png(icon, out, size) if ext == "svg" else square_pad(icon, out, size)
        meta["png_size"] = list(got)
        meta["files"] = sorted(f for f in os.listdir(d) if f != "meta.json")
        meta.pop("error", None)
    except Exception as e:  # noqa: BLE001
        err = str(e)[:120]
        meta["error"] = err
    json.dump(meta, open(meta_path, "w"), ensure_ascii=False, indent=2)
    return name, meta.get("files"), err


def verify(root, size):
    """程序化验证: 尺寸/非空/来源/分类一致 + 主导色彩色/单色统计。"""
    from collections import Counter
    from PIL import Image
    bad, mono, colored, total = [], [], [], 0
    for cat in sorted(os.listdir(root)):
        cdir = os.path.join(root, cat)
        if not os.path.isdir(cdir) or cat.startswith("_"):
            continue
        for n in sorted(os.listdir(cdir)):
            d = os.path.join(cdir, n)
            p = os.path.join(d, f"sticker-{size}.png")
            if not os.path.exists(p):
                continue
            total += 1
            m = json.load(open(os.path.join(d, "meta.json")))
            im = Image.open(p)
            im.load()
            cnt = Counter(c for c in im.convert("RGBA").getdata() if c[3] > 200)
            if im.size != (size, size) or not cnt or not m.get("source") or m.get("category") != cat:
                bad.append((cat, n, im.size))
            top = cnt.most_common(1)[0][0] if cnt else (0, 0, 0, 0)
            (mono if top[0] == top[1] == top[2] else colored).append(n)
    return total, bad, colored, mono


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("manifest")
    ap.add_argument("--root")
    ap.add_argument("--size", type=int, default=1024)
    ap.add_argument("--redownload", action="store_true")
    ap.add_argument("--verify-only", action="store_true")
    a = ap.parse_args()

    man = json.load(open(a.manifest))
    root = a.root or man.get("root") or "./laptop-stickers"

    if a.verify_only:
        total, bad, colored, mono = verify(root, a.size)
        print(f"PNG={total} bad={len(bad)} colored={len(colored)} official_mono={len(mono)}")
        if bad:
            print("BAD:", bad)
            sys.exit(1)
        sys.exit(0)

    results = []
    with cf.ThreadPoolExecutor(8) as ex:
        results = list(ex.map(lambda it: process(it, root, a.size, a.redownload), man["items"]))
    ok = [r for r in results if r[1]]
    fail = [r for r in results if r[2]]
    print(f"OK={len(ok)} FAIL={len(fail)}")
    for n, _, e in fail:
        print(f"  FAIL {n}: {e}")

    total, bad, colored, mono = verify(root, a.size)
    print(f"verify: PNG={total} bad={len(bad)} colored={len(colored)} official_mono={len(mono)}")
    if bad:
        print("BAD:", bad)
        sys.exit(1)


if __name__ == "__main__":
    main()
