"""只读：查某个色盘格（默认 0_0 近黑）到底落在哪些对象/输出包上。

用法（需 Blender）:
  blender -b --python where_cell_used.py -- --lib <label> --cell 0_0
"""

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
    p.add_argument("--cell", default="0_0")
    return p.parse_args(argv)


def main() -> None:
    args = parse()
    target = tuple(int(t) for t in args.cell.split("_"))
    bpy.ops.wm.open_mainfile(filepath=str(ROOT / LIBS[args.lib]))
    per_obj = collections.Counter()
    per_pkg = collections.Counter()
    per_mat = collections.Counter()
    seen = set()
    for obj in bpy.data.objects:
        if obj.type != "MESH":
            continue
        me = obj.data
        if me.name in seen:
            continue
        seen.add(me.name)
        layer = me.uv_layers.get("PaletteUV")
        if layer is None:
            continue
        colls = [c.name for c in obj.users_collection] or ["<无集合>"]
        pkg = next((c for c in colls if c.endswith("_输出包")), colls[0])
        uvs = layer.data
        n = 0
        for poly in me.polygons:
            if poly.loop_total == 0:
                continue
            cu = cv = 0.0
            for li in poly.loop_indices:
                uv = uvs[li].uv
                cu += uv[0]
                cv += uv[1]
            cu /= poly.loop_total
            cv /= poly.loop_total
            if (min(9, max(0, int(cu * 10))), min(9, max(0, int(cv * 10)))) == target:
                n += 1
                mat = (
                    me.materials[poly.material_index]
                    if me.materials and poly.material_index < len(me.materials)
                    else None
                )
                per_mat[mat.name if mat else "<none>"] += 1
        if n:
            per_obj[obj.name] += n
            per_pkg[pkg] += n
    print(f"===== {args.lib} 格 {args.cell} 面数合计 {sum(per_obj.values())} =====")
    print("--- 按对象 top30 ---")
    for name, n in per_obj.most_common(30):
        print(f"  {n:>6}  {name}")
    print("--- 按输出包 ---")
    for name, n in per_pkg.most_common():
        print(f"  {n:>6}  {name}")
    print("--- 按材质 ---")
    for name, n in per_mat.most_common():
        print(f"  {n:>6}  {name}")


if __name__ == "__main__":
    main()
