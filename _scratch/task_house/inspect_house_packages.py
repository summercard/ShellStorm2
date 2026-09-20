"""Inspect {room wall / door} packages in the rooftop reference component library."""
from pathlib import Path
import json
import bpy
from mathutils import Vector

KEYWORDS = ("房间", "门", "雨棚")


def collect(coll):
    out = list(coll.objects)
    for c in coll.children:
        out.extend(collect(c))
    return out


print("=" * 78)
print("SCENES:", [s.name for s in bpy.data.scenes])
print("=" * 78)

print("\n--- collections containing keywords ---")
for coll in bpy.data.collections:
    if any(k in coll.name for k in KEYWORDS):
        objs = collect(coll)
        meshes = [o for o in objs if o.type == "MESH"]
        print("%-28s objs=%-3d meshes=%-3d  %s"
              % (coll.name, len(objs), len(meshes), [o.name for o in objs][:8]))

print("\n--- objects (mesh) whose name contains keywords ---")
for o in bpy.data.objects:
    if o.type == "MESH" and any(k in o.name for k in KEYWORDS):
        bb = [o.matrix_world @ Vector(c) for c in o.bound_box]
        mn = [min(p[i] for p in bb) for i in range(3)]
        mx = [max(p[i] for p in bb) for i in range(3)]
        v = len(o.data.vertices)
        print("  %-30s verts=%-6d world_min=[%.3f,%.3f,%.3f] size=[%.3f,%.3f,%.3f]"
              % (o.name, v, mn[0], mn[1], mn[2], mx[0]-mn[0], mx[1]-mn[1], mx[2]-mn[2]))

print("\n--- root objects 根_*  ---")
for o in bpy.data.objects:
    if o.name.startswith("根_"):
        print("  %-30s loc=[%.3f,%.3f,%.3f]" % (o.name, *o.matrix_world.translation))

print("\n--- material roles on door package ---")
for coll in bpy.data.collections:
    if "门" in coll.name:
        mats = set()
        for o in collect(coll):
            if o.type == "MESH":
                for s in o.material_slots:
                    if s.material:
                        mats.add(s.material.name)
        print("  %-28s -> %s" % (coll.name, sorted(mats)))
