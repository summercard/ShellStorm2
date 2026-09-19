"""探针：列出战局通用组件库各版本 blend 里的 collection / object / 场景数。

用途：确定 wall_door_5m_通用包 的最高可用源版本与其中的对象名、包络，
不写任何文件。
"""
import sys
from pathlib import Path

import bpy

BLENDS = [
    r"I:\工作项目\shellstrom2\ShellStorm2\assets\art\environments\tower_zones\battle\source\common_components\v006\env_battle_common_components_source_v006.blend",
    r"I:\工作项目\shellstrom2\ShellStorm2\assets\art\environments\tower_zones\battle\source\common_components\v007\env_battle_common_components_source_v007.blend",
]

for blend in BLENDS:
    path = Path(blend)
    print("=" * 78)
    print("BLEND %s exists=%s" % (path.name, path.exists()))
    if not path.exists():
        continue
    bpy.ops.wm.open_mainfile(filepath=str(path))
    print("scenes = %d -> %s" % (len(bpy.data.scenes), [s.name for s in bpy.data.scenes][:14]))
    print("collections = %d" % len(bpy.data.collections))
    for col in sorted(bpy.data.collections, key=lambda c: c.name):
        objs = [o.name for o in col.objects]
        print("  COLL %-44s objects=%d %s" % (col.name, len(objs), objs[:6]))
    print("-- objects of interest --")
    for name in (
        "ROOT_wall_door_5m_通用组件",
        "wall_door_5m_主体_输出",
        "wall_door_5m_UI灯光_柔和自发光",
        "ROOT_wall_standard_5m_通用组件",
    ):
        obj = bpy.data.objects.get(name)
        if obj is None:
            print("  %-42s MISSING" % name)
            continue
        loc = obj.matrix_world.translation
        print(
            "  %-42s type=%-6s world=(%.6f, %.6f, %.6f) collections=%s"
            % (name, obj.type, loc.x, loc.y, loc.z, [c.name for c in obj.users_collection])
        )
        print("      props=%s" % dict(obj.items()))
        if obj.type == "MESH":
            import mathutils
            pts = [obj.matrix_world @ mathutils.Vector(c) for c in obj.bound_box]
            lo = [min(p[i] for p in pts) for i in range(3)]
            hi = [max(p[i] for p in pts) for i in range(3)]
            print("      world_bounds lo=%s hi=%s" % ([round(v, 5) for v in lo], [round(v, 5) for v in hi]))
            print("      polys=%d slots=%s uvs=%s" % (
                len(obj.data.polygons),
                [s.material.name if s.material else None for s in obj.material_slots],
                [l.name for l in obj.data.uv_layers],
            ))
    # 该 blend 里未使用的骨架/空物体，用于发现真实 ROOT
    empties = [o.name for o in bpy.data.objects if o.type == "EMPTY"]
    print("empties = %d %s" % (len(empties), empties[:14]))
