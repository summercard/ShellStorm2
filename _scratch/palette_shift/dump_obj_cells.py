"""只读：输出某对象各色盘格的面数 + 各格代表性面的法线/尺寸，判断视觉角色。"""

from __future__ import annotations

import argparse
import collections
import sys
from pathlib import Path

import bpy

ROOT = Path(r"I:\工作项目\shellstrom2\ShellStorm2")
LIBS = {
    "office_v006": "assets/art/environments/tower_zones/expedition/source/common_components/v006/expedition_office_room_components_source_v006.blend",
    "bridge_v007": "assets/art/environments/tower_zones/expedition/source/common_components/v007/expedition_bridge_room_components_source_v007.blend",
    "boss_v008": "assets/art/environments/tower_zones/expedition/source/common_components/v008/expedition_boss_room_components_source_v008.blend",
    "corridor_v002": "assets/art/environments/tower_zones/expedition/source/common_components/v002/expedition_l_corridor_components_source_v002.blend",
    "db_v003": "assets/art/environments/tower_zones/expedition/source/common_components/v003/expedition_db_room_components_source_v003.blend",
}


def parse():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--lib", required=True)
    p.add_argument("--obj", required=True)
    return p.parse_args(argv)


def main() -> None:
    args = parse()
    bpy.ops.wm.open_mainfile(filepath=str(ROOT / LIBS[args.lib]))
    obj = bpy.data.objects.get(args.obj)
    if obj is None:
        print("NO SUCH OBJECT", args.obj)
        return
    me = obj.data
    layer = me.uv_layers.get("PaletteUV")
    uvs = layer.data
    cells = collections.Counter()
    area = collections.defaultdict(float)
    sample = {}
    for poly in me.polygons:
        cu = cv = 0.0
        for li in poly.loop_indices:
            uv = uvs[li].uv
            cu += uv[0]
            cv += uv[1]
        cu /= poly.loop_total
        cv /= poly.loop_total
        key = (min(9, max(0, int(cu * 10))), min(9, max(0, int(cv * 10))))
        cells[key] += 1
        area[key] += poly.area
        sample.setdefault(key, poly)
    print(f"obj={obj.name} polys={len(me.polygons)} dims={tuple(round(v,3) for v in obj.dimensions)}")
    for key, n in cells.most_common():
        p = sample[key]
        c = p.center
        print(
            "  cell %d_%d faces=%5d area=%8.3f 代表面法线=(%5.2f,%5.2f,%5.2f) 质心=(%8.3f,%8.3f,%8.3f)"
            % (key[0], key[1], n, area[key], p.normal.x, p.normal.y, p.normal.z, c.x, c.y, c.z)
        )


if __name__ == "__main__":
    main()
