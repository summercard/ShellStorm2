"""只读：从 per_package.json 汇总「指定色盘格」按包的用量，回答提亮溢出风险。

用法: python cell_by_package.py 9_1 9_2 9_0
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(r"I:\工作项目\shellstrom2\ShellStorm2")
SRC = ROOT / "_scratch/palette_shift/per_package.json"


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    targets = sys.argv[1:] or ["9_1", "9_2", "9_0"]
    data = json.loads(SRC.read_text(encoding="utf-8"))
    for cell in targets:
        print(f"===== 格 {cell} =====")
        rows = []
        for lib, payload in data.items():
            for pkg, d in payload["packages"].items():
                n = d["cells"].get(cell, 0)
                if n:
                    rows.append((n, lib, pkg, d["faces"]))
        rows.sort(reverse=True)
        total = sum(r[0] for r in rows)
        print(f"  合计面数 {total}  落在 {len(rows)} 个包")
        for n, lib, pkg, faces in rows[:14]:
            print(f"    {n:>6}  {lib:<14} {pkg:<34} (包内共 {faces} 面)")
        print()


if __name__ == "__main__":
    main()
