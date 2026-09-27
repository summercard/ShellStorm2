"""只读：把 10x10 色盘按格采样打印（含 HSV）。"""

from __future__ import annotations

import colorsys
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(r"I:\工作项目\shellstrom2\ShellStorm2")
PALETTE = ROOT / "assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"


def sample(path: Path, size: int = 10) -> list[list[tuple[int, int, int]]]:
    im = Image.open(path).convert("RGB")
    w, h = im.size
    cw, ch = w / size, h / size
    grid = []
    for r in range(size):
        row = []
        for c in range(size):
            x = int((c + 0.5) * cw)
            y = int((r + 0.5) * ch)
            row.append(im.getpixel((x, y)))
        grid.append(row)
    return grid


def main() -> None:
    grid = sample(PALETTE)
    print("行=图面从上到下；列=从左到右")
    print("      " + "".join(f"{('c%d' % c):>22}" for c in range(10)))
    for r, row in enumerate(grid):
        cells = []
        for c, (rr, gg, bb) in enumerate(row):
            hh, ss, vv = colorsys.rgb_to_hsv(rr / 255, gg / 255, bb / 255)
            cells.append(f"#{rr:02x}{gg:02x}{bb:02x} {vv*100:5.1f}% S{ss*100:3.0f} H{hh*360:5.1f}")
        print(f"r{r:<2} " + " ".join(f"{t:>22}" for t in cells))
    print()
    print("=== 每行平均明度 V ===")
    for r, row in enumerate(grid):
        vs = [colorsys.rgb_to_hsv(*(p / 255 for p in px))[2] for px in row]
        print(f"r{r}: avg V={sum(vs)/len(vs)*100:5.1f}%  min={min(vs)*100:5.1f}%  max={max(vs)*100:5.1f}%")


if __name__ == "__main__":
    main()
