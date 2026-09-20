"""Measure the door-hole opening and probe the 门与暖灯 welded mesh's structure.

Uses BVHTree.FromPolygons (no depsgraph / view-layer evaluation needed).
"""
import bpy
import bmesh
from mathutils import Vector
from mathutils.bvhtree import BVHTree

print("=" * 78)


def build_bvh(obj):
    verts = [v.co.copy() for v in obj.data.vertices]
    polys = [tuple(p.vertices) for p in obj.data.polygons]
    return BVHTree.FromPolygons(verts, polys, all_triangles=False)


# ---------------------------------------------------------------- A) door hole
door_wall = bpy.data.objects.get("房间门洞墙_水泥结构_制作")
if door_wall is None:
    print("!! 房间门洞墙_水泥结构_制作 not found")
else:
    verts = [v.co for v in door_wall.data.vertices]
    xmin = min(v.x for v in verts); xmax = max(v.x for v in verts)
    ymin = min(v.y for v in verts); ymax = max(v.y for v in verts)
    zmin = min(v.z for v in verts); zmax = max(v.z for v in verts)
    print("A) 门洞墙水泥结构 local x=[%.3f,%.3f] y=[%.3f,%.3f] z=[%.3f,%.3f]"
          % (xmin, xmax, ymin, ymax, zmin, zmax))
    bvh = build_bvh(door_wall)
    step = 0.05
    rows = []
    z = zmin + step * 0.5
    while z <= zmax - step * 0.5 + 1e-6:
        row = []
        x = xmin + step * 0.5
        while x <= xmax - step * 0.5 + 1e-6:
            origin = Vector((x, ymin - 5.0, z))
            hit = bvh.ray_cast(origin, Vector((0.0, 1.0, 0.0)), 30.0)
            row.append("X" if hit[0] is not None else ".")
            x += step
        rows.append((z, "".join(row)))
        z += step
    prev = None
    for z, row in rows:
        if row != prev:
            print("   z=%6.3f  %s" % (z, row))
            prev = row
    print("   columns x from %.4f to %.4f step %.2f" % (xmin, xmax, step))

# ---------------------------------------------------------------- B) loose parts
print("-" * 78)
for cand in ("门与暖灯_主体", "门与暖灯_UI灯光_柔和自发光"):
    obj = bpy.data.objects.get(cand)
    if obj is None:
        print("!! %s not found" % cand)
        continue
    print("B) %s verts=%d polys=%d materials=%s"
          % (obj.name, len(obj.data.vertices), len(obj.data.polygons),
             [m.name for m in obj.data.materials]))
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.faces.ensure_lookup_table()
    seen = set()
    parts = []
    for f in bm.faces:
        if f.index in seen:
            continue
        stack = [f]; seen.add(f.index); group = []
        while stack:
            cur = stack.pop(); group.append(cur)
            for e in cur.edges:
                for nf in e.link_faces:
                    if nf.index not in seen:
                        seen.add(nf.index); stack.append(nf)
        parts.append(group)
    print("   loose parts = %d" % len(parts))
    for i, group in enumerate(parts):
        pmin = [float("inf")] * 3; pmax = [float("-inf")] * 3
        for f in group:
            for v in f.verts:
                for k in range(3):
                    pmin[k] = min(pmin[k], v.co[k]); pmax[k] = max(pmax[k], v.co[k])
        print("     part%-2d faces=%-5d bbox min=[%.3f,%.3f,%.3f] size=[%.3f,%.3f,%.3f]"
              % (i, len(group), pmin[0], pmin[1], pmin[2],
                 pmax[0]-pmin[0], pmax[1]-pmin[1], pmax[2]-pmin[2]))
    bm.free()

# ---------------------------------------------------------------- C) materials
print("-" * 78)
print("C) 制作 meshes materials:")
for name in ("门与暖灯_门扇_制作", "门与暖灯_门板_制作", "门与暖灯_窥窗框_制作",
             "门与暖灯_窥窗玻璃_制作", "门与暖灯_门把手_制作", "门与暖灯_门框_制作",
             "门与暖灯_厚石材门柱_制作", "门与暖灯_自发光灯芯_制作",
             "门与暖灯_门灯罩_制作", "门与暖灯_铰链_制作", "门与暖灯_门槛_制作",
             "门与暖灯_厚门楣_制作", "门与暖灯_进深门槛_制作"):
    o = bpy.data.objects.get(name)
    if o:
        print("   %-30s %s" % (name, [m.name for m in o.data.materials]))
print("=" * 78)
