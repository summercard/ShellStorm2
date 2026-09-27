"""只读：比对指定组件在「备份库 vs 现库」的 UV 色盘格直方图，确认提亮是否真的落在这件上。"""

from __future__ import annotations

import argparse
import collections
import json
import sys
from pathlib import Path

import bpy

GRID = 10.0


def parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--blend", required=True)
    p.add_argument("--label", default="")
    return p.parse_args(argv)


def cells() -> tuple[collections.Counter, int]:
    counter: collections.Counter = collections.Counter()
    total = 0
    seen: set[int] = set()
    for obj in bpy.data.objects:
        if obj.type != "MESH" or "_输出_" not in obj.name:
            continue
        me = obj.data
        if me.as_pointer() in seen:
            continue
        seen.add(me.as_pointer())
        layer = me.uv_layers.get("PaletteUV")
        if layer is None:
            continue
        uvs = layer.data
        for poly in me.polygons:
            if not poly.loop_indices:
                continue
            cu = sum(uvs[li].uv[0] for li in poly.loop_indices) / len(poly.loop_indices)
            cv = sum(uvs[li].uv[1] for li in poly.loop_indices) / len(poly.loop_indices)
            cu = min(max(cu, 0.0), 0.999999)
            cv = min(max(cv, 0.0), 0.999999)
            cell = (int(cu * GRID), int(cv * GRID))
            counter[cell] += 1
            total += 1
    return counter, total


def main() -> None:
    args = parse_args()
    sys.stdout.reconfigure(encoding="utf-8")
    bpy.ops.wm.open_mainfile(filepath=args.blend)
    counter, total = cells()
    rows = 9
    out = {}
    for (u, v), n in sorted(counter.items()):
        out["%d_%d" % (u, v)] = n
    print(
        "CELLS %s total=%d distinct=%d :: %s"
        % (
            args.label,
            total,
            len(counter),
            json.dumps(out, ensure_ascii=False, sort_keys=True),
        )
    )
    # 按图面行汇总，便于看深色行占比
    by_row: collections.Counter = collections.Counter()
    for (u, v), n in counter.items():
        by_row[rows - v] += n
    print(
        "BY_ROW %s :: %s"
        % (args.label, {("r%d" % r): by_row[r] for r in sorted(by_row)})
    )


if __name__ == "__main__":
    main()
