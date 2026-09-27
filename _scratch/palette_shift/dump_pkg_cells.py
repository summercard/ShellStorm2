"""只读：打印指定输出包的完整色盘格直方图（判断是否为棋盘/双色结构）。"""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(r"I:\工作项目\shellstrom2\ShellStorm2")
SRC = ROOT / "_scratch/palette_shift/per_package.json"


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    keys = sys.argv[1:] or ["floor_tile_5m", "tile_upper", "floor_zone_mark"]
    data = json.loads(SRC.read_text(encoding="utf-8"))
    for lib, payload in data.items():
        for pkg, d in payload["packages"].items():
            if not any(k in pkg for k in keys):
                continue
            print(f"===== {lib} / {pkg}  面 {d['faces']} =====")
            for cell, n in d["cells"].items():
                print(f"    {cell:<6} {n:>7}")
            print(f"    材质: {d['mats']}")
            print()


if __name__ == "__main__":
    main()
