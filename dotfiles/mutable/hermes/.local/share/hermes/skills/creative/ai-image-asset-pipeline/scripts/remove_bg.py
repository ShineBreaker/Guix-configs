#!/usr/bin/env python3
"""Flood-fill 去底抠图：移除 AI 立绘的浅色/纯色背景，输出透明 PNG。

用法:
    python3 remove_bg.py --dir <素材目录> [--glob 'char-*.png'] [--threshold 58] [--feather 1] [--suffix -fg]

原理:
    1. 采样四边像素取中位数作为背景基准色
    2. 从四边种子 BFS，颜色距离 < threshold 的 4-连通像素标记为背景
    3. 高斯羽化边缘，输出 alpha 合成结果

已知限制（踩坑记录）:
    - 只能清除与边缘 4-连通且颜色接近背景的像素；被角色主体隔断的
      浅色"地板/底座"会残留 —— 此时提高阈值无效，需换位置启发式策略。
    - PIL PixelAccess 索引顺序是 px[x, y]（x=列, y=行），切勿写成 px[y, x]，
      非正方形图会 IndexError。
"""
import argparse
import glob as globmod
import os
from collections import deque

from PIL import Image, ImageFilter


def edge_median_color(rgb):
    """四边采样像素的中位数颜色，作为背景基准色（抗单点噪声）。"""
    w, h = rgb.size
    px = rgb.load()
    samples = []
    for x in range(0, w, 7):
        samples.append(px[x, 0])
        samples.append(px[x, h - 1])
    for y in range(0, h, 7):
        samples.append(px[0, y])
        samples.append(px[w - 1, y])
    samples.sort(key=lambda p: (p[0], p[1], p[2]))
    return samples[len(samples) // 2]


def flood_fill_bg(rgb, threshold):
    """返回与原图同尺寸的 L mask：255=背景（应透明），0=前景。

    注意：所有像素访问必须用 mpx[x, y]（x=列, y=行）。"""
    w, h = rgb.size
    px = rgb.load()
    mask = Image.new("L", (w, h), 0)
    mpx = mask.load()
    bg = edge_median_color(rgb)

    seeds = [(x, 0) for x in range(w)] + [(x, h - 1) for x in range(w)] \
          + [(0, y) for y in range(h)] + [(w - 1, y) for y in range(h)]
    q = deque()
    for s in seeds:
        if mpx[s[0], s[1]] == 0:
            mpx[s[0], s[1]] = 255
            q.append(s)
    while q:
        x, y = q.popleft()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h and mpx[nx, ny] == 0:
                r, g, b = px[nx, ny]
                dist = ((r - bg[0]) ** 2 + (g - bg[1]) ** 2 + (b - bg[2]) ** 2) ** 0.5
                if dist < threshold:
                    mpx[nx, ny] = 255
                    q.append((nx, ny))
    return mask


def main():
    ap = argparse.ArgumentParser(description="Flood-fill 去底抠图")
    ap.add_argument("--dir", required=True, help="素材目录")
    ap.add_argument("--glob", default="*.png", help="文件匹配模式")
    ap.add_argument("--threshold", type=float, default=58, help="颜色距离阈值 (0-255)")
    ap.add_argument("--feather", type=float, default=1, help="边缘羽化半径 px")
    ap.add_argument("--suffix", default="-fg", help="输出文件名后缀")
    args = ap.parse_args()

    for path in sorted(globmod.glob(os.path.join(args.dir, args.glob))):
        if args.suffix in os.path.basename(path):
            continue
        img = Image.open(path).convert("RGBA")
        mask = flood_fill_bg(img.convert("RGB"), args.threshold)
        mask = mask.filter(ImageFilter.GaussianBlur(args.feather))
        r, g, b, a = img.split()
        # composite(im1, im2, mask): mask=255 处取 im1（黑色=alpha 0）
        a = Image.composite(Image.new("L", img.size, 0), a, mask)
        out_path = os.path.splitext(path)[0] + args.suffix + ".png"
        Image.merge("RGBA", (r, g, b, a)).save(out_path)
        print(f"{os.path.basename(path)} -> {os.path.basename(out_path)}")


if __name__ == "__main__":
    main()
