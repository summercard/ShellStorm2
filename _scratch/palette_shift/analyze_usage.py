"""读取 usage_report.json，按明度分档聚合"深色占比"，并给出各方案的映射表。"""

from __future__ import annotations

import colorsys
import json
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(r"I:\工作项目\shellstrom2\ShellStorm2")
PALETTE = ROOT / "assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"
REPORT = ROOT / "_scratch/palette_shift/usage_report.json"


def grid() -> list[list[tuple[int, int, int]]]:
    im = Image.open(PALETTE).convert("RGB")
    out = []
    for r in range(10):
        row = []
        for c in range(10):
            row.append(im.getpixel((int((c + 0.5) * 51.2), int((r + 0.5) * 51.2))))
        out.append(row)
    return out


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    g = grid()
    report = json.loads(REPORT.read_text(encoding="utf-8"))

    agg: dict[tuple[int, int], int] = {}
    totals = {}
    for label, data in report.items():
        faces = data["face_count"]
        totals[label] = faces
        for key, n in data["cells"].items():
            u, v = (int(t) for t in key.split("_"))
            agg[(u, v)] = agg.get((u, v), 0) + n

    grand = sum(totals.values())
    print("各库面数:", totals)
    print(f"合计 {grand} 面")
    print()
    print("=== 各明度档占比（按面数，全库合计）===")
    buckets = [(0, 20, "极深 <20%"), (20, 30, "深 20-30%"), (30, 40, "中深 30-40%"),
               (40, 50, "中 40-50%"), (50, 70, "浅 50-70%"), (70, 101, "很浅 >70%")]
    for lo, hi, name in buckets:
        n = 0
        for (u, v), cnt in agg.items():
            rr, gg, bb = g[9 - v][u]
            V = colorsys.rgb_to_hsv(rr / 255, gg / 255, bb / 255)[2] * 100
            if lo <= V < hi:
                n += cnt
        print(f"  {name:12s} {n:8d} 面  {n / grand * 100:5.1f}%")
    print()
    print("=== 用到的格（按面数降序，注明图面坐标/色值/明度）===")
    print(f"{'u':>2} {'v':>2} {'图面行':>4} {'#hex':>9} {'明度':>6} {'面数':>9} {'占比':>6}")
    for (u, v), cnt in sorted(agg.items(), key=lambda kv: -kv[1]):
        rr, gg, bb = g[9 - v][u]
        V = colorsys.rgb_to_hsv(rr / 255, gg / 255, bb / 255)[2] * 100
        print(f"{u:>2} {v:>2} {9 - v:>4} #{rr:02x}{gg:02x}{bb:02x} {V:5.1f}% {cnt:>9} {cnt / grand * 100:5.1f}%")


if __name__ == "__main__":
    main()
