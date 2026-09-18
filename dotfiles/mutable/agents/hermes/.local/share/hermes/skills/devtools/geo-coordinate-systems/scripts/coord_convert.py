"""坐标系转换工具（BD-09 / GCJ-02 / WGS-84 六向互转）。

用法（默认 dry-run 只打印；`--write` 才写回）：

    python coord_convert.py bd2wgs data.json            # 预演
    python coord_convert.py bd2wgs data.json --write    # 落盘
    python coord_convert.py --selftest                  # round-trip 自检

输入：对象数组 JSON，逐条读 `latitude` / `longitude`（null 跳过，逐条写回）。

背景：中国境内三套坐标并存——WGS-84（GPS/OSM）、GCJ-02（高德/腾讯）、
BD-09（百度系，含经百度系录入的政务/第三方数据）；后两者相对 WGS 偏移
500m~1.3km，且数据源通常不写元数据。判定方法见 SKILL.md「同名点位三假设残差统计」。

算法为公开标准实现；gcj<->wgs 迭代求逆（默认 5 次，残差 < 10cm）。
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

_A = 6378245.0
_EE = 0.00669342162296594323

# 经纬度值的合理范围（写入前自检用）
_LAT_RANGE = (-90.0, 90.0)
_LNG_RANGE = (-180.0, 180.0)


def _transform_lat(lng: float, lat: float) -> float:
    ret = -100.0 + 2.0 * lng + 3.0 * lat + 0.2 * lat * lat + 0.1 * lng * lat + 0.2 * math.sqrt(abs(lng))
    ret += (20.0 * math.sin(6.0 * lng * math.pi) + 20.0 * math.sin(2.0 * lng * math.pi)) * 2.0 / 3.0
    ret += (20.0 * math.sin(lat * math.pi) + 40.0 * math.sin(lat / 3.0 * math.pi)) * 2.0 / 3.0
    ret += (160.0 * math.sin(lat / 12.0 * math.pi) + 320 * math.sin(lat * math.pi / 30.0)) * 2.0 / 3.0
    return ret


def _transform_lng(lng: float, lat: float) -> float:
    ret = 300.0 + lng + 2.0 * lat + 0.1 * lng * lng + 0.1 * lng * lat + 0.1 * math.sqrt(abs(lng))
    ret += (20.0 * math.sin(6.0 * lng * math.pi) + 20.0 * math.sin(2.0 * lng * math.pi)) * 2.0 / 3.0
    ret += (20.0 * math.sin(lng * math.pi) + 40.0 * math.sin(lng / 3.0 * math.pi)) * 2.0 / 3.0
    ret += (150.0 * math.sin(lng / 12.0 * math.pi) + 300.0 * math.sin(lng / 30.0 * math.pi)) * 2.0 / 3.0
    return ret


def wgs2gcj(lng: float, lat: float) -> tuple[float, float]:
    """WGS-84 → GCJ-02（火星坐标）。"""
    dlat = _transform_lat(lng - 105.0, lat - 35.0)
    dlng = _transform_lng(lng - 105.0, lat - 35.0)
    rad = lat / 180.0 * math.pi
    magic = math.sin(rad)
    magic = 1 - _EE * magic * magic
    sqrt_magic = math.sqrt(magic)
    dlat = (dlat * 180.0) / ((_A * (1 - _EE)) / (magic * sqrt_magic) * math.pi)
    dlng = (dlng * 180.0) / (_A / sqrt_magic * math.cos(rad) * math.pi)
    return lng + dlng, lat + dlat


def gcj2wgs(lng: float, lat: float, iters: int = 5) -> tuple[float, float]:
    """GCJ-02 → WGS-84（迭代求逆）。"""
    wlng, wlat = lng, lat
    for _ in range(iters):
        glng, glat = wgs2gcj(wlng, wlat)
        wlng += lng - glng
        wlat += lat - glat
    return wlng, wlat


def bd2gcj(lng: float, lat: float) -> tuple[float, float]:
    """BD-09 → GCJ-02。"""
    x, y = lng - 0.0065, lat - 0.006
    z = math.sqrt(x * x + y * y) - 0.00002 * math.sin(y * math.pi * 3000.0 / 180.0)
    theta = math.atan2(y, x) - 0.000003 * math.cos(x * math.pi * 3000.0 / 180.0)
    return z * math.cos(theta), z * math.sin(theta)


def gcj2bd(lng: float, lat: float) -> tuple[float, float]:
    """GCJ-02 → BD-09。"""
    z = math.sqrt(lng * lng + lat * lat) + 0.00002 * math.sin(lat * math.pi * 3000.0 / 180.0)
    theta = math.atan2(lat, lng) + 0.000003 * math.cos(lng * math.pi * 3000.0 / 180.0)
    return z * math.cos(theta) + 0.0065, z * math.sin(theta) + 0.006


def bd2wgs(lng: float, lat: float) -> tuple[float, float]:
    """BD-09 → WGS-84。"""
    glng, glat = bd2gcj(lng, lat)
    return gcj2wgs(glng, glat)


def wgs2bd(lng: float, lat: float) -> tuple[float, float]:
    """WGS-84 → BD-09。"""
    glng, glat = wgs2gcj(lng, lat)
    return gcj2bd(glng, glat)


CONVERTERS = {
    "bd2wgs": bd2wgs,
    "wgs2bd": wgs2bd,
    "gcj2wgs": gcj2wgs,
    "wgs2gcj": wgs2gcj,
    "bd2gcj": bd2gcj,
    "gcj2bd": gcj2bd,
}


def convert_records(records: list[dict], direction: str, precision: int = 6) -> tuple[int, int]:
    """就地转换记录列表中非空 `latitude` / `longitude`；返回 (转换条数, 跳过条数)。"""
    fn = CONVERTERS[direction]
    converted = 0
    skipped = 0
    for r in records:
        lat, lng = r.get("latitude"), r.get("longitude")
        if lat is None or lng is None:
            skipped += 1
            continue
        if not (_LAT_RANGE[0] <= lat <= _LAT_RANGE[1] and _LNG_RANGE[0] <= lng <= _LNG_RANGE[1]):
            raise ValueError(f"坐标超出合理范围：{r.get('code')} {lat},{lng}")
        nlng, nlat = fn(lng, lat)
        r["latitude"], r["longitude"] = round(nlat, precision), round(nlng, precision)
        converted += 1
    return converted, skipped


_SELFTEST_POINTS = [
    (108.385246, 22.791647),  # 南宁
    (100.233333, 26.866667),  # 丽江
    (109.156748, 21.410505),  # 北海
]


def _selftest() -> int:
    """round-trip 自检：WGS→BD→WGS / WGS→GCJ→WGS 残差应 < 1m。"""
    worst = 0.0
    for lng, lat in _SELFTEST_POINTS:
        back_bd = bd2wgs(*wgs2bd(lng, lat))
        back_gcj = gcj2wgs(*wgs2gcj(lng, lat))
        d_bd = math.hypot((back_bd[1] - lat) * 111000, (back_bd[0] - lng) * 101000)
        d_gcj = math.hypot((back_gcj[1] - lat) * 111000, (back_gcj[0] - lng) * 101000)
        worst = max(worst, d_bd, d_gcj)
        print(f"  ({lat}, {lng}): WGS→BD→WGS {d_bd * 100:.1f}cm | WGS→GCJ→WGS {d_gcj * 100:.1f}cm")
    print(f"最大残差 {worst * 100:.1f}cm — {'OK' if worst < 1 else '异常，检查实现'}")
    return 0 if worst < 1 else 1


def main() -> None:
    parser = argparse.ArgumentParser(description="BD-09 / GCJ-02 / WGS-84 坐标转换")
    parser.add_argument("direction", nargs="?", choices=sorted(CONVERTERS), help="转换方向，如 bd2wgs")
    parser.add_argument("path", nargs="?", type=Path, help="对象数组 json 文件（含 latitude / longitude）")
    parser.add_argument("--write", action="store_true", help="写回文件（默认只预演打印）")
    parser.add_argument("--sample", type=int, default=5, help="预演时打印的样本条数")
    parser.add_argument("--selftest", action="store_true", help="跑 round-trip 自检后退出")
    args = parser.parse_args()

    if args.selftest:
        raise SystemExit(_selftest())
    if not args.direction or not args.path:
        parser.error("需要 direction 与 path（或 --selftest）")

    data = json.loads(args.path.read_text())
    if not isinstance(data, list):
        raise SystemExit(f"{args.path} 不是对象数组")

    before = [(r.get("code"), r.get("latitude"), r.get("longitude")) for r in data]
    converted, skipped = convert_records(data, args.direction)

    for code, lat, lng in before[: args.sample]:
        row = next(r for r in data if r.get("code") == code)
        if lat is not None and lng is not None:
            print(f"  {code}: ({lat}, {lng}) → ({row['latitude']}, {row['longitude']})")
    print(f"{args.direction}: 转换 {converted} 条，跳过（无坐标）{skipped} 条")

    if args.write:
        args.path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
        print(f"已写回 {args.path}")
    else:
        print("（预演模式，未写回；确认后加 --write）")


if __name__ == "__main__":
    main()
