"""只读诊断 v2：跨零件共面重叠扫描（z-fighting 门禁）。

v1 的缺陷：按 (法线, 平面偏移) 分桶后，**同一个 n-gon 拆出的两个三角形**也在同一桶里，
且两者的 footprint 都是整张面的包围盒 ⇒ 每张面都自配一对。于是 25 m² 的"底板共面"
其实是底板自身两个三角形的自配对，纯噪声，把真正的问题淹掉了。

v2 做法：
  1. 先按连通分量把合并网格还原成原始零件（join 后每个 box 仍是独立连通体）。
  2. 只比较**不同零件**之间的三角形，且平面偏移 < TOL、法线同向，footprint 真有面积交叠。
  3. 按 (零件A, 零件B, 平面高度) 归并，输出最大重叠面积，便于排序定位。
  4. 打印零件数与三角形数哨兵，防止扫空还报 PASS。

用法：blender.exe -b --python diag_floor_tile_zfight2.py -- <blend路径>
不改任何文件。
"""
import bpy, sys
from pathlib import Path
from mathutils import Vector

ARGV = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
if ARGV:
    BLEND = Path(ARGV[0])
else:
    ROOT = Path(r"I:\工作项目\shellstrom2\ShellStorm2")
    BLEND = ROOT / "assets/art/environments/tower_descent_3d/source/floor_tile_5m/env_tower_floor_tile_5m_source_v003.blend"

TOL = 5e-5          # 平面偏移容差 0.05mm
NORMAL_DOT = 0.99995
MIN_AREA = 1e-5     # m^2
TARGET_OBJECT = 'FloorTile_5m'

bpy.ops.wm.open_mainfile(filepath=str(BLEND))
print("DIAG2_BLEND", BLEND)
print("DIAG2_BLENDER", bpy.app.version_string)

obj = bpy.data.objects.get(TARGET_OBJECT)
if obj is None or obj.type != 'MESH':
    print("DIAG2_FAIL 找不到网格对象 %s" % TARGET_OBJECT)
    raise SystemExit(1)
mesh = obj.data
mesh.calc_loop_triangles()
mw = obj.matrix_world
rot = mw.to_3x3()
mat_names = [m.name if m else "<none>" for m in mesh.materials]

# ---- 连通分量 = 原始零件 ------------------------------------------------
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
    for li in loops[1:]:
        union(first, mesh.loops[li].vertex_index)

comp_of_vert = {}
for v in range(len(mesh.vertices)):
    comp_of_vert[v] = find(v)

comp_tris = {}
for tri in mesh.loop_triangles:
    comp_tris.setdefault(comp_of_vert[tri.vertices[0]], []).append(tri.index)

# 零件标签 = 该分量在世界坐标下的包围盒（便于人读）
comp_info = {}
for cid, tris in comp_tris.items():
    pts = []
    for ti in tris:
        for vi in mesh.loop_triangles[ti].vertices:
            pts.append(mw @ mesh.vertices[vi].co)
    comp_info[cid] = (
        min(p.x for p in pts), max(p.x for p in pts),
        min(p.y for p in pts), max(p.y for p in pts),
        min(p.z for p in pts), max(p.z for p in pts),
        len(tris),
    )

print("=" * 78)
print("DIAG2_PARTS object=%s components=%d triangles=%d" % (obj.name, len(comp_tris), len(mesh.loop_triangles)))
for cid in sorted(comp_tris, key=lambda c: -comp_info[c][5]):
    b = comp_info[cid]
    print("   #%-3d X %7.3f..%7.3f  Y %7.3f..%7.3f  Z %7.4f..%7.4f  tris=%d" % (
        cid, b[0], b[1], b[2], b[3], b[4], b[5], b[6]))

# ---- 三角形平面 + 面内 2D 足迹 -----------------------------------------
def tri_plane(ti):
    tri = mesh.loop_triangles[ti]
    n = (rot @ tri.normal)
    if n.length < 1e-9:
        return None
    n = n.normalized()
    o = mw @ mesh.vertices[tri.vertices[0]].co
    return n, n.dot(o), o

def tri_footprint(ti):
    tri = mesh.loop_triangles[ti]
    n = (rot @ tri.normal).normalized()
    axis = max(range(3), key=lambda i: abs(n[i]))
    keep = [i for i in range(3) if i != axis]
    pts = [mw @ mesh.vertices[v].co for v in tri.vertices]
    return (min(p[keep[0]] for p in pts), max(p[keep[0]] for p in pts),
            min(p[keep[1]] for p in pts), max(p[keep[1]] for p in pts),
            keep)

planes = {}
for cid, tris in comp_tris.items():
    for ti in tris:
        pl = tri_plane(ti)
        if pl is None:
            continue
        planes[ti] = (cid, pl[0], pl[1], tri_footprint(ti))

ids = sorted(planes.keys())
found = {}
counters = 0
for i in range(len(ids)):
    a = ids[i]
    ca, na, da, fa = planes[a]
    for j in range(i + 1, len(ids)):
        b = ids[j]
        cb, nb, db, fb = planes[b]
        if ca == cb:
            continue                    # 同零件不比较（v1 的噪声来源）
        if na.dot(nb) < NORMAL_DOT:
            continue
        if abs(da - db) > TOL:
            continue
        counters += 1
        if fa[4] != fb[4]:
            continue                    # 主轴不同，不做面内比较
        ox = min(fa[1], fb[1]) - max(fa[0], fb[0])
        oy = min(fa[3], fb[3]) - max(fa[2], fb[2])
        if ox <= 1e-5 or oy <= 1e-5:
            continue
        area = ox * oy
        if area < MIN_AREA:
            continue
        key = (min(ca, cb), max(ca, cb), round(da, 4))
        rec = found.get(key)
        if rec is None or area > rec[0]:
            found[key] = (area, mat_names[mesh.loop_triangles[a].material_index],
                          mat_names[mesh.loop_triangles[b].material_index],
                          (min(fa[0], fb[0]), max(fa[1], fb[1]),
                           min(fa[2], fb[2]), max(fa[3], fb[3])))

print("=" * 78)
print("DIAG2_CROSS_PART_COPLANAR pairs=%d coplanar_candidates_scanned=%d" % (len(found), counters))
total = 0.0
for key in sorted(found, key=lambda k: -found[k][0]):
    area, ma, mb, fp = found[key]
    total += area
    ba, bb = comp_info[key[0]], comp_info[key[1]]
    print("   area=%7.4f m^2 plane_z=%7.4f  #%d[Z %.4f..%.4f %s] vs #%d[Z %.4f..%.4f %s] fp=(%.3f..%.3f, %.3f..%.3f)" % (
        area, key[2], key[0], ba[4], ba[5], ma, key[1], bb[4], bb[5], mb, fp[0], fp[1], fp[2], fp[3]))
print("DIAG2_TOTAL_AREA %.4f m^2" % total)
print("DIAG2_VERDICT %s" % ("PASS" if not found else "FAIL"))
print("=" * 78)
print("DIAG2_DONE")
