"""只读：列出某对象上落在指定色盘格的面 —— 质心、法线、面积，判断是否可见面。

用法:
  blender -b --python inspect_cell_faces.py -- --lib office_v006 --obj 顶部灯具_输出_部件00 --cell 0_0
"""

from __future__ import annotations

import argparse
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
    p.add_argument("--cell", default="0_0")
    p.add_argument("--limit", type=int, default=12)
    return p.parse_args(argv)


def main() -> None:
    args = parse()
    target = tuple(int(t) for t in args.cell.split("_"))
    bpy.ops.wm.open_mainfile(filepath=str(ROOT / LIBS[args.lib]))
    obj = bpy.data.objects.get(args.obj)
    if obj is None:
        print("NO SUCH OBJECT", args.obj)
        return
    me = obj.data
    layer = me.uv_layers.get("PaletteUV")
    uvs = layer.data
    n = 0
    total_area = 0.0
    hit_area = 0.0
    print(f"obj={obj.name} polys={len(me.polygons)} bounds={tuple(round(v,3) for v in obj.dimensions)}")
    for poly in me.polygons:
        cu = cv = 0.0
        for li in poly.loop_indices:
            uv = uvs[li].uv
            cu += uv[0]
            cv += uv[1]
        cu /= poly.loop_total
        cv /= poly.loop_total
        total_area += poly.area
        if (min(9, max(0, int(cu * 10))), min(9, max(0, int(cv * 10)))) != target:
            continue
        n += 1
        hit_area += poly.area
        if n <= args.limit:
            c = poly.center
            nz = poly.normal
            print(
                "  face%-5d area=%7.4f center=(%8.3f,%8.3f,%8.3f) normal=(%5.2f,%5.2f,%5.2f) uv=(%.3f,%.3f)"
                % (poly.index, poly.area, c.x, c.y, c.z, nz.x, nz.y, nz.z, cu, cv)
            )
    print(f"hit faces={n} hit_area={hit_area:.3f} total_area={total_area:.3f} share={hit_area/total_area*100:.1f}%")


if __name__ == "__main__":
    main()
