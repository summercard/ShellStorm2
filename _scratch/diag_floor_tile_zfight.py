"""只读诊断：打开地砖 .blend，还原零件清单 + 扫描共面重叠（z-fighting 根因）。
用法：blender.exe -b --python diag_floor_tile_zfight.py
不改任何文件。"""
import bpy
from pathlib import Path
from mathutils import Vector

ROOT = Path(r"I:\工作项目\shellstrom2\ShellStorm2")
BLEND = ROOT / "assets/art/environments/tower_descent_3d/source/floor_tile_5m/env_tower_floor_tile_5m_source_v002.blend"

bpy.ops.wm.open_mainfile(filepath=str(BLEND))
print("DIAG_BLEND", BLEND)
print("DIAG_BLENDER", bpy.app.version_string)

print("=" * 78)
print("DIAG_COLLECTIONS")
for coll in bpy.data.collections:
    print("  %-34s objects=%d" % (coll.name, len(coll.objects)))

print("=" * 78)
print("DIAG_OBJECTS")


def wbounds(obj):
    mw = obj.matrix_world
    pts = [mw @ Vector(corner) for corner in obj.bound_box]
    return (
        min(p.x for p in pts), max(p.x for p in pts),
        min(p.y for p in pts), max(p.y for p in pts),
        min(p.z for p in pts), max(p.z for p in pts),
    )


for obj in sorted(bpy.data.objects, key=lambda o: o.name):
    print("  %-30s %-8s coll=%s" % (
        obj.name, obj.type, ",".join(c.name for c in obj.users_collection)))
    if obj.type == "MESH":
        b = wbounds(obj)
        tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
        print("      bbox X %8.4f .. %8.4f | Y %8.4f .. %8.4f | Z %8.4f .. %8.4f | tris=%d"
              % (b[0], b[1], b[2], b[3], b[4], b[5], tris))


def components(mesh):
    parent = list(range(len(mesh.vertices)))

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    def union(a, b):
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[rb] = ra

    for poly in mesh.polygons:
        loops = list(poly.loop_indices)
        first = mesh.loops[loops[0]].vertex_index
        for loop_index in loops[1:]:
            union(first, mesh.loops[loop_index].vertex_index)
    groups = {}
    for poly in mesh.polygons:
        root = find(mesh.loops[poly.loop_indices[0]].vertex_index)
        groups.setdefault(root, []).append(poly.index)
    return list(groups.values())


print("=" * 78)
print("DIAG_PARTS  (merged mesh decomposed into connected components = original parts)")
for obj in bpy.data.objects:
    if obj.type != "MESH":
        continue
    mesh = obj.data
    mw = obj.matrix_world
    mat_names = [m.name if m else "<none>" for m in mesh.materials]
    groups = components(mesh)
    print("-- object %s : %d components, materials=%s" % (obj.name, len(groups), mat_names))
    rows = []
    for polys in groups:
        verts = set()
        mats = set()
        for poly_index in polys:
            poly = mesh.polygons[poly_index]
            mats.add(poly.material_index)
            for loop_index in poly.loop_indices:
                verts.add(mesh.loops[loop_index].vertex_index)
        pts = [mw @ mesh.vertices[v].co for v in verts]
        rows.append((
            min(p.x for p in pts), max(p.x for p in pts),
            min(p.y for p in pts), max(p.y for p in pts),
            min(p.z for p in pts), max(p.z for p in pts),
            sorted(mats), len(polys),
        ))
    rows.sort(key=lambda r: (-r[5], -max(abs(r[0]), abs(r[1]))))
    for r in rows:
        print("   X %7.3f..%7.3f  Y %7.3f..%7.3f  Z %7.4f..%7.4f  mat=%s polys=%d"
              % (r[0], r[1], r[2], r[3], r[4], r[5],
                 ",".join(mat_names[m] if m < len(mat_names) else "?" for m in r[6]), r[7]))

print("=" * 78)
print("DIAG_COPLANAR_SCAN  (two faces on the same plane with overlapping footprint)")
FLAT = 1e-4
for obj in bpy.data.objects:
    if obj.type != "MESH":
        continue
    mesh = obj.data
    mesh.calc_loop_triangles()
    mw = obj.matrix_world
    rot = mw.to_3x3()
    mat_names = [m.name if m else "<none>" for m in mesh.materials]
    buckets = {}
    for tri in mesh.loop_triangles:
        normal = (rot @ tri.normal)
        if normal.length < 1e-9:
            continue
        normal = normal.normalized()
        origin = mw @ mesh.vertices[tri.vertices[0]].co
        offset = normal.dot(origin)
        key = (
            round(normal.x / FLAT) if abs(normal.x) > FLAT else 0,
            round(normal.y / FLAT) if abs(normal.y) > FLAT else 0,
            round(normal.z / FLAT) if abs(normal.z) > FLAT else 0,
            round(offset, 4),
        )
        buckets.setdefault(key, []).append(tri.index)

    def footprint(tri):
        normal = (rot @ mesh.loop_triangles[tri].normal).normalized()
        axis = max(range(3), key=lambda i: abs(normal[i]))
        keep = [i for i in range(3) if i != axis]
        pts = [mw @ mesh.vertices[v].co for v in mesh.loop_triangles[tri].vertices]
        return (
            min(p[keep[0]] for p in pts), max(p[keep[0]] for p in pts),
            min(p[keep[1]] for p in pts), max(p[keep[1]] for p in pts),
        )

    reported = []
    for key, members in buckets.items():
        if len(members) < 2:
            continue
        boxes = [footprint(t) for t in members]
        for i in range(len(members)):
            for j in range(i + 1, len(members)):
                a, b = boxes[i], boxes[j]
                overlap_x = min(a[1], b[1]) - max(a[0], b[0])
                overlap_y = min(a[3], b[3]) - max(a[2], b[2])
                if overlap_x <= 1e-5 or overlap_y <= 1e-5:
                    continue
                area = overlap_x * overlap_y
                if area < 1e-5:
                    continue
                tri_a = mesh.loop_triangles[members[i]]
                tri_b = mesh.loop_triangles[members[j]]
                reported.append((
                    area, key[3], key[:3],
                    mat_names[tri_a.material_index], mat_names[tri_b.material_index],
                    (min(a[0], b[0]), max(a[1], b[1]), min(a[2], b[2]), max(a[3], b[3])),
                ))
    reported.sort(key=lambda r: -r[0])
    print("-- object %s : %d overlapping coplanar triangle pairs" % (obj.name, len(reported)))
    for row in reported[:40]:
        print("   area=%8.5f m^2  plane_n=%s d=%8.4f  %s  vs  %s  footprint=%s"
              % (row[0], row[2], row[1], row[3], row[4],
                 "(%.3f..%.3f, %.3f..%.3f)" % row[5]))

print("=" * 78)
print("DIAG_DONE")
