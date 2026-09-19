"""Focused probe of the door_5m_通用包 component in the v006 batch source.

Prints only what the derivation script needs:
  - the scene datablock inventory (the batch carries many review scenes)
  - the ROOT empty world transform + custom props
  - per-mesh vertex/face counts, UV layers, material slots
  - per-material world-space bounds on the thickness axis (Blender Y), so we can
    tell which face the decoration sits on before deciding the yaw
"""

import json
from pathlib import Path

import bpy
from mathutils import Vector

BLEND = Path(
    r"I:\工作项目\shellstrom2\ShellStorm2\assets\art\environments"
    r"\tower_zones\battle\source\common_components\v006"
    r"\env_battle_common_components_source_v006.blend"
)

bpy.ops.wm.open_mainfile(filepath=str(BLEND))
print("OPENED %s" % bpy.data.filepath)

print("SCENES n=%d names=%s" % (len(bpy.data.scenes), [s.name for s in bpy.data.scenes]))
print("COLLECTIONS n=%d" % len(bpy.data.collections))
print("COLLECTION_NAMES %s" % sorted(c.name for c in bpy.data.collections))

pkg = bpy.data.collections.get("door_5m_通用包")
print("PKG_PRESENT %s" % (pkg is not None))
if pkg is not None:
    print("PKG_OBJECTS %s" % sorted(o.name for o in pkg.objects))
    print("PKG_PROPS %s" % json.dumps(dict(pkg.items()), ensure_ascii=False, default=str))

root = bpy.data.objects.get("ROOT_door_5m_通用组件")
print("ROOT_TYPE %s" % (root.type if root else None))
if root:
    print("ROOT_WORLD_T %s" % [round(v, 6) for v in root.matrix_world.translation])
    print("ROOT_SCALE %s" % [round(v, 6) for v in root.matrix_world.to_scale()])
    print("ROOT_PROPS %s" % json.dumps(dict(root.items()), ensure_ascii=False, default=str))
    print("ROOT_PARENT %s" % (root.parent.name if root.parent else None))

for name in ("door_5m_门扇_输出", "door_5m_UI灯光_柔和自发光"):
    obj = bpy.data.objects.get(name)
    if obj is None:
        print("MESH_MISSING %s" % name)
        continue
    me = obj.data
    print("--- %s ---" % name)
    print("TYPE %s verts=%d polys=%d" % (obj.type, len(me.vertices), len(me.polygons)))
    print("UV %s" % [l.name for l in me.uv_layers])
    print("MATSLOTS %s" % [s.material.name if s.material else None for s in obj.material_slots])
    print("OBJ_PROPS %s" % json.dumps(dict(obj.items()), ensure_ascii=False, default=str))
    print("PARENT %s" % (obj.parent.name if obj.parent else None))
    print(
        "PARENT_INV %s"
        % [round(v, 6) for v in obj.matrix_parent_inverse.translation]
    )
    pts = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    lows = [round(min(p[i] for p in pts), 5) for i in range(3)]
    highs = [round(max(p[i] for p in pts), 5) for i in range(3)]
    print("WORLD_BOUNDS min=%s max=%s" % (lows, highs))

    # Per-material footprint: which Y (thickness) side carries which role, and
    # how much of the surface area each role owns.
    by_mat = {}
    for poly in me.polygons:
        idx = poly.material_index
        slot = obj.material_slots[idx].material if idx < len(obj.material_slots) else None
        key = slot.name if slot else "(none)"
        entry = by_mat.setdefault(key, {"faces": 0, "y_min": None, "y_max": None, "x_min": None, "x_max": None})
        entry["faces"] += 1
        for vid in poly.vertices:
            wp = obj.matrix_world @ me.vertices[vid].co
            for axis, field in ((1, "y"), (0, "x")):
                cur_min = entry[field + "_min"]
                cur_max = entry[field + "_max"]
                v = wp[axis]
                entry[field + "_min"] = v if cur_min is None else min(cur_min, v)
                entry[field + "_max"] = v if cur_max is None else max(cur_max, v)
    for key in sorted(by_mat):
        e = by_mat[key]
        print(
            "MAT %-28s faces=%-6d y=[%s,%s] x=[%s,%s]"
            % (
                key,
                e["faces"],
                round(e["y_min"], 4) if e["y_min"] is not None else None,
                round(e["y_max"], 4) if e["y_max"] is not None else None,
                round(e["x_min"], 4) if e["x_min"] is not None else None,
                round(e["x_max"], 4) if e["x_max"] is not None else None,
            )
        )

    # Normal histogram along Blender Y: how much surface faces +Y vs -Y.
    rot = obj.matrix_world.to_3x3()
    pos_y = neg_y = 0
    for poly in me.polygons:
        nz = (rot @ Vector(poly.normal)).normalized().y
        if nz > 0.5:
            pos_y += 1
        elif nz < -0.5:
            neg_y += 1
    print("NORMAL_Y plusY=%d minusY=%d" % (pos_y, neg_y))

print("PROBE_DONE")
