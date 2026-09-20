"""Inspect roof-module + ivy-variant packages: collection names, roots, mesh composition."""
import bpy
from mathutils import Vector

SLUGS = [
    "房顶完整板", "房顶边缘板", "房顶角板",
    "房间实墙挂藤", "房间窗墙挂藤", "房间门洞墙挂藤",
]


def collect(coll):
    out = list(coll.objects)
    for c in coll.children:
        out.extend(collect(c))
    return out


def aabb(objs):
    mn = [float("inf")] * 3
    mx = [float("-inf")] * 3
    for o in objs:
        for c in o.bound_box:
            p = o.matrix_world @ Vector(c)
            for i in range(3):
                mn[i] = min(mn[i], p[i])
                mx[i] = max(mx[i], p[i])
    return mn, mx


print("=" * 78)
print("ALL COLLECTIONS:")
for c in sorted(bpy.data.collections.keys()):
    print("   ", c)
print("-" * 78)
print("ALL OBJECTS PREFIXED 根_:")
for o in sorted(bpy.data.objects.keys()):
    if o.startswith("根_"):
        print("   ", o, "->", o)
print("=" * 78)

for slug in SLUGS:
    pack = bpy.data.collections.get(slug + "_资产包")
    root = bpy.data.objects.get("根_" + slug)
    make = bpy.data.collections.get(slug + "_制作组件")
    print("\n### %s" % slug)
    print("  pack=%s root=%s make=%s" % (bool(pack), bool(root), bool(make)))
    if root is None:
        continue
    origin = root.matrix_world.translation.copy()
    print("  root origin (world) = [%.4f, %.4f, %.4f]" % (origin[0], origin[1], origin[2]))
    for label, coll in (("资产包", pack), ("制作组件", make)):
        if coll is None:
            continue
        objs = [o for o in collect(coll) if o.type == "MESH"]
        if not objs:
            print("  %s: no mesh" % label)
            continue
        mn, mx = aabb(objs)
        rmn = [mn[i] - origin[i] for i in range(3)]
        rmx = [mx[i] - origin[i] for i in range(3)]
        print("  %s meshes=%d" % (label, len(objs)))
        print("     world  size=[%.4f, %.4f, %.4f]" % (mx[0]-mn[0], mx[1]-mn[1], mx[2]-mn[2]))
        print("     rebased min=[%.4f, %.4f, %.4f]  max=[%.4f, %.4f, %.4f]"
              % (rmn[0], rmn[1], rmn[2], rmx[0], rmx[1], rmx[2]))
        for o in objs:
            omn, omx = aabb([o])
            mats = [m.name for m in o.data.materials]
            print("       - %-34s verts=%-6d size=[%.3f,%.3f,%.3f] mats=%s"
                  % (o.name, len(o.data.vertices),
                     omx[0]-omn[0], omx[1]-omn[1], omx[2]-omn[2], mats))
print("=" * 78)
