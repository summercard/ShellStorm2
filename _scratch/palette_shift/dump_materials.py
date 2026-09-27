"""只读：列出某库里所有材质名 + 各自面数与面积，并给出若干对象的槽指向。"""

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


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--lib", required=True)
    p.add_argument("--objs", default="", help="逗号分隔对象名子串，列出其槽指向")
    args = p.parse_args(argv)
    bpy.ops.wm.open_mainfile(filepath=str(ROOT / LIBS[args.lib]))

    faces = collections.Counter()
    area = collections.defaultdict(float)
    seen = set()
    for obj in bpy.data.objects:
        if obj.type != "MESH":
            continue
        me = obj.data
        if me.as_pointer() in seen:
            continue
        seen.add(me.as_pointer())
        for poly in me.polygons:
            i = poly.material_index
            name = me.materials[i].name if i < len(me.materials) and me.materials[i] else "<none>"
            faces[name] += 1
            area[name] += poly.area
    print("===== %s 材质数据块 =====" % args.lib)
    for name, n in faces.most_common():
        print("  %-28s 面=%-8d 面积=%9.2f  (users=%s)" % (
            name, n, area[name], bpy.data.materials.get(name).users if bpy.data.materials.get(name) else "?"))
    print("  材质数据块总数:", len(bpy.data.materials), "->", [m.name for m in bpy.data.materials])

    if args.objs:
        print("----- 对象槽指向 -----")
        for obj in bpy.data.objects:
            if obj.type != "MESH" or "_输出_" not in obj.name:
                continue
            if not any(t in obj.name for t in args.objs.split(",")):
                continue
            print("  %s" % obj.name)
            for i, slot in enumerate(obj.material_slots):
                print("      slot%d -> %s" % (i, slot.material.name if slot.material else "<none>"))


if __name__ == "__main__":
    main()
